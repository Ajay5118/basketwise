import uuid
from django.conf import settings
from django.db import models


def private_path(instance, filename):
    return f'receipts/{instance.user_id}/{uuid.uuid4().hex}'


class Receipt(models.Model):
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    file = models.FileField(upload_to=private_path)
    file_hash = models.CharField(max_length=64)
    mime_type = models.CharField(max_length=30)
    extraction_status = models.CharField(max_length=20, default='queued')
    extracted_json = models.JSONField(default=dict)
    parser_version = models.CharField(max_length=30, default='synthetic-v1')
    processing_error = models.CharField(max_length=200, blank=True)
    order = models.ForeignKey('orders.Order', null=True, on_delete=models.SET_NULL)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=['user', 'file_hash'], name='unique_receipt_hash')]
