"""App "Bill Summary" screenshots: labelled fee rows and a "To Pay" total, no products.

OCR rarely knows the rupee glyph and reads it as '2', '7', '=', '<', '£' and similar.
Each OCR pass votes for readings of every row; a leading 2/7 without a currency mark
is ambiguous and is only resolved when exactly one reading reconciles with the total.
"""
import re
from decimal import Decimal
from itertools import product

LABELS = {
    'item_subtotal': ['item total', 'item subtotal', 'items total'],
    'handling_fee': ['handling charge', 'handling fee'],
    'delivery_fee': ['delivery fee', 'delivery charge', 'delivery partner fee'],
    'packaging_fee': ['packaging fee', 'packaging charge'],
    'small_cart_fee': ['small cart fee', 'small cart charge'],
    'surge_fee': ['surge fee', 'surge charge', 'rain fee', 'late night fee', 'platform fee', 'convenience fee'],
    'grand_total': ['to pay', 'grand total', 'total paid', 'bill total', 'amount paid'],
}
MARKERS = re.compile(r'bill summary|^\W*to pay\b|^\W*item total\b', re.I | re.M)
AMOUNT = re.compile(r'(₹|rs\.?|inr|[^\w\s.,])?\s?(\d[\d,]*(?:\.\d{1,2})?)(?![\d.])', re.I)
GLYPH_DIGITS = '27'
COMPONENTS = ['item_subtotal', 'handling_fee', 'delivery_fee', 'packaging_fee', 'small_cart_fee', 'surge_fee']


def applies(texts):
    return any(MARKERS.search(text) for text in texts)


def readings(token_prefix, digits):
    value = Decimal(digits.replace(',', ''))
    if token_prefix or len(digits.split('.')[0]) < 2 or digits[0] not in GLYPH_DIGITS:
        return {value}
    return {value, Decimal(digits[1:].replace(',', ''))}


def row_candidates(text):
    rows = {}
    for raw in text.splitlines():
        line = re.sub(r'[!|]', 'l', raw).strip().lower()
        for key, labels in LABELS.items():
            label = next((label for label in labels if re.match(r'^\W*' + label + r'\b', line)), None)
            if not label:
                continue
            amounts = AMOUNT.findall(line[line.index(label) + len(label):])
            # A struck-through original price precedes the charged price; keep the last.
            if amounts and len(amounts) <= 2:
                rows.setdefault(key, []).append(readings(*amounts[-1]))
            break
    return rows


def vote(texts):
    votes = {}
    for text in texts:
        for key, sets in row_candidates(text).items():
            tally = votes.setdefault(key, {})
            for value in set().union(*sets):
                tally[value] = tally.get(value, 0) + 1
    result = {}
    for key, tally in votes.items():
        best = max(tally.values())
        result[key] = sorted(value for value, count in tally.items() if count == best)
    return result


def reconcile(options):
    """Return chosen values and 'reconciled', 'ambiguous', 'mismatch' or 'unchecked'."""
    single = {key: values[0] if len(values) == 1 else None for key, values in options.items()}
    keys = [key for key in COMPONENTS if key in options]
    if 'grand_total' not in options or not keys:
        return single, 'ambiguous' if None in single.values() else 'unchecked'
    solutions = []
    for total in options['grand_total']:
        for combo in product(*(options[key] for key in keys)):
            if abs(sum(combo) - total) <= Decimal('.01'):
                solutions.append({'grand_total': total, **dict(zip(keys, combo))})
    if not solutions:
        return single, 'ambiguous' if None in single.values() else 'mismatch'
    chosen = {}
    for key in ['grand_total', *keys]:
        values = {solution[key] for solution in solutions}
        chosen[key] = values.pop() if len(values) == 1 else None
    return chosen, 'reconciled' if len(solutions) == 1 else 'ambiguous'


def apply(data, texts):
    if not applies(texts):
        return data
    values, outcome = reconcile(vote(texts))
    if not values:
        return data
    for key in ['item_subtotal', 'handling_fee', 'delivery_fee', 'packaging_fee', 'grand_total']:
        value = values.get(key)
        data[key] = format(value, '.2f') if value is not None else None
        if value is not None:
            data['provenance'][key] = 'document_bill_summary'
        else:
            data['provenance'].pop(key, None)
    extras = [values[key] for key in ['small_cart_fee', 'surge_fee'] if key in values]
    data['other_fees'] = format(sum(extras), '.2f') if extras and None not in extras else None
    if data['other_fees'] is not None:
        data['provenance']['other_fees'] = 'document_bill_summary'
    data['warnings'] = [w for w in data['warnings'] if not w.startswith('Please confirm')]
    data['warnings'].append({
        'reconciled': 'Amounts were read from a bill summary and add up to the total. Check them against your screenshot.',
        'ambiguous': 'Some bill summary amounts could not be read reliably and were left blank. Fill them from your screenshot.',
        'mismatch': 'Bill summary amounts do not add up to the total. Check each fee against your screenshot.',
        'unchecked': 'Bill summary amounts were read by OCR without a total to check them. Verify each one.',
    }[outcome])
    if not data['items']:
        data['warnings'] = [w for w in data['warnings'] if not w.startswith('No supported product rows')]
        data['warnings'].append('A bill summary does not list products. Add what you bought, using the category shortcuts.')
    missing = [label for key, label in [('order_date', 'purchase date'), ('grand_total', 'total paid')] if data.get(key) is None]
    if missing:
        data['warnings'].append(f"Please confirm {' and '.join(missing)} before saving.")
    return data
