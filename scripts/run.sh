#!/usr/bin/env bash
# Writes the work item, runs Sortie once, and turns the result into step outputs.
# Reads SA_BIN, SA_WORKFLOW, SA_TASK_FILE, SA_TASK, SA_TITLE, and SA_LABELS.
set -u

# Git Bash on Windows wants POSIX paths for itself and Windows paths for the
# native programs it starts.
if [[ $RUNNER_OS == Windows ]]; then
  to_posix() { cygpath -u "$1" | tr -d '\r'; }
  to_native() { cygpath -w "$1" | tr -d '\r'; }
else
  to_posix() { printf '%s\n' "$1"; }
  to_native() { printf '%s\n' "$1"; }
fi

output_file=$(to_posix "$GITHUB_OUTPUT")

finish() {
  {
    printf 'exit-code=%s\n' "$2"
    printf 'outcome=%s\n' "$3"
  } >>"$output_file"
  if [[ -n $4 ]]; then
    printf '::error title=Sortie Action::%s\n' "$4"
  fi
  exit "$1"
}

# The inputs reach jq through files: a jq argument would put the task text on a
# command line, and jq on Windows reads its environment in the ANSI code page,
# which mangles any non-ASCII text.
# shellcheck disable=SC2016 # the jq variables are not shell expansions
task_filter='
  def trim: gsub("\\A\\s+|\\s+\\z"; "");
  if ($text | test("\\S") | not) then ("" | halt_error(3)) else . end
  | ($title | trim) as $title
  | [{
      id: $id,
      identifier: $id,
      title: (if $title != "" then $title
              else ($text | split("\n") | map(select(test("\\S"))) | first | trim | .[0:200]) end),
      description: $text,
      state: "To Do",
      labels: ($labels | split(",") | map(trim | select(. != "")))
    }]'

write_task_file() {
  local text=${SA_TASK_FILE:-$run_dir/text}
  [[ -n ${SA_TASK_FILE:-} ]] || printf '%s' "${SA_TASK:-}" >"$text" || return 1
  printf '%s' "${SA_TITLE:-}" >"$run_dir/title" || return 1
  printf '%s' "${SA_LABELS:-}" >"$run_dir/labels" || return 1
  jq -n --arg id "$id" \
    --rawfile text "$(to_native "$text")" \
    --rawfile title "$(to_native "$run_dir/title")" \
    --rawfile labels "$(to_native "$run_dir/labels")" \
    "$task_filter" >"$task_path" 2>/dev/null
}

# Sortie runs as a child so this script survives to write the outputs.
launch() {
  if [[ $RUNNER_OS == Windows ]]; then
    # The runner raises the console event for sortie.exe itself. A handler
    # keeps this shell alive without the ignored disposition sortie.exe would
    # inherit.
    trap ':' INT TERM HUP QUIT
    "$bin" --once --once-result "$result_native" --port 0 "$workflow"
    code=$?
    return
  fi

  "$bin" --once --once-result "$result_native" --port 0 "$workflow" &
  local pid=$!
  trap 'kill -INT "$pid" 2>/dev/null' INT
  trap 'kill -TERM "$pid" 2>/dev/null' TERM
  wait "$pid"
  code=$?
  while kill -0 "$pid" 2>/dev/null; do
    wait "$pid"
    code=$?
  done
  # A relayed signal ends a wait early with 128+N; if Sortie exited and was
  # reaped meanwhile, only a repeated wait still knows its real status.
  wait "$pid" 2>/dev/null
  local late=$?
  if [[ $late -ne 127 ]]; then
    code=$late
  fi
}

# Sets entry to a valid outcome, "none" when the file has no entry for the
# work item, or "unreadable".
read_entry() {
  local raw
  raw=$(jq -r --arg id "$id" '
    if (.issues | type) != "array" then error("no issues array")
    else ([.issues[] | select(.identifier == $id)] | first) as $e
      | if $e == null then "none" else "entry " + ($e.outcome | tostring) end
    end' "$result_native" 2>/dev/null | tr -d '\r')
  case $raw in
    none) entry=none ;;
    'entry succeeded' | 'entry stopped' | 'entry failed' | 'entry cancelled') entry=${raw#entry } ;;
    *) entry=unreadable ;;
  esac
}

# Sets status, outcome, and message from Sortie's exit status and the result file.
classify() {
  status=1
  outcome=
  message=
  case $code in
    0 | 2) read_entry ;;
  esac
  case $code in
    0)
      case $entry in
        none) message="The work item was not dispatched. Check that tracker.active_states lists To Do, that file.path expands \$SORTIE_ACTION_TASK_FILE, and whether an eligibility gate declined the work item." ;;
        unreadable) message='Could not confirm that the work item ran: the result file is missing or unreadable.' ;;
        *)
          status=0
          outcome=$entry
          ;;
      esac
      ;;
    1) message='Sortie failed to start, or its poll failed.' ;;
    2)
      status=2
      case $entry in
        succeeded)
          outcome=succeeded
          message='A signal stopped Sortie after the work item succeeded.'
          ;;
        none | unreadable) message='The work item did not succeed.' ;;
        *)
          outcome=$entry
          message='The work item did not succeed.'
          ;;
      esac
      ;;
    *)
      status=$code
      message="Sortie exited with status $code."
      ;;
  esac
}

bin=$(to_posix "$SA_BIN")
workflow=$(to_native "$SA_WORKFLOW")
id="gha-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"

run_dir=$(mktemp -d "$(to_posix "$RUNNER_TEMP")/sortie-run.XXXXXX") ||
  finish 1 '' '' 'Could not create the run directory.'
task_path=$run_dir/task.json
result_native=$(to_native "$run_dir/result.json")

write_task_file
case $? in
  0) ;;
  3) finish 1 '' '' 'The task text is empty.' ;;
  *) finish 1 '' '' 'Could not write the task file.' ;;
esac

if [[ ! -f $bin ]]; then
  finish 1 '' '' 'The Sortie binary is missing.'
fi

SORTIE_ACTION_TASK_FILE=$(to_native "$task_path")
SORTIE_DB_PATH=$(to_native "$run_dir/sortie.db")
SORTIE_WORKSPACE_ROOT=$(to_native "$run_dir/workspaces")
SORTIE_TRACKER_KIND='file'
export SORTIE_ACTION_TASK_FILE SORTIE_DB_PATH SORTIE_WORKSPACE_ROOT SORTIE_TRACKER_KIND
for name in "${!SA_@}"; do
  unset "$name"
done

code=
launch
classify
finish "$status" "$code" "$outcome" "$message"
