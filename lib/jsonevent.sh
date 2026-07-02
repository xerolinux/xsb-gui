#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\t'/\\t}"
    s="${s//$'\r'/\\r}"
    printf '%s' "$s"
}

emit_event() {
    local event="$1" level="$2" message="$3"
    printf '{"event":"%s","level":"%s","message":"%s"}\n' \
        "$(json_escape "$event")" "$(json_escape "$level")" "$(json_escape "$message")"
}

run_cmd() {
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        emit_event "would_run" "info" "$*"
    else
        emit_event "running" "info" "$*"
        local output status
        output="$("$@" 2>&1)"
        status=$?
        if [[ -n "$output" ]]; then
            while IFS= read -r line; do
                emit_event "command_output" "info" "$line"
            done <<< "$output"
        fi
        return "$status"
    fi
}
