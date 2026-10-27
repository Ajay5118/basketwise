from django.conf import settings
from django.db import models
from django.db.models import Q


class Platform(models.Model):
    name = models.CharField(max_length=80)
    slug = models.SlugField(unique=True)
    logo_reference = models.CharField(max_length=200, blank=True)


class Order(models.Model):
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    platform = models.CharField(max_length=30, default='other')
    external_order_id = models.CharField(max_length=100, null=True, blank=True)
    order_date = models.DateField()
    status = models.CharField(max_length=20, default='unknown')
    currency = models.CharField(max_length=3, default='INR')
    item_subtotal = models.DecimalField(max_digits=12, decimal_places=2, null=True)
    handling_fee = models.DecimalField(max_digits=12, decimal_places=2, null=True)
    delivery_fee = models.DecimalField(max_digits=12, decimal_places=2, null=True)
    packaging_fee = models.DecimalField(max_digits=12, decimal_places=2, null=True)
    other_fees = models.DecimalField(max_digits=12, decimal_places=2, null=True)
    taxes = models.DecimalField(max_digits=12, decimal_places=2, null=True)
    discount = models.DecimalField(max_digits=12, decimal_places=2, null=True)
    grand_total = models.DecimalField(max_digits=12, decimal_places=2)
    refunded_amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    import_source = models.CharField(max_length=20, default='receipt')
    verification_status = models.CharField(max_length=20, default='confirmed')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-order_date', '-id']
        indexes = [models.Index(fields=['user', 'order_date']), models.Index(fields=['user', 'platform'])]
        constraints = [models.UniqueConstraint(fields=['user', 'platform', 'external_order_id'], condition=Q(external_order_id__isnull=False) & ~Q(external_order_id=''), name='unique_external_order'), models.CheckConstraint(condition=Q(grand_total__gte=0), name='nonnegative_total')]


class OrderItem(models.Model):
    order = models.ForeignKey(Order, related_name='items', on_delete=models.CASCADE)
    name = models.CharField(max_length=300)
    quantity = models.DecimalField(max_digits=10, decimal_places=3, null=True)
    unit_price = models.DecimalField(max_digits=12, decimal_places=2, null=True)
    unit_price_derived = models.BooleanField(default=False)
    line_total = models.DecimalField(max_digits=12, decimal_places=2, null=True)
    category = models.CharField(max_length=80, default='Uncategorized')


class Refund(models.Model):
    order = models.ForeignKey(Order, related_name='refunds', on_delete=models.CASCADE)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    refund_date = models.DateField()
    status = models.CharField(max_length=20, default='pending')


class Correction(models.Model):
    order = models.ForeignKey(Order, related_name='corrections', on_delete=models.CASCADE)
    before = models.JSONField()
    created_at = models.DateTimeField(auto_now_add=True)


class PaymentTransaction(models.Model):
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    merchant = models.CharField(max_length=80)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    transaction_date = models.DateField()
    source = models.CharField(max_length=30, default='bank_alert')
    source_identifier = models.CharField(max_length=128)
    payment_method = models.CharField(max_length=30, default='unknown')
    status = models.CharField(max_length=30, default='payment_detected')
    linked_order = models.ForeignKey(Order, null=True, on_delete=models.SET_NULL)
    verification_status = models.CharField(max_length=20, default='unverified')

    class Meta:
        constraints = [models.UniqueConstraint(fields=['user', 'source_identifier'], name='unique_payment_source')]


class ImportEvent(models.Model):
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    source_type = models.CharField(max_length=30)
    source_identifier = models.CharField(max_length=128)
    processing_status = models.CharField(max_length=30)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=['user', 'source_type', 'source_identifier'], name='unique_import_event')]


class UserBudget(models.Model):
    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    monthly_limit = models.DecimalField(max_digits=12, decimal_places=2)
    alert_threshold = models.DecimalField(max_digits=4, decimal_places=2, default='0.80')
