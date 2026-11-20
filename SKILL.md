---
name: antigravity-enterprise-deploy
description: >-
  Generates portable enterprise Linux installer .zip bundles (default, bundling
  the agy binary, pre-seeded JSON settings files, and install.sh) or optional OS
  packages (Red Hat RPM via dnf/rpmbuild), plus 1-step Workforce Identity
  Federation (WIF) authentication setups with Ping Identity (PingFederate,
  PingOne) or Okta (OIDC and SAML 2.0) for Google Antigravity (agy). Use when
  packaging or deploying Google Antigravity (agy) as a standalone zip installer
  or optional RHEL/Rocky/AlmaLinux/Fedora RPM, configuring
  ~/.gemini/antigravity-cli/settings.json, ~/.gemini/config/config.json, or
  optional /etc/antigravity/admin_settings.json, or integrating Ping Identity
  or Okta with Google Cloud WIF so end users sign in with a 1-step browser
  redirect and zero gcloud dependency. Don't use for consumer personal Gmail
  onboarding, Compute Engine VM capacity reservations, or unrelated developer
  CLIs.
---

# Google Antigravity (`agy`) Enterprise `.zip` Bundle, 1-Step WIF (Ping & Okta) & Optional RPM

Produces **portable `.zip` installer bundles by default** (`bin/agy-bin` + pre-seeded `.json` files + `install.sh` — **zero `gcloud` CLI, zero OS package manager, and zero MDM required**) so end users simply launch `agy`, press **`Enter`** on **`> 1. Continue with <ping-or-okta>`**, and get redirected straight to **Ping Identity** or **Okta** in their browser.

## Default vs. Optional Packaging Modes

- **Default Mode — Portable `.zip` Bundle (`scripts/build-bundle.sh`):**
  Exports `dist/antigravity-enterprise-bundle-linux-<arch>.zip` containing the SHA-512 verified `agy` binary, `settings.json`, pre-seeded WIF redirect files (`onboarding.json` + `wif-provider-seed.json`), and `install.sh` (`./install.sh` for zero-`sudo` user install, or `sudo ./install.sh --system`).
- **Optional Mode — Native Red Hat `.rpm` Package (`scripts/build-rpm.sh`):**
  Use **only** when the user explicitly requests a `.rpm` package for `dnf` / `yum` / Red Hat Satellite.

## Critical Gotchas (Prevent Silent Misconfigurations)

1. **How 1-Step WIF Redirect Works Without `gcloud` CLI:**
   Neither `settings.json` nor `admin_settings.json` accepts a `wifProvider` key (`admin_settings.json` enforces `additionalProperties: false`; `settings.json` ignores unknown keys). To give end users a **1-step redirect straight to Ping or Okta** with **zero `gcloud` CLI and zero manual provider typing**, pass `WIF_PROVIDER="locations/global/workforcePools/{pool_id}/providers/{provider_id}"` to `scripts/build-bundle.sh`. That pre-seeds three `0600` files under `~/.gemini/antigravity-cli/` (only if absent so active tokens are never overwritten):
   - `settings.json`: pre-fills `gcp.project` and `gcp.location` (`"global"`).
   - `cache/onboarding.json`: `{"previousAuthMethod": "wif"}` ([onboarding seed template](assets/configs/onboarding.json)).
   - `antigravity-oauth-token`: `{"saved_wif_provider": "locations/global/workforcePools/{pool_id}/providers/{provider_id}"}` ([WIF provider seed example](assets/configs/wif-provider-seed.example.json)).
   On first launch, `agy` immediately highlights **`> 1. Continue with {provider_id}`** — the user presses `Enter` once and is redirected straight to Ping or Okta SSO!
2. **Exact `agy` User Settings Path (`~/.gemini/antigravity-cli/settings.json`):**
   `agy` reads CLI preferences from `~/.gemini/antigravity-cli/settings.json` (`0600`), **not** bare `~/.gemini/settings.json`.
3. **`AGY_CLI_DISABLE_AUTO_UPDATE` Requires Literal Lowercase `"true"`:**
   Export `AGY_CLI_DISABLE_AUTO_UPDATE="true"` (literal lowercase `"true"` — `"1"` does **not** disable self-update checks).
4. **MDM & `/etc/antigravity/admin_settings.json` Are Strictly Optional:**
   Omit `admin_settings.json` (`INCLUDE_ADMIN_SETTINGS=0`, default) unless you need root-locked (`0644`, `root:root`) governance ceilings (`agentControls`, `browserControls`, `mcpControls`, `pluginControls`, `featureControls`), JetBrains/Zed file policy, or a custom Enterprise Gateway (`gateway.enabled: true`).
