# Minimal runtime for the bundled linux/x86-64 KDF binary.
# The binary itself is mounted at /usr/local/bin/kdf via docker-compose (it is
# large and lives in the SDK package), so it is NOT copied into the image.
FROM docker.io/library/debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*
RUN update-ca-certificates

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /kdf
ENTRYPOINT ["/entrypoint.sh"]
