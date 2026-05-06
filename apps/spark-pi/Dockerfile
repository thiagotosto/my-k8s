FROM apache/spark:3.5.0

USER root

RUN curl -fL \
      "https://repo1.maven.org/maven2/org/lance/lance-spark-bundle-3.5_2.12/0.4.0/lance-spark-bundle-3.5_2.12-0.4.0.jar" \
      -o /opt/spark/jars/lance-spark-bundle-3.5_2.12-0.4.0.jar && \
    curl -fL \
      "https://repo1.maven.org/maven2/com/google/cloud/bigdataoss/gcs-connector/hadoop3-2.2.22/gcs-connector-hadoop3-2.2.22-shaded.jar" \
      -o /opt/spark/jars/gcs-connector-hadoop3-2.2.22-shaded.jar

USER 185
