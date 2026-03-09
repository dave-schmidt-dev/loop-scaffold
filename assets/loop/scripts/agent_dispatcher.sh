#!/usr/bin/env bash
# agent_dispatcher.sh - Centralized agent selection and health checking.

# Health cache defaults: skip repeated probes for recent checks.
AGENT_HEALTH_CACHE_ENABLED="${AGENT_HEALTH_CACHE_ENABLED:-1}"
AGENT_HEALTH_CACHE_TTL_SECONDS="${AGENT_HEALTH_CACHE_TTL_SECONDS:-1800}"
AGENT_HEALTH_CACHE_FAIL_TTL_SECONDS="${AGENT_HEALTH_CACHE_FAIL_TTL_SECONDS:-90}"
AGENT_HEALTH_CACHE_FILE="${AGENT_HEALTH_CACHE_FILE:-.ralph/state/agent_health_cache.tsv}"
AGENT_HEALTH_MEMO_ENABLED="${AGENT_HEALTH_MEMO_ENABLED:-1}"
AGENT_HEALTH_MEMO_FILE="${AGENT_HEALTH_MEMO_FILE:-.ralph/state/agent_health_memo.tsv}"
AGENT_QUOTA_TRACK_ENABLED="${AGENT_QUOTA_TRACK_ENABLED:-1}"
AGENT_QUOTA_HITS_FILE="${AGENT_QUOTA_HITS_FILE:-.ralph/state/agent_quota_hits.tsv}"
AGENT_QUOTA_MAX_HITS="${AGENT_QUOTA_MAX_HITS:-3}"
AGENT_QUOTA_COOLDOWN_SECONDS="${AGENT_QUOTA_COOLDOWN_SECONDS:-18000}"
CODEX_MODEL_HEALTH="${CODEX_MODEL_HEALTH:-gpt-5.1-codex-mini}"
CODEX_REASONING_HEALTH="${CODEX_REASONING_HEALTH:-medium}"
CODEX_MODEL_IMPLEMENTOR="${CODEX_MODEL_IMPLEMENTOR:-gpt-5.3-codex}"
CODEX_REASONING_IMPLEMENTOR="${CODEX_REASONING_IMPLEMENTOR:-medium}"
CODEX_MODEL_AUDITOR="${CODEX_MODEL_AUDITOR:-gpt-5.4}"
CODEX_REASONING_AUDITOR="${CODEX_REASONING_AUDITOR:-xhigh}"
GEMINI_MODEL_IMPLEMENTOR="${GEMINI_MODEL_IMPLEMENTOR:-gemini-3-flash-preview}"
GEMINI_MODEL_AUDITOR="${GEMINI_MODEL_AUDITOR:-gemini-3.1-pro-preview}"
COPILOT_MODEL_HEALTH="${COPILOT_MODEL_HEALTH:-gpt-5-mini}"
COPILOT_MODEL_IMPLEMENTOR="${COPILOT_MODEL_IMPLEMENTOR:-claude-sonnet-4.6}"
COPILOT_MODEL_AUDITOR="${COPILOT_MODEL_AUDITOR:-claude-opus-4.6}"
CURSOR_MODEL_IMPLEMENTOR="${CURSOR_MODEL_IMPLEMENTOR:-sonnet-4.6-thinking}"
CURSOR_MODEL_AUDITOR="${CURSOR_MODEL_AUDITOR:-opus-4.6-thinking}"
COPILOT_IMPLEMENTOR_FLAGS="${COPILOT_IMPLEMENTOR_FLAGS:-}"
COPILOT_AUDITOR_FLAGS="${COPILOT_AUDITOR_FLAGS:-}"
CURSOR_IMPLEMENTOR_FLAGS="${CURSOR_IMPLEMENTOR_FLAGS:-}"
CURSOR_AUDITOR_FLAGS="${CURSOR_AUDITOR_FLAGS:-}"
AGENT_HEALTH_AGENT_FLAGS="${AGENT_HEALTH_AGENT_FLAGS:-}"

