#!/usr/bin/env bash
# Default Exporter: Builds a portable .zip installer bundle containing:
#   - bin/agy-bin            (SHA-512 verified Google Antigravity CLI binary)
#   - configs/settings.json  (seeded to ~/.gemini/antigravity-cli/settings.json)
#   - configs/*              (optional WIF ADC login-config.json / config.json / admin_settings.json)
#   - install.sh             (one-step bash installer: user-local default, or `sudo ./install.sh --system`)
#
# Usage:
#   ./scripts/build-bundle.sh                                                  # Default .zip (Pattern A Ping/Okta WIF ready)
#   INCLUDE_WIF_ADC=1 GCP_QUOTA_PROJECT="example-gcp-project" ./scripts/build-bundle.sh
#   INCLUDE_ADMIN_SETTINGS=1 ./scripts/build-bundle.sh                         # Also bundles optional admin_settings.json
#   TARGET_ARCH=arm64 ./scripts/build-bundle.sh                                # Cross-package linux_arm64 on an amd64 host
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ASSETS_DIR="${ASSETS_DIR:-$ROOT_DIR/assets}"
CONFIGS_DIR="${CONFIGS_DIR:-$ASSETS_DIR/configs}"

BUNDLE_AGY_BINARY="${BUNDLE_AGY_BINARY:-1}"
INCLUDE_WIF_ADC="${INCLUDE_WIF_ADC:-0}"
INCLUDE_ADMIN_SETTINGS="${INCLUDE_ADMIN_SETTINGS:-0}"
GCP_QUOTA_PROJECT="${GCP_QUOTA_PROJECT:-}"
MANIFEST_BASE_URL="https://antigravity-cli-auto-updater-974169037036.us-central1.run.app"

for cmd in curl sha512sum tar sed python3; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[ERROR] Missing required tool '$cmd'." >&2
    exit 1
  fi
done

if [ -n "${TARGET_ARCH:-}" ]; then
  arch="$TARGET_ARCH"
else
  case "$(uname -m)" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) echo "[ERROR] Unsupported architecture: $(uname -m) (set TARGET_ARCH=amd64 or arm64)" >&2; exit 1 ;;
  esac
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

BUNDLE_NAME="antigravity-enterprise-bundle-linux-${arch}"
BUNDLE_ROOT="$WORK_DIR/$BUNDLE_NAME"
mkdir -p "$BUNDLE_ROOT/bin" "$BUNDLE_ROOT/configs"

# 1. Stage JSON configuration files
install -m 0644 "$CONFIGS_DIR/agy-cli-settings.json" "$BUNDLE_ROOT/configs/settings.json"

if [ "$INCLUDE_WIF_ADC" = "1" ]; then
  WIF_LOGIN_SRC="${WIF_LOGIN_CONFIG_FILE:-$CONFIGS_DIR/wif-login-config.example.json}"
  if [ ! -f "$WIF_LOGIN_SRC" ]; then
    echo "[ERROR] INCLUDE_WIF_ADC=1 requires $WIF_LOGIN_SRC" >&2
    exit 1
  fi
  install -m 0644 "$WIF_LOGIN_SRC" "$BUNDLE_ROOT/configs/wif-login-config.json"
  install -m 0644 "$CONFIGS_DIR/user_app_config.json" "$BUNDLE_ROOT/configs/config.json"
fi

if [ "$INCLUDE_ADMIN_SETTINGS" = "1" ]; then
  if [ ! -f "$CONFIGS_DIR/admin_settings.json" ]; then
    echo "[ERROR] INCLUDE_ADMIN_SETTINGS=1 requires $CONFIGS_DIR/admin_settings.json" >&2
    exit 1
  fi
  install -m 0644 "$CONFIGS_DIR/admin_settings.json" "$BUNDLE_ROOT/configs/admin_settings.json"
fi

