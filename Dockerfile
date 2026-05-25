FROM debian:bookworm-slim AS builder

ARG ZOLA_VERSION=0.22.1
RUN apt-get update && apt-get install -y --no-install-recommends wget ca-certificates && \
    wget -q "https://github.com/getzola/zola/releases/download/v${ZOLA_VERSION}/zola-v${ZOLA_VERSION}-x86_64-unknown-linux-gnu.tar.gz" -O /tmp/zola.tar.gz && \
    tar -xzf /tmp/zola.tar.gz -C /usr/local/bin/ && \
    rm /tmp/zola.tar.gz && \
    apt-get purge -y wget && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

WORKDIR /site
COPY . .
RUN zola build

FROM nginx:1.27-alpine
COPY --from=builder /site/public /usr/share/nginx/html
EXPOSE 80
