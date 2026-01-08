#!/bin/sh
set -eu

BIN_NAME="jaspa"
VERSION="${VERSION:-}"
INSTALL_DIR="${INSTALL_DIR:-}"
DOWNLOAD_ROOT="${DOWNLOAD_ROOT:-}"
BIN_REPO_ROOT="https://raw.githubusercontent.com/zombie-flesh-eaters/jaspa-bin/main/releases"

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

maybe_source_file() {
  file="$1"
  if [ -f "$file" ]; then
    # shellcheck disable=SC1090
    . "$file"
    info "Reloaded environment from ${file}"
  fi
}

ensure_path_config() {
  dir="$1"
  label="$2"
  if [ -z "$dir" ]; then
    return
  fi
  already_in_path="0"
  if echo "$PATH" | tr ':' '\n' | grep -qx "$dir"; then
    already_in_path="1"
  fi

  profile=""
  profiles="${HOME}/.profile ${HOME}/.bash_profile ${HOME}/.bashrc ${HOME}/.zprofile ${HOME}/.zshrc"
  for candidate in $profiles; do
    if [ -f "$candidate" ]; then
      profile="$candidate"
      break
    fi
  done
  if [ -z "$profile" ]; then
    profile="${HOME}/.profile"
  fi
  if [ ! -f "$profile" ]; then
    touch "$profile"
  fi

  if ! grep -F "$dir" "$profile" >/dev/null 2>&1; then
    cat >>"$profile" <<EOF

# Added by Jaspa installer: ensure ${label} is on PATH
if [ -d "$dir" ]; then
  case ":\$PATH:" in
    *:"$dir":*) ;;
    *)
      export PATH="$dir:\$PATH"
      ;;
  esac
fi
EOF
    info "Added ${label} to PATH via ${profile}. Open a new shell or 'source ${profile}' to refresh your PATH."
  fi

  if [ "$already_in_path" = "0" ]; then
    PATH="$dir:$PATH"
    export PATH
  fi
}

need_cmd uname
need_cmd mktemp
need_cmd chmod

fetch_latest_version() {
  local latest_url="${BIN_REPO_ROOT}/latest"
  local latest=""
  if command -v curl >/dev/null 2>&1; then
    latest="$(curl -fsSL "$latest_url" 2>/dev/null || true)"
  elif command -v wget >/dev/null 2>&1; then
    latest="$(wget -qO- "$latest_url" 2>/dev/null || true)"
  fi
  latest="$(printf '%s' "$latest" | tr -d '\r' | head -n1)"
  if [ -n "$latest" ]; then
    VERSION="$latest"
  fi
}

if [ -z "$VERSION" ] && [ -z "$DOWNLOAD_ROOT" ]; then
  fetch_latest_version
  if [ -z "$VERSION" ]; then
    abort "could not determine latest version (set VERSION=... or check releases repo availability)"
  fi
fi

case "$VERSION" in
  *://*)
    abort "could not determine latest version (got URL instead of tag; set VERSION=... manually)"
    ;;
esac

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
else
  URL="${BIN_REPO_ROOT}/${VERSION}/${ASSET}"
fi

info "Detected target: ${TARGET}"
info "Downloading ${ASSET}..."

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if command -v curl >/dev/null 2>&1; then
  if ! curl -fL -o "${TMP_DIR}/${BIN_NAME}" "$URL"; then
    abort "download failed (check URL: $URL)"
  fi
elif command -v wget >/dev/null 2>&1; then
  if ! wget -O "${TMP_DIR}/${BIN_NAME}" "$URL"; then
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
ensure_path_config "$INSTALL_DIR" "the Jaspa CLI"

if ! command -v cargo >/dev/null 2>&1; then
  if command -v curl >/dev/null 2>&1; then
    info "Rust not found. Installing via rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    ensure_path_config "${HOME}/.cargo/bin" "Rust's cargo"
    maybe_source_file "${HOME}/.cargo/env"
    info "Rust installed."
  else
    echo "Note: cargo not found. Install Rust via https://rustup.rs" >&2
  fi
else
  ensure_path_config "${HOME}/.cargo/bin" "Rust's cargo"
  maybe_source_file "${HOME}/.cargo/env"
fi
