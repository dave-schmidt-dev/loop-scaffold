# Security Policy

## Scope

This repository packages scaffold templates and loop automation scripts. It should not contain live credentials, private datasets, or environment-specific secrets.

## Reporting

If you find a security issue, please avoid filing a public issue with exploit details. Open a private report through the channel associated with the repository owner, or share a minimal reproduction without secrets.

## Expectations for Contributions

- Do not commit API keys, access tokens, cookies, session exports, or `.env` files.
- Keep new automation behavior opt-in when it weakens confirmation or approval boundaries.
- Prefer explicit configuration over hardcoded personal defaults.
