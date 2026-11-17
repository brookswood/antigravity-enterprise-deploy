# Okta & Google Cloud Workforce Identity Federation (WIF) Guide

Use this reference when integrating **Google Antigravity (`agy`)** with **Okta** (OIDC or SAML 2.0) and **Google Cloud Workforce Identity Federation (WIF)**.

## 1. Choosing Pattern A vs. Pattern B

Neither `~/.gemini/antigravity-cli/settings.json` nor `/etc/antigravity/admin_settings.json` supports a custom `wifProvider` JSON property. Choose one of the two supported workstation patterns below:

| Criteria | Pattern A (Recommended): Native `agy` Browser WIF | Pattern B: Pre-Provisioned `wif-okta-login-config.json` + ADC |
| :--- | :--- | :--- |
| **JSON Seeded on Workstation** | **4 lines** in `~/.gemini/antigravity-cli/settings.json` (`gcp.project` + `gcp.location`) | **4 lines** in `settings.json` + **9 lines** in `/etc/antigravity/wif-okta-login-config.json` (+ **3 lines** in `~/.gemini/config/config.json` for Desktop/IDE) |
| **Requires `google-cloud-cli` (`gcloud`)?** | **No** | **Yes** |
| **First-Time Developer Flow** | Selects **Sign in with Google Cloud → Workforce Identity Federation**, enters `locations/global/workforcePools/{pool_id}/providers/{provider_id}` **once**, completes Okta SSO + MFA; `agy` persists the WIF provider in OS Keyring across restarts and `/logout`. | Runs `gcloud auth application-default login` (reads `CLOUDSDK_AUTH_LOGIN_CONFIG_FILE` automatically, opens Okta SSO + MFA), then runs `agy` with zero prompts (`AGY_ADC_AUTH="true"`). |

### Pattern A Workstation JSON (`~/.gemini/antigravity-cli/settings.json`)

```json
{
  "gcp": {
    "project": "example-gcp-project",
    "location": "global"
  }
}
```

### Pattern B Workstation JSONs & Environment Variables

1. **`/etc/antigravity/wif-okta-login-config.json`** (`0644`, contains **no secrets** — generated via `gcloud iam workforce-pools create-login-config`):
   ```json
   {
     "universe_domain": "googleapis.com",
     "universe_cloud_web_domain": "cloud.google",
     "type": "external_account_authorized_user_login_config",
     "audience": "//iam.googleapis.com/locations/global/workforcePools/example-okta-pool/providers/okta-oidc",
     "auth_url": "https://auth.cloud.google/authorize",
     "token_url": "https://sts.googleapis.com/v1/oauthtoken",
     "token_info_url": "https://sts.googleapis.com/v1/introspect"
   }
   ```
2. **`~/.gemini/config/config.json`** (`0600` — enables ADC in the Antigravity Desktop / IDE app):
   ```json
   {
     "userSettings": {
       "enableAdc": true
     }
   }
   ```
3. **`/etc/profile.d/` Environment Exports (for `agy` CLI + `gcloud`):**
   ```bash
   export AGY_ADC_AUTH="true"
   export GOOGLE_CLOUD_QUOTA_PROJECT="example-gcp-project"
   export CLOUDSDK_AUTH_LOGIN_CONFIG_FILE="/etc/antigravity/wif-okta-login-config.json"
   ```

> **Note on Remote Control Flag:** `--remote-control` is hidden when `AGY_ADC_AUTH="true"` is active because Remote Control requires direct OAuth rather than ADC. Prefer **Pattern A** if developers use `agy` Remote Control.

## 2. One-Time Admin Setup: Google Cloud Workforce Pool & Okta App

### 2.1 Create the Organization Workforce Pool

```bash
ORG_ID="123456789012"
POOL_ID="example-okta-pool"
PROVIDER_ID="okta-oidc"
GCP_PROJECT_ID="example-gcp-project"

gcloud iam workforce-pools create "$POOL_ID" \
  --organization="$ORG_ID" \
  --location="global" \
  --display-name="Corporate Okta Workforce Pool" \
  --session-duration="43200s"
```

### 2.2 Configure Okta Provider (Option 1: OIDC — Recommended)

1. In **Okta Admin Console → Applications → Create App Integration**, choose **OIDC - OpenID Connect** and **Web Application**.
2. Enable **Authorization Code** grant type.
3. Set **Sign-in redirect URI** (exact match, no trailing slash):
   ```text
   https://auth.cloud.google/signin-callback/locations/global/workforcePools/example-okta-pool/providers/okta-oidc
   ```
