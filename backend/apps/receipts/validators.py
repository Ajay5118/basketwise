from decimal import Decimal
from io import BytesIO
from PIL import Image
from pypdf import PdfReader
from django.conf import settings
from rest_framework.exceptions import ValidationError


def validate_upload(file):
    if file.size > settings.MAX_RECEIPT_BYTES:
        raise ValidationError({'file': 'Maximum receipt size is 10 MB.'})
    data = file.read()
    file.seek(0)
    try:
        if data.startswith(b'%PDF-'):
            pdf = PdfReader(BytesIO(data), strict=True)
            if pdf.is_encrypted or not 1 <= len(pdf.pages) <= settings.MAX_RECEIPT_PAGES:
                raise ValueError()
            # Reject active and embedded payloads.
            if any(token in data for token in (b'/JavaScript', b'/JS', b'/Launch', b'/EmbeddedFile', b'/OpenAction')):
                raise ValueError()
            return 'application/pdf'
        with Image.open(BytesIO(data)) as image:
            if image.format not in ('JPEG', 'PNG') or image.width * image.height > 25_000_000:
                raise ValueError()
            kind = image.format
            image.verify()
        return 'image/jpeg' if kind == 'JPEG' else 'image/png'
    except Exception:
        raise ValidationError({'file': 'Invalid, unsafe or unsupported document. Use PNG, JPEG or a PDF of at most 10 pages.'})


def financial_warnings(data):
    warnings = []
    items = data.get('items', [])
    subtotal = data.get('item_subtotal')
    total = data.get('grand_total')
    if subtotal is not None and items and all(i.get('line_total') is not None for i in items):
        if abs(sum(Decimal(str(i['line_total'])) for i in items) - Decimal(str(subtotal))) > Decimal('.01'):
            warnings.append('Product totals do not equal item subtotal.')
    fields = ['item_subtotal', 'handling_fee', 'delivery_fee', 'packaging_fee', 'taxes', 'discount']
    if total is not None and all(data.get(f) is not None for f in fields):
        # Most invoices have no extra fees, so other_fees only joins the sum when stated.
        calculated = sum(Decimal(str(data[f])) for f in fields[:-1]) + Decimal(str(data.get('other_fees') or 0)) - Decimal(str(data['discount']))
        if abs(calculated - Decimal(str(total))) > Decimal('.01'):
            warnings.append('Fees, discount and subtotal do not reconcile with grand total.')
    return warnings
