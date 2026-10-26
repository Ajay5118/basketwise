from decimal import Decimal, ROUND_HALF_UP
from django.db import transaction
from rest_framework import serializers
from .models import Order, OrderItem, Correction, PaymentTransaction, Refund


class ItemSerializer(serializers.ModelSerializer):
    def validate(self, data):
        if data.get('unit_price_derived'):
            quantity, total = data.get('quantity'), data.get('line_total')
            if quantity and total is not None:
                data['unit_price'] = (total / quantity).quantize(Decimal('.01'), rounding=ROUND_HALF_UP)
            else:
                data['unit_price'] = None
                data['unit_price_derived'] = False
        return data

    class Meta:
        model = OrderItem
        fields = ['id', 'name', 'quantity', 'unit_price', 'unit_price_derived', 'line_total', 'category']
        extra_kwargs = {k: {'min_value': Decimal('0')} for k in ['unit_price', 'line_total']}

    def validate_quantity(self, value):
        if value is not None and value <= 0:
            raise serializers.ValidationError('Quantity must be positive.')
        return value


class OrderSerializer(serializers.ModelSerializer):
    items = ItemSerializer(many=True)
    class Meta:
        model = Order
        fields = ['id', 'platform', 'external_order_id', 'order_date', 'status', 'currency', 'item_subtotal', 'handling_fee', 'delivery_fee', 'packaging_fee', 'taxes', 'discount', 'grand_total', 'refunded_amount', 'import_source', 'verification_status', 'items', 'created_at', 'updated_at']
        read_only_fields = ['refunded_amount', 'import_source', 'verification_status', 'created_at', 'updated_at']
        extra_kwargs = {k: {'min_value': Decimal('0')} for k in ['item_subtotal', 'handling_fee', 'delivery_fee', 'packaging_fee', 'taxes', 'discount', 'grand_total']}
        validators = []  # User-scoped constraint is enforced inside atomic confirmation/update.

    def validate_currency(self, value):
        if value != 'INR':
            raise serializers.ValidationError('MVP supports INR only.')
        return value

    def validate_platform(self, value):
        if value not in ['instamart', 'blinkit', 'zepto', 'bigbasket', 'other']:
            raise serializers.ValidationError('Unsupported platform.')
        return value

    def validate_status(self, value):
        if value not in ['unknown', 'delivered', 'pending', 'cancelled', 'refunded']:
            raise serializers.ValidationError('Unsupported status.')
        return value

    def validate_items(self, items):
        if not items:
            raise serializers.ValidationError('Review and enter at least one product.')
        return items

    def create(self, data):
        items = data.pop('items')
        order = Order.objects.create(**data)
        OrderItem.objects.bulk_create([OrderItem(order=order, **item) for item in items])
        return order

    @transaction.atomic
    def update(self, instance, data):
        instance = Order.objects.select_for_update().get(pk=instance.pk)
        if data.get('grand_total', instance.grand_total) < instance.refunded_amount:
            raise serializers.ValidationError('Total cannot be less than confirmed refunds.')
        Correction.objects.create(order=instance, before=OrderSerializer(instance).data)
        items = data.pop('items', None)
        for key, value in data.items():
            setattr(instance, key, value)
        instance.save()
        if items is not None:
            instance.items.all().delete()
            OrderItem.objects.bulk_create([OrderItem(order=instance, **item) for item in items])
        return instance


class PaymentSerializer(serializers.ModelSerializer):
    class Meta:
        model = PaymentTransaction
        exclude = ['user', 'source_identifier']


class RefundSerializer(serializers.ModelSerializer):
    amount = serializers.DecimalField(max_digits=12, decimal_places=2, min_value=Decimal('.01'))
    status = serializers.ChoiceField(choices=['pending', 'confirmed'])
    class Meta:
        model = Refund
        fields = ['id', 'amount', 'refund_date', 'status']
