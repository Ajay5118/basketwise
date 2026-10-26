import re
from decimal import Decimal, ROUND_HALF_UP

MONEY = r'(?:₹|Rs\.?|INR)?\s*([0-9]+(?:,[0-9]{3})*(?:\.[0-9]{1,2})?)'


def parse(text, platform='other'):
    result = {'platform': platform, 'currency': 'INR' if re.search(r'₹|\bINR\b|\bRs\.?', text, re.I) else None, 'status': 'unknown', 'external_order_id': None, 'order_date': None, 'items': [], 'provenance': {}, 'warnings': []}
    for key, labels in {'item_subtotal': ['item subtotal', 'subtotal'], 'handling_fee': ['handling fee', 'handling charge'], 'delivery_fee': ['delivery fee', 'delivery charge'], 'packaging_fee': ['packaging fee'], 'taxes': ['taxes', 'tax'], 'discount': ['discount'], 'grand_total': ['grand total', 'total paid', 'bill total']}.items():
        result[key] = None
        for label in labels:
            match = re.search(r'^\s*' + label + r'\s*:?\s*' + MONEY + r'\s*$', text, re.I | re.M)
            if match:
                result[key] = format(Decimal(match[1].replace(',', '')), '.2f')
                result['provenance'][key] = 'document'
                break
    status = re.search(r'^\s*(?:Order status\s*:\s*)?(delivered|cancelled|canceled|refunded|pending)\s*$', text, re.I | re.M)
    if status:
        result['status'] = status[1].lower().replace('canceled', 'cancelled')
    match = re.search(r'Order\s*(?:ID|number|#)\s*:?\s*([\w-]+)', text, re.I)
    if match:
        result['external_order_id'] = match[1]
    match = re.search(r'Order date\s*:\s*(\d{4}-\d{2}-\d{2})\b', text, re.I)
    if match:
        from datetime import date
        try:
            result['order_date'] = date.fromisoformat(match[1]).isoformat()
        except ValueError:
            pass
    # Deliberately narrow supported layouts; unfamiliar rows remain unknown.
    pattern = r'^(.+?)\s*(?:\|\s*|\n\s*)Quantity\s*:\s*(\d+(?:\.\d+)?)\s*(?:\|\s*|\n\s*)Line total\s*:\s*' + MONEY + r'\s*$'
    for match in re.finditer(pattern, text, re.I | re.M):
        name, quantity, total = match.groups()
        quantity, total = Decimal(quantity), Decimal(total.replace(',', ''))
        if quantity <= 0:
            continue
        result['items'].append({'name': name.strip(), 'quantity': str(quantity), 'line_total': format(total, '.2f'), 'unit_price': format((total / quantity).quantize(Decimal('.01'), rounding=ROUND_HALF_UP), '.2f'), 'unit_price_derived': True, 'category': 'Uncategorized'})
    if not result['items']:
        result['warnings'].append('No supported product rows found. Enter products manually.')
    for key in ['order_date', 'grand_total', 'item_subtotal', 'currency']:
        if result[key] is None:
            result['warnings'].append(f'{key} is unknown; review required.')
    return result