# 2. Download and SHA-512 verify the Google Antigravity CLI (agy) binary
agy_ver="config-only"
if [ "$BUNDLE_AGY_BINARY" = "1" ]; then
  echo "Fetching Antigravity CLI manifest for linux_${arch}..."
  manifest_json="$(curl -fsSL "$MANIFEST_BASE_URL/manifests/linux_${arch}.json")"
  agy_ver="$(printf '%s' "$manifest_json" | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  agy_url="$(printf '%s' "$manifest_json" | sed -n 's/.*"url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  agy_sha="$(printf '%s' "$manifest_json" | sed -n 's/.*"sha512"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"

  echo "Downloading Antigravity CLI v${agy_ver} (${arch})..."
  payload="$WORK_DIR/agy_payload"
  curl -fsSL -o "$payload" "$agy_url"

  actual_sha="$(sha512sum "$payload" | cut -d' ' -f1)"
  if [ "$actual_sha" != "$agy_sha" ]; then
    echo "[ERROR] SHA-512 checksum mismatch! Expected $agy_sha, got $actual_sha" >&2
    exit 1
  fi

  case "$agy_url" in
    *.tar.gz*)
      tar -xzf "$payload" -C "$WORK_DIR" antigravity
      install -m 0755 "$WORK_DIR/antigravity" "$BUNDLE_ROOT/bin/agy-bin"
      ;;
    *)
      install -m 0755 "$payload" "$BUNDLE_ROOT/bin/agy-bin"
      ;;
  esac
fi

# 3. Generate standalone install.sh inside the bundle
cat << 'EOF_HEADER' > "$BUNDLE_ROOT/install.sh"
#!/usr/bin/env bash
# Standalone Google Antigravity (agy) Enterprise Bundle Installer
#
# Modes:
#   ./install.sh                  # Default user-local install (~/.local/bin/agy + ~/.gemini/antigravity-cli/settings.json)
#   ./install.sh --force-config   # Overwrite existing user settings.json / config.json
#   sudo ./install.sh --system    # System-wide install (/opt/google/antigravity-cli + /usr/bin/agy + /etc/profile.d/)
set -euo pipefail

BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="user"
FORCE_CONFIG="0"
EOF_HEADER

printf 'DEFAULT_QUOTA_PROJECT="%s"\n' "$GCP_QUOTA_PROJECT" >> "$BUNDLE_ROOT/install.sh"

cat << 'EOF_BODY' >> "$BUNDLE_ROOT/install.sh"

for arg in "$@"; do
  case "$arg" in
    --system) MODE="system" ;;
    --user) MODE="user" ;;
    --force-config|--force) FORCE_CONFIG="1" ;;
    -h|--help)
      echo "Usage: ./install.sh [--user | --system] [--force-config]"
      exit 0
      ;;
    *)
      echo "[ERROR] Unknown flag: $arg" >&2
      exit 1
      ;;
  esac
done

HAS_WIF_ADC="0"
if [ -f "$BUNDLE_DIR/configs/wif-login-config.json" ]; then
  HAS_WIF_ADC="1"
fi

copy_user_cfg() {
  local src="$1"
  local dst="$2"
  mkdir -p -m 0700 "$(dirname "$dst")"
  if [ ! -f "$dst" ] || [ "$FORCE_CONFIG" = "1" ]; then
    install -m 0600 "$src" "$dst"
    echo "Installed config: $dst"
  else
    echo "Preserved existing config: $dst (pass --force-config to overwrite)"
  fi
}

