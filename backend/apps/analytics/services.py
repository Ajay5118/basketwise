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
    for field in ['item_subtotal', 'handling_fee', 'delivery_fee', 'discount']:
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
