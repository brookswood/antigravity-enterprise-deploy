#!/usr/bin/env bash
# Optional Exporter: Builds google-antigravity-config-<version>-<release>.rpm for RHEL / Rocky / AlmaLinux / Fedora
# (Note: For the default portable .zip bundle, run ./scripts/build-bundle.sh instead.)
#
# Usage:
#   WIF_PROVIDER="locations/global/workforcePools/example-pool/providers/ping-sso" ./scripts/build-rpm.sh
#   ./scripts/build-rpm.sh                                      # Base RPM: agy + settings.json
#   INCLUDE_WIF_ADC=1 ./scripts/build-rpm.sh                    # Pattern B: also bundles wif-login-config.json + AGY_ADC_AUTH=true
#   INCLUDE_ADMIN_SETTINGS=1 ./scripts/build-rpm.sh             # Optional: also builds google-antigravity-admin-policy subpackage
#   BUNDLE_AGY_BINARY=0 ./scripts/build-rpm.sh                  # Config-only noarch RPM
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ASSETS_DIR="${ASSETS_DIR:-$ROOT_DIR/assets}"
CONFIGS_DIR="${CONFIGS_DIR:-$ASSETS_DIR/configs}"

PKG_VERSION="${PKG_VERSION:-1.0.0}"
PKG_RELEASE="${PKG_RELEASE:-1}"
BUNDLE_AGY_BINARY="${BUNDLE_AGY_BINARY:-1}"
WIF_PROVIDER="${WIF_PROVIDER:-}"
INCLUDE_ADMIN_SETTINGS="${INCLUDE_ADMIN_SETTINGS:-0}"
INCLUDE_WIF_ADC="${INCLUDE_WIF_ADC:-${INCLUDE_OKTA_WIF_ADC:-0}}"
GCP_QUOTA_PROJECT="${GCP_QUOTA_PROJECT:-}"
MANIFEST_BASE_URL="https://antigravity-cli-auto-updater-974169037036.us-central1.run.app"

for cmd in rpmbuild tar sha512sum curl sed python3; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[ERROR] Missing '$cmd'. Install prerequisites: sudo dnf install -y rpm-build curl tar coreutils python3" >&2
    exit 1
  fi
done

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

RPM_TOPDIR="$WORK_DIR/rpmbuild"
STAGE_ROOT="$WORK_DIR/rootfs"
mkdir -p "$RPM_TOPDIR"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
mkdir -p \
  "$STAGE_ROOT/etc/profile.d" \
  "$STAGE_ROOT/etc/skel/.gemini/antigravity-cli" \
  "$STAGE_ROOT/usr/share/google-antigravity-config"

install -m 0644 "$CONFIGS_DIR/agy-cli-settings.json" \
  "$STAGE_ROOT/usr/share/google-antigravity-config/agy-cli-settings.json"
install -m 0600 "$CONFIGS_DIR/agy-cli-settings.json" \
  "$STAGE_ROOT/etc/skel/.gemini/antigravity-cli/settings.json"

HAS_WIF_SEED="0"
if [ -n "$WIF_PROVIDER" ]; then
  HAS_WIF_SEED="1"
  mkdir -p "$STAGE_ROOT/etc/skel/.gemini/antigravity-cli/cache"
  python3 - "$WIF_PROVIDER" "$STAGE_ROOT/usr/share/google-antigravity-config/wif-provider-seed.json" "$STAGE_ROOT/usr/share/google-antigravity-config/onboarding.json" << 'EOF_WIF'
import json, re, sys

provider, seed_path, onboard_path = sys.argv[1].strip(), sys.argv[2], sys.argv[3]
provider = re.sub(r"^//iam\.googleapis\.com/", "", provider)
if not re.match(r"^locations/[^/]+/workforcePools/[^/]+/providers/[^/]+$", provider):
  raise SystemExit(
      f"[ERROR] WIF_PROVIDER must match 'locations/<loc>/workforcePools/<pool>/providers/<provider>', got: {provider}"
  )
with open(seed_path, "w", encoding="utf-8") as f:
  json.dump({"saved_wif_provider": provider}, f, indent=2)
  f.write("\n")
with open(onboard_path, "w", encoding="utf-8") as f:
  json.dump({"previousAuthMethod": "wif"}, f, indent=2)
  f.write("\n")
EOF_WIF
  chmod 0644 "$STAGE_ROOT/usr/share/google-antigravity-config/wif-provider-seed.json" \
    "$STAGE_ROOT/usr/share/google-antigravity-config/onboarding.json"
  install -m 0600 "$STAGE_ROOT/usr/share/google-antigravity-config/wif-provider-seed.json" \
    "$STAGE_ROOT/etc/skel/.gemini/antigravity-cli/antigravity-oauth-token"
  install -m 0600 "$STAGE_ROOT/usr/share/google-antigravity-config/onboarding.json" \
    "$STAGE_ROOT/etc/skel/.gemini/antigravity-cli/cache/onboarding.json"
fi

