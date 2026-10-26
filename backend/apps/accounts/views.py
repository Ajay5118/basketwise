import uuid
from django.contrib.auth import get_user_model
from django.contrib.auth.password_validation import validate_password
from django.contrib.auth.tokens import default_token_generator
from django.core.mail import send_mail
from django.core.exceptions import ValidationError as DjangoValidationError
from django.utils import timezone
from django.utils.encoding import force_bytes, force_str
from django.utils.http import urlsafe_base64_encode, urlsafe_base64_decode
from rest_framework import serializers
from rest_framework.views import APIView
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.exceptions import ValidationError
from rest_framework_simplejwt.tokens import RefreshToken
from apps.orders.serializers import OrderSerializer, PaymentSerializer, RefundSerializer
from apps.orders.models import UserBudget
from django.db import transaction
from drf_spectacular.utils import extend_schema, extend_schema_view
from drf_spectacular.types import OpenApiTypes
from config.schema import PasswordSerializer, ResetSerializer, ResetConfirmSerializer, DetailSerializer

User = get_user_model()


class RegistrationSerializer(serializers.Serializer):
    email = serializers.EmailField()
    password = serializers.CharField(min_length=8, write_only=True)
    consent = serializers.BooleanField()

    def validate(self, data):
        if not data['consent']:
            raise serializers.ValidationError({'consent': 'Consent is required to process receipts.'})
        data['email'] = data['email'].lower()
        if User.objects.filter(email__iexact=data['email']).exists():
            raise serializers.ValidationError({'email': 'This email is already registered.'})
        try:
            validate_password(data['password'])
        except DjangoValidationError as error:
            raise serializers.ValidationError({'password': error.messages})
        return data


@extend_schema_view(post=extend_schema(responses={201: OpenApiTypes.OBJECT}))
class RegisterView(APIView):
    permission_classes = [AllowAny]
    serializer_class = RegistrationSerializer
    def post(self, request):
        serializer = self.serializer_class(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        user = User.objects.create_user(username=uuid.uuid4().hex, email=data['email'], password=data['password'], consent_at=timezone.now())
        token = RefreshToken.for_user(user)
        return Response({'access': str(token.access_token), 'refresh': str(token)}, status=201)


class ProfileSerializer(serializers.ModelSerializer):
    monthly_budget = serializers.DecimalField(max_digits=12, decimal_places=2, min_value=0, allow_null=True, required=False)
    theme = serializers.ChoiceField(choices=['system', 'light', 'dark'], required=False)
    class Meta:
        model = User
        fields = ['id', 'email', 'monthly_budget', 'theme', 'notifications', 'consent_at']
        read_only_fields = ['id', 'email', 'consent_at']

    @transaction.atomic
    def update(self, instance, data):
        instance = super().update(instance, data)
        if 'monthly_budget' in data:
            if instance.monthly_budget is None:
                UserBudget.objects.filter(user=instance).delete()
            else:
                UserBudget.objects.update_or_create(user=instance, defaults={'monthly_limit': instance.monthly_budget})
        return instance


class ProfileView(APIView):
    serializer_class = ProfileSerializer
    def get(self, request):
        return Response(self.serializer_class(request.user).data)
    def patch(self, request):
        serializer = self.serializer_class(request.user, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)


@extend_schema_view(delete=extend_schema(request=PasswordSerializer, responses={204: None}))
class AccountView(APIView):
    def delete(self, request):
        if not request.user.check_password(request.data.get('password', '')):
            raise ValidationError({'password': 'Incorrect password.'})
        for receipt in request.user.receipt_set.all():
            receipt.file.delete(save=False)
        request.user.delete()
        return Response(status=204)


@extend_schema_view(get=extend_schema(responses=OpenApiTypes.OBJECT))
class ExportView(APIView):
    def get(self, request):
        orders = request.user.order_set.prefetch_related('items', 'refunds', 'corrections')
        response = Response({
            'profile': ProfileSerializer(request.user).data,
            'orders': [{**OrderSerializer(order).data, 'refunds': RefundSerializer(order.refunds.all(), many=True).data, 'corrections': list(order.corrections.values('before', 'created_at'))} for order in orders],
            'payments': PaymentSerializer(request.user.paymenttransaction_set.all(), many=True).data,
            'receipts': list(request.user.receipt_set.values('id', 'file_hash', 'extraction_status', 'extracted_json', 'parser_version', 'created_at')),
            'audit_events': list(request.user.auditevent_set.values('action', 'resource', 'created_at')),
        })
        response['Content-Disposition'] = 'attachment; filename="basketwise-export.json"'
        return response


@extend_schema_view(post=extend_schema(request=ResetSerializer, responses=DetailSerializer))
class PasswordResetView(APIView):
    permission_classes = [AllowAny]
    def post(self, request):
        user = User.objects.filter(email__iexact=request.data.get('email', '')).first()
        if user:
            uid = urlsafe_base64_encode(force_bytes(user.pk))
            token = default_token_generator.make_token(user)
            send_mail('BasketWise password reset', f'Enter these values in BasketWise password reset.\nUser: {uid}\nToken: {token}', None, [user.email])
        return Response({'detail': 'If the account exists, reset instructions have been sent.'})


@extend_schema_view(post=extend_schema(request=ResetConfirmSerializer, responses=DetailSerializer))
class PasswordResetConfirmView(APIView):
    permission_classes = [AllowAny]
    def post(self, request):
        try:
            user = User.objects.get(pk=force_str(urlsafe_base64_decode(request.data.get('uid', ''))))
        except (ValueError, TypeError, User.DoesNotExist, UnicodeDecodeError):
            raise ValidationError('Invalid reset request.')
        if not default_token_generator.check_token(user, request.data.get('token', '')):
            raise ValidationError('Invalid or expired reset token.')
        password = request.data.get('password', '')
        try:
            validate_password(password, user)
        except DjangoValidationError as error:
            raise ValidationError({'password': error.messages})
        user.set_password(password)
        user.save()
        for outstanding in user.outstandingtoken_set.all():
            from rest_framework_simplejwt.token_blacklist.models import BlacklistedToken
            BlacklistedToken.objects.get_or_create(token=outstanding)
        return Response({'detail': 'Password reset complete.'})
