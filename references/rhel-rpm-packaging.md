# Optional Native Red Hat / RPM Packaging Guide (`dnf` & `rpmbuild`)

> **Optional Packaging Mode:** By default, this skill exports a portable `.zip` installer bundle via `scripts/build-bundle.sh` (no `rpmbuild` or `dnf` required). Load this reference **only** when the user explicitly wants a native Red Hat `.rpm` package for RHEL 8/9/10, Rocky Linux, AlmaLinux, or Fedora.

## 1. RPM Build Flags (`scripts/build-rpm.sh`)

The optional RPM packager (`scripts/build-rpm.sh` and `assets/google-antigravity-config.spec`) supports three independent flags:

- `BUNDLE_AGY_BINARY=1` *(default)*: Downloads the official `linux_amd64` or `linux_arm64` Antigravity CLI release manifest, verifies its `sha512sum`, stages `/opt/google/antigravity-cli/agy-bin`, and installs `/usr/bin/agy` (`AGY_CLI_DISABLE_AUTO_UPDATE="true"`). Set `BUNDLE_AGY_BINARY=0` for a config-only `noarch` RPM.
- `INCLUDE_WIF_ADC=0` *(default — Pattern A native browser WIF for Ping or Okta)*: Seeds `~/.gemini/antigravity-cli/settings.json` (`0600`) without requiring `gcloud`. Set `INCLUDE_WIF_ADC=1` (Pattern B) to also package `/etc/antigravity/wif-login-config.json`, seed `~/.gemini/config/config.json` (`enableAdc: true`), and export `AGY_ADC_AUTH="true"` + `CLOUDSDK_AUTH_LOGIN_CONFIG_FILE`.
- `INCLUDE_ADMIN_SETTINGS=0` *(default — no MDM / no `/etc/antigravity/admin_settings.json`)*: Emits only the base `google-antigravity-config` RPM. Set `INCLUDE_ADMIN_SETTINGS=1` to also emit an optional `google-antigravity-admin-policy` `noarch` subpackage installing `/etc/antigravity/admin_settings.json` (`0644`, `root:root`).

## 2. Optional `admin_settings.json` Schema Rules

Only four governance blocks are exclusive to `/etc/antigravity/admin_settings.json` (`0644`, `root:root`): `agentControls`, `browserControls`, `mcpControls`, and `featureControls`. All top-level keys enforce `additionalProperties: false`:

```json
{
  "caCertPath": "/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem",
  "proxy": {
    "address": "http://proxy.example.com:8080"
  },
  "agentControls": {
    "permissionPreset": "default"
  },
  "browserControls": {
    "browserEnabled": true,
    "javascriptExecutionPolicy": "request_review"
  },
  "mcpControls": {
    "mcpEnabled": true
  },
  "featureControls": {
    "remoteControlEnabled": false,
    "multiagentControls": {
      "boostCommandDisabled": false,
      "teamworkPreviewCommandDisabled": false
    }
  }
}
```

- **Valid `agentControls.permissionPreset` values:** `"request_review"`, `"default"`, `"turbo"`.
- **Valid `browserControls.javascriptExecutionPolicy` values:** `"disabled"`, `"request_review"`, `"not_enforced"`.
- **Omit `gateway` unless deploying a custom Enterprise Gateway:** `gateway.enabled: true` is strictly for organizations without Gemini Enterprise seats routing through a custom proxy.

## 3. Corporate TLS Inspection & Building via `rpmbuild`

`agy` automatically trusts the host Red Hat OS certificate store (`/etc/pki/ca-trust/source/anchors/` + `sudo update-ca-trust`) and standard proxy environment variables (`HTTPS_PROXY`, `HTTP_PROXY`, `NO_PROXY`) without needing `admin_settings.json`.

```bash
# Optional RPM build (base RPM only — Pattern A Ping/Okta WIF ready, no admin_settings.json)
./scripts/build-rpm.sh

# Optional RPM build with Pattern B WIF ADC + optional admin-policy subpackage
INCLUDE_WIF_ADC=1 INCLUDE_ADMIN_SETTINGS=1 GCP_QUOTA_PROJECT="example-gcp-project" ./scripts/build-rpm.sh

# Install via native DNF and verify 0600 seeding
sudo dnf install -y ./dist/google-antigravity-config-[0-9]*.rpm
su - "$SUDO_USER" -c 'agy --version && stat -c "%a %U:%G %n" ~/.gemini/antigravity-cli/settings.json'
```
