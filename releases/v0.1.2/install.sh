#!/usr/bin/env bash
set -euo pipefail

REPO="alexwoollam/jaspa"
BIN_NAME="jaspa"
VERSION="${VERSION:-}"
INSTALL_DIR="${INSTALL_DIR:-}"
DOWNLOAD_ROOT="${DOWNLOAD_ROOT:-}"
BIN_REPO_ROOT="https://raw.githubusercontent.com/zombie-flesh-eaters/jaspa-bin/main/releases"
GITHUB_TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"

abort() {
  echo "error: $*" >&2
  exit 1
}

info() {
  echo "$*"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || abort "missing required command: $1"
}

need_cmd uname
need_cmd mktemp
need_cmd chmod

fetch_latest_version() {
  local _data=""
  local _url=""
  if command -v curl >/dev/null 2>&1; then
    if [ -n "$GITHUB_TOKEN" ]; then
      _data="$(curl -fsSL -H "Authorization: token ${GITHUB_TOKEN}" \
        "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null || true)"
    else
      _data="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null || true)"
    fi
  elif command -v wget >/dev/null 2>&1; then
    if [ -n "$GITHUB_TOKEN" ]; then
      _data="$(wget -qO- --header="Authorization: token ${GITHUB_TOKEN}" \
        "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null || true)"
    else
      _data="$(wget -qO- "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null || true)"
    fi
  fi
  VERSION="$(printf '%s' "$_data" \
    | sed -nE 's/.*"tag_name":[[:space:]]*"([^"]+)".*/\1/p' \
    | head -n1)"

  if [ -z "$VERSION" ] && command -v curl >/dev/null 2>&1 && [ -z "$GITHUB_TOKEN" ]; then
    _url="$(curl -fsSL -o /dev/null -w '%{url_effective}' \
      "https://github.com/${REPO}/releases/latest" 2>/dev/null || true)"
    VERSION="$(printf '%s' "$_url" | sed -E 's#.*?/tag/([^/]+)$#\1#')"
  fi
}

if [ -z "$VERSION" ] && [ -z "$DOWNLOAD_ROOT" ]; then
  fetch_latest_version
  if [ -z "$VERSION" ]; then
    if [ -n "$GITHUB_TOKEN" ]; then
      abort "could not determine latest version (check token permissions)"
    else
      abort "could not determine latest version (private repo? set VERSION=... or GITHUB_TOKEN=...)"
    fi
  fi
fi

if [ -z "$DOWNLOAD_ROOT" ] && [ -n "$VERSION" ]; then
  DOWNLOAD_ROOT="${BIN_REPO_ROOT}/${VERSION}"
fi

OS="$(uname -s)"
ARCH="$(uname -m)"

case "$ARCH" in
  x86_64) ARCH="x86_64" ;;
  arm64|aarch64) ARCH="aarch64" ;;
  *) abort "unsupported architecture: $ARCH" ;;
esac

case "$OS" in
  Darwin)
    TARGET="${ARCH}-apple-darwin"
    ;;
  Linux)
    if [ -f /etc/alpine-release ]; then
      TARGET="${ARCH}-unknown-linux-musl"
    else
      TARGET="${ARCH}-unknown-linux-gnu"
    fi
    ;;
  *)
    abort "unsupported OS: $OS"
    ;;
esac

ASSET="${BIN_NAME}-${TARGET}"
if [ -n "$DOWNLOAD_ROOT" ]; then
  URL="${DOWNLOAD_ROOT}/${ASSET}"
elif [ -n "$VERSION" ]; then
  URL="https://github.com/${REPO}/releases/download/${VERSION}/${ASSET}"
else
  abort "missing VERSION and DOWNLOAD_ROOT; set VERSION=... to continue"
fi

info "Detected target: ${TARGET}"
info "Downloading ${ASSET}..."

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if command -v curl >/dev/null 2>&1; then
  if [ -n "$GITHUB_TOKEN" ]; then
    if ! curl -fL -H "Authorization: token ${GITHUB_TOKEN}" -o "${TMP_DIR}/${BIN_NAME}" "$URL"; then
      abort "download failed (check URL/token: $URL)"
    fi
  elif ! curl -fL -o "${TMP_DIR}/${BIN_NAME}" "$URL"; then
    abort "download failed (check URL: $URL)"
  fi
elif command -v wget >/dev/null 2>&1; then
  if [ -n "$GITHUB_TOKEN" ]; then
    if ! wget -O "${TMP_DIR}/${BIN_NAME}" --header="Authorization: token ${GITHUB_TOKEN}" "$URL"; then
      abort "download failed (check URL/token: $URL)"
    fi
  elif ! wget -O "${TMP_DIR}/${BIN_NAME}" "$URL"; then
    abort "download failed (check URL: $URL)"
  fi
else
  abort "need curl or wget to download"
fi

chmod +x "${TMP_DIR}/${BIN_NAME}"

if [ -z "$INSTALL_DIR" ]; then
  if [ -w /usr/local/bin ]; then
    INSTALL_DIR="/usr/local/bin"
  else
    INSTALL_DIR="${HOME}/.local/bin"
  fi
fi

mkdir -p "$INSTALL_DIR"
mv "${TMP_DIR}/${BIN_NAME}" "${INSTALL_DIR}/${BIN_NAME}"

info "Installed ${BIN_NAME} ${VERSION} to ${INSTALL_DIR}/${BIN_NAME}"

if ! echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
  echo "Note: add ${INSTALL_DIR} to your PATH to run '${BIN_NAME}' from anywhere."
fi

if ! command -v cargo >/dev/null 2>&1; then
  if command -v curl >/dev/null 2>&1; then
    info "Rust not found. Installing via rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    if [ -d "${HOME}/.cargo/bin" ] && ! echo "$PATH" | tr ':' '\n' | grep -qx "${HOME}/.cargo/bin"; then
      export PATH="${HOME}/.cargo/bin:${PATH}"
    fi
    info "Rust installed. Open a new shell or run: source ~/.cargo/env"
  else
    echo "Note: cargo not found. Install Rust via https://rustup.rs" >&2
  fi
fi
