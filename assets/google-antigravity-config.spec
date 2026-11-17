%global debug_package %{nil}
# Disable binary stripping on pre-compiled Go executable
%global __strip /bin/true

%if 0%{?bundle_agy}
%global pkg_arch %{_arch}
%else
%global pkg_arch noarch
%endif

Name:           google-antigravity-config
Version:        %{pkg_version}
Release:        %{pkg_release}%{?dist}
Summary:        Native Red Hat RPM installer and CLI settings for Google Antigravity (agy)
License:        Apache-2.0
URL:            https://antigravity.google
BuildArch:      %{pkg_arch}
Requires:       coreutils

%description
Installs Google Antigravity CLI (agy), populates /etc/skel/.gemini/antigravity-cli/settings.json
for new local accounts, and idempotently seeds ~/.gemini/antigravity-cli/settings.json
for existing and SSO/LDAP/Okta WIF users via native Red Hat package management (no MDM required).

%if 0%{?with_admin_policy}
%package admin-policy
Summary:        Optional /etc/antigravity/admin_settings.json governance policy for Google Antigravity
BuildArch:      noarch
Requires:       %{name} = %{version}-%{release}

%description admin-policy
Optional subpackage that installs /etc/antigravity/admin_settings.json (root:root, 0644)
via native DNF/RPM for environments that choose to enforce system-wide Antigravity
agent, browser, MCP, or gateway governance controls without a third-party MDM agent.
%endif

%prep
%setup -q -c -T

%build
# Assets are pre-staged in SOURCE0 tarball

%install
rm -rf %{buildroot}
tar -xzf %{SOURCE0} -C %{buildroot}

%files
%defattr(-,root,root,-)

%dir %attr(0755,root,root) /usr/share/google-antigravity-config
%attr(0644,root,root) /usr/share/google-antigravity-config/agy-cli-settings.json

%dir %attr(0700,root,root) /etc/skel/.gemini
%dir %attr(0700,root,root) /etc/skel/.gemini/antigravity-cli
%config(noreplace) %attr(0600,root,root) /etc/skel/.gemini/antigravity-cli/settings.json

%attr(0644,root,root) /etc/profile.d/google-antigravity-seed.sh

%if 0%{?with_okta_wif_adc}
%attr(0644,root,root) /usr/share/google-antigravity-config/user_app_config.json
%dir %attr(0700,root,root) /etc/skel/.gemini/config
%config(noreplace) %attr(0600,root,root) /etc/skel/.gemini/config/config.json
%dir %attr(0755,root,root) /etc/antigravity
%config(noreplace) %attr(0644,root,root) /etc/antigravity/wif-okta-login-config.json
%endif

%if 0%{?bundle_agy}
%dir %attr(0755,root,root) /opt/google/antigravity-cli
%attr(0755,root,root) /opt/google/antigravity-cli/agy-bin
%attr(0755,root,root) /usr/bin/agy
%endif

%if 0%{?with_admin_policy}
%files admin-policy
%defattr(-,root,root,-)
%dir %attr(0755,root,root) /etc/antigravity
%config(noreplace) %attr(0644,root,root) /etc/antigravity/admin_settings.json
%endif

%changelog
* Tue Nov 17 2026 Platform Engineering <noreply@example.com> - 1.0.0-1
- Native Red Hat RPM packaging for Google Antigravity (agy) with optional Okta WIF ADC and admin-policy support
