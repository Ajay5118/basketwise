import hashlib
from django.db import transaction, IntegrityError
from django.contrib.auth import get_user_model
from django.shortcuts import get_object_or_404
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.exceptions import ValidationError
from rest_framework.parsers import MultiPartParser
from rest_framework import serializers
from rest_framework import generics
from apps.orders.models import Order, ImportEvent
from apps.orders.serializers import OrderSerializer
from .models import Receipt
from .validators import validate_upload, financial_warnings
from .tasks import process_receipt
from .duplicate_detector import candidates
from drf_spectacular.utils import extend_schema, extend_schema_view
from drf_spectacular.types import OpenApiTypes
from config.schema import UploadSerializer, ReceiptStatusSerializer


class ConfirmSerializer(OrderSerializer):
    reviewed = serializers.BooleanField()
    acknowledge_warnings = serializers.BooleanField(required=False)
    class Meta(OrderSerializer.Meta):
        fields = [*OrderSerializer.Meta.fields, 'reviewed', 'acknowledge_warnings']


def info(receipt):
    return {'id': receipt.pk, 'status': receipt.extraction_status, 'error': receipt.processing_error, 'order_id': receipt.order_id}


class ReceiptListSerializer(serializers.ModelSerializer):
    status = serializers.CharField(source='extraction_status')
    class Meta:
        model = Receipt
        fields = ['id', 'status', 'processing_error', 'order_id', 'created_at']


class ReceiptListView(generics.ListAPIView):
    serializer_class = ReceiptListSerializer
    def get_queryset(self):
        return Receipt.objects.filter(user=self.request.user).exclude(extraction_status='confirmed').order_by('-created_at')


@extend_schema_view(post=extend_schema(request=UploadSerializer, responses={202: ReceiptStatusSerializer}))
class UploadView(APIView):
    parser_classes = [MultiPartParser]
    def post(self, request):
        file = request.FILES.get('file')
        if not file:
            raise ValidationError({'file': 'Choose a receipt.'})
        mime = validate_upload(file)
        digest = hashlib.sha256(file.read()).hexdigest()
        file.seek(0)
        existing = Receipt.objects.filter(user=request.user, file_hash=digest).first()
        if existing:
            return Response(info(existing))
        with transaction.atomic():
            get_user_model().objects.select_for_update().get(pk=request.user.pk)
            existing = Receipt.objects.filter(user=request.user, file_hash=digest).first()
            if existing:
                return Response(info(existing))
            receipt = Receipt.objects.create(user=request.user, file=file, mime_type=mime, file_hash=digest)
            ImportEvent.objects.create(user=request.user, source_type='receipt', source_identifier=digest, processing_status='queued')
        try:
            process_receipt.delay(receipt.pk)
        except Exception:
            receipt.extraction_status = 'failed'
            receipt.processing_error = 'Processing queue unavailable. Retry when the worker is running.'
            receipt.save(update_fields=['extraction_status', 'processing_error'])
        receipt.refresh_from_db()
        return Response(info(receipt), status=202)


@extend_schema_view(get=extend_schema(responses=ReceiptStatusSerializer), post=extend_schema(request=ConfirmSerializer, responses=OpenApiTypes.OBJECT))
class ReceiptView(APIView):
    def get(self, request, pk, action):
        receipt = get_object_or_404(Receipt, user=request.user, pk=pk)
        return Response({**info(receipt), **({'data': receipt.extracted_json} if action == 'preview' else {})})

    def post(self, request, pk, action):
        if action == 'retry':
            receipt = get_object_or_404(Receipt, user=request.user, pk=pk)
            if not receipt.file or receipt.order_id or receipt.extraction_status in ['processing', 'queued']:
                raise ValidationError('This receipt cannot be retried.')
            receipt.extraction_status = 'queued'
            receipt.save(update_fields=['extraction_status'])
            try:
                process_receipt.delay(receipt.pk)
            except Exception:
                receipt.extraction_status = 'failed'
                receipt.processing_error = 'Processing queue unavailable.'
                receipt.save(update_fields=['extraction_status', 'processing_error'])
            return Response(info(receipt), status=202)
        if action != 'confirm':
            raise ValidationError('Unsupported action.')
        try:
            with transaction.atomic():
                get_user_model().objects.select_for_update().get(pk=request.user.pk)
                receipt = get_object_or_404(Receipt.objects.select_for_update(), user=request.user, pk=pk)
                if receipt.order_id:
                    return Response(OrderSerializer(receipt.order).data)
                if receipt.extraction_status != 'review':
                    raise ValidationError('Receipt is not ready for review.')
                if request.data.get('reviewed') is not True:
                    raise ValidationError('Explicit review is required.')
                serializer = OrderSerializer(data=request.data)
                serializer.is_valid(raise_exception=True)
                data = serializer.validated_data
                warnings = financial_warnings(data)
                potential = candidates(request.user, data)
                if (warnings or potential) and request.data.get('acknowledge_warnings') is not True:
                    raise ValidationError({'warnings': warnings, 'potential_duplicates': potential})
                external = data.get('external_order_id')
                existing = Order.objects.filter(user=request.user, platform=data.get('platform', 'other'), external_order_id=external).first() if external else None
                order = existing or serializer.save(user=request.user)
                receipt.order = order
                receipt.extraction_status = 'confirmed'
                receipt.save(update_fields=['order', 'extraction_status'])
                ImportEvent.objects.filter(user=request.user, source_identifier=receipt.file_hash).update(processing_status='confirmed')
                return Response(OrderSerializer(order).data, status=200 if existing else 201)
        except IntegrityError:
            raise ValidationError('An order with this platform and external ID already exists.')
