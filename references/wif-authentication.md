# Workforce Identity Federation (WIF) Guide: Ping Identity & Okta

Use this reference when integrating **Google Antigravity (`agy`)** with **Ping Identity** (**PingFederate**, **PingOne**, or **PingOne Advanced Identity Cloud**) or **Okta** (OIDC or SAML 2.0) via **Google Cloud Workforce Identity Federation (WIF)**.

## 1. Workstation JSON Patterns (Identical for Both Ping Identity & Okta)

Neither `~/.gemini/antigravity-cli/settings.json` nor `/etc/antigravity/admin_settings.json` accepts a custom `wifProvider`, `pingIssuer`, or `oktaIssuer` field. Both **Ping Identity** and **Okta** use the exact same two workstation JSON patterns:

| Criteria | Pattern A (Recommended): Native `agy` Browser WIF | Pattern B: Pre-Provisioned `wif-login-config.json` + ADC |
| :--- | :--- | :--- |
| **JSON Bundled in `.zip` (or RPM)** | **4 lines** in `settings.json` (`gcp.project` + `gcp.location`) | **4 lines** in `settings.json` + **9 lines** in `wif-login-config.json` (+ **3 lines** in `config.json` for Desktop/IDE) |
| **Requires `google-cloud-cli` (`gcloud`)?** | **No** | **Yes** |
| **Build Command** | `./scripts/build-bundle.sh` *(default)* | `INCLUDE_WIF_ADC=1 GCP_QUOTA_PROJECT="example-gcp-project" ./scripts/build-bundle.sh` |
| **First-Time Developer Flow** | Selects **Sign in with Google Cloud → Workforce Identity Federation**, enters `locations/global/workforcePools/{pool_id}/providers/{provider_id}` **once**, signs into Ping or Okta + MFA in browser; `agy` saves the WIF provider in OS Keyring across restarts and `/logout`. | Runs `gcloud auth application-default login` (reads `CLOUDSDK_AUTH_LOGIN_CONFIG_FILE` automatically, opens Ping or Okta SSO + MFA), then runs `agy` with zero auth prompts (`AGY_ADC_AUTH="true"`). |

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

1. **`wif-login-config.json`** (`0600` user / `0644` system, contains **no secrets** — generated via `gcloud iam workforce-pools create-login-config` for either your Ping or Okta provider):
   ```json
   {
     "universe_domain": "googleapis.com",
     "universe_cloud_web_domain": "cloud.google",
     "type": "external_account_authorized_user_login_config",
     "audience": "//iam.googleapis.com/locations/global/workforcePools/example-workforce-pool/providers/ping-idp",
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
3. **Wrapper / Profile Environment Exports (handled automatically by `install.sh` when `INCLUDE_WIF_ADC=1`):**
   ```bash
   export AGY_ADC_AUTH="true"
   export GOOGLE_CLOUD_QUOTA_PROJECT="example-gcp-project"
   export CLOUDSDK_AUTH_LOGIN_CONFIG_FILE="$HOME/.config/antigravity/wif-login-config.json"
   ```

> **Note on Remote Control Flag:** `--remote-control` is hidden when `AGY_ADC_AUTH="true"` is active because Remote Control requires direct OAuth rather than ADC. Prefer **Pattern A** when developers use `agy` Remote Control.

---

## 2. Step 1 (Shared): Create the Google Cloud Workforce Pool

Create the Workforce Identity Pool once at the Google Cloud **Organization** level (`global`) before registering your Ping Identity or Okta provider:

```bash
ORG_ID="123456789012"
POOL_ID="example-workforce-pool"
GCP_PROJECT_ID="example-gcp-project"

gcloud iam workforce-pools create "$POOL_ID" \
  --organization="$ORG_ID" \
  --location="global" \
  --display-name="Corporate Workforce Pool" \
  --session-duration="43200s"
