#!/usr/bin/env python3
"""PreToolUse hook: reject `git commit` messages that break the commit rules.

Claude Code runs this before every Bash / PowerShell tool call. When the
command contains a `git commit` whose message can be read from the command
itself (-m, -F <file>, -F - with a heredoc or a PowerShell here-string), the
message is checked against the rules of ~/.claude/guides/git.md, which follow
@commitlint/config-conventional (error-level rules) with the stricter header
cap the user set (72):

  - header `<type>(<scope>)!: <subject>`, type from the Conventional Commits
    set, lowercase type and scope, header <= 72 chars
  - subject not empty, not ending in '.', not starting with an uppercase letter
  - a blank line between header and body; body lines <= 100 chars
  - no `Co-Authored-By: Claude` trailer (hard rule in ~/.claude/CLAUDE.md)

Merge and revert messages git writes ("Merge ...", "Revert ...") are skipped,
as commitlint's default ignores do. A commit whose message cannot be read from
the command (editor, -C/--fixup, a file that does not exist yet) is allowed:
this hook only judges text it can see. Stdlib only; exit 0 always, a denial is
the JSON permissionDecision.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import sys

TYPES = ("build", "chore", "ci", "docs", "feat", "fix", "perf", "refactor",
         "revert", "style", "test")
HEADER_MAX = 72
BODY_LINE_MAX = 100
HEADER_RE = re.compile(r"^(?P<type>[^\s(!:]+)(?:\((?P<scope>[^()]*)\))?(?P<bang>!)?: (?P<subject>.*)$")
IGNORED_RE = re.compile(r"^(Merge |Revert \"|Revert ')")
TRAILER_RE = re.compile(r"^co-authored-by:\s*claude\b", re.IGNORECASE | re.MULTILINE)
HEREDOC_RE = re.compile(r"<<-?[ \t]*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1[^\n]*\n(.*?)\n[ \t]*\2[ \t]*(?=\n|$)", re.DOTALL)
HERESTRING_RE = re.compile(r"@(['\"])\r?\n(.*?)\r?\n\1@", re.DOTALL)
SKIP_FLAGS = {"-C", "-c", "--reuse-message", "--reedit-message", "--fixup", "--squash"}
GIT_OPTS_WITH_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace"}


def deny(reason: str) -> None:
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }}))


def lint(message: str) -> list[str]:
    msg = message.replace("\r\n", "\n").strip("\n")
    lines = msg.split("\n")
    header = lines[0].strip()
    if IGNORED_RE.match(header):
        return []
    problems = []
    m = HEADER_RE.match(header)
    if not m:
        problems.append(f"header {header!r} is not `<type>(<scope>): <subject>`")
    else:
        if m["type"] not in TYPES:
            problems.append(f"type {m['type']!r} is not one of {', '.join(TYPES)}")
        if m["scope"] is not None and (not m["scope"] or m["scope"] != m["scope"].lower()):
            problems.append(f"scope {m['scope']!r} must be a non-empty lowercase noun")
        subject = m["subject"].strip()
        if not subject:
            problems.append("subject is empty")
        else:
            if subject.endswith("."):
                problems.append("subject ends with a period")
            if subject[0].isupper():
                problems.append("subject starts with an uppercase letter (lowercase imperative)")
    if len(header) > HEADER_MAX:
        problems.append(f"header is {len(header)} chars (max {HEADER_MAX}; aim for 50)")
    if len(lines) > 1 and lines[1].strip():
        problems.append("no blank line between header and body")
    long_lines = [i + 1 for i, l in enumerate(lines[1:], start=1) if len(l) > BODY_LINE_MAX]
    if long_lines:
        problems.append(f"body lines {long_lines} exceed {BODY_LINE_MAX} chars (wrap at ~72)")
    if TRAILER_RE.search(msg):
        problems.append("Co-Authored-By: Claude trailer is forbidden")
    return problems


def split_commands(command: str) -> tuple[list[list[str]], list[str]]:
    """Return the simple commands as token lists, plus the heredoc/here-string
    bodies in order of appearance (they are cut out before tokenizing)."""
    bodies: list[str] = []

    def keep(match: re.Match, group: int) -> str:
        bodies.append(match.group(group))
        return f" __BODY{len(bodies) - 1}__ "

    text = HEREDOC_RE.sub(lambda m: keep(m, 3), command)
    text = HERESTRING_RE.sub(lambda m: keep(m, 2), text)
    lex = shlex.shlex(text, posix=True, punctuation_chars=";&|()\n")
    lex.whitespace = " \t\r"
    lex.whitespace_split = True
    commands, current = [], []
    for tok in lex:
        if tok and set(tok) <= set(";&|()\n"):
            if current:
                commands.append(current)
            current = []
        else:
            current.append(tok)
    if current:
        commands.append(current)
    return commands, bodies


def commit_message(tokens: list[str], bodies: list[str], cwd: str) -> str | None:
    """Message of a `git ... commit ...` token list, or None if not a commit
    or the message is not visible in the command."""
    try:
        i = next(k for k, t in enumerate(tokens) if os.path.basename(t).lower() in ("git", "git.exe"))
    except StopIteration:
        return None
    workdir = cwd
    i += 1
    while i < len(tokens) and tokens[i].startswith("-"):
        opt = tokens[i].split("=", 1)[0]
        if opt == "-C" and i + 1 < len(tokens):
            workdir = os.path.join(workdir, tokens[i + 1])
        i += 2 if opt in GIT_OPTS_WITH_VALUE and "=" not in tokens[i] else 1
    if i >= len(tokens) or tokens[i] != "commit":
        return None
    args = tokens[i + 1:]
    messages, file_arg = [], None
    k = 0
    while k < len(args):
        a = args[k]
        nxt = args[k + 1] if k + 1 < len(args) else None
        if a.split("=", 1)[0] in SKIP_FLAGS:
            return None
        if a in ("--message", "--file") and nxt is not None:
            (messages.append(nxt) if a == "--message" else None)
            file_arg = nxt if a == "--file" else file_arg
            k += 2; continue
        if a.startswith("--message="):
            messages.append(a.split("=", 1)[1]); k += 1; continue
        if a.startswith("--file="):
            file_arg = a.split("=", 1)[1]; k += 1; continue
        if re.fullmatch(r"-[A-Za-z]+.*", a):
            # Short-option cluster, as git parses it: `-am msg`, `-mmsg`,
            # `-qF -`. The first letter that takes a value owns the rest of
            # the token, or the next token when nothing follows it.
            for pos in range(1, len(a)):
                ch = a[pos]
                if ch in "mFCct":
                    value, used = (a[pos + 1:], 1) if pos + 1 < len(a) else (nxt, 2)
                    if ch in "Cc":
                        return None
                    if value is not None and ch == "m":
                        messages.append(value)
                    elif value is not None and ch == "F":
                        file_arg = value
                    k += used
                    break
            else:
                k += 1
            continue
        k += 1
    for idx, m in enumerate(messages):
        hit = re.fullmatch(r"\s*__BODY(\d+)__\s*", m)
        if hit:
            messages[idx] = bodies[int(hit.group(1))]
    if messages:
        return "\n\n".join(messages)
    if file_arg is None:
        return None
    if file_arg == "-":
        return bodies[0] if bodies else None
    path = file_arg if os.path.isabs(file_arg) else os.path.join(workdir, file_arg)
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None


def main() -> int:
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return 0
    command = (data.get("tool_input") or {}).get("command") or ""
    if "commit" not in command:
        return 0
    try:
        commands, bodies = split_commands(command)
    except ValueError:
        return 0  # unbalanced quotes: let the shell report it
    problems = []
    for tokens in commands:
        msg = commit_message(tokens, bodies, data.get("cwd") or os.getcwd())
        if msg is not None:
            problems += lint(msg)
    if problems:
        deny("Commit message breaks ~/.claude/guides/git.md (Conventional Commits): "
             + "; ".join(problems) + ". Rewrite the message and commit again.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
