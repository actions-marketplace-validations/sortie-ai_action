# Security Policy

## Supported Versions

Security fixes ship in a new release of the latest major version and move its major tag, so a workflow that uses `sortie-ai/action@v1` receives them on its next run. A workflow pinned to an exact version or commit SHA must update the pin.

| Version | Supported |
|---------|-----------|
| v1 | Yes (latest v1.x.x) |

The Sortie binary the action installs has its own [security policy](https://github.com/sortie-ai/sortie/blob/main/SECURITY.md).

## Reporting a Vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Report vulnerabilities privately through:

- [GitHub Security Advisories](https://github.com/sortie-ai/action/security/advisories/new): "Report a vulnerability" button (preferred)
- If you are unable to use GitHub Security Advisories, email **security@sortie-ai.com** with the subject line `[VULNERABILITY] <short description>`.

### What to Include

- **Action version:** the tag or commit SHA in your `uses:` line, and the Sortie version from the step log.
- **Runner:** GitHub-hosted or self-hosted, OS and architecture.
- **Steps to reproduce:** the calling workflow, the Sortie workflow file, and the inputs that trigger the issue.
- **Impact assessment:** what an attacker can achieve (command execution, secret leak, unverified binary, etc.).
- **Proof of concept:** logs or a patch demonstrating the issue. If you have a fix, include it.

You do not need to encrypt your report. If you require encrypted communication, note this in your initial report and we will establish a secure channel.

## Response Process

| Stage | Timeline |
|-------|----------|
| Acknowledgment | Within **3 business days** of receipt |
| Initial triage and severity assessment | Within **7 business days** |
| Fix development and review | Depends on severity and complexity |
| Coordinated release | Negotiated with reporter |

If you have not received an acknowledgment within the stated window, follow up on the same channel.

## Disclosure Policy

We follow **coordinated disclosure**. The reporter and maintainers agree on a disclosure date, defaulting to **90 days** from the initial report or sooner once a fix is available. The fix release and a [GitHub Security Advisory](https://github.com/sortie-ai/action/security/advisories) are published together, and the reporter is credited unless they request anonymity.

## Scope

### In Scope

- Input text (`task`, `title`, `labels`, file contents) executed as shell code or as a workflow command.
- Secrets exposed in step logs or outputs by the action's own scripts.
- Installing a Sortie binary that failed checksum or attestation verification, including through a poisoned cache entry.
- State or files from one run reaching a later run or the repository checkout.

### Out of Scope

Please report these as regular issues, or to the project they belong to:

- Vulnerabilities in the Sortie binary: use the [Sortie security policy](https://github.com/sortie-ai/sortie/blob/main/SECURITY.md).
- Bugs in coding agents launched by Sortie.
- Secrets visible to the agent because the calling workflow set them on the step. The agent inherits the step's environment by design.
- An agent acting on instructions planted in pull request text, CI logs or checked-out files. That content is untrusted input to the agent, and the calling workflow decides what the agent may change and push.
- Issues that require write access to the calling workflow or the Sortie workflow file.
- Vulnerabilities in GitHub Actions, the runner, or the hosting environment.
- Automated scanner output without analysis demonstrating actual exploitability.

If you are unsure whether an issue is in scope, report it.
