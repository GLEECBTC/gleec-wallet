# Build the GLEEC komodo-defi-proxy at the gas-free commit and run it with a
# config rendered from environment variables at container start.
#
# Mirrors the upstream Containerfile build, but clones a pinned commit so the
# image matches what is (meant to be) deployed at quicknode.gleec.com/gasfree.

# ---------- build stage ----------
FROM docker.io/library/debian:bookworm-slim AS build

ARG PROXY_REPO=https://github.com/GLEECBTC/komodo-defi-proxy.git
ARG PROXY_COMMIT=4526f9d6322c90bb944ca5a0f24e9b547d967696

RUN apt-get update \
    && apt-get install -y build-essential curl pkg-config libssl-dev git ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN curl https://sh.rustup.rs -sSf | bash -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /usr/src
RUN git clone "$PROXY_REPO" komodo-defi-proxy \
    && cd komodo-defi-proxy \
    && git checkout "$PROXY_COMMIT"

WORKDIR /usr/src/komodo-defi-proxy
# Stock proxy — no source patches. The browser CORS handling lives in the NGINX edge
# config (../nginx/nginx.conf), not in the proxy. (gasfree-cors.patch is kept as a
# reference-only alternative; it is intentionally NOT applied.)
RUN cargo build --release

# ---------- runtime stage ----------
FROM docker.io/library/debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y ca-certificates curl gettext-base \
    && rm -rf /var/lib/apt/lists/*
RUN update-ca-certificates

COPY --from=build /usr/src/komodo-defi-proxy/target/release/komodo-defi-proxy /usr/local/bin/
# The proxy config references RSA key paths (used only for `authorized` routes,
# which the gas-free route is NOT). Reuse the repo's throwaway test keypair so
# the paths resolve.
COPY --from=build /usr/src/komodo-defi-proxy/assets/.pubkey_test /assets/.pubkey_test
COPY --from=build /usr/src/komodo-defi-proxy/assets/.privkey_test /assets/.privkey_test

COPY config.template.json /config/config.template.json
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
