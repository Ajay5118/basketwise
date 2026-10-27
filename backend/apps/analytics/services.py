from decimal import Decimal
from collections import defaultdict
from datetime import date, timedelta
from rest_framework.exceptions import ValidationError

ZERO = Decimal('0')


def scoped_orders(user, params):
    query = user.order_set.filter(verification_status='confirmed').exclude(status__in=['cancelled', 'pending', 'unknown'])
    for field, lookup in [('start', 'order_date__gte'), ('end', 'order_date__lte')]:
        if params.get(field):
            try:
                query = query.filter(**{lookup: date.fromisoformat(params[field])})
            except ValueError:
                raise ValidationError({field: 'Use YYYY-MM-DD.'})
    return query.prefetch_related('items')


def totals(orders):
    orders = list(orders)
    gross = sum((o.grand_total for o in orders), ZERO)
    refunds = sum((o.refunded_amount for o in orders), ZERO)
    result = {'gross_spending': gross, 'net_spending': gross-refunds, 'confirmed_refunds': refunds, 'order_count': len(orders), 'average_order_value': (gross/len(orders)).quantize(Decimal('.01')) if orders else ZERO}
    for field in ['item_subtotal', 'handling_fee', 'delivery_fee', 'other_fees', 'discount']:
        known = [getattr(o, field) for o in orders if getattr(o, field) is not None]
        result[field] = sum(known, ZERO)
        result[field + '_unknown_count'] = len(orders) - len(known)
    return {k: format(v, '.2f') if isinstance(v, Decimal) else v for k, v in result.items()}


def grouped(orders, kind):
    groups = defaultdict(lambda: ZERO)
    for order in orders:
        if kind == 'categories':
            for item in order.items.all():
                if item.line_total is not None:
                    groups[item.category] += item.line_total
            continue
        key = order.platform if kind == 'platforms' else order.order_date.strftime('%Y-%m')
        if kind == 'weekly':
            key = (order.order_date-timedelta(days=order.order_date.weekday())).isoformat()
        groups[key] += order.grand_total - order.refunded_amount
    values = sorted(groups.items(), key=lambda entry: -entry[1]) if kind in ['categories', 'platforms'] else sorted(groups.items())
    return [{'label': key, 'amount': format(value, '.2f')} for key, value in values]


def products(orders):
    groups = defaultdict(lambda: {'orders': 0, 'quantity': ZERO, 'quantity_unknown': 0, 'spending': ZERO})
    for order in orders:
        seen = set()
        for item in order.items.all():
            row = groups[item.name]
            if item.name not in seen:
                row['orders'] += 1
                seen.add(item.name)
            if item.quantity is None:
                row['quantity_unknown'] += 1
            else:
                row['quantity'] += item.quantity
            if item.line_total is not None:
                row['spending'] += item.line_total
    return [{'name': name, **{key: str(value) if isinstance(value, Decimal) else value for key, value in row.items()}} for name, row in sorted(groups.items(), key=lambda entry: -entry[1]['orders'])[:20]]


FEE_TYPES = [('delivery_fee', 'Delivery'), ('handling_fee', 'Handling'), ('packaging_fee', 'Packaging'), ('other_fees', 'Small cart, surge & other')]
HEAVY_SHARE = Decimal('0.5')


def order_fees(order):
    known = [getattr(order, field) for field, _ in FEE_TYPES if getattr(order, field) is not None]
    return sum(known, ZERO) if known else None


def item_value(order):
    if order.item_subtotal is not None:
        return order.item_subtotal
    items = list(order.items.all())
    if items and all(item.line_total is not None for item in items):
        return sum((item.line_total for item in items), ZERO)
    return None


def fee_summary(orders):
    """Fees are summed where stated; the share uses only orders with both fees and item value."""
    fees = ZERO
    unknown = 0
    comparable_fees = comparable_items = ZERO
    for order in orders:
        paid = order_fees(order)
        if paid is None:
            unknown += 1
            continue
        fees += paid
        value = item_value(order)
        if value is not None:
            comparable_fees += paid
            comparable_items += value
    share = (comparable_fees / comparable_items * 100).quantize(Decimal('.1')) if comparable_items else None
    return {'fees': format(fees, '.2f'), 'order_count': len(orders), 'fees_unknown_count': unknown,
            'comparable_items': format(comparable_items, '.2f'), 'fee_share_percent': str(share) if share is not None else None}


def fee_insights(orders, today):
    orders = list(orders)
    first = today.replace(day=1)
    last_first = (first - timedelta(days=1)).replace(day=1)
    this_month = [o for o in orders if o.order_date >= first]
    last_month = [o for o in orders if last_first <= o.order_date < first]
    by_type = []
    for field, label in FEE_TYPES:
        known = [getattr(o, field) for o in orders if getattr(o, field) is not None]
        if known:
            by_type.append({'key': field, 'label': label, 'amount': format(sum(known, ZERO), '.2f'), 'order_count': len(known)})
    by_type.sort(key=lambda row: -Decimal(row['amount']))
    platforms = defaultdict(lambda: {'fees': ZERO, 'orders': 0})
    months = defaultdict(lambda: ZERO)
    heavy = []
    for order in orders:
        paid = order_fees(order)
        if paid is None:
            continue
        row = platforms[order.platform]
        row['fees'] += paid
        row['orders'] += 1
        months[order.order_date.strftime('%Y-%m')] += paid
        value = item_value(order)
        if value and paid >= value * HEAVY_SHARE:
            heavy.append((order, paid, value))
    worst = max(heavy, key=lambda entry: entry[1] / entry[2], default=None)
    return {
        'this_month': fee_summary(this_month),
        'last_month': fee_summary(last_month),
        'all_time': fee_summary(orders),
        'by_type': by_type,
        'by_platform': sorted(({'platform': key, 'fees': format(row['fees'], '.2f'), 'orders': row['orders'], 'average_fee': format((row['fees'] / row['orders']).quantize(Decimal('.01')), '.2f')} for key, row in platforms.items()), key=lambda row: -Decimal(row['average_fee'])),
        'monthly': [{'label': key, 'amount': format(value, '.2f')} for key, value in sorted(months.items())[-6:]],
        'heavy_baskets': {'count': len(heavy), 'fees': format(sum((paid for _, paid, _ in heavy), ZERO), '.2f'), 'items': format(sum((value for _, _, value in heavy), ZERO), '.2f')},
        'worst_order': {'id': worst[0].id, 'order_date': worst[0].order_date.isoformat(), 'platform': worst[0].platform, 'fees': format(worst[1], '.2f'), 'items': format(worst[2], '.2f')} if worst else None,
    }
