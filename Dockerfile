FROM node:26-trixie-slim

# The Update versions workflow updates the OpenCode and OpenChamber pins.
# Each other tool installs its latest release unless a build argument selects an exact version.
ARG OPENCODE_VERSION=2.3.2
ARG OPENCHAMBER_VERSION=2.8.0
ARG PLAYWRIGHT_VERSION=latest
ARG QUINT_VERSION=latest
ARG UV_VERSION=latest
ARG RTK_VERSION=latest
ARG FFF_VERSION=latest
ARG GH_VERSION=latest
ARG GITLEAKS_VERSION=latest
ARG TEMURIN_VERSION=latest
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
    "@informalsystems/quint@${QUINT_VERSION}" \
  && npm cache clean --force \
  && mkdir -p /usr/local/share \
  && npm ls -g --depth=0 --json \
    | jq -r '.dependencies | to_entries[] | select(.key | IN("@opencode/cli", "@openchamber/web", "playwright", "@informalsystems/quint")) | "\(.key) \(.value.version)"' \
    >> /usr/local/share/image-versions.txt \
  && test "$(wc -l < /usr/local/share/image-versions.txt)" -eq 4

ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright

# Install the Chromium build of the installed Playwright and its system libraries.
# The root file system is read-only at runtime, so this is the only browser build.
RUN playwright install --with-deps chromium \
  && rm -rf /var/lib/apt/lists/* \
  && set -- /opt/ms-playwright/chromium-*/chrome-linux64/chrome \
  && test "$#" -eq 1 \
  && test -x "$1" \
  && ln -s "$1" /usr/local/bin/chromium \
  && printf 'chromium %s\n' "$(chromium --version)" >> /usr/local/share/image-versions.txt \
  && cat /usr/local/share/image-versions.txt

ENV CHROME_PATH=/usr/local/bin/chromium

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

ENV OPENCODE_CONFIG_DIR=/home/node/.config/opencode
ENV OPENCODE_CONFIG=/home/node/.config/opencode/opencode.jsonc
ENV OPENCODE_DATA_DIR=/home/node/.local/share/opencode

ENV OPENCHAMBER_DATA_DIR=/home/node/.config/openchamber
ENV OPENCHAMBER_OPENCODE_HOSTNAME=127.0.0.1

# The Claude Agent SDK labels requests sdk-ts when this is empty, and sdk-*
# labels use the 5-hour limit faster (anthropics/claude-code#97074).
ENV CLAUDE_CODE_ENTRYPOINT=opencode-claude

EXPOSE 3000

ENTRYPOINT ["/usr/local/bin/yolo-entrypoint"]