if [ "$INCLUDE_WIF_ADC" = "1" ]; then
  WIF_LOGIN_SRC="${WIF_LOGIN_CONFIG_FILE:-$CONFIGS_DIR/wif-login-config.example.json}"
  if [ ! -f "$WIF_LOGIN_SRC" ]; then
    echo "[ERROR] INCLUDE_WIF_ADC=1 requires $WIF_LOGIN_SRC" >&2
    exit 1
  fi
  mkdir -p "$STAGE_ROOT/etc/antigravity" "$STAGE_ROOT/etc/skel/.gemini/config"
  install -m 0644 "$WIF_LOGIN_SRC" "$STAGE_ROOT/etc/antigravity/wif-login-config.json"
  install -m 0644 "$CONFIGS_DIR/user_app_config.json" \
    "$STAGE_ROOT/usr/share/google-antigravity-config/user_app_config.json"
  install -m 0600 "$CONFIGS_DIR/user_app_config.json" \
    "$STAGE_ROOT/etc/skel/.gemini/config/config.json"
fi

if [ "$INCLUDE_ADMIN_SETTINGS" = "1" ]; then
  if [ ! -f "$CONFIGS_DIR/admin_settings.json" ]; then
    echo "[ERROR] INCLUDE_ADMIN_SETTINGS=1 requires $CONFIGS_DIR/admin_settings.json" >&2
    exit 1
  fi
  mkdir -p "$STAGE_ROOT/etc/antigravity"
  install -m 0644 "$CONFIGS_DIR/admin_settings.json" \
    "$STAGE_ROOT/etc/antigravity/admin_settings.json"
fi

{
  echo '# Managed by google-antigravity-config RPM'
  echo 'export AGY_CLI_DISABLE_AUTO_UPDATE="true"'
  if [ -n "$GCP_QUOTA_PROJECT" ]; then
    printf 'export GOOGLE_CLOUD_QUOTA_PROJECT="%s"\n' "$GCP_QUOTA_PROJECT"
  fi
  if [ "$INCLUDE_WIF_ADC" = "1" ]; then
    echo 'export AGY_ADC_AUTH="true"'
    echo 'if [ -r "/etc/antigravity/wif-login-config.json" ]; then'
    echo '  export CLOUDSDK_AUTH_LOGIN_CONFIG_FILE="/etc/antigravity/wif-login-config.json"'
    echo 'fi'
  fi
  cat << 'EOF'

if [ -n "${HOME:-}" ] && [ "$(id -u 2>/dev/null || echo 0)" -ge 1000 ] && [ -d "$HOME" ] && [ -w "$HOME" ]; then
  _share="/usr/share/google-antigravity-config"
  if [ ! -f "$HOME/.gemini/antigravity-cli/settings.json" ] && [ -f "$_share/agy-cli-settings.json" ]; then
    mkdir -p -m 0700 "$HOME/.gemini" "$HOME/.gemini/antigravity-cli" 2>/dev/null || true
    install -m 0600 "$_share/agy-cli-settings.json" "$HOME/.gemini/antigravity-cli/settings.json" 2>/dev/null || true
  fi
  if [ ! -f "$HOME/.gemini/antigravity-cli/antigravity-oauth-token" ] && [ -f "$_share/wif-provider-seed.json" ]; then
    mkdir -p -m 0700 "$HOME/.gemini/antigravity-cli" 2>/dev/null || true
    install -m 0600 "$_share/wif-provider-seed.json" "$HOME/.gemini/antigravity-cli/antigravity-oauth-token" 2>/dev/null || true
  fi
  if [ ! -f "$HOME/.gemini/antigravity-cli/cache/onboarding.json" ] && [ -f "$_share/onboarding.json" ]; then
    mkdir -p -m 0700 "$HOME/.gemini/antigravity-cli/cache" 2>/dev/null || true
    install -m 0600 "$_share/onboarding.json" "$HOME/.gemini/antigravity-cli/cache/onboarding.json" 2>/dev/null || true
  fi
  if [ -f "$_share/user_app_config.json" ] && [ ! -f "$HOME/.gemini/config/config.json" ]; then
    mkdir -p -m 0700 "$HOME/.gemini" "$HOME/.gemini/config" 2>/dev/null || true
    install -m 0600 "$_share/user_app_config.json" "$HOME/.gemini/config/config.json" 2>/dev/null || true
  fi
  unset _share
fi
EOF
} > "$STAGE_ROOT/etc/profile.d/google-antigravity-seed.sh"
chmod 0644 "$STAGE_ROOT/etc/profile.d/google-antigravity-seed.sh"

