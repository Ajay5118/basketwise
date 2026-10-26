from .pdf_extractor import extract_pdf
from .image_ocr import extract_image
from .platform_detector import detect
from .parser_registry import PARSERS
from .validators import financial_warnings


def extract(path, mime_type):
    text = extract_pdf(path) if mime_type == 'application/pdf' else extract_image(path)
    if not text.strip():
        raise ValueError('No readable text found')
    data = PARSERS[detect(text)](text)
    data['warnings'].extend(financial_warnings(data))
    return data
