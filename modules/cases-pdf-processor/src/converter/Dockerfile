FROM python:3.13-slim
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends libxcb1 && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    && pip uninstall -y opencv-python \
    && pip install --no-cache-dir opencv-python-headless
RUN python -c "\
from docling.document_converter import DocumentConverter; \
from docling.datamodel.base_models import InputFormat; \
import tempfile, os; \
pdf = b'%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n3 0 obj<</Type/Page/MediaBox[0 0 612 792]/Parent 2 0 R>>endobj\nxref\n0 4\n0000000000 65535 f \n0000000009 00000 n \n0000000058 00000 n \n0000000115 00000 n \ntrailer<</Size 4/Root 1 0 R>>\nstartxref\n178\n%%EOF'; \
f = tempfile.NamedTemporaryFile(suffix='.pdf', delete=False); f.write(pdf); f.close(); \
DocumentConverter(allowed_formats=[InputFormat.PDF]).convert(f.name); \
os.unlink(f.name)"
COPY main.py .
CMD ["functions-framework", "--target=cases_pdf_converter", "--port=8080"]
