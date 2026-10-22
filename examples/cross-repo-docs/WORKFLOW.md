---
tracker:
  kind: file
  active_states:
    - To Do
  terminal_states:
    - Done
  handoff_state: In Review

file:
  path: $SORTIE_ACTION_TASK_FILE

hooks:
  after_create: |
    git clone --quiet "$SORTIE_CHECKOUT_DIR" .
    git clone --quiet "$SORTIE_SOURCE_DIR" source
    printf '.sortie/\nsource/\n' >> .git/info/exclude
  before_run: |
    git checkout --quiet -B "sortie/${SORTIE_ISSUE_IDENTIFIER}"
  after_run: |
    [ "$SORTIE_RUN_OUTCOME" = succeeded ] || exit 0
    git add -A
    git diff --cached --quiet || git \
      -c user.name=github-actions[bot] \
      -c user.email=41898282+github-actions[bot]@users.noreply.github.com \
      commit --quiet -m "docs: document the latest change of the source repository"
    git push --quiet origin "sortie/${SORTIE_ISSUE_IDENTIFIER}"
  timeout_ms: 120000

agent:
  kind: claude-code
  max_turns: 3
  max_sessions: 1
  max_cost_usd: 5
  turn_timeout_ms: 600000

claude-code:
  permission_mode: bypassPermissions
  max_budget_usd: 5
---

{{/* The working directory is the documentation repository; the source
     repository is a read-only clone in source/. needs-human-review ends the
     run as succeeded; blocked ends it as stopped, which keeps after_run from
     pushing. */}}
{{ .issue.description }}

Your working directory is the documentation repository. The `source`
directory holds the source repository at the commit above, with one earlier
commit of history. Edit files outside `source` only.

Write `needs-human-review` to `.sortie/status` when the documentation covers
the change. Write `no-change-needed` when the change needs no documentation.
Write `blocked` and the reason when you cannot finish.
