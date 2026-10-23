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

Your workflow decides when there is work. The action runs [Sortie](https://github.com/sortie-ai/sortie) once, and Sortie drives the agent under the timeouts and cost limits from your Sortie workflow file. The step fails if the agent does not finish the task.

## Highlights

- Works with any agent Sortie supports, including Claude Code, Copilot, OpenCode, Codex, Kiro and Gemini
- Runs on Linux, macOS, and Windows runners, on x64 and arm64, with no Docker image
- Verifies every download against the release checksums and its GitHub attestation
- Caches the Sortie release between runs
- Stops the agent gracefully and runs its hooks when the job is cancelled

## Usage

A Dependabot update broke the build. Nobody has to read the log: the agent gets it and fixes the code.

```yaml
on:
  workflow_run:
    workflows: [CI]
    types: [completed]

jobs:
  fix-dependabot:
    runs-on: ubuntu-latest
    if: >-
      github.event.workflow_run.conclusion == 'failure' &&
      github.event.workflow_run.actor.login == 'dependabot[bot]' &&
      github.event.workflow_run.head_repository.full_name == github.repository
    
    permissions:
      contents: write
      actions: read

    steps:
      - uses: actions/checkout@v7
        with:
          ref: ${{ github.event.workflow_run.head_sha }}
          persist-credentials: false

      - run: npm install -g @anthropic-ai/claude-code

      - run: gh run view "$RUN_ID" --log-failed > "$RUNNER_TEMP/failure.log"
        env:
          GH_TOKEN: ${{ github.token }}
          RUN_ID: ${{ github.event.workflow_run.id }}

      - uses: sortie-ai/action@v1
        with:
          workflow: .sortie/WORKFLOW.md
          title: Fix '${{ github.event.workflow_run.display_title }}' dependabot update
          task-file: ${{ runner.temp }}/failure.log
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
```

The [examples](#examples) show how to push the fix and open a pull request.

### Inputs

| Input | Default | Description |
|---|---|---|
| `workflow` | | Path to your Sortie workflow file. Required. |
| `task` | | Task text for the agent. |
| `task-file` | | Path to a file with the task text, for long input such as a CI log. Use instead of `task`. |
| `title` | first line of the task | Task title. |
| `labels` | | Comma-separated labels, so your workflow file can pick an agent or prompt per task. |
| `version` | `latest` | Sortie version to install. Pin it, for example `v1.30.0`. Versions older than `v1.30.0` are refused. |
| `verify-attestation` | `true` | Check the download against its GitHub attestation. The checksum check always runs. |

### Outputs

| Output | Description |
|---|---|
| `outcome` | How the task ended: `succeeded`, `stopped`, `failed`, or `cancelled`. |
| `exit-code` | Exit status of Sortie. |

## Examples

- [Fix a failed Dependabot pull request](examples/dependabot-fix)
- [Sync documentation on a schedule](examples/docs-sync)
- [Open a documentation pull request in another repository](examples/cross-repo-docs)

## Documentation

See the [Sortie documentation](https://docs.sortie-ai.com) for workflow files, agents, and credentials.

## License

Sortie Action is released under the [Apache License 2.0](LICENSE).

## Support

Found a bug or missing something? [Open an issue](https://github.com/sortie-ai/action/issues).
