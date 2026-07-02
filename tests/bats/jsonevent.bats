#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../../lib/jsonevent.sh"
}

@test "json_escape escapes backslashes and quotes" {
  result="$(json_escape 'say "hi" \ there')"
  [ "$result" = 'say \"hi\" \\ there' ]
}

@test "json_escape escapes a literal tab as \\t" {
  result="$(json_escape "$(printf 'a\tb')")"
  [ "$result" = 'a\tb' ]
}

@test "json_escape escapes a literal carriage return as \\r" {
  result="$(json_escape "$(printf 'a\rb')")"
  [ "$result" = 'a\rb' ]
}

@test "emit_event prints a well-formed JSON line" {
  result="$(emit_event "preflight_start" "info" "checking system")"
  [ "$result" = '{"event":"preflight_start","level":"info","message":"checking system"}' ]
}

@test "run_cmd executes the command when DRY_RUN is unset" {
  unset DRY_RUN
  result="$(run_cmd echo hello)"
  [[ "$result" == *"hello"* ]]
}

@test "run_cmd previews without executing when DRY_RUN=1" {
  DRY_RUN=1
  result="$(run_cmd rm -f /nonexistent-marker-file)"
  [[ "$result" == *'"event":"would_run"'* ]]
  [[ "$result" == *"rm -f /nonexistent-marker-file"* ]]
}

@test "run_cmd emits one command_output event per line of wrapped command output" {
  unset DRY_RUN
  result="$(run_cmd printf 'line one\nline two\nline three\n')"
  count="$(printf '%s\n' "$result" | grep -c '"event":"command_output"')"
  [ "$count" -eq 3 ]
  [[ "$result" == *'"event":"command_output","level":"info","message":"line one"'* ]]
  [[ "$result" == *'"event":"command_output","level":"info","message":"line two"'* ]]
  [[ "$result" == *'"event":"command_output","level":"info","message":"line three"'* ]]
}

@test "run_cmd emits no command_output event when the wrapped command has no output" {
  unset DRY_RUN
  result="$(run_cmd true)"
  [[ "$result" != *"command_output"* ]]
}

@test "run_cmd propagates the wrapped command's real exit status" {
  unset DRY_RUN
  run run_cmd false
  [ "$status" -ne 0 ]
}
