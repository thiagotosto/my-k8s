FROM python:3.13-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY main.py .
CMD ["functions-framework", "--target=cases_pdf_indexer", "--port=8080"]
