import io
import json
import logging
import os
import re
import time
from datetime import datetime

import lancedb
import pyarrow as pa
import pypdf
from google.cloud import pubsub_v1, storage
from openai import OpenAI
from sentence_transformers import SentenceTransformer

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)


class Worker:
    def __init__(self):
        self.storage = storage.Client()
        self.subscriber = pubsub_v1.SubscriberClient()
        self.openai_client = OpenAI()
        self.st_model = SentenceTransformer("all-MiniLM-L6-v2")
        self.db = lancedb.connect(os.environ["LANCE_URI"])
        self.table = None
        self.subscription = os.environ.get(
            "PUBSUB_SUBSCRIPTION",
            "projects/jusl-496520/subscriptions/cases-summarizer-sub",
        )
        self.model_name = os.environ.get("OPENAI_MODEL", "gpt-4o-mini")
        self.bucket_name = os.environ["GCS_BUCKET"]
        self.table_name = "default$cases_summaries"

    def run(self):
        logger.info("Starting pull loop on %s", self.subscription)
        while True:
            response = self.subscriber.pull(
                request={"subscription": self.subscription, "max_messages": 1},
                timeout=30,
            )
            if not response.received_messages:
                continue
            for msg in response.received_messages:
                self.process_message(msg.message, msg.ack_id)

    def process_message(self, message, ack_id):
        start = time.time()
        try:
            data = json.loads(message.data.decode())
        except Exception as e:
            logger.error("Malformed Pub/Sub message: %s", e)
            self.subscriber.acknowledge(
                request={"subscription": self.subscription, "ack_ids": [ack_id]}
            )
            return

        bucket = data.get("bucket", self.bucket_name)
        name = data.get("name", "")
        logger.info("Received GCS object gs://%s/%s", bucket, name)

        try:
            blob = self.storage.bucket(bucket).blob(name)
            pdf_bytes = blob.download_as_bytes()
        except Exception as e:
            logger.error("Failed to download gs://%s/%s: %s", bucket, name, e)
            return

        file_stem = name.rsplit("/", 1)[-1].replace(".pdf", "")

        reader = pypdf.PdfReader(io.BytesIO(pdf_bytes))
        doc_ranges = self.extract_doc_ranges(reader)

        if not doc_ranges:
            logger.warning("No doc ranges found in %s", name)
            self.subscriber.acknowledge(
                request={"subscription": self.subscription, "ack_ids": [ack_id]}
            )
            return

        logger.info("Found %d doc_id(s) in %s", len(doc_ranges), name)

        for doc_id, p_start, p_end in doc_ranges:
            if self.is_duplicate(doc_id):
                logger.debug("Skipping duplicate doc_id=%s", doc_id)
                continue
            logger.info("Processing doc_id=%s", doc_id)
            text = self.extract_text(reader, p_start, p_end)
            if not text.strip():
                row = self._build_empty_row(doc_id, file_stem, p_start, p_end)
            else:
                llm_fields = self.classify_and_summarize(text)
                embedding = (
                    self.embed(llm_fields.get("resumo", ""))
                    if llm_fields.get("resumo")
                    else []
                )
                row = {
                    "doc_id": doc_id,
                    "file_stem": file_stem,
                    "tipo_documento": llm_fields.get("tipo_documento", ""),
                    "polo_emissor": llm_fields.get("polo_emissor", ""),
                    "data_juntada": llm_fields.get("data_juntada", None),
                    "pagina_inicio": p_start,
                    "pagina_fim": p_end,
                    "resumo": llm_fields.get("resumo", ""),
                    "resumo_embedding": embedding,
                    "processed_at": datetime.utcnow().isoformat() + "Z",
                }
            self.write_row(row)
            logger.info("Wrote doc_id=%s", doc_id)

        elapsed = time.time() - start
        logger.info("Completed %s in %.1fs", name, elapsed)
        self.subscriber.acknowledge(
            request={"subscription": self.subscription, "ack_ids": [ack_id]}
        )

    def _build_empty_row(self, doc_id, file_stem, p_start, p_end):
        return {
            "doc_id": doc_id,
            "file_stem": file_stem,
            "tipo_documento": "",
            "polo_emissor": "",
            "data_juntada": None,
            "pagina_inicio": p_start,
            "pagina_fim": p_end,
            "resumo": "",
            "resumo_embedding": [],
            "processed_at": datetime.utcnow().isoformat() + "Z",
        }

    def extract_doc_ranges(self, reader):
        pattern = re.compile(r"Num\. (\d+) - Pág\. (\d+)")
        entries = {}
        for i, page in enumerate(reader.pages):
            text = page.extract_text() or ""
            for m in pattern.finditer(text):
                doc_id = m.group(1)
                page_num = int(m.group(2))
                if doc_id not in entries:
                    entries[doc_id] = page_num

        sorted_docs = sorted(entries.items(), key=lambda x: x[1])
        total_pages = len(reader.pages)
        ranges = []
        for idx, (doc_id, p_start) in enumerate(sorted_docs):
            p_end = sorted_docs[idx + 1][1] - 1 if idx + 1 < len(sorted_docs) else total_pages
            ranges.append((doc_id, p_start, p_end))
        return ranges

    def extract_text(self, reader, p_start, p_end):
        texts = []
        for i in range(p_start - 1, min(p_end, len(reader.pages))):
            t = reader.pages[i].extract_text() or ""
            texts.append(t)
        return "\n".join(texts)

    def is_duplicate(self, doc_id):
        if self.table is None:
            return False
        try:
            results = self.table.search().where(f"doc_id = '{doc_id}'").limit(1).to_list()
            return len(results) > 0
        except Exception:
            return False

    def classify_and_summarize(self, text):
        prompt = (
            "Você é um analisador de documentos jurídicos brasileiros.\n"
            "Analise o texto fornecido e retorne exclusivamente um JSON com os campos abaixo.\n"
            "Não inclua texto fora do JSON.\n"
            "\n"
            "Campos:\n"
            "- tipo_documento: um dos valores [PETICAO_INICIAL, SENTENCA, CONTESTACAO, DESPACHO]\n"
            "- polo_emissor: um dos valores [AUTOR, REU, JUIZ, TERCEIRO]\n"
            "- data_juntada: data de juntada ou protocolo no formato YYYY-MM-DD, ou null se ausente\n"
            "- resumo: resumo estruturado em Markdown usando o template correspondente ao tipo_documento\n"
            "\n"
            "Templates por tipo_documento:\n"
            "PETICAO_INICIAL → [FATOS_CHAVE]: <fatos alegados pelo autor>\\n[TESES_JURIDICAS]: <teses jurídicas invocadas>\\n[PEDIDOS_EFETIVOS]:\\n- <item 1 (Valor: R$ X se monetário)>\\n[PROVAS_PRODUZIDAS]: <provas listadas ou anexadas>\n"
            "SENTENCA        → [PRELIMINARES_DECIDIDAS]: <preliminares decididas>\\n[FATOS_CONVENCIMENTO]: <fatos considerados provados>\\n[RATIO_DECIDENDI]: <fundamentação jurídica>\\n[DISPOSITIVO]: <parte dispositiva — resultado, condenações, custas>\n"
            "CONTESTACAO     → [PRELIMINARES_ARGUIDAS]: <preliminares arguidas>\\n[TESES_DEFESA]: <defesas de mérito>\\n[PEDIDOS_DEFESA]: <pedidos do réu>\n"
            "DESPACHO        → [TIPO_DESPACHO]: <ex: saneamento, homologação, intimação>\\n[DETERMINACOES]: <o que o juiz determinou>\\n[PRAZO]: <prazo fixado, se houver>\n"
            "\n"
            "Texto do documento:\n"
            f"{text[:12000]}"
        )

        delays = [1, 2, 4]
        for attempt, delay in enumerate(delays):
            try:
                response = self.openai_client.chat.completions.create(
                    model=self.model_name,
                    messages=[{"role": "user", "content": prompt}],
                    response_format={"type": "json_object"},
                )
                content = response.choices[0].message.content
                return json.loads(content)
            except json.JSONDecodeError:
                logger.warning("Failed to parse JSON from LLM response on attempt %d", attempt + 1)
                return {}
            except Exception as e:
                logger.warning(
                    "classify_and_summarize attempt %d failed: %s", attempt + 1, e
                )
                if attempt < len(delays) - 1:
                    time.sleep(delay)
        return {}

    def embed(self, text):
        if not text:
            return []
        vec = self.st_model.encode(text, normalize_embeddings=True)
        return vec.tolist()

    def write_row(self, row):
        schema = pa.schema([
            pa.field("doc_id", pa.string()),
            pa.field("file_stem", pa.string()),
            pa.field("tipo_documento", pa.string()),
            pa.field("polo_emissor", pa.string()),
            pa.field("data_juntada", pa.string()),
            pa.field("pagina_inicio", pa.int32()),
            pa.field("pagina_fim", pa.int32()),
            pa.field("resumo", pa.string()),
            pa.field("resumo_embedding", pa.list_(pa.float32(), 384)),
            pa.field("processed_at", pa.string()),
        ])

        if self.table is None:
            if self.table_name not in self.db.table_names():
                self.table = self.db.create_table(self.table_name, schema=schema)
            else:
                self.table = self.db.open_table(self.table_name)

        embedding = row.get("resumo_embedding", [])
        if len(embedding) != 384:
            embedding = [0.0] * 384
        row["resumo_embedding"] = embedding

        self.table.add([row])

        try:
            self.table.create_fts_index(
                "resumo", language="Portuguese", lower_case=True, stem=True, replace=False
            )
        except Exception:
            pass
        try:
            self.table.create_index(
                "resumo_embedding",
                config=lancedb.index.IvfPq(num_partitions=4, num_sub_vectors=12),
                metric="cosine",
                replace=False,
            )
        except Exception:
            pass


def main():
    worker = Worker()
    worker.run()


if __name__ == "__main__":
    main()
