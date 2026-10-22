---
tracker:
  kind: file
  active_states: [Open]
file:
  path: $SORTIE_ACTION_TASK_FILE
agent:
  kind: mock
  max_sessions: 1
price_table:
  fetch: false
---
{{ .issue.description }}
