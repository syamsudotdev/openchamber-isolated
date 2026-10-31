FROM node:26-trixie-slim

ARG OPENCODE_VERSION=2.2.5
ARG OPENCHAMBER_VERSION=2.5.3
ARG PLAYWRIGHT_VERSION=1.64.1
ARG TARGETARCH=amd64

RUN test "${TARGETARCH}" = amd64 \
  || { echo "This image supports linux/amd64 only." >&2; exit 1; }

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
    unzip \
  && rm -rf /var/lib/apt/lists/*

RUN node -e 'const [major, minor] = process.versions.node.split(".").map(Number); if (major < 24 || (major === 24 && minor < 14)) { console.error("Node >=24.14.0 is required."); process.exit(1); }' \
  && npm install -g --allow-scripts=@opencode/cli,node-pty \
    "@opencode/cli@${OPENCODE_VERSION}" \
    "@openchamber/web@${OPENCHAMBER_VERSION}" \
    "playwright@${PLAYWRIGHT_VERSION}" \
  && npm cache clean --force

# Install only the Chromium system libraries. Projects download their own browser builds.
RUN playwright install-deps chromium \
  && rm -rf /var/lib/apt/lists/*

COPY install-tools.sh /opt/bootstrap/install-tools.sh
RUN TARGETARCH="${TARGETARCH}" sh /opt/bootstrap/install-tools.sh \
  && rtk hook opencode --help

ENV JAVA_HOME=/opt/temurin-25
ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV PATH="/opt/android-cli/bin:${JAVA_HOME}/bin:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${ANDROID_HOME}/build-tools/37.0.0:${PATH}"

COPY install-android.sh /opt/bootstrap/install-android.sh
RUN TARGETARCH="${TARGETARCH}" sh /opt/bootstrap/install-android.sh \
  && chown -R node:node /opt/android-sdk

COPY install-opencode-claude.sh /opt/bootstrap/install-opencode-claude.sh
COPY patches/opencode-claude/ /opt/bootstrap/patches/opencode-claude/
RUN sh /opt/bootstrap/install-opencode-claude.sh /opt/opencode-claude

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

COPY bootstrap/opencode/ /opt/bootstrap/opencode/
COPY opencode.jsonc /opt/bootstrap/opencode/opencode.jsonc
COPY bootstrap/gradle/ /opt/bootstrap/gradle/
COPY entrypoint.sh /usr/local/bin/yolo-entrypoint

RUN chmod 0555 /usr/local/bin/yolo-entrypoint \
  && chown -R node:node /opt/bootstrap/opencode /opt/bootstrap/gradle

USER node
WORKDIR /workspace

ENV HOME=/home/node
ENV XDG_CONFIG_HOME=/home/node/.config
ENV XDG_DATA_HOME=/home/node/.local/share
ENV XDG_CACHE_HOME=/home/node/.cache
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV PLAYWRIGHT_BROWSERS_PATH=/home/node/.cache/ms-playwright

ENV OPENCODE_CONFIG_DIR=/home/node/.config/opencode
ENV OPENCODE_CONFIG=/home/node/.config/opencode/opencode.jsonc
ENV OPENCODE_DATA_DIR=/home/node/.local/share/opencode

ENV OPENCHAMBER_DATA_DIR=/home/node/.config/openchamber
ENV OPENCHAMBER_OPENCODE_HOSTNAME=127.0.0.1

EXPOSE 3000

ENTRYPOINT ["/usr/local/bin/yolo-entrypoint"]
