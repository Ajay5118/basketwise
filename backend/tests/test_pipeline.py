import io
import tempfile
from pathlib import Path
from decimal import Decimal
from unittest.mock import patch
from django.test import TestCase, override_settings
from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APIClient
from reportlab.pdfgen.canvas import Canvas
from PIL import Image
from apps.receipts.parser_registry import PARSERS
from apps.receipts.validators import financial_warnings
from apps.receipts.pdf_extractor import extract_pdf
from apps.receipts.image_ocr import extract_image
from apps.receipts.models import Receipt
from apps.orders.models import Order, Refund, PaymentTransaction

FIXTURE = Path(__file__).parent / 'fixtures' / 'instamart.txt'


def pdf_bytes(text=None):
    buffer = io.BytesIO()
    canvas = Canvas(buffer, invariant=1)
    y = 800
    for line in (text or FIXTURE.read_text(encoding='utf-8')).splitlines():
        canvas.drawString(40, y, line.encode('ascii', errors='replace').decode())
        y -= 20
    canvas.save()
    return buffer.getvalue()


class ParsingTests(TestCase):
    def test_instamart_example(self):
        result = PARSERS['instamart'](FIXTURE.read_text(encoding='utf-8'))
        self.assertEqual(result['grand_total'], '286.00')
        self.assertEqual(result['item_subtotal'], '274.00')
        self.assertEqual(result['handling_fee'], '12.00')
        self.assertEqual(result['delivery_fee'], '0.00')
        self.assertEqual(result['items'][0]['unit_price'], '47.00')
        self.assertEqual(result['items'][1]['unit_price'], '45.00')
        self.assertTrue(result['items'][0]['unit_price_derived'])
        self.assertIsNone(result['order_date'])

    def test_synthetic_platform_variants(self):
        for platform, parser in PARSERS.items():
            with self.subTest(platform=platform):
                result = parser(FIXTURE.read_text(encoding='utf-8').replace('Instamart', platform))
                self.assertEqual(result['platform'], platform)
                self.assertEqual(result['grand_total'], '286.00')

    def test_unknowns_not_fabricated(self):
        data = PARSERS['other']('An unfamiliar receipt')
        self.assertIsNone(data['grand_total'])
        self.assertEqual(data['items'], [])
        self.assertIsNone(data['delivery_fee'])
        self.assertIsNone(data['currency'])

    def test_unlabelled_date_and_status_mentions_are_not_order_facts(self):
        data = PARSERS['other']('Refund date: 2026-10-21\nThe delivered item was damaged')
        self.assertIsNone(data['order_date'])
        self.assertEqual(data['status'], 'unknown')

    def test_reconciliation(self):
        data = PARSERS['instamart'](FIXTURE.read_text(encoding='utf-8'))
        data.update(packaging_fee='0', taxes='0', discount='0')
        self.assertEqual(financial_warnings(data), [])
        data['grand_total'] = '999'
        self.assertIn('do not reconcile', financial_warnings(data)[0])

    def test_native_pdf_extraction(self):
        with tempfile.NamedTemporaryFile(suffix='.pdf', delete=False) as file:
            file.write(pdf_bytes())
            path = file.name
        try:
            self.assertIn('Grand total', extract_pdf(path))
        finally:
            Path(path).unlink()

    def test_ocr_adapter_boundary(self):
        buffer = io.BytesIO()
        Image.new('RGB', (40, 40), 'white').save(buffer, format='PNG')
        buffer.seek(0)
        # Adapter contract only; this does not establish real OCR accuracy.
        with patch('pytesseract.image_to_string', return_value='readable') as ocr:
            self.assertEqual(extract_image(buffer), 'readable')
            self.assertEqual(ocr.call_args.kwargs['timeout'], 25)


