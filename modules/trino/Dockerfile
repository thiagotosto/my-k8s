FROM alpine:3.21 AS downloader
RUN apk add --no-cache curl && \
    mkdir -p /tmp/lance && \
    curl -fL "https://github.com/lancedb/lance-trino/releases/download/v0.2.2-beta.1/lance-trino-0.2.2-beta.1-trino476.tar.gz" \
      | tar -xz --strip-components=1 -C /tmp/lance/

FROM trinodb/trino:476
USER root
COPY --from=downloader /tmp/lance/ /usr/lib/trino/plugin/lance/
USER trino