# --- Priority Lists ---
IMPLEMENTOR_PRIORITY=(
    "codex:exec:--skip-git-repo-check -c model=${CODEX_MODEL_IMPLEMENTOR} -c reasoning.effort=${CODEX_REASONING_IMPLEMENTOR}"
    "gemini:-p:--model ${GEMINI_MODEL_IMPLEMENTOR}"
    "copilot:-p:--model ${COPILOT_MODEL_IMPLEMENTOR} ${COPILOT_IMPLEMENTOR_FLAGS}"
    "agent:-p:--model ${CURSOR_MODEL_IMPLEMENTOR} ${CURSOR_IMPLEMENTOR_FLAGS}"
    "vibe:--prompt"
)

AUDITOR_PRIORITY=(
    "copilot:-p:--model ${COPILOT_MODEL_AUDITOR} ${COPILOT_AUDITOR_FLAGS}"
    "agent:-p:--model ${CURSOR_MODEL_AUDITOR} ${CURSOR_AUDITOR_FLAGS}"
    "codex:exec:--skip-git-repo-check -c model=${CODEX_MODEL_AUDITOR} -c reasoning.effort=${CODEX_REASONING_AUDITOR}"
    "gemini:-p:--model ${GEMINI_MODEL_AUDITOR}"
)

is_truthy_dispatcher() {
    local value="${1:-}"
    case "$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')" in
        1|true|yes|on) return 0 ;;
        *) return 1 ;;
    esac
}

is_positive_int_dispatcher() {
    local value="${1:-}"
    case "$value" in
        ""|*[!0-9]*) return 1 ;;
        *) [ "$value" -gt 0 ] ;;
    esac
}

entry_parse() {
    local entry="$1"
    local __bin_var="$2"
    local __cmd_var="$3"
    local __args_var="$4"
    local parsed_bin rest parsed_cmd parsed_args

    parsed_bin="${entry%%:*}"
    rest="${entry#*:}"
    if [[ "$rest" == "$entry" ]]; then
        parsed_cmd=""
        parsed_args=""
    else
        parsed_cmd="${rest%%:*}"
        parsed_args="${rest#*:}"
        if [[ "$parsed_args" == "$rest" ]]; then
            parsed_args=""
        fi
    fi

    printf -v "$__bin_var" '%s' "$parsed_bin"
    printf -v "$__cmd_var" '%s' "$parsed_cmd"
    printf -v "$__args_var" '%s' "$parsed_args"
}

resolved_parse() {
    local resolved="$1"
    local __bin_var="$2"
    local __cmd_var="$3"
    local __args_var="$4"
    local parsed_bin rest parsed_cmd parsed_args

    parsed_bin="${resolved%%:*}"
    rest="${resolved#*:}"
    if [[ "$rest" == "$resolved" || -z "$rest" ]]; then
        parsed_cmd=""
        parsed_args=""
    else
        parsed_cmd="${rest%% *}"
        if [[ "$parsed_cmd" == "$rest" ]]; then
            parsed_args=""
        else
            parsed_args="${rest#"$parsed_cmd"}"
            parsed_args="${parsed_args# }"
        fi
    fi

    printf -v "$__bin_var" '%s' "$parsed_bin"
    printf -v "$__cmd_var" '%s' "$parsed_cmd"
    printf -v "$__args_var" '%s' "$parsed_args"
}

health_cache_prepare() {
    if ! is_truthy_dispatcher "$AGENT_HEALTH_CACHE_ENABLED"; then
        return 1
    fi
    mkdir -p "$(dirname "$AGENT_HEALTH_CACHE_FILE")" 2>/dev/null || true
}

health_memo_prepare() {
    if ! is_truthy_dispatcher "$AGENT_HEALTH_MEMO_ENABLED"; then
        return 1
    fi
    mkdir -p "$(dirname "$AGENT_HEALTH_MEMO_FILE")" 2>/dev/null || true
    touch "$AGENT_HEALTH_MEMO_FILE" 2>/dev/null || true
}

quota_tracker_prepare() {
    if ! is_truthy_dispatcher "$AGENT_QUOTA_TRACK_ENABLED"; then
        return 1
    fi
    mkdir -p "$(dirname "$AGENT_QUOTA_HITS_FILE")" 2>/dev/null || true
    touch "$AGENT_QUOTA_HITS_FILE" 2>/dev/null || true
}