@override_settings(CELERY_TASK_ALWAYS_EAGER=True, SECURE_SSL_REDIRECT=False)
class FlowTests(TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.media = override_settings(MEDIA_ROOT=self.temp.name)
        self.media.enable()
        self.addCleanup(self.temp.cleanup)
        self.addCleanup(self.media.disable)
        self.user = get_user_model().objects.create_user(username='one', email='one@example.com', password='secure-Test-1234')
        self.other = get_user_model().objects.create_user(username='two', email='two@example.com', password='secure-Test-1234')
        self.client = APIClient()
        self.client.force_authenticate(self.user)

    def upload(self):
        response = self.client.post('/api/v1/receipts/upload/', {'file': SimpleUploadedFile('receipt.pdf', pdf_bytes(), content_type='application/pdf')}, format='multipart')
        self.assertIn(response.status_code, [200, 202], response.data)
        return response.data['id']

    def confirm(self, receipt_id, **updates):
        draft = dict(Receipt.objects.get(pk=receipt_id).extracted_json)
        draft.update(order_date='2026-10-21', reviewed=True, acknowledge_warnings=True)
        draft.update(updates)
        return self.client.post(f'/api/v1/receipts/{receipt_id}/confirm/', draft, format='json')

    def test_upload_review_correct_confirm_dashboard(self):
        pk = self.upload()
        self.assertEqual(Receipt.objects.get(pk=pk).extraction_status, 'review')
        self.assertEqual(Order.objects.count(), 0)
        preview = self.client.get(f'/api/v1/receipts/{pk}/preview/')
        self.assertEqual(preview.data['data']['grand_total'], '286.00')
        self.assertIsNone(preview.data['data']['order_date'])
        response = self.confirm(pk)
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['grand_total'], '286.00')
        overview = self.client.get('/api/v1/analytics/overview/')
        self.assertEqual(overview.data['net_spending'], '286.00')
        self.assertEqual(overview.data['order_count'], 1)
        self.assertEqual(self.confirm(pk).status_code, 200)
        self.assertEqual(self.upload(), pk)
        self.assertEqual(Order.objects.count(), 1)

    def test_missing_review_date_and_warning_acknowledgement(self):
        pk = self.upload()
        self.assertEqual(self.confirm(pk, reviewed=False).status_code, 400)
        self.assertEqual(self.confirm(pk, order_date=None).status_code, 400)
        self.assertEqual(
            self.confirm(
                pk,
                packaging_fee='0',
                taxes='0',
                discount='0',
                grand_total='999.00',
                acknowledge_warnings=False,
            ).status_code,
            400,
        )
        self.assertEqual(Order.objects.count(), 0)

    def test_exact_external_id_across_different_files(self):
        pk = self.upload()
        first = self.confirm(pk, external_order_id='TEST-ONE')
        response = self.client.post('/api/v1/receipts/upload/', {'file': SimpleUploadedFile('other.pdf', pdf_bytes(FIXTURE.read_text(encoding='utf-8')+'\nOrder ID: TEST-ONE'))}, format='multipart')
        second = self.confirm(response.data['id'], external_order_id='TEST-ONE')
        self.assertEqual(first.data['id'], second.data['id'])
        self.assertEqual(Order.objects.count(), 1)

    def test_possible_duplicate_requires_acknowledgement_not_merge(self):
        self.confirm(self.upload())
        response = self.client.post('/api/v1/receipts/upload/', {'file': SimpleUploadedFile('second.pdf', pdf_bytes(FIXTURE.read_text(encoding='utf-8')+'\nDifferent purchase'))}, format='multipart')
        pk = response.data['id']
        self.assertEqual(self.confirm(pk, acknowledge_warnings=False).status_code, 400)
        self.assertEqual(self.confirm(pk).status_code, 201)
        self.assertEqual(Order.objects.count(), 2)

    def test_cross_user_isolation(self):
        pk = self.upload()
        order = self.confirm(pk).data['id']
        self.client.force_authenticate(self.other)
        for path in [f'receipts/{pk}/preview/', f'receipts/{pk}/status/', f'orders/{order}/']:
            self.assertEqual(self.client.get('/api/v1/'+path).status_code, 404)
        self.assertEqual(self.client.patch(f'/api/v1/orders/{order}/', {'grand_total': '1'}).status_code, 404)
        self.assertEqual(self.client.delete(f'/api/v1/orders/{order}/').status_code, 404)
        self.assertEqual(self.confirm(pk).status_code, 404)
        self.assertEqual(self.client.get('/api/v1/orders/').data['count'], 0)
        self.assertEqual(self.client.get('/api/v1/receipts/').data['count'], 0)
        self.assertEqual(self.client.get('/api/v1/analytics/overview/').data['net_spending'], '0.00')

    def test_malicious_uploads(self):
        for name, content in [('x.pdf', b'<script>bad</script>'), ('x.png', b'not a PNG'), ('x.pdf', b'%PDF-1.7 /JavaScript')]:
            response = self.client.post('/api/v1/receipts/upload/', {'file': SimpleUploadedFile(name, content)}, format='multipart')
            self.assertEqual(response.status_code, 400)
        self.assertEqual(Receipt.objects.count(), 0)

    def test_upload_limits(self):
        with override_settings(MAX_RECEIPT_BYTES=10):
            response = self.client.post('/api/v1/receipts/upload/', {'file': SimpleUploadedFile('x.pdf', pdf_bytes())}, format='multipart')
            self.assertEqual(response.status_code, 400)

    def test_refunds_cancelled_and_pending(self):
        order = self.confirm(self.upload()).data['id']
        response = self.client.post(f'/api/v1/orders/{order}/refunds/', {'amount': '86.00', 'refund_date': '2026-10-22', 'status': 'confirmed'}, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(self.client.get('/api/v1/analytics/overview/').data['net_spending'], '200.00')
        self.assertEqual(self.client.post(f'/api/v1/orders/{order}/refunds/', {'amount': '999', 'refund_date': '2026-10-22', 'status': 'confirmed'}, format='json').status_code, 400)
        self.client.patch(f'/api/v1/orders/{order}/', {'status': 'cancelled'}, format='json')
        self.assertEqual(self.client.get('/api/v1/analytics/overview/').data['net_spending'], '0.00')

    def test_bank_alert_does_not_become_order(self):
        message = 'Rs.806.00 is debited from your account ending 3489 towards VPA *******.rzp@hdfcbank (Blinkit) on 21-10-26.'
        response = self.client.post('/api/v1/payments/import/', {'text': message}, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['merchant'], 'blinkit')
        self.assertEqual(response.data['transaction_date'], '2026-10-21')
        self.assertEqual(response.data['status'], 'payment_detected')
        self.assertEqual(response.data['payment_method'], 'UPI')
        self.assertEqual(Order.objects.count(), 0)
        self.assertEqual(self.client.post('/api/v1/payments/import/', {'text': message}, format='json').status_code, 200)
        self.assertEqual(PaymentTransaction.objects.count(), 1)
        self.assertNotIn('3489', str(response.data))

    def test_payment_linking_no_double_count(self):
        order = self.confirm(self.upload()).data['id']
        payment = self.client.post('/api/v1/payments/import/', {'text': 'Rs.286.00 is debited towards UPI Instamart on 21-10-26.'}, format='json').data['id']
        response = self.client.post(f'/api/v1/payments/{payment}/link-order/', {'order': order}, format='json')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(self.client.get('/api/v1/analytics/overview/').data['net_spending'], '286.00')
        self.client.force_authenticate(self.other)
        self.assertEqual(self.client.post(f'/api/v1/payments/{payment}/link-order/', {'order': order}).status_code, 404)

    def test_corrected_quantity_recomputes_derived_price(self):
        pk = self.upload()
        draft = Receipt.objects.get(pk=pk).extracted_json
        draft['items'][0]['quantity'] = '4'
        response = self.confirm(pk, items=draft['items'])
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['items'][0]['unit_price'], '23.50')

    def test_export_and_audit_are_user_scoped_without_source_text(self):
        from apps.accounts.models import AuditEvent
        self.confirm(self.upload())
        exported = self.client.get('/api/v1/export/')
        self.assertEqual(len(exported.data['orders']), 1)
        self.assertFalse(any('286' in str(event.resource) for event in AuditEvent.objects.all()))
        self.client.force_authenticate(self.other)
        self.assertEqual(self.client.get('/api/v1/export/').data['orders'], [])

    def test_unavailable_queue_is_a_retriable_failure(self):
        with patch('apps.receipts.views.process_receipt.delay', side_effect=ConnectionError()):
            pk = self.upload()
        self.assertEqual(Receipt.objects.get(pk=pk).extraction_status, 'failed')
        response = self.client.post(f'/api/v1/receipts/{pk}/retry/', {}, format='json')
        self.assertEqual(response.status_code, 202)
        self.assertEqual(Receipt.objects.get(pk=pk).extraction_status, 'review')

    def test_pending_order_is_not_spending(self):
        response = self.confirm(self.upload(), status='pending')
        self.assertEqual(response.status_code, 201)
        self.assertEqual(self.client.get('/api/v1/analytics/overview/').data['net_spending'], '0.00')

    def test_auth_refresh_rotation(self):
        self.client.force_authenticate(None)
        self.assertEqual(self.client.get('/api/v1/orders/').status_code, 401)
        login = self.client.post('/api/v1/auth/login/', {'email': self.user.email, 'password': 'secure-Test-1234'}, format='json')
        self.assertEqual(login.status_code, 200)
        old = login.data['refresh']
        refreshed = self.client.post('/api/v1/auth/refresh/', {'refresh': old}, format='json')
        self.assertEqual(refreshed.status_code, 200)
        self.assertEqual(self.client.post('/api/v1/auth/refresh/', {'refresh': old}, format='json').status_code, 401)

    def test_delete_requires_password_and_removes_files(self):
        self.upload()
        self.assertEqual(self.client.delete('/api/v1/account/', {'password': 'wrong'}, format='json').status_code, 400)
        self.assertEqual(self.client.delete('/api/v1/account/', {'password': 'secure-Test-1234'}, format='json').status_code, 204)
        self.assertFalse(list(Path(self.temp.name).rglob('*.*')))
