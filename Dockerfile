FROM node:24-bookworm-slim

ARG OPENCODE_VERSION=2.0.18
ARG OPENCHAMBER_VERSION=2.0.3

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    jq \
    openssh-client \
    python3 \
    build-essential \
    ripgrep \
  && rm -rf /var/lib/apt/lists/*

RUN npm install -g \
    "@opencode/cli@${OPENCODE_VERSION}" \
    "@openchamber/web@${OPENCHAMBER_VERSION}" \
  && npm cache clean --force

RUN mkdir -p \
    /workspace \
    /opt/bootstrap \
    /home/node/.config/opencode \
    /home/node/.config/openchamber \
    /home/node/.local/share/opencode \
    /home/node/.cache/opencode \
  && chown -R node:node \
    /workspace \
    /home/node

COPY opencode.jsonc /opt/bootstrap/opencode.jsonc
COPY entrypoint.sh /usr/local/bin/yolo-entrypoint

RUN chmod 0555 /usr/local/bin/yolo-entrypoint \
  && chown node:node /opt/bootstrap/opencode.jsonc

USER node
WORKDIR /workspace

ENV HOME=/home/node
ENV XDG_CONFIG_HOME=/home/node/.config
ENV XDG_DATA_HOME=/home/node/.local/share
ENV XDG_CACHE_HOME=/home/node/.cache

ENV OPENCODE_CONFIG_DIR=/home/node/.config/opencode
ENV OPENCODE_CONFIG=/home/node/.config/opencode/opencode.jsonc
ENV OPENCODE_DATA_DIR=/home/node/.local/share/opencode

ENV OPENCHAMBER_DATA_DIR=/home/node/.config/openchamber
ENV OPENCHAMBER_OPENCODE_HOSTNAME=127.0.0.1

EXPOSE 3000

ENTRYPOINT ["/usr/local/bin/yolo-entrypoint"]
