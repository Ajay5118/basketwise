from unittest.mock import patch
import io
import tempfile
from PIL import Image, ImageDraw
from django.test import SimpleTestCase, TestCase, override_settings
from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APIClient
from apps.receipts.models import Receipt
from apps.receipts.image_ocr import prepare_image
from apps.receipts.parsers.generic import parse
from apps.receipts.parsers.tax_invoice import number_words, total_in_words


# Invented receipt text. No customer invoice details are used in this fixture.
TAX_INVOICE = '''Example Shop Tax Invoice
Invoice Date: 02-Feb-2026
Order Id: EXAMPLE-42
Sr. No | UPC | Item Description | MRP | Discount | Qty. | Taxable Value | CGST (%) | CGST (INR) | SGST (%) | SGST (INR) | Cess (%) | Additional Cess Val | Total
1 123 Example Pantry | 200.00 | 20.00 2 300.00 9.00 27.00 9.00 27.00 0.00 0.00 354.00
456 Storage Container
(HSN-123456)
Amount in Words: Three Hundred And Fifty-Four Rupees and Zero Paise Only
Terms & Conditions
'''


class TaxInvoiceTests(SimpleTestCase):
    def test_explicit_tax_table_and_amount_in_words(self):
        result = parse(TAX_INVOICE)
        self.assertEqual(len(result['items']), 1)
        self.assertEqual(result['items'][0]['name'], 'Example Pantry Storage Container')
        self.assertEqual(result['items'][0]['quantity'], '2')
        self.assertEqual(result['items'][0]['line_total'], '354.00')
        self.assertEqual(result['items'][0]['unit_price'], '177.00')
        self.assertEqual(result['grand_total'], '354.00')
        self.assertEqual(result['currency'], 'INR')
        self.assertEqual(result['external_order_id'], 'EXAMPLE-42')
        # Invoice date does not establish order/delivery status or an order date.
        self.assertIsNone(result['order_date'])
        self.assertEqual(result['status'], 'unknown')
        self.assertIsNone(result['item_subtotal'])
        self.assertEqual(result['provenance']['grand_total'], 'document_amount_in_words')

    def test_numeric_explicit_total_takes_priority(self):
        result = parse(TAX_INVOICE + '\nGrand total: INR 355.00')
        self.assertEqual(result['grand_total'], '355.00')
        self.assertEqual(result['provenance']['grand_total'], 'document')

    def test_table_requires_all_known_headers_and_complete_row(self):
        for text in [TAX_INVOICE.replace('SGST (INR)', 'Other column'), TAX_INVOICE.replace('9.00 27.00 9.00 27.00 0.00 0.00', '9.00 27.00'), TAX_INVOICE.replace('20.00 2 300.00', '20.00 ? 300.00')]:
            with self.subTest(text=text):
                self.assertEqual(parse(text)['items'], [])

    def test_reordered_tax_columns_and_inconsistent_totals_stay_unknown(self):
        reordered = TAX_INVOICE.replace('CGST (INR)', 'TEMP').replace('SGST (INR)', 'CGST (INR)').replace('TEMP', 'SGST (INR)')
        wrong_tax = TAX_INVOICE.replace('9.00 27.00 9.00', '9.00 37.00 9.00')
        for text in [reordered, wrong_tax]:
            with self.subTest(text=text):
                self.assertEqual(parse(text)['items'], [])

    def test_unfamiliar_or_malformed_words_are_unknown(self):
        for text in ['Amount in Words: Three mystery Rupees and Zero Paise Only', 'Amount in Words: Three Rupees and One Hundred Paise Only', 'Amount in Words: Three Four Rupees and Zero Paise Only']:
            self.assertIsNone(total_in_words(text))
        self.assertIsNone(number_words('twenty sixty'))
        self.assertIsNone(number_words('and'))
        self.assertIsNone(number_words('three hundred and and five'))
        self.assertEqual(number_words('One Lakh Twenty Three Thousand Four Hundred Fifty Six'), 123456)
        self.assertEqual(total_in_words('Amount in Three Hundred Rupees and Fifty Paise Only\nWords:'), '300.50')
        self.assertEqual(total_in_words('Amount in Words: Three Rupees and Zero Paisa Only'), '3.00')

    def test_small_gridded_images_are_upscaled_and_rules_removed(self):
        image = Image.new('RGB', (400, 600), 'white')
        draw = ImageDraw.Draw(image)
        draw.line((10, 50, 390, 50), fill='black')
        draw.line((200, 30, 200, 300), fill='black')
        draw.rectangle((40, 80, 45, 90), fill='black')
        prepared = prepare_image(image)
        self.assertEqual(prepared.size, (1200, 1800))
        self.assertGreater(prepared.getpixel((300, 150)), 240)
        self.assertLess(prepared.getpixel((126, 255)), 20)

    def test_exif_rotation_and_size_bound(self):
        image = Image.new('RGB', (120, 240), 'white')
        image.getexif()[274] = 6
        self.assertEqual(prepare_image(image).size, (720, 360))
        with patch('PIL.ImageOps.exif_transpose', return_value=Image.new('RGB', (6000, 4000), 'white')):
            self.assertEqual(max(prepare_image(image).size), 3072)


@override_settings(CELERY_TASK_ALWAYS_EAGER=True, SECURE_SSL_REDIRECT=False)
class TaxInvoiceUploadTests(TestCase):
    def test_photo_upload_recovers_review_without_confirming_an_order(self):
        with tempfile.TemporaryDirectory() as media, override_settings(MEDIA_ROOT=media):
            image = io.BytesIO()
            Image.new('RGB', (400, 600), 'white').save(image, format='PNG')
            user = get_user_model().objects.create_user(username='invoice-recovery', email='invoice@example.invalid', password='Synthetic-Password-123!')
            client = APIClient()
            client.force_authenticate(user)
            with patch('pytesseract.image_to_string', return_value=TAX_INVOICE):
                response = client.post('/api/v1/receipts/upload/', {'file': SimpleUploadedFile('synthetic-grid.png', image.getvalue(), content_type='image/png')}, format='multipart')
            self.assertEqual(response.status_code, 202, response.data)
            receipt = Receipt.objects.get(pk=response.data['id'])
            self.assertEqual(receipt.extraction_status, 'review')
            self.assertIsNone(receipt.order_id)
            self.assertEqual(len(receipt.extracted_json['items']), 1)
            self.assertEqual(receipt.extracted_json['grand_total'], '354.00')
            self.assertFalse(any('No supported product' in warning for warning in receipt.extracted_json['warnings']))
            self.assertIn('document_amount_in_words', receipt.extracted_json['provenance'].values())