if [ "$MODE" = "user" ]; then
  BIN_DIR="${AGY_INSTALL_DIR:-$HOME/.local/bin}"
  SHARE_DIR="$HOME/.local/share/google-antigravity-config"
  mkdir -p -m 0700 "$HOME/.gemini" "$HOME/.gemini/antigravity-cli" "$SHARE_DIR"
  mkdir -p "$BIN_DIR"

  install -m 0600 "$BUNDLE_DIR/configs/settings.json" "$SHARE_DIR/settings.json"
  copy_user_cfg "$BUNDLE_DIR/configs/settings.json" "$HOME/.gemini/antigravity-cli/settings.json"

  if [ "$HAS_WIF_ADC" = "1" ]; then
    mkdir -p -m 0700 "$HOME/.config/antigravity" "$HOME/.gemini/config"
    install -m 0600 "$BUNDLE_DIR/configs/wif-login-config.json" "$HOME/.config/antigravity/wif-login-config.json"
    echo "Installed WIF login config: $HOME/.config/antigravity/wif-login-config.json"
    if [ -f "$BUNDLE_DIR/configs/config.json" ]; then
      copy_user_cfg "$BUNDLE_DIR/configs/config.json" "$HOME/.gemini/config/config.json"
    fi
  fi

  if [ -f "$BUNDLE_DIR/bin/agy-bin" ]; then
    install -m 0755 "$BUNDLE_DIR/bin/agy-bin" "$BIN_DIR/agy-bin"
    {
      echo '#!/usr/bin/env bash'
      echo 'set -euo pipefail'
      echo 'export AGY_CLI_DISABLE_AUTO_UPDATE="true"'
      if [ -n "$DEFAULT_QUOTA_PROJECT" ]; then
        printf 'export GOOGLE_CLOUD_QUOTA_PROJECT="${GOOGLE_CLOUD_QUOTA_PROJECT:-%s}"\n' "$DEFAULT_QUOTA_PROJECT"
      fi
      if [ "$HAS_WIF_ADC" = "1" ]; then
        echo 'export AGY_ADC_AUTH="${AGY_ADC_AUTH:-true}"'
        echo 'export CLOUDSDK_AUTH_LOGIN_CONFIG_FILE="${CLOUDSDK_AUTH_LOGIN_CONFIG_FILE:-$HOME/.config/antigravity/wif-login-config.json}"'
      fi
      cat << 'EOF_WRAP'
if [ ! -f "$HOME/.gemini/antigravity-cli/settings.json" ] && [ -f "$HOME/.local/share/google-antigravity-config/settings.json" ]; then
  mkdir -p -m 0700 "$HOME/.gemini" "$HOME/.gemini/antigravity-cli" 2>/dev/null || true
  install -m 0600 "$HOME/.local/share/google-antigravity-config/settings.json" "$HOME/.gemini/antigravity-cli/settings.json" 2>/dev/null || true
fi
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/agy-bin" "$@"
EOF_WRAP
    } > "$BIN_DIR/agy"
    chmod 0755 "$BIN_DIR/agy"
    echo "Installed binary & wrapper: $BIN_DIR/agy"
  fi

  # Ensure ~/.local/bin and optional WIF env vars are present in ~/.bashrc / ~/.zshrc
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -f "$rc" ] || continue
    if ! grep -q "# >>> google-antigravity-bundle >>>" "$rc" 2>/dev/null; then
      {
        echo ""
        echo "# >>> google-antigravity-bundle >>>"
        echo 'export PATH="$HOME/.local/bin:$PATH"'
        echo 'export AGY_CLI_DISABLE_AUTO_UPDATE="true"'
        if [ -n "$DEFAULT_QUOTA_PROJECT" ]; then
          printf 'export GOOGLE_CLOUD_QUOTA_PROJECT="${GOOGLE_CLOUD_QUOTA_PROJECT:-%s}"\n' "$DEFAULT_QUOTA_PROJECT"
        fi
        if [ "$HAS_WIF_ADC" = "1" ]; then
          echo 'export AGY_ADC_AUTH="${AGY_ADC_AUTH:-true}"'
          echo 'export CLOUDSDK_AUTH_LOGIN_CONFIG_FILE="${CLOUDSDK_AUTH_LOGIN_CONFIG_FILE:-$HOME/.config/antigravity/wif-login-config.json}"'
        fi
        echo "# <<< google-antigravity-bundle <<<"
      } >> "$rc"
      echo "Updated shell profile: $rc"
    fi
  done

  if [ -f "$BUNDLE_DIR/configs/admin_settings.json" ]; then
    echo "[NOTE] configs/admin_settings.json requires root (/etc/antigravity/admin_settings.json)."
    echo "       Run 'sudo ./install.sh --system' if you also want to enforce root-level admin_settings.json."
  fi

  echo "Done! Open a new shell or run '$BIN_DIR/agy --version' to verify."
  exit 0
