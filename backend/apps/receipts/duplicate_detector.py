from apps.orders.models import Order


def candidates(user, data):
    query = Order.objects.filter(user=user, platform=data.get('platform'), order_date=data.get('order_date'), grand_total=data.get('grand_total'))
    return list(query.values_list('id', flat=True)) if data.get('order_date') and data.get('grand_total') else []
