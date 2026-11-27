FROM node:26-trixie-slim AS openchamber

# The Update versions workflow updates the OpenCode and OpenChamber pins.
# Each other tool installs its latest release unless a build argument selects an exact version.
ARG OPENCODE_VERSION=2.4.2
ARG OPENCHAMBER_VERSION=2.8.1
ARG PLAYWRIGHT_VERSION=latest
ARG QUINT_VERSION=latest
ARG UV_VERSION=latest
ARG RTK_VERSION=latest
ARG FFF_VERSION=latest
ARG GH_VERSION=latest
ARG GITLEAKS_VERSION=latest
ARG CLAUDE_VERSION=latest
ARG ACTIONLINT_VERSION=latest
ARG SOPS_VERSION=latest
ARG COSIGN_VERSION=latest
ARG MAESTRO_VERSION=latest
ARG TEMURIN_VERSION=latest
ARG TARGETARCH=amd64

RUN test "${TARGETARCH}" = amd64 \
  || { echo "This image supports linux/amd64 only." >&2; exit 1; }

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    age \
    bash \
    ca-certificates \
    curl \
    git \
    jq \
    librsvg2-bin \
    openssh-client \
    python3 \
    build-essential \
    ripgrep \
    shellcheck \
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
  && printf 'age %s\n' "$(dpkg-query -W -f='${Version}' age)" >> /usr/local/share/image-versions.txt \
  && printf 'shellcheck %s\n' "$(dpkg-query -W -f='${Version}' shellcheck)" >> /usr/local/share/image-versions.txt \
  && printf 'rsvg-convert %s\n' "$(dpkg-query -W -f='${Version}' librsvg2-bin)" >> /usr/local/share/image-versions.txt \
  && cat /usr/local/share/image-versions.txt

ENV CHROME_PATH=/usr/local/bin/chromium

COPY install-tools.sh /opt/bootstrap/install-tools.sh
RUN TARGETARCH="${TARGETARCH}" \
  CLAUDE_VERSION="${CLAUDE_VERSION}" \
  ACTIONLINT_VERSION="${ACTIONLINT_VERSION}" \
  SOPS_VERSION="${SOPS_VERSION}" \
  COSIGN_VERSION="${COSIGN_VERSION}" \
  MAESTRO_VERSION="${MAESTRO_VERSION}" \
  sh /opt/bootstrap/install-tools.sh \
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

# /usr/local is read-only at runtime, so the installed Claude Code cannot
# replace itself. Manual `claude update` still fails for the same reason.
ENV DISABLE_AUTOUPDATER=1

EXPOSE 3000

ENTRYPOINT ["/usr/local/bin/yolo-entrypoint"]

# Docker Sandboxes workload for openchamber-isolated.yaml. Keep this stage last,
# because the kit build uses the default target; Compose and CI select openchamber.
FROM openchamber AS sandbox

# Docker Sandboxes requires the user agent with UID 1000 and home /home/agent.
# The link keeps the /home/node paths in the bundled configuration valid.
USER root
RUN usermod --login agent --home /home/agent --move-home node \
  && groupmod --new-name agent node \
  && ln -s /home/agent /home/node

USER agent

ENV HOME=/home/agent
ENV XDG_CONFIG_HOME=/home/agent/.config
ENV XDG_DATA_HOME=/home/agent/.local/share
ENV XDG_CACHE_HOME=/home/agent/.cache
ENV OPENCODE_CONFIG_DIR=/home/agent/.config/opencode
ENV OPENCODE_CONFIG=/home/agent/.config/opencode/opencode.jsonc
ENV OPENCODE_DATA_DIR=/home/agent/.local/share/opencode
ENV OPENCHAMBER_DATA_DIR=/home/agent/.config/openchamber
ENV NPM_CONFIG_CACHE=/home/agent/.cache/npm

# The sandbox adds its proxy CA to this bundle at start.
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ENV CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
ENV REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt

# A lifecycle hook starts OpenChamber; sandbox sessions open a login shell.
ENTRYPOINT ["bash"]
CMD ["-l"]
