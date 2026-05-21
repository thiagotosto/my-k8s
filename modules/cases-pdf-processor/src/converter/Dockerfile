FROM python:3.13-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
RUN python -c "from docling.document_converter import DocumentConverter; \
               from docling.datamodel.base_models import InputFormat; \
               DocumentConverter(allowed_formats=[InputFormat.PDF])"
COPY main.py .
CMD ["functions-framework", "--target=cases_pdf_converter", "--port=8080"]
