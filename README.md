<h1 align="center">Sortie Action</h1>
<p align="center">
  <a href="https://github.com/sortie-ai/action/actions/workflows/ci.yml">
    <img alt="CI" src="https://github.com/sortie-ai/action/actions/workflows/ci.yml/badge.svg">
  </a>
  <a href="https://github.com/sortie-ai/action/actions/workflows/self-test.yml">
    <img alt="Self-test" src="https://github.com/sortie-ai/action/actions/workflows/self-test.yml/badge.svg">
  </a>
</p>

Hand a task from your GitHub workflow to a coding agent and get a reviewable change back.

The action runs [Sortie](https://github.com/sortie-ai/sortie) once. Your workflow's triggers decide that there is work, such as a failed Dependabot update, a schedule, or a merge. Sortie then drives the agent your Sortie workflow file selects, under that file's timeouts, cost limits, and hooks. The step passes when the agent finishes the task and fails otherwise.

## Highlights

- Works with any agent Sortie supports, including Claude Code, Codex, Copilot CLI, and OpenCode
- Runs on Linux, macOS, and Windows runners, as a composite action with no Docker image
- Verifies every download against the release checksums and its GitHub attestation
- Caches the Sortie release between runs
- Stops the agent gracefully and runs its hooks when the job is cancelled

## Usage

```yaml
steps:
  - uses: actions/checkout@v7
    with:
      persist-credentials: false

  - run: npm install -g @anthropic-ai/claude-code@latest

  - uses: sortie-ai/action@v1
    with:
      workflow: .sortie/WORKFLOW.md
      task: Update the README so that it lists the supported Node.js versions.
      version: v1.30.0
    env:
      ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
```

The action installs Sortie, not the agent. Install the agent's CLI in an earlier step and pass its key in the action step's `env:`.

### Inputs

| Input | Default | Description |
|---|---|---|
| `workflow` | | Path to your Sortie workflow file. Required. |
| `task` | | Task text for the agent. |
| `task-file` | | Path to a file with the task text, for long input such as a CI log. Use instead of `task`. |
| `title` | first line of the task | Title of the task. |
| `labels` | | Comma-separated labels, so your workflow file can pick an agent or prompt per task. |
| `version` | `latest` | Sortie version to install. Pin it, for example `v1.30.0`. Versions older than `v1.30.0` are refused. |
| `verify-attestation` | `true` | Check the download against its GitHub attestation. The checksum check always runs. |

### Outputs

| Output | Description |
|---|---|
| `outcome` | How the task ended: `succeeded`, `stopped`, `failed`, or `cancelled`. |
| `exit-code` | Exit status of Sortie. |

## Examples

Each example is a complete GitHub workflow with its Sortie workflow file:

- [Fix a failed Dependabot pull request](examples/dependabot-fix)
- [Sync documentation on a schedule](examples/docs-sync)
- [Open a documentation pull request in another repository](examples/cross-repo-docs)

## Documentation

Writing Sortie workflow files, agent setup, and credentials are covered in the [Sortie documentation](https://docs.sortie-ai.com).

## License

Sortie Action is released under the [Apache License 2.0](LICENSE).

## Support

Found a bug or missing something? [Open an issue](https://github.com/sortie-ai/action/issues).