fi

# --system mode (requires root)
if [ "$(id -u)" -ne 0 ]; then
  echo "[ERROR] --system mode requires root. Re-run with: sudo ./install.sh --system" >&2
  exit 1
fi

mkdir -p -m 0755 /usr/share/google-antigravity-config /etc/profile.d
mkdir -p -m 0700 /etc/skel/.gemini /etc/skel/.gemini/antigravity-cli
install -m 0644 "$BUNDLE_DIR/configs/settings.json" /usr/share/google-antigravity-config/agy-cli-settings.json
install -m 0600 "$BUNDLE_DIR/configs/settings.json" /etc/skel/.gemini/antigravity-cli/settings.json

if [ "$HAS_WIF_ADC" = "1" ]; then
  mkdir -p -m 0755 /etc/antigravity
  mkdir -p -m 0700 /etc/skel/.gemini/config
  install -m 0644 "$BUNDLE_DIR/configs/wif-login-config.json" /etc/antigravity/wif-login-config.json
  if [ -f "$BUNDLE_DIR/configs/config.json" ]; then
    install -m 0644 "$BUNDLE_DIR/configs/config.json" /usr/share/google-antigravity-config/user_app_config.json
    install -m 0600 "$BUNDLE_DIR/configs/config.json" /etc/skel/.gemini/config/config.json
  fi
fi

if [ -f "$BUNDLE_DIR/configs/admin_settings.json" ]; then
  mkdir -p -m 0755 /etc/antigravity
  install -m 0644 "$BUNDLE_DIR/configs/admin_settings.json" /etc/antigravity/admin_settings.json
  echo "Installed optional system policy: /etc/antigravity/admin_settings.json"
fi

{
  echo '# Managed by google-antigravity-bundle install.sh --system'
  echo 'export AGY_CLI_DISABLE_AUTO_UPDATE="true"'
  if [ -n "$DEFAULT_QUOTA_PROJECT" ]; then
    printf 'export GOOGLE_CLOUD_QUOTA_PROJECT="%s"\n' "$DEFAULT_QUOTA_PROJECT"
  fi
  if [ "$HAS_WIF_ADC" = "1" ]; then
    echo 'export AGY_ADC_AUTH="true"'
    echo 'export CLOUDSDK_AUTH_LOGIN_CONFIG_FILE="/etc/antigravity/wif-login-config.json"'
  fi
  cat << 'EOF_PROF'
if [ -n "${HOME:-}" ] && [ "$(id -u 2>/dev/null || echo 0)" -ge 1000 ] && [ -d "$HOME" ] && [ -w "$HOME" ]; then
  if [ ! -f "$HOME/.gemini/antigravity-cli/settings.json" ] && [ -f "/usr/share/google-antigravity-config/agy-cli-settings.json" ]; then
    mkdir -p -m 0700 "$HOME/.gemini" "$HOME/.gemini/antigravity-cli" 2>/dev/null || true
    install -m 0600 "/usr/share/google-antigravity-config/agy-cli-settings.json" "$HOME/.gemini/antigravity-cli/settings.json" 2>/dev/null || true
  fi
  if [ -f "/usr/share/google-antigravity-config/user_app_config.json" ] && [ ! -f "$HOME/.gemini/config/config.json" ]; then
    mkdir -p -m 0700 "$HOME/.gemini" "$HOME/.gemini/config" 2>/dev/null || true
    install -m 0600 "/usr/share/google-antigravity-config/user_app_config.json" "$HOME/.gemini/config/config.json" 2>/dev/null || true
  fi
fi
EOF_PROF
} > /etc/profile.d/google-antigravity-seed.sh
chmod 0644 /etc/profile.d/google-antigravity-seed.sh