quota_tracker_get() {
    local agent_bin="$1"
    if ! is_truthy_dispatcher "$AGENT_QUOTA_TRACK_ENABLED"; then
        return 1
    fi
    if [[ ! -f "$AGENT_QUOTA_HITS_FILE" ]]; then
        return 1
    fi
    awk -F'\t' -v bin="$agent_bin" '$1==bin {print $2 "\t" $3}' "$AGENT_QUOTA_HITS_FILE" | tail -n 1
}

quota_tracker_set() {
    local agent_bin="$1"
    local hit_count="$2"
    local last_epoch="$3"
    quota_tracker_prepare || return 0
    {
        if [[ -f "$AGENT_QUOTA_HITS_FILE" ]]; then
            awk -F'\t' -v bin="$agent_bin" '$1!=bin' "$AGENT_QUOTA_HITS_FILE"
        fi
        printf '%s\t%s\t%s\n' "$agent_bin" "$hit_count" "$last_epoch"
    } > "${AGENT_QUOTA_HITS_FILE}.tmp"
    mv "${AGENT_QUOTA_HITS_FILE}.tmp" "$AGENT_QUOTA_HITS_FILE"
}

quota_tracker_reset() {
    local agent_bin="$1"
    if ! is_truthy_dispatcher "$AGENT_QUOTA_TRACK_ENABLED"; then
        return 0
    fi
    quota_tracker_prepare || return 0
    if [[ ! -f "$AGENT_QUOTA_HITS_FILE" ]]; then
        return 0
    fi
    awk -F'\t' -v bin="$agent_bin" '$1!=bin' "$AGENT_QUOTA_HITS_FILE" > "${AGENT_QUOTA_HITS_FILE}.tmp"
    mv "${AGENT_QUOTA_HITS_FILE}.tmp" "$AGENT_QUOTA_HITS_FILE"
}

quota_tracker_record_hit() {
    local agent_bin="$1"
    local row count epoch now_epoch
    if ! is_truthy_dispatcher "$AGENT_QUOTA_TRACK_ENABLED"; then
        return 0
    fi
    now_epoch="$(date +%s)"
    row="$(quota_tracker_get "$agent_bin" || true)"
    count="$(printf '%s' "$row" | awk -F'\t' '{print $1}')"
    epoch="$(printf '%s' "$row" | awk -F'\t' '{print $2}')"
    if [[ ! "$count" =~ ^[0-9]+$ ]]; then
        count=0
    fi
    if [[ "$epoch" =~ ^[0-9]+$ ]] && is_positive_int_dispatcher "$AGENT_QUOTA_COOLDOWN_SECONDS"; then
        if (( now_epoch - epoch > AGENT_QUOTA_COOLDOWN_SECONDS )); then
            count=0
        fi
    fi
    count=$((count + 1))
    quota_tracker_set "$agent_bin" "$count" "$now_epoch"
}

