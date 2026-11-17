# Native Red Hat / RPM Packaging Guide (`dnf` & `rpmbuild`)

Use this reference when building or customizing a native Red Hat Enterprise Linux (RHEL 8/9/10), Rocky Linux, AlmaLinux, or Fedora RPM package for **Google Antigravity (`agy`)** without requiring a third-party MDM agent.

## 1. Packaging Architecture & Build Flags

The bundled packager (`scripts/build-rpm.sh` and `assets/google-antigravity-config.spec`) supports three independent build flags:

- `BUNDLE_AGY_BINARY=1` *(default)*: Downloads the official `linux_amd64` or `linux_arm64` Antigravity CLI release manifest from `https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_<arch>.json`, verifies its `sha512sum`, stages `/opt/google/antigravity-cli/agy-bin`, and installs `/usr/bin/agy` (`AGY_CLI_DISABLE_AUTO_UPDATE="true"`). Set `BUNDLE_AGY_BINARY=0` to build a config-only `noarch` RPM.
- `INCLUDE_ADMIN_SETTINGS=0` *(default — no MDM / no `/etc/antigravity/admin_settings.json`)*: Emits only the base `google-antigravity-config` RPM. Set `INCLUDE_ADMIN_SETTINGS=1` to also emit an optional `google-antigravity-admin-policy` `noarch` subpackage installing `/etc/antigravity/admin_settings.json` (`0644`, `root:root`).
- `INCLUDE_OKTA_WIF_ADC=0` *(default — Pattern A native browser WIF)*: Seeds `~/.gemini/antigravity-cli/settings.json` (`0600`) without requiring `gcloud`. Set `INCLUDE_OKTA_WIF_ADC=1` (Pattern B) to also package `/etc/antigravity/wif-okta-login-config.json`, seed `~/.gemini/config/config.json` (`enableAdc: true`), and export `AGY_ADC_AUTH="true"` + `CLOUDSDK_AUTH_LOGIN_CONFIG_FILE`.

## 2. Optional `admin_settings.json` Schema Rules

Only four governance blocks are exclusive to `/etc/antigravity/admin_settings.json` (`0644`, `root:root`): `agentControls`, `browserControls`, `mcpControls`, and `featureControls`. All top-level keys are strictly validated (`additionalProperties: false`):

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

## 3. Corporate TLS Inspection & Proxy Setup on RHEL

`agy` automatically trusts the host Red Hat OS certificate store and standard proxy environment variables (`HTTPS_PROXY`, `HTTP_PROXY`, `NO_PROXY`) without needing `admin_settings.json`:

```bash
sudo cp corporate-root-ca.crt /etc/pki/ca-trust/source/anchors/
sudo update-ca-trust
```

### Firewall & Secure Web Gateway Policy (`TCP 443`)

| Endpoint / Domain | Action | Purpose |
| :--- | :--- | :--- |
| `businessaicode.googleapis.com`, `discoveryengine.googleapis.com` | **ALLOW** | Gemini Enterprise AI developer tools inference, settings, and governance APIs |
| `aiplatform.googleapis.com` *(or `aiplatform.<region>.rep.googleapis.com`)* | **ALLOW** | Vertex AI regional/global model endpoints |
| `cloudcode-pa.googleapis.com` | **ALLOW** | Companion entitlement verification (block only in air-gapped Gateway or strict ADC-only enclaves) |
| `oauth2.googleapis.com`, `accounts.google.com`, `sts.googleapis.com`, `iamcredentials.googleapis.com`, `www.googleapis.com` | **ALLOW** | Google Cloud OAuth 2.0, WIF STS token exchange, and userinfo verification |
| `auth.cloud.google`, `antigravity.google`, `{okta_domain}` | **ALLOW** | WIF authorization broker, PKCE callback (`https://antigravity.google/oauth-callback`), and Okta SSO |
| `antigravity-cli-auto-updater-974169037036.us-central1.run.app` | **ALLOW on Build Host** | Official CLI release manifests & SHA-512 binary payloads during `build-rpm.sh` |
| `daily-cloudcode-pa.googleapis.com`, `aicode.googleapis.com`, `generativelanguage.googleapis.com` | **BLOCK** | Blocks consumer-only `@gmail.com` endpoints on corporate workstations |

## 4. Building, Signing & Rolling Out via `dnf`

Copy `scripts/build-rpm.sh`, `assets/google-antigravity-config.spec`, and `assets/configs/` into a working build directory, edit `configs/agy-cli-settings.json` with your target Google Cloud project ID, and run:

```bash
# Default build: agy binary + ~/.gemini/antigravity-cli/settings.json (no admin_settings.json)
./build-rpm.sh

# Optional: also emit google-antigravity-admin-policy-*.noarch.rpm
INCLUDE_ADMIN_SETTINGS=1 ./build-rpm.sh

# Optional: Sign RPMs and install via native DNF
rpmsign --addsign ./dist/*.rpm
sudo dnf install -y ./dist/google-antigravity-config-[0-9]*.rpm

# Verify binary wrapper and 0600 user config seeding
su - "$SUDO_USER" -c 'agy --version && stat -c "%a %U:%G %n" ~/.gemini/antigravity-cli/settings.json'
```

## 5. Troubleshooting Linux RPM Deployments

| Symptom | Root Cause & Fix |
| :--- | :--- |
| `Permission denied` self-update warning in `agy` | Confirm `AGY_CLI_DISABLE_AUTO_UPDATE="true"` (lowercase `"true"`, not `"1"`) is exported in both `/etc/profile.d/google-antigravity-seed.sh` and `/usr/bin/agy`. |
| `~/.gemini/antigravity-cli/settings.json` missing over `ssh host agy ...` | Non-login SSH skips `/etc/profile.d/*.sh`. Use the `/usr/bin/agy` wrapper in `build-rpm.sh`, which seeds `settings.json` immediately before `exec`. |
| `agentControls` or `mcpControls` ignored | Those keys only apply inside `/etc/antigravity/admin_settings.json` (`0644`, `root:root`). Build with `INCLUDE_ADMIN_SETTINGS=1` and install `google-antigravity-admin-policy`. |
| `x509: certificate signed by unknown authority` | Install the corporate TLS inspection Root CA into `/etc/pki/ca-trust/source/anchors/` and run `sudo update-ca-trust`. |
