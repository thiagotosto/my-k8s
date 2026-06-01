FROM python:3.13-slim
RUN pip install uv
WORKDIR /app
COPY pyproject.toml .
RUN uv pip install --system -r pyproject.toml
RUN python -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('all-MiniLM-L6-v2')"
COPY worker.py /app/
CMD ["python", "/app/worker.py"]
