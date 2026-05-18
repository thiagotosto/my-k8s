FROM apache/spark:4.0.2

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
      libgl1 \
      libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fL \
      "https://repo1.maven.org/maven2/org/lance/lance-spark-bundle-4.0_2.13/0.4.0/lance-spark-bundle-4.0_2.13-0.4.0.jar" \
      -o /opt/spark/jars/lance-spark-bundle-4.0_2.13-0.4.0.jar && \
    curl -fL \
      "https://repo1.maven.org/maven2/com/google/cloud/bigdataoss/gcs-connector/hadoop3-2.2.22/gcs-connector-hadoop3-2.2.22-shaded.jar" \
      -o /opt/spark/jars/gcs-connector-hadoop3-2.2.22-shaded.jar

RUN pip install --no-cache-dir --timeout=120 \
      torch torchvision --index-url https://download.pytorch.org/whl/cpu

RUN pip install --no-cache-dir --timeout=120 \
      sentence-transformers \
      open-clip-torch \
      Pillow \
      pylance \
      lancedb \
      pandas \
      google-cloud-storage \
      pypdf

RUN pip install --no-cache-dir --timeout=600 --retries=5 \
      docling

USER 185
