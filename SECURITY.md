# Security Policy

## Supported versions

Security fixes are applied to the latest release on the default branch. Older development builds are not supported.

## Reporting a vulnerability

Please do not open a public issue for a vulnerability that could put users at risk.

Use GitHub's **Report a vulnerability** / private security advisory feature for this repository. Include:

- Affected version and macOS version
- Reproduction steps
- Security impact
- Any suggested mitigation

The maintainer will acknowledge a complete report when practical, investigate it, and coordinate disclosure after a fix is available.

## Display safety

A bug that can disable every visible display, prevent recovery of a display disabled by LumaDeck, or unexpectedly intercept user input should be treated as a security-sensitive safety issue.

## Private API warning

The full build dynamically resolves undocumented macOS display APIs. This is an explicit compatibility risk, not a security boundary. Do not assume those APIs are stable or validated by Apple for third-party use.
