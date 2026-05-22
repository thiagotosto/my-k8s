import json
import os
import re
import tempfile

import functions_framework
from google.cloud import pubsub_v1, storage
from pypdf import PdfReader


@functions_framework.cloud_event
def cases_pdf_indexer(cloud_event):
    data = cloud_event.data
    print(f"Event: {data}")
    bucket_name = data["bucket"]
    file_path = data["name"]

    if not file_path.startswith("raw/cases_pdf/"):
        return

    storage_client = storage.Client()
    blob = storage_client.bucket(bucket_name).blob(file_path)

    with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as tmp:
        blob.download_to_file(tmp)
        tmp_path = tmp.name

    index = {}
    reader = PdfReader(tmp_path)
    pattern = re.compile(r"Num\. ([1-9][0-9]*) - Pág\. ([1-9][0-9]*)")
    for page_idx, page in enumerate(reader.pages):
        text = page.extract_text() or ""
        match = pattern.search(text)
        if match:
            doc_id = match.group(1)
            page_num = page_idx + 1  # 1-based
            if doc_id not in index:
                index[doc_id] = {"min_page": page_num, "max_page": page_num}
            else:
                index[doc_id]["min_page"] = min(index[doc_id]["min_page"], page_num)
                index[doc_id]["max_page"] = max(index[doc_id]["max_page"], page_num)

    publisher = pubsub_v1.PublisherClient()
    topic = os.environ["PUBSUB_TOPIC"]
    for doc_id, pages in index.items():
        message = json.dumps({
            "doc_id": doc_id,
            "min_page": pages["min_page"],
            "max_page": pages["max_page"],
            "bucket": bucket_name,
            "file_path": file_path,
        }).encode("utf-8")
        publisher.publish(topic, message).result()
