"""Generate a labelled synthetic PDF for manual end-to-end testing."""
from pathlib import Path
from reportlab.pdfgen.canvas import Canvas

root = Path(__file__).resolve().parent.parent
target = root / 'tests' / 'fixtures' / 'instamart.synthetic.pdf'
canvas = Canvas(str(target))
y = 800
for line in (root / 'tests' / 'fixtures' / 'instamart.txt').read_text(encoding='utf-8').splitlines():
    canvas.drawString(40, y, line.encode('ascii', errors='replace').decode())
    y -= 22
canvas.save()
print(target)
