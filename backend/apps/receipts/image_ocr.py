from PIL import Image
import pytesseract
from django.conf import settings


def extract_image(source):
    pytesseract.pytesseract.tesseract_cmd = settings.TESSERACT_CMD
    with Image.open(source) as image:
        return pytesseract.image_to_string(image.convert('RGB'), config='--psm 6', timeout=25)