4. Configure a `groups` claim on the ID token and assign your developer Okta group (e.g., `antigravity-developers`).
5. Register the OIDC provider in Google Cloud:
   ```bash
   gcloud iam workforce-pools providers create-oidc "$PROVIDER_ID" \
     --workforce-pool="$POOL_ID" \
     --location="global" \
     --display-name="Okta OIDC" \
     --issuer-uri="https://example.okta.com/oauth2/default" \
     --client-id="YOUR_OKTA_CLIENT_ID" \
     --client-secret-value="YOUR_OKTA_CLIENT_SECRET" \
     --web-sso-response-type="code" \
     --web-sso-assertion-claims-behavior="merge-user-info-over-id-token-claims" \
     --attribute-mapping="google.subject=assertion.sub,google.display_name=assertion.name,google.groups=assertion.groups,attribute.email=assertion.email"
   ```

### 2.3 Configure Okta Provider (Option 2: SAML 2.0 Alternative)

1. In **Okta Admin Console → Applications → Create App Integration**, choose **SAML 2.0**.
2. Set:
   - **Single sign-on URL (ACS URL):** `https://auth.cloud.google/signin-callback/locations/global/workforcePools/example-okta-pool/providers/okta-saml`
   - **Audience URI (SP Entity ID):** `https://iam.googleapis.com/locations/global/workforcePools/example-okta-pool/providers/okta-saml`
3. Configure Attribute Statements (`email` → `user.email`) and Group Attribute Statements (`groups`), download the IdP Metadata XML, and register:
   ```bash
   gcloud iam workforce-pools providers create-saml "okta-saml" \
     --workforce-pool="$POOL_ID" \
     --location="global" \
     --display-name="Okta SAML 2.0" \
     --idp-metadata-path="./okta-idp-metadata.xml" \
     --attribute-mapping="google.subject=assertion.subject,google.groups=assertion.attributes.groups,attribute.email=assertion.attributes.email[0]"
   ```

### 2.4 Enable APIs & Bind Cloud IAM Roles to the Okta Group

```bash
OKTA_GROUP="antigravity-developers"
PRINCIPAL_SET="principalSet://iam.googleapis.com/locations/global/workforcePools/${POOL_ID}/group/${OKTA_GROUP}"

gcloud services enable \
  cloudaicompanion.googleapis.com \
  aiplatform.googleapis.com \
  iam.googleapis.com \
  sts.googleapis.com \
  --project="$GCP_PROJECT_ID"

gcloud projects add-iam-policy-binding "$GCP_PROJECT_ID" \
  --member="$PRINCIPAL_SET" \
  --role="roles/cloudaicompanion.user"

gcloud projects add-iam-policy-binding "$GCP_PROJECT_ID" \
  --member="$PRINCIPAL_SET" \
  --role="roles/serviceusage.serviceUsageConsumer"
```

If using **Gemini Enterprise Standard or Plus** seat licenses rather than consumption billing, also assign seats to `$PRINCIPAL_SET` in **Google Cloud Console → Gemini Enterprise → Licenses**.

### 2.5 Generate `wif-okta-login-config.json` (Pattern B Only)

```bash
gcloud iam workforce-pools create-login-config \
  "locations/global/workforcePools/${POOL_ID}/providers/${PROVIDER_ID}" \
  --output-file="configs/wif-okta-login-config.json"
```

## 3. Developer Verification & Headless SSH Notes

- **Pattern A verification:** Run `agy`, select **Sign in with Google Cloud → Workforce Identity Federation**, and enter `locations/global/workforcePools/{pool_id}/providers/{provider_id}`. Over headless SSH (`SSH_CONNECTION` / `SSH_TTY`), `agy` automatically skips launching a local browser, prints the `https://auth.cloud.google/authorize?...` URL for laptop sign-in, and prompts for the authorization code.
- **Pattern B verification:** Run `gcloud auth application-default login` (add `--no-browser` over headless SSH; note that `gcloud auth login` without `application-default` does **not** populate ADC), run `gcloud auth application-default set-quota-project example-gcp-project` if needed, and launch `agy`.

## 4. Troubleshooting Okta + WIF

| Error / Symptom | Resolution |
| :--- | :--- |
| `Invalid redirect_uri` on Okta login page | Confirm the Okta Redirect URI / ACS URL matches `https://auth.cloud.google/signin-callback/locations/global/workforcePools/{pool_id}/providers/{provider_id}` with no trailing slash. |
| `PERMISSION_DENIED` on `cloudaicompanion.googleapis.com` | Verify `google.groups` attribute mapping matches your Okta group claim and that both `roles/cloudaicompanion.user` and `roles/serviceusage.serviceUsageConsumer` are bound on `{gcp_project_id}`. |
| `ADC authentication failed` when `AGY_ADC_AUTH="true"` | Run `gcloud auth application-default login` to create or refresh `~/.config/gcloud/application_default_credentials.json`. |
| `SERVICE_DISABLED` or missing quota project under ADC | Enable `sts.googleapis.com` and `cloudaicompanion.googleapis.com` on `{gcp_project_id}` and export `GOOGLE_CLOUD_QUOTA_PROJECT="{gcp_project_id}"`. |
