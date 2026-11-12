#!/usr/bin/env bash
# test_statusline_throttle.sh — behaviour of configs/ccstatusline/statusline-throttle.sh:
# the first call renders, later calls answer from the cache, a stale cache is refreshed
# in the background, sessions are cached apart and old ones are pruned.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_framework.sh"

THROTTLE="$PROJECT_ROOT/configs/ccstatusline/statusline-throttle.sh"

echo -e "${_T_BOLD}Test: statusline-throttle.sh${_T_NC}"

# ---------------------------------------------------------------------------
suite "Repo file"
# ---------------------------------------------------------------------------
assert_file_exists "$THROTTLE" "configs/ccstatusline/statusline-throttle.sh is in the repo"
if grep -q $'\r' "$THROTTLE"; then crlf=1; else crlf=0; fi
assert_eq "0" "$crlf" "script has LF line endings (Git Bash rejects CRLF)"

# A stand-in renderer: counts its runs and prints the count with the tag it was given.
export XDG_CACHE_HOME="$TEST_TMPDIR/cache"
export COUNT_FILE="$TEST_TMPDIR/count"
RENDERER="$TEST_TMPDIR/renderer.sh"
cat > "$RENDERER" <<'EOF'
#!/usr/bin/env bash
n=0
[ -f "$COUNT_FILE" ] && n=$(cat "$COUNT_FILE")
n=$((n + 1))
printf '%s' "$n" > "$COUNT_FILE"
in=$(cat)
tag=${in##*\"tag\":\"}
printf 'render %s %s\n' "$n" "${tag%%\"*}"
EOF
CACHE="$XDG_CACHE_HOME/ccstatusline-throttle"

call() { printf '%s' "$1" | bash "$THROTTLE" bash "$RENDERER"; }
count() { cat "$COUNT_FILE" 2>/dev/null || echo 0; }
# wait_for <seconds> <command...>: poll until the command succeeds
wait_for() {
    local tries=$(( $1 * 5 )); shift
    while (( tries-- > 0 )); do
        "$@" && return 0
        sleep 0.2
    done
    return 1
}

# ---------------------------------------------------------------------------
suite "No renderer given"
# ---------------------------------------------------------------------------
out="$(printf '{}' | bash "$THROTTLE")"
assert_contains "$out" "no renderer" "says so instead of printing nothing"

if [[ -z ${EPOCHSECONDS:-} ]]; then
    # bash < 5 (macOS /bin/bash): no clock to throttle on, every call renders.
    suite "bash without EPOCHSECONDS: passes every call straight to the renderer"
    a="$(call '{"session_id":"s-1","tag":"a"}')"
    b="$(call '{"session_id":"s-1","tag":"b"}')"
    assert_eq "render 1 a" "$a" "first call renders"
    assert_eq "render 2 b" "$b" "second call renders again"
    print_test_summary
    exit $?
fi

# ---------------------------------------------------------------------------
suite "First call of a session renders and caches"
# ---------------------------------------------------------------------------
a="$(call '{"session_id":"s-1","tag":"a"}')"
assert_eq "render 1 a" "$a" "shows the fresh render"
assert_file_exists "$CACHE/s-1.out" "cached under the session id"

# ---------------------------------------------------------------------------
suite "Fresh cache: answered without rendering"
# ---------------------------------------------------------------------------
b="$(call '{"session_id":"s-1","tag":"b"}')"
assert_eq "render 1 a" "$b" "second call inside the interval shows the cached line"
assert_eq "1" "$(count)" "renderer did not run again"

# ---------------------------------------------------------------------------
suite "Stale cache: cached line now, one refresh in the background"
# ---------------------------------------------------------------------------
printf '%s' "$(( EPOCHSECONDS - 3600 ))" > "$CACHE/s-1.stamp"
c="$(call '{"session_id":"s-1","tag":"c"}')"
assert_eq "render 1 a" "$c" "stale call still answers with the cached line"
refreshed() { [[ "$(cat "$CACHE/s-1.out" 2>/dev/null)" == "render 2 c" ]]; }
wait_for 15 refreshed || true
assert_eq "render 2 c" "$(cat "$CACHE/s-1.out")" "background render replaced the cached line"
d="$(call '{"session_id":"s-1","tag":"d"}')"
assert_eq "render 2 c" "$d" "next call shows the refreshed line"
assert_eq "2" "$(count)" "and does not render again inside the interval"

# ---------------------------------------------------------------------------
suite "Sessions are cached apart"
# ---------------------------------------------------------------------------
e="$(call '{"session_id":"s-2","tag":"e"}')"
assert_eq "render 3 e" "$e" "another session renders its own line"
f="$(call '{"session_id":"s-1","tag":"f"}')"
assert_eq "render 2 c" "$f" "the first session keeps its own cached line"

# ---------------------------------------------------------------------------
suite "A refresh prunes sessions not rendered for a week"
# ---------------------------------------------------------------------------
printf '%s' "$(( EPOCHSECONDS - 700000 ))" > "$CACHE/old.stamp"
printf 'old line' > "$CACHE/old.out"
printf '%s' "$(( EPOCHSECONDS - 3600 ))" > "$CACHE/s-2.stamp"
call '{"session_id":"s-2","tag":"g"}' >/dev/null
pruned() { [[ ! -e "$CACHE/old.stamp" && ! -e "$CACHE/old.out" ]]; }
wait_for 15 pruned || true
assert_file_not_exists "$CACHE/old.stamp" "week-old stamp removed"
assert_file_not_exists "$CACHE/old.out" "week-old line removed"
assert_file_exists "$CACHE/s-1.out" "recent sessions are kept"

print_test_summary
