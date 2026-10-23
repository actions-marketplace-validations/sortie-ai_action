---
tracker:
  kind: file
  active_states: [To Do]
  handoff_state: In Review
file:
  path: $SORTIE_ACTION_TASK_FILE
agent:
  kind: mock
  max_sessions: 1
  max_retry_backoff_ms: 50
dispatch:
  rules:
    - name: fail
      match:
        labels: [fail]
      mock:
        turn_outcomes: [failed]
    - name: slow
      match:
        labels: [slow]
      mock:
        turn_delay_ms: 600000
hooks:
  after_run: |-
    if not exist %SORTIE_TEST_DIR% mkdir %SORTIE_TEST_DIR% & (echo %SORTIE_RUN_OUTCOME%)> %SORTIE_TEST_DIR%\outcome.txt & copy /y %SORTIE_ACTION_TASK_FILE% %SORTIE_TEST_DIR%\task.json
price_table:
  fetch: false
---
{{ .issue.description }}