```

---

## 3. Step 2A: Configure Ping Identity (`PingFederate` or `PingOne`)

### Option P1: PingFederate or PingOne AIC via SAML 2.0 (Most Common for Enterprise Ping)

1. In **PingFederate** (**Applications → SP Connections → Create Connection → Browser SSO Profiles → SAML 2.0**) or **PingOne / PingOne AIC**, configure a new SAML 2.0 application with Google Cloud's Workforce Broker values (`PROVIDER_ID="ping-saml"`):
   - **Partner's Entity ID (SP Entity ID / Audience URI):**
     ```text
     https://iam.googleapis.com/locations/global/workforcePools/example-workforce-pool/providers/ping-saml
     ```
   - **Assertion Consumer Service (ACS) URL (POST binding, exact match, no trailing slash):**
     ```text
     https://auth.cloud.google/signin-callback/locations/global/workforcePools/example-workforce-pool/providers/ping-saml
     ```
2. Map `SAML_SUBJECT` (e.g., employee email or immutable user ID) and extend the SAML Attribute Contract with `email` and `groups` (mapped from LDAP/AD `memberOf` CNs or Ping group names, e.g., `antigravity-developers`).
3. Export the **SAML Signing / IdP Metadata XML** (`ping-idp-metadata.xml`) from PingFederate / PingOne and register the provider in Google Cloud:
   ```bash
   PROVIDER_ID="ping-saml"

   gcloud iam workforce-pools providers create-saml "$PROVIDER_ID" \
     --workforce-pool="$POOL_ID" \
     --location="global" \
     --display-name="Ping Identity SAML 2.0" \
     --idp-metadata-path="./ping-idp-metadata.xml" \
     --attribute-mapping="google.subject=assertion.subject,google.groups=assertion.attributes.groups,attribute.email=assertion.attributes.email[0]"
   ```

### Option P2: PingOne or PingFederate via OIDC (`create-oidc`)

1. In **PingOne** (**Applications → Add Application → OIDC Web App**) or **PingFederate** (**OAuth Server → Clients**):
   - Enable **Authorization Code** grant type.
   - Set **Redirect URI** (exact match, no trailing slash, `PROVIDER_ID="ping-oidc"`):
     ```text
     https://auth.cloud.google/signin-callback/locations/global/workforcePools/example-workforce-pool/providers/ping-oidc
     ```
   - Include `openid`, `profile`, `email`, and a `groups` claim on the ID token / UserInfo endpoint.
   - Copy the **Issuer URI**:
     - **PingOne Cloud:** `https://auth.pingone.com/{environment_id}/as` *(or `.eu`, `.ca`, `.asia` regional domain)*
     - **PingFederate:** `https://{pingfederate_host}` *(must match the exact `iss` claim in PingFederate's `/.well-known/openid-configuration`)*
2. Register the Ping OIDC provider in Google Cloud:
   ```bash
   PROVIDER_ID="ping-oidc"

   gcloud iam workforce-pools providers create-oidc "$PROVIDER_ID" \
     --workforce-pool="$POOL_ID" \
     --location="global" \
     --display-name="Ping Identity OIDC" \
     --issuer-uri="https://auth.pingone.com/YOUR_PING_ENV_ID/as" \
     --client-id="YOUR_PING_CLIENT_ID" \
     --client-secret-value="YOUR_PING_CLIENT_SECRET" \
     --web-sso-response-type="code" \
     --web-sso-assertion-claims-behavior="merge-user-info-over-id-token-claims" \
     --attribute-mapping="google.subject=assertion.sub,google.display_name=assertion.name,google.groups=assertion.groups,attribute.email=assertion.email"
   ```

---

## 4. Step 2B: Configure Okta (OIDC or SAML 2.0)

### Option O1: Okta OIDC Web App

1. In **Okta Admin Console → Applications → Create App Integration**, select **OIDC - OpenID Connect** and **Web Application**, enable **Authorization Code**, configure a `groups` claim, and set **Sign-in redirect URI**:
   ```text
   https://auth.cloud.google/signin-callback/locations/global/workforcePools/example-workforce-pool/providers/okta-oidc
   ```
2. Register the Okta OIDC provider in Google Cloud:
   ```bash
   PROVIDER_ID="okta-oidc"

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

### Option O2: Okta SAML 2.0 App

1. In **Okta Admin Console → Applications → Create App Integration → SAML 2.0**, set:
   - **Single sign-on URL (ACS URL):** `https://auth.cloud.google/signin-callback/locations/global/workforcePools/example-workforce-pool/providers/okta-saml`
   - **Audience URI (SP Entity ID):** `https://iam.googleapis.com/locations/global/workforcePools/example-workforce-pool/providers/okta-saml`
2. Add Attribute Statements (`email` → `user.email`) and Group Attribute Statements (`groups`), download `okta-idp-metadata.xml`, and register:
   ```bash
   PROVIDER_ID="okta-saml"

   gcloud iam workforce-pools providers create-saml "$PROVIDER_ID" \
     --workforce-pool="$POOL_ID" \
     --location="global" \
     --display-name="Okta SAML 2.0" \
     --idp-metadata-path="./okta-idp-metadata.xml" \
     --attribute-mapping="google.subject=assertion.subject,google.groups=assertion.attributes.groups,attribute.email=assertion.attributes.email[0]"
   ```

---

## 5. Step 3 (Shared): Grant Cloud IAM Roles & Firewall Allowlist

### 5.1 Bind Your Federated Ping or Okta Group to the Google Cloud Project

```bash
IDP_GROUP="antigravity-developers"
PRINCIPAL_SET="principalSet://iam.googleapis.com/locations/global/workforcePools/${POOL_ID}/group/${IDP_GROUP}"

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

### 5.2 Generate `wif-login-config.json` (Pattern B Only)

```bash
gcloud iam workforce-pools create-login-config \
  "locations/global/workforcePools/${POOL_ID}/providers/${PROVIDER_ID}" \
  --output-file="assets/configs/wif-login-config.json"

WIF_LOGIN_CONFIG_FILE="assets/configs/wif-login-config.json" \
INCLUDE_WIF_ADC=1 \
GCP_QUOTA_PROJECT="$GCP_PROJECT_ID" \
./scripts/build-bundle.sh
```

### 5.3 Outbound `TCP 443` Firewall Allowlist (Ping Identity & Okta)

- **IdP SSO Host(s):**
  - **Ping Identity:** `{pingfederate_host}`, `auth.pingone.com` *(or `.eu` / `.ca` / `.asia`)*, `*.pingidentity.com` / `*.forgeblocks.com` (PingOne AIC)
  - **Okta:** `{org}.okta.com` *(or `{org}.oktapreview.com` / custom domain)*
- **Google WIF & STS:** `auth.cloud.google`, `sts.googleapis.com`, `oauth2.googleapis.com`, `iamcredentials.googleapis.com`, `www.googleapis.com`
- **Antigravity & Cloud AI:** `antigravity.google`, `businessaicode.googleapis.com`, `cloudcode-pa.googleapis.com`, `aiplatform.googleapis.com`, `discoveryengine.googleapis.com`

---

## 6. Troubleshooting Ping & Okta WIF

| Error / Symptom | Resolution |
| :--- | :--- |
| `Invalid redirect_uri` (OIDC) or ACS mismatch (SAML) | Confirm the Ping or Okta callback URL matches `https://auth.cloud.google/signin-callback/locations/global/workforcePools/{pool_id}/providers/{provider_id}` byte-for-byte with no trailing slash. |
| PingFederate OIDC `Issuer mismatch` | Ensure `--issuer-uri` matches the exact `iss` string in `https://{pingfederate_host}/.well-known/openid-configuration` (PingFederate often includes or omits a trailing `/` depending on Virtual Server ID settings). |
| Ping SAML `groups` claim empty (`PERMISSION_DENIED`) | In PingFederate, if LDAP `memberOf` sends full DNs (`CN=antigravity-developers,OU=...`), either apply an OGNL expression extracting the `CN` or match the full attribute value in your `$PRINCIPAL_SET` group binding. |
| `ADC authentication failed` when `AGY_ADC_AUTH="true"` | Run `gcloud auth application-default login` (note: `gcloud auth login` without `application-default` does **not** create `~/.config/gcloud/application_default_credentials.json`). |