5. **Non-Interactive SSH Safety:**
   Non-login SSH commands (`ssh host agy ...`) skip `~/.bashrc` and `/etc/profile.d/*.sh`. Both `build-bundle.sh` and `build-rpm.sh` install a lightweight `agy` wrapper that idempotently seeds missing `0600` user files right before `exec`.

## Configuration & Pre-Seed File Map

| Linux File Path | Included in Default WIF `.zip`? | Purpose |
| :--- | :--- | :--- |
| `~/.gemini/antigravity-cli/settings.json` | **Yes** (`0600`) | Pre-populates `gcp` (`project`, `location`), `toolPermission`, `enableTerminalSandbox`, `permissions` |
| `~/.gemini/antigravity-cli/cache/onboarding.json` | **Yes, when `WIF_PROVIDER` set** (`0600`) | Sets `{"previousAuthMethod": "wif"}` so `agy` shows 1-step `Continue with <provider>` on first run |
| `~/.gemini/antigravity-cli/antigravity-oauth-token` | **Yes, when `WIF_PROVIDER` set** (`0600`, seed-if-absent) | Pre-populates `saved_wif_provider` (works even with Linux OS Keyring because empty keyrings fall back to file storage on first run) |
| `wif-login-config.json` & `~/.gemini/config/config.json` | **Optional (`INCLUDE_WIF_ADC=1`)** | Alternative `gcloud` ADC flow (`enableAdc: true` + `AGY_ADC_AUTH="true"`); **requires `gcloud` CLI** |
| `/etc/antigravity/admin_settings.json` | **Optional (`INCLUDE_ADMIN_SETTINGS=1`)** | Root-only (`0644`, `root:root`) governance locks across `agy`, Desktop App, VS Code, JetBrains, and Zed |

## Workflow Router

1. **Default Action — Export the 1-Step WIF `.zip` Bundle (Zero `gcloud` Required):**
   Edit `gcp.project` in the [CLI settings template](assets/configs/agy-cli-settings.json), then run the [portable ZIP bundle builder](scripts/build-bundle.sh) with your Ping Identity or Okta WIF provider resource name:
   ```bash
   # Recommended: 1-step Ping Identity or Okta WIF .zip (no gcloud CLI, no provider typing by end users)
   WIF_PROVIDER="locations/global/workforcePools/example-workforce-pool/providers/ping-sso" \
     ./scripts/build-bundle.sh

   # End-user experience on target workstation:
   #   1) unzip antigravity-enterprise-bundle-linux-amd64.zip && ./antigravity-enterprise-bundle-linux-amd64/install.sh
   #   2) Run `agy` -> press Enter on "> 1. Continue with ping-sso" -> sign in via browser!
   ```
2. **Ping Identity (`PingFederate` / `PingOne`) & Okta Workforce Pool Setup:**
   Read the [Ping Identity and Okta WIF authentication guide](references/wif-authentication.md) for side-by-side SAML 2.0 & OIDC Workforce Pool setup, Cloud IAM `principalSet` bindings, firewall allowlists, and the optional `gcloud` ADC alternative ([WIF login config example](assets/configs/wif-login-config.example.json) and [desktop ADC config template](assets/configs/user_app_config.json)).
3. **Optional Native Red Hat `.rpm` Package (`dnf` / `rpmbuild`):**
   Only when requested instead of `.zip`, read the [optional RHEL RPM packaging guide](references/rhel-rpm-packaging.md) and use the [optional RPM build script](scripts/build-rpm.sh), [RPM spec template](assets/google-antigravity-config.spec), and optional [admin policy template](assets/configs/admin_settings.json).

## Public Documentation References

- **Antigravity in the Enterprise (Licensing, WIF & ADC):** https://antigravity.google/docs/enterprise
- **Antigravity CLI Install, Reference & Settings:** https://antigravity.google/docs/cli/install · https://antigravity.google/docs/cli/reference · https://antigravity.google/docs/settings · https://antigravity.google/docs/permissions
- **Workforce Identity Federation with PingFederate & PingOne AIC:** https://docs.cloud.google.com/iam/docs/workforce-federation-pingfederate · https://docs.cloud.google.com/iam/docs/workforce-federation-pingone-aic · https://docs.cloud.google.com/iam/docs/workforce-federation-oidc-saml
- **Workforce Identity Federation with Okta & `create-login-config`:** https://docs.cloud.google.com/iam/docs/workforce-sign-in-okta · https://docs.cloud.google.com/iam/docs/configuring-workforce-identity-federation · https://docs.cloud.google.com/sdk/gcloud/reference/iam/workforce-pools/create-login-config
- **Enterprise Gateway & Linux `/etc/antigravity/admin_settings.json` Precedence:** https://docs.cloud.google.com/gemini/enterprise/docs/ai-developer-tools/deploy-enterprise-gateway#deploy-mdm · https://docs.cloud.google.com/docs/security/compliance/deploy-antigravity-us-public-sector
