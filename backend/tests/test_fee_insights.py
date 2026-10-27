from datetime import date
from decimal import Decimal
from unittest.mock import patch
from django.contrib.auth import get_user_model
from django.test import TestCase
from rest_framework.test import APIClient
from apps.orders.models import Order, OrderItem

TODAY = date(2026, 10, 27)


class FeeInsightsTests(TestCase):
    def setUp(self):
        self.user = get_user_model().objects.create_user(username='fees', email='fees@example.invalid', password='Synthetic-Password-123!')
        self.client = APIClient()
        self.client.force_authenticate(self.user)

    def order(self, when, platform='zepto', status='delivered', items=None, **amounts):
        order = Order.objects.create(user=self.user, order_date=when, platform=platform, status=status, grand_total=amounts.pop('grand_total', '0'), **amounts)
        for name, total in items or []:
            OrderItem.objects.create(order=order, name=name, line_total=Decimal(total))
        return order

    def insights(self, **params):
        with patch('apps.analytics.views.timezone.localdate', return_value=TODAY):
            response = self.client.get('/api/v1/analytics/fees/', params)
        self.assertEqual(response.status_code, 200, response.data)
        return response.data

    def test_month_totals_share_types_and_heavy_baskets(self):
        # Small basket: 60 of items, 9.99 + 27 + 75 of fees.
        small = self.order(TODAY.replace(day=5), item_subtotal='60', handling_fee='9.99', delivery_fee='27', other_fees='75', grand_total='171.99')
        # Subtotal unknown: item value comes from complete line totals.
        self.order(TODAY.replace(day=9), platform='blinkit', items=[('Rice', '300'), ('Dal', '140')], delivery_fee='0', handling_fee='10', grand_total='450')
        # Fees not stated at all: counted as unknown, never as zero.
        self.order(TODAY.replace(day=12), platform='instamart', item_subtotal='200', grand_total='200')
        self.order(date(2026, 9, 20), item_subtotal='500', delivery_fee='30', grand_total='530')
        self.order(TODAY.replace(day=2), status='cancelled', item_subtotal='90', delivery_fee='40', grand_total='130')
        data = self.insights()
        month = data['this_month']
        self.assertEqual((month['fees'], month['order_count'], month['fees_unknown_count']), ('121.99', 3, 1))
        self.assertEqual(month['comparable_items'], '500.00')
        self.assertEqual(month['fee_share_percent'], '24.4')
        self.assertEqual(data['last_month']['fees'], '30.00')
        self.assertEqual([row['key'] for row in data['by_type']], ['other_fees', 'delivery_fee', 'handling_fee'])
        self.assertEqual(data['by_type'][1]['amount'], '57.00')
        self.assertEqual(data['by_platform'][0], {'platform': 'zepto', 'fees': '141.99', 'orders': 2, 'average_fee': '71.00'})
        self.assertEqual(data['heavy_baskets'], {'count': 1, 'fees': '111.99', 'items': '60.00'})
        self.assertEqual(data['worst_order']['id'], small.id)
        self.assertEqual(data['monthly'], [{'label': '2026-09', 'amount': '30.00'}, {'label': '2026-10', 'amount': '121.99'}])

    def test_unknown_item_value_and_no_orders(self):
        empty = self.insights()
        self.assertEqual(empty['this_month']['fees'], '0.00')
        self.assertIsNone(empty['this_month']['fee_share_percent'])
        self.assertIsNone(empty['worst_order'])
        self.order(TODAY, items=[('Unpriced', '0')], delivery_fee='20', grand_total='20')
        OrderItem.objects.update(line_total=None)
        data = self.insights()
        self.assertEqual(data['this_month']['fees'], '20.00')
        self.assertIsNone(data['this_month']['fee_share_percent'])
        self.assertEqual(data['heavy_baskets']['count'], 0)

    def test_scoped_to_user_and_date_range(self):
        other = get_user_model().objects.create_user(username='other', email='other@example.invalid', password='Synthetic-Password-123!')
        Order.objects.create(user=other, order_date=TODAY, platform='zepto', status='delivered', grand_total='99', delivery_fee='99')
        self.order(date(2026, 8, 1), item_subtotal='100', delivery_fee='25', grand_total='125')
        self.assertEqual(self.insights()['all_time']['fees'], '25.00')
        self.assertEqual(self.insights(start='2026-09-01')['all_time']['order_count'], 0)
