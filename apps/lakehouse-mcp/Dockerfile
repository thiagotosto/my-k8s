ARG BASE_IMAGE
FROM ${BASE_IMAGE}
WORKDIR /app
COPY pyproject.toml .
RUN uv pip install --system -r pyproject.toml
COPY server.py /app/
CMD ["python", "/app/server.py"]
