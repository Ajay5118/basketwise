from .pdf_extractor import extract_pdf
from .image_ocr import extract_image_passes
from .parsers import bill_summary
from .platform_detector import detect
from .parser_registry import PARSERS
from .validators import financial_warnings


def extract(path, mime_type):
    texts = [extract_pdf(path)] if mime_type == 'application/pdf' else extract_image_passes(path)
    text = next((candidate for candidate in texts if candidate.strip()), '')
    if not text.strip():
        raise ValueError('No readable text found')
    data = PARSERS[detect(text)](text)
    bill_summary.apply(data, texts)
    data['warnings'].extend(financial_warnings(data))
    return data
