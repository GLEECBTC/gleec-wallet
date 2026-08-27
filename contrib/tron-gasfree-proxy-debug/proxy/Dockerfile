# Build the GLEEC komodo-defi-proxy fixed branch and run it with a config
# rendered from environment variables at container start.
#
# Mirrors the upstream Containerfile build, but clones a pinned commit so the
# image matches the intended quicknode.gleec.com/gasfree deployment baseline.

# ---------- build stage ----------
FROM docker.io/library/debian:bookworm-slim AS build

ARG PROXY_REPO=https://github.com/GLEECBTC/komodo-defi-proxy.git
ARG PROXY_COMMIT=45c9a06e6a98c611520317933414113480530b60

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
# Fixed proxy branch — no local source patches. Browser response CORS still lives in
# the NGINX edge config (../nginx/nginx.conf). gasfree-cors.patch is kept only as
# a reference alternative for deployments without edge CORS.
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
