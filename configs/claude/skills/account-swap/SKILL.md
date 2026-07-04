---
name: account-swap
description: "Use when the user wants the current/default claude session to run on a different logged-in account's credential without /login — typically a usage limit was hit mid-session and they want to continue on another account. Args: <profile> | default | --status."
---

Swap which account's credential occupies `~/.claude` by running the
`claude-swap` helper (deployed to `~/.local/bin` by env-setup module 08).
It uses move semantics — the live credential is written back to its home
before the other one is checked in — because Claude Code's refresh tokens
rotate and duplicated copies can invalidate an account's whole token family.

Steps:

1. No argument, or the user is unsure what exists: run `claude-swap --status`
   (Bash) and show the current owner plus the available targets.
2. Run `claude-swap $ARGUMENTS` via Bash. Relay its output — especially any
   freshness warning (a credential unrefreshed for >7 days may need one
   re-login).
3. On success, tell the user: keep working — if the next replies still act as
   the old account (its usage-limit message keeps appearing), exit and run
   `claude -c` to resume this same conversation on the swapped credential.
4. On "no stored credential for '<name>'": the account has never been
   captured on this machine. Tell the user to run `claude-as <name>` once in
   a terminal and `/login` there, then retry the swap.

Never print the contents of any `.credentials.json`, and never copy
credential files around manually — all movements go through `claude-swap`.
While a profile is checked out, `claude-as <that-profile>` is blocked by
design; swap back with `claude-swap default` first.

macOS: the default account's credential lives in the Keychain, so file
swapping does not apply — the script refuses and the user should use
`/login` instead.