if [ "$BUNDLE_AGY_BINARY" = "1" ]; then
  case "$(uname -m)" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) echo "[ERROR] Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
  esac

  echo "Fetching Antigravity CLI manifest for linux_${arch}..."
  manifest_json="$(curl -fsSL "$MANIFEST_BASE_URL/manifests/linux_${arch}.json")"
  agy_ver="$(printf '%s' "$manifest_json" | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  agy_url="$(printf '%s' "$manifest_json" | sed -n 's/.*"url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  agy_sha="$(printf '%s' "$manifest_json" | sed -n 's/.*"sha512"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"

  echo "Downloading Antigravity CLI v${agy_ver}..."
  payload="$WORK_DIR/agy_payload"
  curl -fsSL -o "$payload" "$agy_url"

  actual_sha="$(sha512sum "$payload" | cut -d' ' -f1)"
  if [ "$actual_sha" != "$agy_sha" ]; then
    echo "[ERROR] SHA-512 checksum mismatch! Expected $agy_sha, got $actual_sha" >&2
    exit 1
  fi

  mkdir -p "$STAGE_ROOT/opt/google/antigravity-cli" "$STAGE_ROOT/usr/bin"
  case "$agy_url" in
    *.tar.gz*)
      tar -xzf "$payload" -C "$WORK_DIR" antigravity
      install -m 0755 "$WORK_DIR/antigravity" "$STAGE_ROOT/opt/google/antigravity-cli/agy-bin"
      ;;
    *)
      install -m 0755 "$payload" "$STAGE_ROOT/opt/google/antigravity-cli/agy-bin"
      ;;
  esac

  {
    cat << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "update" ]; then
  echo "Antigravity CLI (agy) is managed via Red Hat DNF/RPM (google-antigravity-config)."
  echo "Run 'sudo dnf upgrade google-antigravity-config' to update."
  exit 0
fi

export AGY_CLI_DISABLE_AUTO_UPDATE="true"
EOF
    if [ -n "$GCP_QUOTA_PROJECT" ]; then
      printf 'export GOOGLE_CLOUD_QUOTA_PROJECT="${GOOGLE_CLOUD_QUOTA_PROJECT:-%s}"\n' "$GCP_QUOTA_PROJECT"
    fi
    if [ "$INCLUDE_WIF_ADC" = "1" ]; then
      echo 'export AGY_ADC_AUTH="${AGY_ADC_AUTH:-true}"'
      echo 'export CLOUDSDK_AUTH_LOGIN_CONFIG_FILE="${CLOUDSDK_AUTH_LOGIN_CONFIG_FILE:-/etc/antigravity/wif-login-config.json}"'
    fi
    cat << 'EOF'

if [ -n "${HOME:-}" ] && [ -d "$HOME" ] && [ -w "$HOME" ]; then
  _share="/usr/share/google-antigravity-config"
  if [ ! -f "$HOME/.gemini/antigravity-cli/settings.json" ] && [ -f "$_share/agy-cli-settings.json" ]; then
    mkdir -p -m 0700 "$HOME/.gemini" "$HOME/.gemini/antigravity-cli" 2>/dev/null || true
    install -m 0600 "$_share/agy-cli-settings.json" "$HOME/.gemini/antigravity-cli/settings.json" 2>/dev/null || true
  fi
  if [ ! -f "$HOME/.gemini/antigravity-cli/antigravity-oauth-token" ] && [ -f "$_share/wif-provider-seed.json" ]; then
    mkdir -p -m 0700 "$HOME/.gemini/antigravity-cli" 2>/dev/null || true
    install -m 0600 "$_share/wif-provider-seed.json" "$HOME/.gemini/antigravity-cli/antigravity-oauth-token" 2>/dev/null || true
  fi
  if [ ! -f "$HOME/.gemini/antigravity-cli/cache/onboarding.json" ] && [ -f "$_share/onboarding.json" ]; then
    mkdir -p -m 0700 "$HOME/.gemini/antigravity-cli/cache" 2>/dev/null || true
    install -m 0600 "$_share/onboarding.json" "$HOME/.gemini/antigravity-cli/cache/onboarding.json" 2>/dev/null || true
  fi
  unset _share
fi

exec /opt/google/antigravity-cli/agy-bin "$@"
EOF
  } > "$STAGE_ROOT/usr/bin/agy"
  chmod 0755 "$STAGE_ROOT/usr/bin/agy"

  if [ "$PKG_VERSION" = "1.0.0" ] && [ -n "$agy_ver" ]; then
    PKG_VERSION="${agy_ver//-/_}"
  fi
fi

tar -czf "$RPM_TOPDIR/SOURCES/rootfs.tar.gz" -C "$STAGE_ROOT" .
cp "$ASSETS_DIR/google-antigravity-config.spec" "$RPM_TOPDIR/SPECS/"

rpmbuild -bb \
  --define "_topdir $RPM_TOPDIR" \
  --define "SOURCE0 $RPM_TOPDIR/SOURCES/rootfs.tar.gz" \
  --define "pkg_version $PKG_VERSION" \
  --define "pkg_release $PKG_RELEASE" \
  --define "bundle_agy $BUNDLE_AGY_BINARY" \
  --define "with_wif_seed $HAS_WIF_SEED" \
  --define "with_admin_policy $INCLUDE_ADMIN_SETTINGS" \
  --define "with_wif_adc $INCLUDE_WIF_ADC" \
  "$RPM_TOPDIR/SPECS/google-antigravity-config.spec"

OUT_DIR="${OUT_DIR:-$ROOT_DIR/dist}"
mkdir -p "$OUT_DIR"
cp -v "$RPM_TOPDIR"/RPMS/*/*.rpm "$OUT_DIR/"
echo "RPM(s) successfully built in: $OUT_DIR"
