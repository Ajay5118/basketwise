from pypdf import PdfReader
from django.conf import settings
from contextlib import closing


def extract_pdf(path):
    reader = PdfReader(path)
    if reader.is_encrypted or len(reader.pages) > settings.MAX_RECEIPT_PAGES:
        raise ValueError('Unsupported PDF')
    parts = []
    for index, page in enumerate(reader.pages):
        text = page.extract_text() or ''
        if len(text.strip()) < 20:
            import pypdfium2
            import pytesseract
            pytesseract.pytesseract.tesseract_cmd = settings.TESSERACT_CMD
            with closing(pypdfium2.PdfDocument(path)) as document:
                pdf_page = document[index]
                width, height = pdf_page.get_size()
                scale = min(2, 3000 / max(width, height))
                bitmap = pdf_page.render(scale=scale)
                text = pytesseract.image_to_string(bitmap.to_pil(), config='--psm 6', timeout=25)
                bitmap.close()
                pdf_page.close()
        parts.append(text)
    return '\n'.join(parts)
