from unittest.mock import patch
import io
import tempfile
from PIL import Image
from django.test import SimpleTestCase, TestCase, override_settings
from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APIClient
from apps.receipts.models import Receipt
from apps.receipts.parsers import bill_summary
from apps.receipts.parsers.generic import parse
from apps.receipts.validators import financial_warnings


# Invented OCR passes of an app bill summary. The rupee glyph is misread as 2, =, <, £ or $,
# and struck-through original prices precede the charged ones, as Tesseract does on screenshots.
PASS_PREPARED = '''Bill Summary
Item Total     =150 2120
Small Cart Fee    <25
Handling Charge    25.49
Surge Fee    =30 220
Delivery Fee    22
To Pay    2230.00 £19.49'''
PASS_PLAIN = '''Bill Summary
Item Total =150 2120
Smal! Cart Fee 225
Handling Charge 25.49
Surge Fee =30 220
Delivery Fee 22
Add products worth 249 to get free delivery
To Pay 2230.00 $192.49'''
PASS_UPSCALED = '''Bill Summary
Item Total =150 120
Small Cart Fee £25
Handling Charge 25.49
Surge Fee =30 20
Delivery Fee <22
To Pay 2230.00 £192.49
Incl. all taxes and charges SAVING 737'''
PASSES = [PASS_PREPARED, PASS_PLAIN, PASS_UPSCALED]


def summarise(texts):
    return bill_summary.apply(parse(texts[0]), texts)


class BillSummaryTests(SimpleTestCase):
    def test_passes_vote_and_total_resolves_misread_rupee_glyph(self):
        data = summarise(PASSES)
        # 120 + 5.49 + 22 + (25 + 20) = 192.49; 25.49 is the rupee glyph read as "2".
        self.assertEqual(
            {k: data[k] for k in ['item_subtotal', 'handling_fee', 'delivery_fee', 'packaging_fee', 'other_fees', 'grand_total']},
            {'item_subtotal': '120.00', 'handling_fee': '5.49', 'delivery_fee': '22.00', 'packaging_fee': None, 'other_fees': '45.00', 'grand_total': '192.49'},
        )
        self.assertEqual(data['provenance']['grand_total'], 'document_bill_summary')
        self.assertTrue(any('add up to the total' in w for w in data['warnings']))
        self.assertTrue(any('category shortcuts' in w for w in data['warnings']))
        self.assertFalse(any('No supported product rows' in w for w in data['warnings']))

    def test_several_reconciling_readings_stay_unknown(self):
        # 22 + 25.49 and 2 + 45.49 both fit; neither delivery nor handling may be guessed.
        text = 'Bill Summary\nItem Total 100\nHandling Charge 25.49\nDelivery Fee 22\nTo Pay £127.49'
        data = summarise([text])
        self.assertEqual(data['item_subtotal'], '100.00')
        self.assertEqual(data['grand_total'], '127.49')
        self.assertIsNone(data['handling_fee'])
        self.assertIsNone(data['delivery_fee'])
        self.assertNotIn('handling_fee', data['provenance'])
        self.assertTrue(any('left blank' in w for w in data['warnings']))

    def test_without_total_ambiguous_amounts_are_not_invented(self):
        data = summarise(['Bill Summary\nItem Total £80\nHandling Charge 25.49'])
        self.assertEqual(data['item_subtotal'], '80.00')
        self.assertIsNone(data['handling_fee'])
        self.assertIsNone(data['grand_total'])
        self.assertTrue(any('total paid' in w for w in data['warnings']))

    def test_amounts_that_do_not_add_up_are_flagged(self):
        data = summarise(['Bill Summary\nItem Total £80\nDelivery Fee £10\nTo Pay £95'])
        self.assertEqual((data['item_subtotal'], data['delivery_fee'], data['grand_total']), ('80.00', '10.00', '95.00'))
        self.assertTrue(any('do not add up' in w for w in data['warnings']))

    def test_other_layouts_are_untouched(self):
        text = 'Order ID: X1\nHandling fee: ₹12\nGrand total: ₹286'
        self.assertEqual(summarise([text]), parse(text))

    def test_reconciliation_includes_stated_other_fees(self):
        data = {'items': [], 'item_subtotal': '100', 'handling_fee': '5', 'delivery_fee': '0', 'packaging_fee': '0', 'taxes': '0', 'discount': '0', 'other_fees': '15', 'grand_total': '120'}
        self.assertEqual(financial_warnings(data), [])
        self.assertEqual(len(financial_warnings({**data, 'other_fees': None})), 1)


@override_settings(CELERY_TASK_ALWAYS_EAGER=True, SECURE_SSL_REDIRECT=False)
class BillSummaryUploadTests(TestCase):
    def test_screenshot_upload_then_confirm_keeps_other_fees(self):
        with tempfile.TemporaryDirectory() as media, override_settings(MEDIA_ROOT=media):
            image = io.BytesIO()
            Image.new('RGB', (600, 450), 'white').save(image, format='PNG')
            user = get_user_model().objects.create_user(username='bill-summary', email='summary@example.invalid', password='Synthetic-Password-123!')
            client = APIClient()
            client.force_authenticate(user)
            with patch('pytesseract.image_to_string', side_effect=PASSES):
                response = client.post('/api/v1/receipts/upload/', {'file': SimpleUploadedFile('synthetic-summary.png', image.getvalue(), content_type='image/png')}, format='multipart')
            self.assertEqual(response.status_code, 202, response.data)
            receipt = Receipt.objects.get(pk=response.data['id'])
            self.assertEqual(receipt.extraction_status, 'review')
            self.assertEqual(receipt.extracted_json['other_fees'], '45.00')
            payload = {'reviewed': True, 'acknowledge_warnings': True, 'order_date': '2026-10-01', 'grand_total': '192.49',
                       'items': [{'name': 'Potato chips', 'quantity': '2', 'line_total': '120', 'category': 'Snacks'}]}
            confirmed = client.post(f'/api/v1/receipts/{receipt.pk}/confirm/', payload, format='json')
            self.assertEqual(confirmed.status_code, 201, confirmed.data)
            self.assertEqual(confirmed.data['other_fees'], '45.00')
            self.assertEqual(confirmed.data['handling_fee'], '5.49')
            self.assertEqual(confirmed.data['items'][0]['category'], 'Snacks')
            summary = client.get('/api/v1/analytics/overview/').data
            self.assertEqual(summary['other_fees'], '45.00')
