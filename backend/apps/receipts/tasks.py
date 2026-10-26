from datetime import timedelta
from celery import shared_task
from django.conf import settings
from django.utils import timezone
from .models import Receipt
from .extractor import extract
from .duplicate_detector import candidates
import tempfile
import shutil
from pathlib import Path


@shared_task
def process_receipt(receipt_id):
    if not Receipt.objects.filter(pk=receipt_id, extraction_status='queued').update(extraction_status='processing'):
        return
    receipt = Receipt.objects.get(pk=receipt_id)
    temporary_path = None
    try:
        # Storage API supports both private local volumes and private S3 objects.
        with tempfile.NamedTemporaryFile(delete=False) as temporary:
            temporary_path = Path(temporary.name)
            with receipt.file.open('rb') as source:
                shutil.copyfileobj(source, temporary)
        receipt.extracted_json = extract(str(temporary_path), receipt.mime_type)
        receipt.extracted_json['potential_duplicates'] = candidates(receipt.user, receipt.extracted_json)
        receipt.extraction_status = 'review'
        receipt.processing_error = ''
    except Exception:
        # Never put source text, filesystem paths or OCR exception payloads in logs/API.
        receipt.extraction_status = 'failed'
        receipt.processing_error = 'Extraction failed. Check document readability and OCR runtime, then retry.'
    finally:
        if temporary_path:
            temporary_path.unlink(missing_ok=True)
    receipt.save(update_fields=['extracted_json', 'extraction_status', 'processing_error'])


@shared_task
def cleanup_receipts():
    for receipt in Receipt.objects.filter(created_at__lt=timezone.now() - timedelta(days=settings.RECEIPT_RETENTION_DAYS)).exclude(file=''):
        receipt.file.delete(save=True)
