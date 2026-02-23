# Security Policy

## Supported Versions

Only the latest release is supported.

| Version | Supported          |
|:--------|:------------------ |
| latest  | :white_check_mark: |
| older   | :x:                |

## Reporting a Vulnerability

**Do not submit an issue or pull request**: this might reveal the vulnerability.

Instead, [privately report a vulnerability via GitHub](https://github.com/geneyoo/nocrumbs/security/advisories/new).

We will deal with the vulnerability privately and submit a patch as soon as possible.

## Scope

NoCrumbs is fully local — no network calls, no telemetry. Security concerns are limited to local data handling and subprocess execution. Gitleaks pre-commit scanning is enabled to prevent accidental secret commits.