quota_tracker_is_blocked() {
    local agent_bin="$1"
    local row count epoch now_epoch age
    if ! is_truthy_dispatcher "$AGENT_QUOTA_TRACK_ENABLED"; then
        return 1
    fi
    if ! is_positive_int_dispatcher "$AGENT_QUOTA_MAX_HITS"; then
        return 1
    fi
    if ! is_positive_int_dispatcher "$AGENT_QUOTA_COOLDOWN_SECONDS"; then
        return 1
    fi
    row="$(quota_tracker_get "$agent_bin" || true)"
    count="$(printf '%s' "$row" | awk -F'\t' '{print $1}')"
    epoch="$(printf '%s' "$row" | awk -F'\t' '{print $2}')"
    if [[ ! "$count" =~ ^[0-9]+$ || ! "$epoch" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    if (( count < AGENT_QUOTA_MAX_HITS )); then
        return 1
    fi
    now_epoch="$(date +%s)"
    age=$((now_epoch - epoch))
    if (( age <= AGENT_QUOTA_COOLDOWN_SECONDS )); then
        return 0
    fi
    quota_tracker_reset "$agent_bin"
    return 1
}

health_memo_get() {
    local agent_bin="$1"
    if ! is_truthy_dispatcher "$AGENT_HEALTH_MEMO_ENABLED"; then
        return 1
    fi
    if [[ ! -f "$AGENT_HEALTH_MEMO_FILE" ]]; then
        return 1
    fi
    awk -F'\t' -v bin="$agent_bin" '$1==bin {print $2}' "$AGENT_HEALTH_MEMO_FILE" | tail -n 1
}

health_memo_set() {
    local agent_bin="$1"
    local health_status="$2"
    health_memo_prepare || return 0
    {
        if [[ -f "$AGENT_HEALTH_MEMO_FILE" ]]; then
            awk -F'\t' -v bin="$agent_bin" '$1!=bin' "$AGENT_HEALTH_MEMO_FILE"
        fi
        printf '%s\t%s\n' "$agent_bin" "$health_status"
    } > "${AGENT_HEALTH_MEMO_FILE}.tmp"
    mv "${AGENT_HEALTH_MEMO_FILE}.tmp" "$AGENT_HEALTH_MEMO_FILE"
}

dispatcher_health_memo_reset() {
    rm -f "$AGENT_HEALTH_MEMO_FILE" 2>/dev/null || true
}

health_cache_get() {
    local agent_bin="$1"
    if [[ ! -f "$AGENT_HEALTH_CACHE_FILE" ]]; then
        return 1
    fi
    awk -F'\t' -v bin="$agent_bin" '$1==bin {print $2 "\t" $3}' "$AGENT_HEALTH_CACHE_FILE" | tail -n 1
}

health_cache_set() {
    local agent_bin="$1"
    local health_status="$2"
    local now_epoch
    now_epoch="$(date +%s)"
    health_cache_prepare || return 0
    {
        if [[ -f "$AGENT_HEALTH_CACHE_FILE" ]]; then
            awk -F'\t' -v bin="$agent_bin" '$1!=bin' "$AGENT_HEALTH_CACHE_FILE"
        fi
        printf '%s\t%s\t%s\n' "$agent_bin" "$now_epoch" "$health_status"
    } > "${AGENT_HEALTH_CACHE_FILE}.tmp"
    mv "${AGENT_HEALTH_CACHE_FILE}.tmp" "$AGENT_HEALTH_CACHE_FILE"
}

entry_to_resolved() {
    local entry="$1"
    local bin cmd args full_args
    entry_parse "$entry" bin cmd args
    full_args="$args"
    [[ -n "$cmd" ]] && full_args="$cmd $args"
    echo "$bin:$full_args"
}

list_configured_implementors() {
    local i=0
    local entry
    for entry in "${IMPLEMENTOR_PRIORITY[@]}"; do
        i=$((i + 1))
        printf '%s) %s\n' "$i" "$(entry_to_resolved "$entry")"
    done
}

list_configured_auditors() {
    local i=0
    local entry
    for entry in "${AUDITOR_PRIORITY[@]}"; do
        i=$((i + 1))
        printf '%s) %s\n' "$i" "$(entry_to_resolved "$entry")"
    done
}

resolve_configured_agent_override() {
    local role="$1"
    local selector="$2"
    local -a entries=()
    local idx=0
    local entry resolved bin cmd args full_args

    case "$role" in
        implementor|reviewer) entries=("${IMPLEMENTOR_PRIORITY[@]}") ;;
        auditor) entries=("${AUDITOR_PRIORITY[@]}") ;;
        *) return 1 ;;
    esac

    if [[ "$selector" =~ ^[0-9]+$ ]]; then
        idx="$selector"
        if (( idx >= 1 && idx <= ${#entries[@]} )); then
            echo "$(entry_to_resolved "${entries[idx-1]}")"
            return 0
        fi
        return 1
    fi

    for entry in "${entries[@]}"; do
        resolved="$(entry_to_resolved "$entry")"
        entry_parse "$entry" bin cmd args
        full_args="$args"
        [[ -n "$cmd" ]] && full_args="$cmd $args"
        if [[ "$selector" == "$bin" || "$selector" == "$resolved" || "$selector" == "$entry" || "$selector" == "$full_args" ]]; then
            echo "$resolved"
            return 0
        fi
    done
    return 1
}

# Internal helper for timeout execution
run_with_timeout_internal() {
    local timeout_s="$1"
    local cmd="$2"
    local no_output_timeout_s="${3:-0}"
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    python3 "${script_dir}/timeout_wrapper.py" "$timeout_s" "$cmd" "$no_output_timeout_s"
}

dispatcher_first_matching_line() {
    local haystack="$1"
    local pattern="$2"
    printf '%s\n' "$haystack" | grep -Ei "$pattern" | head -n 1
}

# Returns 0 if agent is alive, 1 otherwise.
check_agent_health() {
    local agent_bin="$1"
    local now_epoch cache_row cache_epoch cache_status cache_age memo_status
    local probe_ec=0
    local quota_pattern="quota|rate limit|usage cap|exhausted|too many requests|try again in"
    local fatal_pattern="stream disconnected|disconnected|not supported|Authentication required|No prompt provided|not logged in|invalid model|unknown model"

    if ! command -v "$agent_bin" >/dev/null 2>&1; then
        return 1
    fi

    memo_status="$(health_memo_get "$agent_bin" || true)"
    if [[ "$memo_status" == "ok" ]]; then
        return 0
    fi
    if [[ "$memo_status" == "fail" || "$memo_status" == "unknown" || "$memo_status" == "quota" ]]; then
        return 1
    fi

    if is_truthy_dispatcher "$AGENT_HEALTH_CACHE_ENABLED" && is_positive_int_dispatcher "$AGENT_HEALTH_CACHE_TTL_SECONDS"; then
        cache_row="$(health_cache_get "$agent_bin" || true)"
        if [[ -n "$cache_row" ]]; then
            cache_epoch="$(printf '%s' "$cache_row" | awk -F'\t' '{print $1}')"
            cache_status="$(printf '%s' "$cache_row" | awk -F'\t' '{print $2}')"
            now_epoch="$(date +%s)"
            if [[ "$cache_epoch" =~ ^[0-9]+$ ]]; then
                cache_age=$((now_epoch - cache_epoch))
                local effective_ttl="$AGENT_HEALTH_CACHE_TTL_SECONDS"
                if [[ "$cache_status" == "fail" || "$cache_status" == "unknown" || "$cache_status" == "quota" ]] && is_positive_int_dispatcher "$AGENT_HEALTH_CACHE_FAIL_TTL_SECONDS"; then
                    effective_ttl="$AGENT_HEALTH_CACHE_FAIL_TTL_SECONDS"
                fi
                if (( cache_age >= 0 && cache_age <= effective_ttl )); then
                    if [[ "$cache_status" == "ok" ]]; then
                        echo "Checking health of ${agent_bin}..." >&2
                        echo "  -> OK (cached ${cache_age}s ago)" >&2
                        health_memo_set "$agent_bin" "ok"
                        return 0
                    fi
                    echo "Checking health of ${agent_bin}..." >&2
                    if [[ "$cache_status" == "unknown" ]]; then
                        echo "  -> UNKNOWN (cached ${cache_age}s ago)" >&2
                        health_memo_set "$agent_bin" "unknown"
                    elif [[ "$cache_status" == "quota" ]]; then
                        echo "  -> FAILED quota (cached ${cache_age}s ago)" >&2
                        health_memo_set "$agent_bin" "quota"
                    else
                        echo "  -> FAILED (cached ${cache_age}s ago)" >&2
                        health_memo_set "$agent_bin" "fail"
                    fi
                    return 1
                fi
            fi
        fi
    fi

    echo "Checking health of ${agent_bin}..." >&2

    local test_prompt="respond with OK"
    local timeout_val=35
    local result=""
    local errexit_was_set=0
    if [[ "$-" == *e* ]]; then
        errexit_was_set=1
    fi

    set +e
    case "$agent_bin" in
        codex)
            result=$(echo "$test_prompt" | run_with_timeout_internal "$timeout_val" "codex exec --skip-git-repo-check -c model=${CODEX_MODEL_HEALTH} -c reasoning.effort=${CODEX_REASONING_HEALTH} -" 2>&1)
            ;;
        gemini)
            # Correct order for Gemini CLI
            result=$(run_with_timeout_internal "$timeout_val" "gemini -p \"$test_prompt\"" 2>&1)
            ;;
        agent)
            result=$(run_with_timeout_internal "$timeout_val" "agent -p \"$test_prompt\" ${AGENT_HEALTH_AGENT_FLAGS}" 2>&1)
            ;;
        copilot)
            # Use a minimal/non-premium probe configuration for fast, low-cost liveness checks.
            result=$(run_with_timeout_internal "$timeout_val" "copilot -p \"just say OK\" --model ${COPILOT_MODEL_HEALTH} --disable-builtin-mcps --no-custom-instructions --silent --available-tools --no-ask-user --no-auto-update --no-bash-env" 2>&1)
            ;;
        vibe)
            result=$(run_with_timeout_internal "$timeout_val" "vibe --prompt \"$test_prompt\"" 2>&1)
            ;;
        *)
            result=$(echo "$test_prompt" | run_with_timeout_internal "$timeout_val" "$agent_bin" 2>&1)
            ;;
    esac
    probe_ec=$?
    if [[ "$errexit_was_set" -eq 1 ]]; then
        set -e
    fi

    if [[ "$result" == *"TIMEOUT"* || "$probe_ec" -eq 124 ]]; then
        echo "  -> TIMEOUT" >&2
        health_cache_set "$agent_bin" "fail"
        health_memo_set "$agent_bin" "fail"
        return 1
    fi

    # High-confidence auth/quota/model failures should still win over a zero exit.
    if [[ "$result" =~ ($quota_pattern) ]]; then
        local quota_msg
        quota_msg="$(dispatcher_first_matching_line "$result" "$quota_pattern")"
        echo "  -> FAILED quota: ${quota_msg}" >&2
        quota_tracker_record_hit "$agent_bin"
        health_cache_set "$agent_bin" "quota"
        health_memo_set "$agent_bin" "quota"
        return 1
    fi

    if [[ "$result" =~ ($fatal_pattern) ]]; then
        local err_msg
        err_msg="$(dispatcher_first_matching_line "$result" "$fatal_pattern")"
        echo "  -> FAILED: ${err_msg}" >&2
        health_cache_set "$agent_bin" "fail"
        health_memo_set "$agent_bin" "fail"
        return 1
    fi

    # SUCCESS: treat zero-exit probes as healthy once explicit fatal conditions are excluded.
    # Some CLIs emit noisy stderr (including generic "ERROR:" blobs) during startup even when
    # the probe completes successfully.
    if [[ "$probe_ec" -eq 0 || "$result" == *"OK"* ]]; then
        echo "  -> OK" >&2
        health_cache_set "$agent_bin" "ok"
        health_memo_set "$agent_bin" "ok"
        quota_tracker_reset "$agent_bin"
        return 0
    fi

    if [[ "$result" == *"ERROR:"* ]]; then
        local generic_err
        generic_err="$(dispatcher_first_matching_line "$result" "ERROR:")"
        echo "  -> UNKNOWN (${generic_err}; exit=${probe_ec})" >&2
        health_cache_set "$agent_bin" "unknown"
        health_memo_set "$agent_bin" "unknown"
        return 1
    fi

    if [[ -n "${result//[[:space:]]/}" ]]; then
        echo "  -> UNKNOWN (unexpected output; exit=${probe_ec})" >&2
        health_cache_set "$agent_bin" "unknown"
        health_memo_set "$agent_bin" "unknown"
        return 1
    fi

    echo "  -> FAILED: Empty response" >&2
    health_cache_set "$agent_bin" "fail"
    health_memo_set "$agent_bin" "fail"
    return 1
}

get_active_implementor() {
    for entry in "${IMPLEMENTOR_PRIORITY[@]}"; do
        entry_parse "$entry" bin cmd args
        if quota_tracker_is_blocked "$bin"; then
            echo "Checking health of ${bin}..." >&2
            echo "  -> FAILED quota (cooldown active; trying fallback)" >&2
            continue
        fi
        local full_args="$args"
        [[ -n "$cmd" ]] && full_args="$cmd $args"
        if check_agent_health "$bin"; then
            echo "$bin:$full_args"
            return 0
        fi
    done
    return 1
}

get_active_auditor() {
    local implementor_bin="$1"
    for entry in "${AUDITOR_PRIORITY[@]}"; do
        entry_parse "$entry" bin cmd args
        [[ "$bin" == "$implementor_bin" ]] && continue
        if quota_tracker_is_blocked "$bin"; then
            echo "Checking health of ${bin}..." >&2
            echo "  -> FAILED quota (cooldown active; trying fallback)" >&2
            continue
        fi
        local full_args="$args"
        [[ -n "$cmd" ]] && full_args="$cmd $args"
        if check_agent_health "$bin"; then
            echo "$bin:$full_args"
            return 0
        fi
    done
    return 1
}
