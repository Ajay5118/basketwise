from django.contrib.auth.models import AbstractUser
from django.db import models
from django.db.models.functions import Lower


class User(AbstractUser):
    email = models.EmailField(unique=True)
    consent_at = models.DateTimeField(null=True)
    monthly_budget = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True)
    theme = models.CharField(max_length=10, default='system')
    notifications = models.BooleanField(default=False)
    USERNAME_FIELD = 'email'
    REQUIRED_FIELDS = ['username']

    class Meta(AbstractUser.Meta):
        constraints = [models.UniqueConstraint(Lower('email'), name='unique_normalized_email')]


class AuditEvent(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE)
    action = models.CharField(max_length=10)
    resource = models.CharField(max_length=80)
    created_at = models.DateTimeField(auto_now_add=True)
