from datetime import date, timedelta
from decimal import Decimal
from django.utils import timezone
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.exceptions import NotFound
from .services import scoped_orders, totals, grouped, products, fee_insights
from drf_spectacular.utils import extend_schema, extend_schema_view
from drf_spectacular.types import OpenApiTypes


@extend_schema_view(get=extend_schema(responses=OpenApiTypes.OBJECT))
class AnalyticsView(APIView):
    def get(self, request, kind):
        if kind not in ['overview', 'monthly', 'weekly', 'platforms', 'categories', 'products', 'fees']:
            raise NotFound()
        orders = scoped_orders(request.user, request.query_params)
        if kind == 'products':
            return Response(products(orders))
        if kind == 'fees':
            return Response(fee_insights(orders, timezone.localdate()))
        if kind != 'overview':
            return Response(grouped(orders, kind))
        first = timezone.localdate().replace(day=1)
        next_first = (first.replace(day=28) + timedelta(days=4)).replace(day=1)
        last = first-timedelta(days=1)
        current = totals(orders.filter(order_date__gte=first, order_date__lt=next_first))
        previous = totals(orders.filter(order_date__gte=last.replace(day=1), order_date__lte=last))
        old = Decimal(previous['net_spending'])
        change = ((Decimal(current['net_spending'])-old)/old*100).quantize(Decimal('.01')) if old else None
        return Response({**totals(orders), 'this_month': current, 'last_month': previous, 'change_percent': str(change) if change is not None else None, 'platforms': grouped(orders, 'platforms')})
