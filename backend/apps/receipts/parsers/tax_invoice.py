"""Conservative support for explicitly labelled Indian tax-invoice tables."""
import re
from decimal import Decimal, ROUND_HALF_UP

DECIMAL = re.compile(r'\d+(?:,\d{3})*\.\d{2}')
ONES = dict(zip('zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen'.split(), range(20)))
TENS = dict(zip('twenty thirty forty fifty sixty seventy eighty ninety'.split(), range(20, 100, 10)))
SCALES = {'thousand': 1000, 'lakh': 100000, 'lakhs': 100000, 'crore': 10000000, 'crores': 10000000}
TABLE_HEADERS = [r'Item\s+Description', r'\bMRP\b', r'\bDiscount\b', r'\bQty\b', r'Taxable\s+Value', r'CGST\s*\(INR\)', r'SGST\s*\(INR\)', r'\bTotal\b']


def supported_header(line):
    previous_end = 0
    for label in TABLE_HEADERS:
        match = re.search(label, line, re.I)
        if match is None or match.start() < previous_end:
            return False
        previous_end = match.end()
    return True


def number_words(text):
    words = re.findall(r'[a-z]+', text.lower().replace('-', ' '))
    if not words or words[0] == 'and' or words[-1] == 'and' or re.sub(r'[a-z\s-]', '', text.lower()):
        return None
    total = current = 0
    previous_scale = float('inf')
    previous = None
    for word in words:
        if word == 'and':
            if previous == 'and':
                return None
            previous = word
            continue
        if word in ONES or word in TENS:
            value = ONES.get(word, TENS.get(word))
            if previous in ONES or previous in TENS:
                if previous not in TENS or word not in ONES or value >= 10:
                    return None
            current += value
        elif word == 'hundred' and 0 < current < 10:
            current *= 100
        elif word in SCALES and current and SCALES[word] < previous_scale:
            previous_scale = SCALES[word]
            total += current * previous_scale
            current = 0
        else:
            return None
        previous = word
    return total + current


def total_in_words(text):
    for index, line in enumerate(text.splitlines()):
        if not re.match(r'\s*Amount\s+in\b', line, re.I):
            continue
        candidate = ' '.join(text.splitlines()[index:index + 3])
        candidate = re.sub(r'^\s*Amount\s+in\s*(?:Words\s*:?)?\s*', '', candidate, flags=re.I)
        match = re.match(r'([A-Za-z\s-]+?)\s+Rupees?\s+(?:and\s+)?([A-Za-z\s-]+?)\s+Pais[ae]\s+Only\b', candidate, re.I)
        if match:
            rupees, paise = number_words(match[1]), number_words(match[2])
            if rupees is not None and paise is not None and 0 <= paise < 100 and rupees < 10 ** 10:
                return format(Decimal(rupees) + Decimal(paise) / 100, '.2f')
    return None


def table_items(text):
    lines = text.splitlines()
    header = next((i for i, line in enumerate(lines) if supported_header(line)), None)
    if header is None:
        return []
    items = []
    for line in lines[header + 1:]:
        if re.search(r'\b(?:Amount\s+in|Terms|Conditions|Total)\b', line, re.I):
            break
        amounts = list(DECIMAL.finditer(line))
        # This schema has MRP, discount, taxable amount, tax rates/amounts and
        # a final tax-inclusive line total. Incomplete numeric rows stay unknown.
        if len(amounts) == 10 and not any(match.start() and line[match.start() - 1] == '-' for match in amounts):
            values = [Decimal(match[0].replace(',', '')) for match in amounts]
            taxable, cgst, sgst, cess_rate, additional_cess, line_total = (values[i] for i in (2, 4, 6, 7, 8, 9))
            expected_total = taxable + cgst + sgst + taxable * cess_rate / 100 + additional_cess
            if abs(expected_total - line_total) > Decimal('.02'):
                continue
            quantity_text = line[amounts[1].end():amounts[2].start()].strip(' |')
            if not re.fullmatch(r'\d+(?:\.\d+)?', quantity_text):
                continue
            quantity = Decimal(quantity_text)
            if quantity <= 0:
                continue
            name = line[:amounts[0].start()].strip(' |')
            name = re.sub(r'^\d+\s+', '', name)
            name = re.sub(r'^\d+\s+', '', name).strip(' |')
            if not name or not re.search(r'[A-Za-z]', name):
                continue
            total = line_total
            items.append({'name': name, 'quantity': str(quantity), 'line_total': format(total, '.2f'), 'unit_price': format((total / quantity).quantize(Decimal('.01'), rounding=ROUND_HALF_UP), '.2f'), 'unit_price_derived': True, 'category': 'Uncategorized'})
        elif items and not re.search(r'\bHSN\b|\d+\.\d{2}', line, re.I):
            continuation = re.sub(r'^\s*\d*\s*', '', line).strip(' |')
            if continuation and re.search(r'[A-Za-z]', continuation):
                items[-1]['name'] += ' ' + continuation
    return items


def enrich(data, text):
    if not re.search(r'\bTax\s+Invoice\b', text, re.I):
        return
    if not data['items']:
        data['items'] = table_items(text)
        if data['items']:
            data['provenance']['items'] = 'document_tax_invoice_table'
            data['warnings'].append('Tax invoice product rows were read by OCR. Check names, quantities and tax-inclusive line totals against the invoice.')
    if data['grand_total'] is None:
        total = total_in_words(text)
        if total is not None:
            data['grand_total'] = total
            data['provenance']['grand_total'] = 'document_amount_in_words'
            data['warnings'].append('Grand total was read from the invoice amount in words. Verify it against the printed total.')
