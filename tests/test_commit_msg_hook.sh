#!/usr/bin/env bash
# test_commit_msg_hook.sh — Pins configs/claude/hooks/check_commit_msg.py.
# Feeds the hook the PreToolUse JSON Claude Code sends for a Bash/PowerShell
# call and checks it denies exactly the commit messages that break the
# Conventional Commits rules of guides/git.md, and nothing else.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_framework.sh"
set +e

echo -e "${_T_BOLD}Test: commit-message hook${_T_NC}"

HOOK="$PROJECT_ROOT/configs/claude/hooks/check_commit_msg.py"
PY="$(command -v python3 || command -v python)"
if [[ -z "$PY" ]]; then
    echo "SKIP: no python — the commit-message hook needs python"
    exit 0
fi

# _decision <command> -> prints "deny" or "allow"
_decision() {
    local payload
    payload="$("$PY" -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]},"cwd":"."}))' "$1")"
    if printf '%s' "$payload" | "$PY" "$HOOK" | grep -q '"deny"'; then echo deny; else echo allow; fi
}

# _expect <allow|deny> <command> <label>
_expect() {
    local got
    got="$(_decision "$2")"
    assert_eq "$1" "$got" "$3"
}

_expect allow 'git commit -m "fix(docs): ban the arm rendering"'   "scoped conventional header passes"
_expect allow 'git add -A && git -C "/a b" commit -q -m "feat!: drop v1" -m "Why."' "chained command, -C path, breaking bang"
_expect allow 'git commit -am "test: cover the parser"'             "-am cluster with a good message"
_expect allow 'git commit -qm "fix: handle -m clusters"'            "-qm cluster with a good message"
_expect deny  'git commit -m "Fix typo in README"'                  "no type, sentence case"
_expect deny  'git commit -m "docs: fix typo."'                     "subject ends with a period"
_expect deny  'git commit -m "update stuff"'                        "header without type"
_expect deny  'git commit -m "feature(x): add y"'                   "type outside the Conventional Commits set"
_expect deny  'git commit -m "feat(API): add y"'                    "uppercase scope"
_expect deny  "git commit -m \"feat: $(printf 'x%.0s' {1..70})\""   "header over 72 chars"
_expect deny  'git commit -am "Tests"'                              "-am cluster with a bad message"
_expect deny  'git commit -qmBad'                                   "attached -m value"
_expect deny  'git commit --message "Nope"'                         "--message with a bad message"

_expect allow $'git -C "D:/x y" commit -q -F - <<\'EOF\'\nfeat(claude): add hook\n\nWhy it exists.\n\nRefs #1\nEOF' \
    "heredoc message passes"
_expect deny  $'git commit -q -F - <<\'EOF\'\nfeat: add hook\nbody right under the header\nEOF' \
    "heredoc without a blank line before the body"
_expect deny  $'git commit -F - <<\'EOF\'\nfeat: add hook\n\nbody\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\nEOF' \
    "Co-Authored-By: Claude trailer"
_expect deny  $'git commit -qF - <<\'EOF\'\nWIP\nEOF'               "-qF cluster reading a heredoc"
_expect allow $'git commit -m @\'\nci: fix runner tags\n\nBecause.\n\'@' "PowerShell here-string passes"
_expect deny  $'git commit -m @\'\nCI fix\n\'@'                      "PowerShell here-string with a bad header"

# Messages the hook cannot see, and non-commit commands, are left alone.
_expect allow 'git commit'                                  "editor commit"
_expect allow 'git commit --amend --no-edit'                "amend keeping the message"
_expect allow 'git commit -C HEAD'                          "reuse a message"
_expect allow 'git commit --fixup abc123'                   "fixup commit"
_expect allow 'git commit -t template.txt'                  "template only"
_expect allow 'git commit -F does-not-exist.txt'            "message file not written yet"
_expect allow "git commit -m \"Merge branch 'x' into develop\"" "merge message git writes"
_expect allow 'git log --grep="commit -m Bad"'              "git log mentioning commit"
_expect allow 'echo "git commit -m Bad" > notes.txt'        "echo of a commit command"
_expect allow 'git commit -m "unbalanced'                   "unbalanced quotes left to the shell"

print_test_summary
