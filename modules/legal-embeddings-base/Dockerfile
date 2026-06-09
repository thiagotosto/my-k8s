FROM python:3.13-slim
RUN pip install uv
RUN uv pip install --system sentence-transformers
RUN python -c "from sentence_transformers import SentenceTransformer; m = SentenceTransformer('rufimelo/Legal-BERTimbau-base'); print('dim:', m.get_sentence_embedding_dimension())"
