import io
import shutil
import tempfile
from pathlib import Path
from unittest import skipUnless
from django.conf import settings
from django.test import SimpleTestCase
import pypdfium2
from contextlib import closing
from apps.receipts.image_ocr import extract_image
from apps.receipts.pdf_extractor import extract_pdf
from apps.receipts.parser_registry import PARSERS
from .test_pipeline import pdf_bytes


@skipUnless(shutil.which(settings.TESSERACT_CMD), 'Real Tesseract executable unavailable; OCR runtime coverage not established.')
class OCRRuntimeTests(SimpleTestCase):
    def test_real_image_ocr(self):
        with closing(pypdfium2.PdfDocument(pdf_bytes())) as pdf:
            page = pdf[0]
            bitmap = page.render(scale=3)
            image = bitmap.to_pil().copy()
            bitmap.close()
            page.close()
        buffer = io.BytesIO()
        image.save(buffer, format='PNG')
        buffer.seek(0)
        result = PARSERS['instamart'](extract_image(buffer))
        self.assertEqual(result['grand_total'], '286.00')
        self.assertEqual(len(result['items']), 2)

    def test_real_scanned_pdf_ocr(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'scanned.pdf'
            with closing(pypdfium2.PdfDocument(pdf_bytes())) as pdf:
                page = pdf[0]
                bitmap = page.render(scale=2)
                image = bitmap.to_pil().convert('RGB')
                image.save(path, format='PDF', resolution=144)
                bitmap.close()
                page.close()
            result = PARSERS['instamart'](extract_pdf(str(path)))
            self.assertEqual(result['grand_total'], '286.00')
