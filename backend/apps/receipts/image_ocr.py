from PIL import Image, ImageOps
import pytesseract
from django.conf import settings


def prepare_image(image):
    """Keep tiny invoice text readable without sending images off-device."""
    image = ImageOps.exif_transpose(image)
    # A bounded working image prevents large phone photos dominating worker RAM.
    image.thumbnail((3072, 3072))
    if image.mode in ('RGBA', 'LA') or 'transparency' in image.info:
        rgba = image.convert('RGBA')
        background = Image.new('RGBA', rgba.size, 'white')
        image = Image.alpha_composite(background, rgba)
    image = ImageOps.grayscale(image)
    pixels = image.load()
    # Remove only uninterrupted, long dark rules. Table borders otherwise cause
    # Tesseract to join a whole invoice into a few unusable text lines.
    for horizontal in (True, False):
        rows, columns = (image.height, image.width) if horizontal else (image.width, image.height)
        minimum = max(30, int(columns * (.15 if horizontal else .03)))
        for row in range(rows):
            start = None
            for column in range(columns + 1):
                dark = column < columns and (pixels[column, row] if horizontal else pixels[row, column]) < 160
                if dark and start is None:
                    start = column
                if not dark and start is not None:
                    if column - start >= minimum:
                        for position in range(start, column):
                            if horizontal:
                                pixels[position, row] = 255
                            else:
                                pixels[row, position] = 255
                    start = None
    scale = min(3, 3072 / max(image.size))
    if scale > 1:
        image = image.resize((round(image.width * scale), round(image.height * scale)), Image.Resampling.BICUBIC)
    return image


def ocr_prepared(prepared):
    return pytesseract.image_to_string(prepared, config='--psm 6 -c preserve_interword_spaces=1', timeout=25)


def extract_image(source):
    pytesseract.pytesseract.tesseract_cmd = settings.TESSERACT_CMD
    with Image.open(source) as image:
        return ocr_prepared(prepare_image(image))


def extract_image_passes(source):
    """Prepared pass first (gridded invoices), then plain passes that keep app screenshots legible."""
    pytesseract.pytesseract.tesseract_cmd = settings.TESSERACT_CMD
    with Image.open(source) as image:
        prepared = prepare_image(image)
        plain = ImageOps.grayscale(ImageOps.exif_transpose(image))
    plain.thumbnail((3072, 3072))
    passes = [ocr_prepared(prepared)]
    if max(plain.size) <= 1600:
        upscaled = plain.resize((plain.width * 2, plain.height * 2), Image.Resampling.LANCZOS)
        passes.append(pytesseract.image_to_string(plain, config='--psm 6', timeout=20))
        passes.append(pytesseract.image_to_string(upscaled, config='--psm 4', timeout=20))
    else:
        passes.append(pytesseract.image_to_string(plain, config='--psm 4', timeout=25))
    return passes
