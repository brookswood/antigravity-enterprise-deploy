# `antigravity-enterprise-deploy` — Agent Skill

An open-source [Agent Skill](https://agentskills.io) for generating turnkey enterprise Linux deployment configurations, native Red Hat RPM packages (`dnf` / `rpmbuild`), and **Okta Workforce Identity Federation (WIF)** authentication setups for **Google Antigravity (`agy`)**.

![Google Antigravity Okta WIF Architecture](docs/images/antigravity-okta-wif-architecture.png)

## What This Skill Covers

- **Configuration Schema & Precedence Guardrails:** Prevents common misconfigurations across `~/.gemini/antigravity-cli/settings.json` (`0600`), `~/.gemini/config/config.json` (`enableAdc`), and optional `/etc/antigravity/admin_settings.json` (`0644`, `root:root`).
- **Native Red Hat / RPM Packaging (`dnf`, Optional MDM):** Turnkey [`scripts/build-rpm.sh`](scripts/build-rpm.sh) and [`assets/google-antigravity-config.spec`](assets/google-antigravity-config.spec) supporting RHEL 8/9/10, Rocky Linux, AlmaLinux, and Fedora with SHA-512 binary verification, `AGY_CLI_DISABLE_AUTO_UPDATE="true"`, non-login SSH wrapper seeding, and an opt-in `google-antigravity-admin-policy` subpackage.
- **Okta (OIDC & SAML 2.0) + Google Cloud Workforce Identity Federation (WIF):**
  - **Pattern A (Recommended):** 4-line `gcp` block in `settings.json` + native `agy` PKCE WIF browser sign-in (zero `gcloud` dependency).
  - **Pattern B:** Zero-paste `/etc/antigravity/wif-okta-login-config.json` (`gcloud iam workforce-pools create-login-config`) + Application Default Credentials (`AGY_ADC_AUTH="true"` / `enableAdc: true`).

![Google Antigravity Native Red Hat RPM Architecture](docs/images/antigravity-rpm-architecture.png)

## Install the Skill

### Google Antigravity (`agy`)

```bash
git clone https://github.com/brookswood/antigravity-enterprise-deploy.git \
  ~/.gemini/config/skills/antigravity-enterprise-deploy
```

### Agent Skills CLI (`npx skills`)

```bash
npx skills add brookswood/antigravity-enterprise-deploy
```

## Repository Structure

```text
antigravity-enterprise-deploy/
├── SKILL.md                                  # Router, schema guardrails & precedence map
├── references/
│   ├── rhel-rpm-packaging.md                 # Native DNF/RPM build, TLS CA & proxy guide
│   └── okta-wif-authentication.md            # Okta OIDC/SAML Workforce Pool, IAM & ADC guide
├── scripts/
│   └── build-rpm.sh                          # Turnkey RPM builder (SHA-512 verified)
└── assets/
    ├── google-antigravity-config.spec        # RPM spec (base + optional admin-policy)
    └── configs/
        ├── agy-cli-settings.json             # Template for ~/.gemini/antigravity-cli/settings.json
        ├── admin_settings.json               # Optional /etc/antigravity/admin_settings.json template
        ├── user_app_config.json              # Optional ~/.gemini/config/config.json (enableAdc)
        └── wif-okta-login-config.example.json
```

## License

[Apache-2.0](LICENSE)
