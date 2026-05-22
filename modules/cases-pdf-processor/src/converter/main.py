import base64
import json
import tempfile
from pathlib import Path

import functions_framework
from docling.datamodel.base_models import InputFormat
from docling.document_converter import DocumentConverter
from google.cloud import storage


@functions_framework.cloud_event
def cases_pdf_converter(cloud_event):
    raw = base64.b64decode(cloud_event.data["message"]["data"]).decode("utf-8")
    msg = json.loads(raw)
    print(f"Event: {msg}")
    doc_id = msg["doc_id"]
    min_page = int(msg["min_page"])
    max_page = int(msg["max_page"])
    bucket_name = msg["bucket"]
    file_path = msg["file_path"]

    storage_client = storage.Client()
    output_blob_path = f"raw/cases_md/{Path(file_path).stem}/{doc_id}.md"
    output_blob = storage_client.bucket(bucket_name).blob(output_blob_path)
    if output_blob.exists():
        return

    with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as tmp:
        storage_client.bucket(bucket_name).blob(file_path).download_to_file(tmp)
        tmp_path = tmp.name

    converter = DocumentConverter(allowed_formats=[InputFormat.PDF])
    markdown = converter.convert(
        source=tmp_path,
        page_range=(min_page, max_page),
    ).document.export_to_markdown()

    output_blob.upload_from_string(markdown, content_type="text/markdown")