if [ -f "$BUNDLE_DIR/bin/agy-bin" ]; then
  mkdir -p -m 0755 /opt/google/antigravity-cli /usr/bin
  install -m 0755 "$BUNDLE_DIR/bin/agy-bin" /opt/google/antigravity-cli/agy-bin
  {
    echo '#!/usr/bin/env bash'
    echo 'set -euo pipefail'
    echo 'export AGY_CLI_DISABLE_AUTO_UPDATE="true"'
    if [ -n "$DEFAULT_QUOTA_PROJECT" ]; then
      printf 'export GOOGLE_CLOUD_QUOTA_PROJECT="${GOOGLE_CLOUD_QUOTA_PROJECT:-%s}"\n' "$DEFAULT_QUOTA_PROJECT"
    fi
    if [ "$HAS_WIF_ADC" = "1" ]; then
      echo 'export AGY_ADC_AUTH="${AGY_ADC_AUTH:-true}"'
      echo 'export CLOUDSDK_AUTH_LOGIN_CONFIG_FILE="${CLOUDSDK_AUTH_LOGIN_CONFIG_FILE:-/etc/antigravity/wif-login-config.json}"'
    fi
    cat << 'EOF_SYSWRAP'
if [ -n "${HOME:-}" ] && [ -d "$HOME" ] && [ -w "$HOME" ]; then
  if [ ! -f "$HOME/.gemini/antigravity-cli/settings.json" ] && [ -f "/usr/share/google-antigravity-config/agy-cli-settings.json" ]; then
    mkdir -p -m 0700 "$HOME/.gemini" "$HOME/.gemini/antigravity-cli" 2>/dev/null || true
    install -m 0600 "/usr/share/google-antigravity-config/agy-cli-settings.json" "$HOME/.gemini/antigravity-cli/settings.json" 2>/dev/null || true
  fi
fi
exec /opt/google/antigravity-cli/agy-bin "$@"
EOF_SYSWRAP
  } > /usr/bin/agy
  chmod 0755 /usr/bin/agy
  echo "Installed system binary & wrapper: /usr/bin/agy"
fi

echo "System-wide installation complete!"
EOF_BODY
chmod 0755 "$BUNDLE_ROOT/install.sh"

# 4. Create .zip archive preserving Unix executable permissions (0755/0644)
OUT_DIR="${OUT_DIR:-$ROOT_DIR/dist}"
mkdir -p "$OUT_DIR"
ZIP_PATH="$OUT_DIR/${BUNDLE_NAME}.zip"
rm -f "$ZIP_PATH"

if command -v zip >/dev/null 2>&1; then
  (cd "$WORK_DIR" && zip -qr "$ZIP_PATH" "$BUNDLE_NAME")
else
  python3 - "$WORK_DIR" "$BUNDLE_NAME" "$ZIP_PATH" << 'EOF_PYZIP'
import os, stat, sys, zipfile

work_dir, bundle_name, zip_path = sys.argv[1], sys.argv[2], sys.argv[3]
root = os.path.join(work_dir, bundle_name)
with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
  for dirpath, dirnames, filenames in os.walk(root):
    dirnames.sort()
    for fname in sorted(filenames):
      full = os.path.join(dirpath, fname)
      rel = os.path.relpath(full, work_dir)
      st = os.stat(full)
      zi = zipfile.ZipInfo(rel)
      zi.compress_type = zipfile.ZIP_DEFLATED
      zi.external_attr = (stat.S_IMODE(st.st_mode) | stat.S_IFREG) << 16
      with open(full, "rb") as f:
        zf.writestr(zi, f.read())
EOF_PYZIP
fi

echo "Portable ZIP bundle ready (agy ${agy_ver}): $ZIP_PATH"
