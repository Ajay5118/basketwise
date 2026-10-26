import hashlib
import re
from datetime import datetime
from decimal import Decimal
from django.db import transaction, IntegrityError
from django.db.models import Q
from django.shortcuts import get_object_or_404
from rest_framework import generics
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.exceptions import ValidationError
from .models import Order, PaymentTransaction, Refund
from .serializers import OrderSerializer, PaymentSerializer, RefundSerializer
from apps.receipts.platform_detector import detect
from drf_spectacular.utils import extend_schema, extend_schema_view
from config.schema import AlertSerializer, LinkSerializer


class OrderListView(generics.ListAPIView):
    serializer_class = OrderSerializer
    def get_queryset(self):
        query = Order.objects.filter(user=self.request.user).prefetch_related('items')
        params = self.request.query_params
        for key in ['platform', 'status', 'import_source']:
            if params.get(key):
                query = query.filter(**{key: params[key]})
        for key, lookup in [('start', 'order_date__gte'), ('end', 'order_date__lte')]:
            if params.get(key):
                try:
                    query = query.filter(**{lookup: datetime.strptime(params[key], '%Y-%m-%d').date()})
                except ValueError:
                    raise ValidationError({key: 'Use YYYY-MM-DD.'})
        for key, lookup in [('min_amount', 'grand_total__gte'), ('max_amount', 'grand_total__lte')]:
            if params.get(key):
                try:
                    amount = Decimal(params[key])
                    if not amount.is_finite():
                        raise ValueError()
                    query = query.filter(**{lookup: amount})
                except Exception:
                    raise ValidationError({key: 'Invalid amount.'})
        if params.get('search'):
            term = params['search'][:200]
            query = query.filter(Q(items__name__icontains=term) | Q(external_order_id__icontains=term) | Q(platform__icontains=term)).distinct()
        return query


class OrderDetailView(generics.RetrieveUpdateDestroyAPIView):
    serializer_class = OrderSerializer
    http_method_names = ['get', 'patch', 'delete', 'head', 'options']
    def get_queryset(self):
        return Order.objects.filter(user=self.request.user).prefetch_related('items')
    def perform_destroy(self, instance):
        instance.receipt_set.update(extraction_status='review')
        instance.delete()
    def retrieve(self, request, *args, **kwargs):
        order = self.get_object()
        return Response({**self.get_serializer(order).data, 'corrections': list(order.corrections.values('before', 'created_at')), 'refunds': RefundSerializer(order.refunds.all(), many=True).data})
    def update(self, request, *args, **kwargs):
        try:
            return super().update(request, *args, **kwargs)
        except IntegrityError:
            raise ValidationError('An order with this platform and external ID already exists.')


class RefundView(APIView):
    serializer_class = RefundSerializer
    @transaction.atomic
    def post(self, request, pk):
        order = get_object_or_404(Order.objects.select_for_update(), user=request.user, pk=pk)
        serializer = self.serializer_class(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        if data['status'] == 'confirmed':
            if order.refunded_amount + data['amount'] > order.grand_total:
                raise ValidationError('Refund exceeds remaining order total.')
            order.refunded_amount += data['amount']
            order.save(update_fields=['refunded_amount', 'updated_at'])
        serializer.save(order=order)
        return Response(serializer.data, status=201)


class PaymentListView(generics.ListAPIView):
    serializer_class = PaymentSerializer
    def get_queryset(self):
        return PaymentTransaction.objects.filter(user=self.request.user).order_by('-transaction_date', '-id')


@extend_schema_view(post=extend_schema(request=AlertSerializer, responses=PaymentSerializer))
class PaymentImportView(APIView):
    def post(self, request):
        alert = AlertSerializer(data=request.data)
        alert.is_valid(raise_exception=True)
        text = request.data.get('text', '')
        if not isinstance(text, str) or len(text) > 4000:
            raise ValidationError('Alert must contain at most 4000 characters.')
        amount = re.search(r'(?:Rs\.?|INR|₹)\s*([\d,]+(?:\.\d{1,2})?)\s+is\s+debited', text, re.I)
        date = re.search(r'\bon\s+(\d{2}-\d{2}-\d{2,4})\b', text, re.I)
        if not amount or not date:
            raise ValidationError('Unsupported alert. Expected debit amount and DD-MM-YY date.')
        try:
            when = datetime.strptime(date[1], '%d-%m-%y' if len(date[1]) == 8 else '%d-%m-%Y').date()
        except ValueError:
            raise ValidationError('Invalid transaction date.')
        identifier = request.data.get('source_identifier') or hashlib.sha256(text.strip().encode()).hexdigest()
        if not isinstance(identifier, str) or len(identifier) > 128:
            raise ValidationError('Invalid source identifier.')
        value = Decimal(amount[1].replace(',', ''))
        if value <= 0 or value > Decimal('9999999999.99'):
            raise ValidationError('Debit amount is outside supported limits.')
        payment, created = PaymentTransaction.objects.get_or_create(user=request.user, source_identifier=identifier, defaults={'merchant': detect(text), 'amount': value, 'transaction_date': when, 'payment_method': 'UPI' if re.search(r'\b(VPA|UPI)\b', text, re.I) else 'unknown'})
        return Response(PaymentSerializer(payment).data, status=201 if created else 200)


@extend_schema_view(post=extend_schema(request=LinkSerializer, responses=PaymentSerializer))
class PaymentLinkView(APIView):
    def post(self, request, pk):
        link = LinkSerializer(data=request.data)
        link.is_valid(raise_exception=True)
        payment = get_object_or_404(PaymentTransaction, user=request.user, pk=pk)
        order = get_object_or_404(Order, user=request.user, pk=link.validated_data['order'])
        if order.grand_total != payment.amount or payment.merchant not in ['other', order.platform]:
            raise ValidationError('Merchant or amount does not match this order.')
        payment.linked_order = order
        payment.verification_status = 'confirmed'
        payment.save()
        return Response(PaymentSerializer(payment).data)
