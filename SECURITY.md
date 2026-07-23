# Security policy

## Supported versions

Security fixes are applied to the latest published release.

## Reporting a vulnerability

Do not post credentials, tokens, private network details, or an exploitable
security issue in a public GitHub issue. Use GitHub's **Report a
vulnerability** private-reporting feature for this repository. If private
reporting is unavailable, open a public issue containing only a request for a
private contact channel and no vulnerability details.

Include the affected version, hardware, reproduction conditions, impact, and
suggested mitigation when possible. Credentials accidentally exposed in logs
should be revoked immediately.

The gateway is intended for a trusted local network. The HTTP integration has
no independent authentication layer beyond Tasmota's configuration, so do not
expose it directly to the internet.
