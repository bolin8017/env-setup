# Comprehensive Review — 2026-07-03

Full-project review covering both engines (Bash + PowerShell), all modules,
runtime config assets, tests, and CI. Six focused review passes were run, one
per subsystem; every finding below was verified against the actual code, and
items marked **[tested]** were empirically reproduced (pwsh 7.6.3 /
Windows PowerShell 5.1.26100 / bash parser repros on this machine).

Severity: **H** = user-visible breakage or data-loss risk on realistic input;
**M** = silent misbehavior, broken contract, or parity divergence;
**L** = edge case, hygiene, or latent hazard.

---

## 1. Cross-cutting themes

1. **False-success reporting.** Package-install failures are swallowed on both
   engines; bash additionally runs modules inside `if "$fn"` which suspends
   `set -e`, so the Installation Summary's Failed column is unreliable.
2. **Self-update promise not kept.** Generated zshrc fragments are guarded by
   marker-grep and never update in place, so machines that self-update still
   run old, buggy fragments (two already-fixed bugs never reach them).
3. **The Windows PowerShell 5.1 path (i.e. the bootstrap one-liner path) has a
   cluster of hard failures**: no re-exec into pwsh 7, stderr-redirect
   exceptions, JSONC parse failures, BOM'd JSON writes, stale PATH after
   winget git install.
4. **Uninstall data-safety holes**: order-insensitive file comparison on
   Windows can delete user-modified files; one bash path deletes a
   user-modified fragment unconditionally.
5. **YAML parser divergence** between `lib/yaml.sh` and `lib/Config.psm1`
   (quoted `#`, duplicate sections) — same config behaves differently per
   platform, with zero diagnostics.
6. **Unwired config knobs**: keys documented in `config.yaml.example` that no
   code reads, and env switches that no module honors.

---

## 2. Bash engine core (`setup.sh`, `uninstall.sh`, `bootstrap.sh`, `lib/*.sh`)

### H — bash-core-1: `pkg_install` returns success when the install fails
`lib/package.sh:194-221`. The apt/dnf/brew branches never set `had_failure`
(only the no-sudo defer path does). Scenario: on Ubuntu ≤ 20.04 apt has no
`zoxide`; apt-get exits 100, `pkg_install` returns 0, and the curl fallback at
`modules/05-cli-tools.sh:109` never runs — zoxide missing, module reports
success. Same pattern hits `modules/01-core.sh:141`. `pkg_remove` is
internally inconsistent (brew branch records failure, apt/dnf don't).
**Fix:** `|| had_failure=true` on every install branch; surface a
"failed to install" summary next to `show_missing_apt_summary`.

### H — bash-core-2: `if "$install_fn"` suspends errexit through the whole module
`setup.sh:250`, `uninstall.sh:180`. Bash disables `set -e` inside an `if`
condition, so a module whose middle steps fail keeps executing and its
status is decided by the *last* command only. Combined with bash-core-1 the
summary routinely lies. **Fix direction:** `if ( set -e; "$install_fn" ); then`
(subshell re-enables errexit) — note exported-variable implications, or keep
behavior and make `log_error` feed a per-module error counter.

### H — bash-core-3: shipped `auto_yes: true` kills the sudo prompt
`lib/package.sh:74` + `config.yaml:19`. `sudo_available()` treats
`AUTO_YES=true` as batch mode and never runs `sudo -v`. Interactive fresh
Ubuntu/WSL run with the shipped default: every apt package (zsh, tmux, git,
build-essential…) is deferred "to your administrator" even though the user is
at a TTY. **Fix:** separate "overwrite files without asking" from "no sudo
prompting"; only skip `sudo -v` when there is genuinely no TTY.

### M — bash-core-4: `--config <nonexistent>` silently ignored
`lib/config.sh:23-42`. A typo'd `--config` path falls through to the repo
`config.yaml` with no warning; with `auto_yes: true` the run then overwrites
dotfiles using the wrong profile. **Fix:** error out when an explicit path
does not exist.

### M — bash-core-5 [tested]: YAML parser corrupts quoted values containing `#`
`lib/yaml.sh:43-51`. `name: "a # b"   # comment` parses to `"a` (unbalanced
quote, quotes not stripped). The comment position is decided on a
quote-masked copy but stripped from the original line. `lib/Config.psm1`
handles this correctly and has a Pester regression test
(`Config.Tests.ps1:100`); bash has none → engine divergence. **Fix:** strip
by position computed on the masked copy; add the mirrored bash test.

### M — bash-core-6 [tested]: flat-style lists bind to the wrong key
`lib/yaml.sh:54-79`. A list item indented level with its key
(`flatlist:\n- one`) is attributed to the *parent* key; `cfg_list` returns
empty and the feature is silently skipped. **Fix:** attribute to the most
recent key header, or warn on the unsupported form.

### M — bash-core-7 [tested]: non-2-space indentation silently mis-namespaces keys
`lib/yaml.sh:34-35, 96-104`. 4-space indent yields `CFG_X__VALUE`
(double underscore) or picks up a stale key from an earlier section. The
parser drops unrecognized lines with zero diagnostics. **Fix:** post-parse
lint pass that warns about any non-blank line matching neither rule
(tabs, odd indents included).

### M — bash-core-8: `bootstrap.sh` re-run dies on the documented workflow
`bootstrap.sh:42`. `git pull --ff-only` hard-fails under `set -e` when the
user edited the tracked `config.yaml` in `~/.local/share/env-setup` and
upstream also touched it. **Fix:** catch the failure and print recovery
guidance (stash / config.local.yaml), or stash around the pull.

### M — bash-core-9: `_start_sudo_keepalive` EXIT trap clobbers any future trap
`lib/package.sh:104`. Latent (no other production EXIT trap today).
**Fix:** chain the prior trap or document the constraint.

### L — bash-core-10 [tested]: `bash lib/backup.sh list` exits after first entry
`lib/backup.sh:143`. `((count++))` from 0 returns status 1 under the
standalone `set -euo pipefail`. **Fix:** `count=$((count+1))`.

### L — bash-core-11: `deploy_config` prompts during `--dry-run`
`lib/dryrun.sh:78-101`. With `AUTO_YES=false` and a differing existing dest, a
dry-run blocks on `ask_yes_no`. Masked today by shipped `auto_yes: true`.

### L — bash-core-12: unbounded backup growth
`lib/backup.sh:21-64`. Every run snapshots `~/.oh-my-zsh` (tens of MB) into a
new timestamped dir; nothing prunes. **Fix:** keep last N; consider excluding
re-clonable trees.

### L — bash-core-13: `is_protected_path "/"` returns "not protected"
`lib/uninstall.sh:32-40`. `_abs "/"` normalizes to the empty string, which
matches no guard. Latent (callers hardcode paths). **Fix:** treat empty/`/`
as always protected.

### L — bash-core-14: `strip_block_from_file` changes file permissions
`lib/uninstall.sh:167-173`. `mv` of a mode-600 mktemp file over `.zshrc`
replaces its mode; temp leaks if awk fails. **Fix:** `cat "$tmp" > "$file"`.

### L — bash-core-15: `remove_fragment` marker matched as regex
`lib/uninstall.sh:143`. `grep -q "$marker"` — metachars in a marker mismatch.
**Fix:** `grep -qF`.

### L — bash-core-16: `add_to_shell_config` is dead code and bypasses dry-run
`lib/common.sh:162-175`. Only tests reference it. Flagged, not deleted
(pre-existing dead code).

### L — bash-core-17: `setup.sh` doesn't export `DRY_RUN`/`AUTO_YES`
`setup.sh:131-152` vs `uninstall.sh:108`; CLAUDE.md claims they're exported.
Harmless today (modules are sourced), inconsistent tomorrow.

### L — bash-core-18: doc mismatch on backup location
`config.yaml:24` / `config.yaml.example:24` say `~/.config/env-setup/backups/`;
actual is `~/.env-setup/backups` (`lib/backup.sh:18`).

### L — bash-core-19: `PROTECTED_EXTRA` construction can abort uninstall
`uninstall.sh:111`. A trailing empty `cfg_list` line makes the final
`[[ -n ]] &&` return 1 under errexit. Latent. **Fix:** `|| true` inside.

### Maintainability
- `_module_in_filter` + module-runner loop duplicated between `setup.sh:198-256`
  and `uninstall.sh:152-181` → candidate `lib/runner.sh`.
- All modules share one shell namespace when sourced; `_prefix` convention is
  the only collision guard.

---

## 3. Bash modules (`modules/*.sh`)

### H — bash-mod-1: generated fragments never update (self-update broken promise)
`modules/02-languages.sh:25,133,226` (nvm/pyenv/conda), `modules/01-core.sh:42`
(homebrew). Fragments are rewritten only when the file is missing or lacks the
marker — but old and new versions both contain the marker, so content never
upgrades. Verified: commits `364fa40` (pyenv `--no-rehash`) and `7dfb2c0`
(eager node for MCP) changed fragment content; self-updating machines never
receive either fix. **Fix:** content comparison or a version stamp in the
fragment header; extract the 4× copy-pasted writer into
`write_generated_fragment <name> <content>`.

### H — bash-mod-2: macOS `~/.tmux.conf` becomes unremovable + keep-existing violation
`modules/07-tmux.sh:97-113,183`. On macOS the module appends a 3-line block
after deploying `tmux.conf`, so uninstall's byte-compare never matches → the
file is "preserved" while `~/.tmux/tmux.macos.conf` (unmodified) is deleted →
dangling `source-file` error on next tmux start. The append also runs under
`--keep-existing`. **Fix:** move the macOS source block into the repo
`tmux.conf` (guarded by `if-shell uname Darwin`) and drop the append logic.

### H — bash-mod-3: `uninstall_cli_tools` unconditionally deletes user-modified `50-tools.zsh`
`modules/05-cli-tools.sh:207`. `remove_fragment` without a marker argument is
a bare `dry_run_rm` with no byte-compare. Teardown order 06→05 means the only
file that reaches this deletion is precisely a user-modified one that 06 just
preserved. **Fix:** use `remove_managed_file` with the repo source path.

### M — bash-mod-4: homebrew fragment never written when brew is pre-installed
`modules/01-core.sh:23-26` early-returns before the fragment write at
`:38-47`. Apple Silicon + user-installed brew + env-setup's skeleton `.zshrc`:
PATH loses `/opt/homebrew/bin` in new shells; re-runs can't repair it.
**Fix:** write the fragment before the early return.

### M — bash-mod-5: dry-run network leak via command substitution
`modules/01-core.sh:29`, `modules/06-shell.sh:64-65`.
`dry_run_cmd /bin/bash -c "$(curl …)"` evaluates the substitution before
dry_run_cmd sees it — dry-run still downloads the full installer and floods
the log with it. Modules 02/03/05 use the correct single-quoted pipeline form.
**Fix:** match the 02 pattern.

### M — bash-mod-6: nvm half-install detected as installed
`modules/02-languages.sh:14`. `[[ -d ~/.nvm ]]` alone; an interrupted first
install leaves a shell without `nvm.sh`, re-runs skip installation, `nvm
install` is command-not-found, module still reports success. Same class as
the already-fixed OMZ repair (`caeeb0d`). **Fix:** probe
`[[ -s ~/.nvm/nvm.sh ]]`, clear and reinstall when broken.

### M — bash-mod-7: `SKIP_CLI_TOOLS` / `SKIP_SHELL_SETUP` are dead switches
`lib/config.sh:116-124` sets `CFG_CLI_TOOLS_ENABLED`/`CFG_SHELL_ENABLED`, but
no module reads `cli_tools.enabled` / `shell.enabled` (05 checks per-tool
keys, 06 checks `shell.install_zsh` etc.). `SKIP_SHELL_SETUP=true bash
setup.sh` still overwrites `~/.zshrc`. Windows twin has the same mapping
(`lib/Config.psm1:129-130`) with the same dead ends. **Fix:** gate the module
entry points.

### M — bash-mod-8: `shell.plugins.builtin` is read by nothing; `external` installs but never enables
`config.yaml:148-198` vs `configs/zshrc/10-omz.zsh:22-54`. The effective
plugin list is hardcoded in the fragment. Adding to `builtin` does nothing;
adding to `external` clones but never loads; removing from `external`
uninstalls the clone while `10-omz.zsh` still lists it → OMZ "plugin not
found" warning each shell. **Fix:** have 06-shell generate the `plugins=(…)`
section from config, or remove the knob and document the fragment as the
source of truth.

### M — bash-mod-9: 04-docker reports success after total failure
`modules/04-docker.sh:37-51`. GPG download `|| true`, then update/install/
usermod fail one by one (errexit suspended), then unconditional
`log_success "Docker Engine installed"`. **Fix:** post-install
`command_exists docker` verification (dry-run exempt), as 01/05 do.

### L — bash-mod-10: 03-python-tools installers never verified
`modules/03-python-tools.sh:16,31,50`. On a no-sudo box with deferred build
deps, `pip install jupyterlab` fails under PEP 668 yet "Jupyter Lab installed"
prints. **Fix:** apply the `DRY_RUN || command_exists` verification pattern.

### L — bash-mod-11: dry-run previews swallowed by redirects
`modules/08-claude-code.sh:762,766`, `modules/07-tmux.sh:189`.
`dry_run_cmd … >/dev/null 2>&1` hides the `[DRY-RUN] Would run:` line, so
`uninstall.sh --dry-run` under-reports actions.

### L — bash-mod-12: fresh-machine `--dry-run` prints phantom [ERROR]s
`modules/06-shell.sh:26,70`, `modules/07-tmux.sh:21`. Post-install existence
checks lack the `[[ "$DRY_RUN" == true ]] ||` exemption that 01/05 have.

### L — bash-mod-13: assorted confirmed nits
- `modules/02-languages.sh:18,125`: `curl -o- …` / bare `curl` missing `-fsSL`.
- `modules/02-languages.sh:18`: nvm pinned at v0.40.1 with no drift reminder.
- `modules/05-cli-tools.sh:109-118`: no-sudo zoxide fallback still leaves a
  misleading admin-summary entry, and PATH may hide the fallback install from
  the verifier.
- `modules/08-claude-code.sh:622-630`: `_latest_bak` picks by mtime, but
  `cp -p` preserves source mtime → wrong "newest" possible. Filenames embed a
  timestamp; sort lexically.
- `modules/06-shell.sh:58-61`: OMZ half-install repair `rm -rf`s user content
  under `custom/` — worth a louder warning.

### Consistency (vs `.claude/rules/shell-scripts.md`)
- 06-shell internal helpers lack the `_` prefix (`install_zsh`,
  `install_oh_my_zsh`, `install_powerlevel10k`, `install_zsh_plugins`,
  `deploy_shell_config`, `set_default_shell`).
- `pkg_install_cask` exists but is never used — 02/04 call bare
  `brew install --cask`.
- `modules/10-worklog.sh:56` uses raw `command -v` instead of `command_exists`.
- 04-docker prints its header before the `cfg_enabled` gate; others gate first.

### Maintainability
- Generated-fragment writer duplicated 4×; post-install verification
  three-liner duplicated in 01/05/07 and missing in 02/03/04/06;
  `cfg_list`-into-array while-loop appears 7×.

---

## 4. PowerShell engine core (`setup.ps1`, `uninstall.ps1`, `bootstrap.ps1`, `lib/*.psm1`)

### H — ps-core-1 [tested]: `Remove-ManagedFile` can delete user-modified files
`lib/Uninstall.psm1:59` (same pattern `lib/DryRun.psm1:53`). `Compare-Object`
on `Get-Content` output is an unordered multiset comparison — reordering lines
in a deployed config makes uninstall judge it "identical to repo" and delete
it. Bash uses `cmp -s` (true byte compare). **Fix:** `Get-FileHash` /
byte-equality in both `Remove-ManagedFile` and `Deploy-Config`.

### H — ps-core-2 [tested]: the 5.1 path breaks all JSON merges (JSONC + BOM)
`bootstrap.ps1:83` runs `setup.ps1` in-process under 5.1 and never re-execs
into pwsh 7 (even after 06-Shell installs it). Consequences under 5.1:
- `Merge-WtSettings` (`lib/WindowsTerminal.psm1:14`) feeds JSONC (Windows
  Terminal settings with `//` comments) to `ConvertFrom-Json` → throws,
  failing 06-Shell. Under pwsh 7 it parses but the rewrite silently deletes
  all user comments.
- `Set-Content -Encoding utf8` writes UTF-8 **with BOM** on 5.1
  (`modules/08-ClaudeCode.ps1:105,121`, `modules/10-Worklog.ps1:54`,
  `modules/06-Shell.ps1:97`) — a BOM'd `~/.claude.json` breaks strict
  `JSON.parse` consumers.
**Fix:** re-exec into pwsh from bootstrap once available; add one BOM-less
write helper (`[IO.File]::WriteAllText`) used by all JSON writers; strip or
warn about comments before WT merge.

### H — ps-core-3: bootstrap fails on a truly fresh box (stale PATH after git install)
`bootstrap.ps1:40-44,55-69`. `winget install Git.Git` doesn't refresh the
session `$env:Path`; the immediate `git` call throws CommandNotFound under
EAP=Stop. winget's exit code is also unchecked. **Fix:** refresh PATH from
registry or probe `$env:ProgramFiles\Git\cmd\git.exe`; check `$LASTEXITCODE`.

### M — ps-core-4: the no-admin defer path is dead code
`lib/Package.psm1:70`; no caller passes `-RequiresAdmin`
(`modules/01-Core.ps1:25-26`, `modules/06-Shell.ps1:184-185` are machine-scope
installs). On a non-admin box winget fails → module throws → Failed; the
"Administrator Action Required" summary never prints, contradicting CLAUDE.md.
**Fix:** defer on winget elevation-failure exit codes (don't pre-gate on
`Test-Elevated` — UAC may still work), mirroring `record_missing_apt_package`.

### M — ps-core-5: `Install-Pkg` ignores scoop failures
`lib/Package.psm1:44-49`. No exit-code check; stale "Stage 2 will fix"
comment. A 404/hash-mismatch leaves the module green. **Fix:** gate on scoop
exit code or post-install `Test-Command`.

### M — ps-core-6: newest-backup selection sorts by preserved mtime
`lib/Backup.psm1:31-32`, duplicated `modules/08-ClaudeCode.ps1:180-181`.
`Copy-Item` preserves source LastWriteTime, so `.bak.*` mtimes are original
edit times; non-monotonic mtimes restore the wrong backup. Filename stamps are
authoritative. **Fix:** `Sort-Object Name`; export one shared finder from
Backup.psm1.

### M — ps-core-7 [tested]: `Merge-WtSettings` corrupts array-form `profiles`
`lib/WindowsTerminal.psm1:16-21`. Legacy `"profiles": [ … ]` gets a bogus
`defaults` member injected into every element via pipeline enumeration; font
never applies; file rewritten anyway. **Fix:** detect array form, wrap or
skip with a warning.

### L — ps-core-8 [tested]: `Remove-ManagedSettingsKeys` unwraps one-element arrays
`lib/ClaudeConfig.psm1:66-67`. `$cur.$k | ConvertTo-Json` serializes `@('x')`
as `"x"`, so `["x"]` vs `"x"` compare equal and the key is wrongly stripped on
uninstall. **Fix:** `ConvertTo-Json -InputObject $cur.$k`.

### Parity gaps (vs Bash engine)
- Duplicate YAML section headers: bash merges, PS replaces the section map
  (`lib/Config.psm1:85-86`) — values silently lost on Windows only.
- `uninstall.ps1:79` honors config `general.dry_run` (a leftover `true` makes
  Windows uninstall a silent no-op); `uninstall.sh` doesn't. Conversely bash
  honors exported `DRY_RUN=true`; PS only knows `-DryRun`/config.
- No log file on Windows (`setup_logging` has no PS analog).
- Module failure granularity differs (bash continues mid-module, PS aborts at
  first terminating error).
- Interactive consent: bash previews and prompts before settings/MCP merges;
  PS mutates without asking (backup only).

### Maintainability
- `Test-ModuleInFilter` duplicated verbatim (`setup.ps1:47-60`,
  `uninstall.ps1:52-61`) → Common.psm1.
- TLS 1.2 opt-in tripled (`02:40`, `06:141`, `bootstrap.ps1:77`).

---

## 5. PowerShell modules (`modules/*.ps1`)

### H — ps-mod-1 [tested]: stderr redirects on native commands throw under 5.1
`modules/10-Worklog.ps1:61,76`, `modules/08-ClaudeCode.ps1:130,145,248,254`,
`modules/03-PythonTools.ps1:39-40`. Under WinPS 5.1 + EAP=Stop, a native
command writing to a redirected stderr (`*> $null`, `2>$null`) throws
RemoteException and kills the module. Fresh bootstrap (5.1 in-process, gh not
yet authenticated): `gh repo view` stderr banner → 10-Worklog Failed, setup
exits 1; the designed lazy-clone fallback is unreachable on 5.1.
**Fix:** an `Invoke-Native` helper that temporarily sets EAP=Continue and
captures output.

### M — ps-mod-2: `Set-WindowsTerminalFont` not idempotent → uninstall restore ineffective
`modules/06-Shell.ps1:95-98`. No merged-vs-current comparison (unlike
`Sync-ClaudeSettings`); every run backs up + rewrites. After two runs the
"newest backup" already contains the merged font, so `Uninstall-Shell`'s
restore is a no-op and backups accumulate. **Fix:** compare, skip when equal.

### M — ps-mod-3: `Sync-ClaudeMcp` missing the Bash idempotency check
`modules/08-ClaudeCode.ps1:119-122` vs `08-claude-code.sh:537-549`. With ≥1
declared server, every run backs up and rewrites the live `~/.claude.json`;
restores lose post-backup Claude Code state; uninstall restore converges to
already-merged content. **Fix:** port the current==expected short-circuit.

### M — ps-mod-4: `windows.powershell.omp_theme` half-wired
`modules/06-Shell.ps1:190-193` deploys by configured name;
`configs/pwsh/00-omp-init.ps1:3` hardcodes `envsetup.omp.json`. Custom theme
names silently fall back to OMP's default. Same class:
`configs/pwsh/20-modules.ps1` hardcodes three modules regardless of
`windows.powershell.modules`. **Fix:** write the chosen values into a
generated state file (the `update.ps1` pattern) or deploy under the fixed name.

### M — ps-mod-5: `Remove-ClaudeBinFromPath` over-deletes
`modules/08-ClaudeCode.ps1:54-68`. Removes `~/.local/bin` from user PATH
unconditionally on uninstall, even when `Add-ClaudeBinToPath` had detected it
pre-existing (pipx uses the same dir). **Fix:** record "added by us" state, or
only remove when the dir is gone/empty.

### M — ps-mod-6: plugin/marketplace registration lacks idempotency pre-checks
`modules/08-ClaudeCode.ps1:125-148` vs `08-claude-code.sh:395-421,452-480`.
config.yaml.example:291 promises the skip; PS re-shells-out every run (slow,
networked, misleading "Failed to install plugin" on already-installed, and a
hard failure on 5.1 via ps-mod-1). **Fix:** port the two JSON pre-checks.

### M — ps-mod-7 [tested]: empty-string config values crash Worklog module
`modules/10-Worklog.ps1:28-35,66-70`. Six `[Parameter(Mandatory)][string]`
params without `[AllowEmptyString()]`; capture-role machines legitimately omit
`vault_repo`/`vault_path` → binding throws → module Failed. Bash degrades
gracefully. **Fix:** add `[AllowEmptyString()]` (as `Resolve-WorklogPath`
already does) or default before binding.

### M — ps-mod-8: corrupted user JSON aborts the whole module
`modules/08-ClaudeCode.ps1:100-102,113,119,199`. `ConvertFrom-Json` throws
under EAP=Stop → all later steps (marketplaces, plugins, ccstatusline) are
skipped. Bash `jq empty`-checks and continues. **Fix:** try/catch → warn +
return.

### L — ps-mod-9: 02-Languages ignores nvm/pyenv failures
`modules/02-Languages.ps1:164,187`. `nvm use` symlink failure (no Developer
Mode, unelevated) unchecked; `pyenv global` runs even when the Python build
failed. **Fix:** check `$LASTEXITCODE` / verify python.exe exists.

### L — ps-mod-10: 09-UserDirs missing the Bash path validation
`modules/09-UserDirs.ps1:16-18` vs `09-user-dirs.sh:13-27`. No guard against
absolute paths, `~/` prefixes, or `..` components — dirs can be created (and
uninstalled) outside `$HOME`. **Fix:** port the three guards.

### L — ps-mod-11: `Uninstall-ClaudeCode` leaves the version store
`modules/08-ClaudeCode.ps1:257-258` removes only the launcher; Bash also
removes `~/.local/share/claude` (potentially hundreds of MB).

### L — ps-mod-12: uninstall scope decided by current config, not detection
`modules/06-Shell.ps1:84-87`. Flipping `windows.powershell5_profile` to false
before uninstalling orphans the 5.1 profile. Detection-driven teardown should
check both paths exist.

### L — ps-mod-13: assorted
- `Remove-NerdFont` (`06:217`) prints success even in dry-run / nothing-to-do.
- `general.backup: true` unimplemented on Windows: first overwrite of an
  existing `profile.ps1` is unrecoverable. One `Backup-File` call fixes it.
- `Add-ClaudeBinToPath` never broadcasts `WM_SETTINGCHANGE`
  (`Enable-SessionFonts` at `06:114-123` already has the P/Invoke to reuse).
- `languages.conda.enabled: true` silently ignored on Windows (no module reads
  it) — deserves one log line.
- Uninstall leaves empty dirs: `~/.config/powershell/fragments`,
  `~/.config/oh-my-posh`, `~/.config/worklog`, `~/.env-setup`.

### Consistency
- `Invoke-OrDryRun` is unused inside modules — all use hand-rolled
  `if (Test-DryRun)` blocks (no actual leaks found; convention drift only).
- `Get-NewestBakPath` (08) duplicates `Restore-NewestBak` discovery;
  `enabledPlugins` iteration duplicated between install and uninstall.

---

## 6. Runtime config assets (`configs/` excluding `configs/claude/`)

### H — cfg-1: tmux.conf `bc` version detection is broken on modern tmux
`configs/tmux/tmux.conf:139,167,183`. Versions with letters (3.5a brew, 3.2a
Ubuntu 22.04) are bc syntax errors → comparison false → the "< 2.9" legacy
branch applies options removed in tmux 2.9 (`status-bg`, `pane-border-fg`, …)
→ startup error spam, theme partially unapplied. `bc` also isn't in any
install list. **Fix:** drop the checks (all supported platforms ≥ 3.0) or use
native `%if #{>=:#{version},2.9}`.

### H — cfg-2: self-update can hang shell startup on credential prompts
`configs/zshrc/55-self-update.zsh:38,43`, `configs/pwsh/45-self-update.ps1:38,44`.
git fetch/pull stderr is discarded but stdin stays attached — expired HTTPS
token or passphrase-protected SSH key shows an invisible prompt; new shells
appear frozen at cadence expiry. **Fix:** `GIT_TERMINAL_PROMPT=0` (+
`GIT_SSH_COMMAND='ssh -oBatchMode=yes'`).

### M — cfg-3: update prompt collides with p10k instant prompt
`55-self-update.zsh:49` does interactive `read -q` during zshrc init while
instant prompt (`.p10k.zsh:1727`, verbose) intercepts output — the question is
buffered invisible while the keyboard is being consumed. **Fix:** defer to a
precmd hook, drop interactivity, or background the fetch and report next
prompt.

### M — cfg-4: zsh-completions never registered
`configs/zshrc/30-completion.zsh:6` appends to fpath *after* OMZ's compinit
(run at `10-omz.zsh:57`); the plugins-array route doesn't work either (the
documented OMZ pitfall — `src/` is added to fpath only post-compinit). Net:
the whole extra-completions package silently does nothing. **Fix:** a
`05-completion-fpath.zsh` fragment ordered before 10-omz; remove from plugins.

### M — cfg-5: `[Environment]::UserInteractive` is not an interactivity check
`configs/pwsh/45-self-update.ps1:19`. True for all non-service processes;
profile-loading automation (`pwsh -File` without `-NoProfile`) hits `Read-Host`
at cadence expiry and hangs. zsh has `[[ -o interactive ]] + [[ -t 0 ]]`;
pwsh equivalent missing. **Fix:** also require
`-not [Console]::IsInputRedirected` and bail on `-NonInteractive` in
`GetCommandLineArgs()`.

### M — cfg-6: `alias grep='grep --color=auto -n'` pollutes pipelines
`configs/aliases.zsh:16`. `-n` stays active in pipes (unlike `--color=auto`);
`… | grep x | awk …` breaks silently. **Fix:** drop `-n`.

### M — cfg-7: unconditional `LC_ALL=en_US.UTF-8` and `EDITOR=vim`
`configs/zshrc/40-env.zsh:6-11`. No module runs `locale-gen`; minimal
Debian/WSL images lack en_US.UTF-8 → setlocale warnings everywhere, LC_*
overridden. vim is never installed by this repo → `git commit` fails.
**Fix:** set only `LANG` gated on `locale -a`; gate EDITOR on `command -v`.

### L — cfg-8: pain-control overrides hand-written tmux binds
`configs/tmux/tmux.conf:99-100` (`bind >`/`<` swap-pane) are re-bound by
tmux-pain-control loaded at line 218. Pick one source.

### L — cfg-9: hardcoded pwsh fragment values (see ps-mod-4)
`00-omp-init.ps1:3` theme name; `20-modules.ps1` module list.

### L — cfg-10: `45-self-update.ps1:28` — `(Get-Content -Raw).Trim()` outside try
Empty stamp file → method call on $null → red error every shell start until
manually cleared. zsh side already handles this.

### L — cfg-11: `localip` uses `ifconfig` (`configs/aliases.zsh:140`) — absent on
modern Ubuntu. Use `ip -4 addr` / `hostname -I`.

### L — cfg-12: nested-shell PATH duplication
`40-env.zsh:14` and generated 15-pyenv fragment prepend unconditionally;
16-nvm's `case ":$PATH:"` guard is the correct template to copy.

### Parity gaps (zsh vs pwsh UX)
- git shortcuts: zsh has gs/ga/gc/gp/gl/gd/gco/gb/glog; pwsh only `g`.
- `cat`: zsh `bat --paging=never` vs pwsh `bat` (pager on Windows only).
- `lt` means mtime-sort on zsh, tree view on pwsh.
- pwsh shadowing `ls`/`cat` converts object pipelines to text (tradeoff to
  document, at minimum).

### Verified clean
config.yaml == config.yaml.example (test-guaranteed); all other example keys
have live readers on at least one engine; zellij configs valid; worklog
command docs match module-generated state keys; ccstatusline launcher logic
correct; self-update cadence-gate core logic correct on both engines; omp
theme JSON valid; p10k fragment ordering correct.

---

## 7. Tests & CI

### H — test-1: a test that can never fail
`tests/test_common.sh:66-67`. `command_exists X || true` swallows the real
exit code; `assert_false 1` asserts a constant. **Fix:** capture `$?` under a
`set +e` window (pattern already in `test_uninstall.sh:26`).

### H — test-2: dry-run suite runs against the real $HOME
`tests/test_dryrun.sh:91-128`. Full installer dry-run against the developer's
real home, mutation detected *after* the fact via 3 checksums only.
**Fix:** sandboxed `HOME` (as `test_uninstall.sh:11` does) + assert-empty.

### M — test-3: real-$HOME log pollution
`test_common.sh:73`, `test_modules.sh:17`, `test_self_update.sh:13`,
`test_worklog.sh:14`, `test_ccstatusline.sh:16`, `test_user_dirs.sh:15` —
`LOG_DIR` binds to real `~/.env-setup` at source time; several suites
re-point HOME too late. **Fix:** export sandbox HOME before sourcing
lib/common.sh.

### M — test-4: orphaned e2e test
`tests/e2e/test_uninstall_roundtrip.sh` is referenced by nothing (not
run_all.sh, not CI, not the docker harness) yet covers the highest-risk flow
(install → user edits → uninstall preserves/removes correctly) hermetically.
**Fix:** add to `run_all.sh`'s array.

### M — test-5: integration.yml paths filter misses what it tests
`.github/workflows/integration.yml:12-18` omits `uninstall.sh` and
`scripts/**`; a PR touching only uninstall.sh skips the only workflow that
exercises a real uninstall. **Fix:** extend the paths list.

### M — test-6: Pester failure detection misses discovery/fixture crashes
`ci.yml:102-103,141-142`. `FailedCount -gt 0` stays 0 when a `BeforeAll`
throws (tests NotRun, job green). **Fix:** `if ($r.Result -ne 'Passed')`.

### M — test-7: local shellcheck diverges from CI
`tests/test_shellcheck.sh:32-47` omits `uninstall.sh` (CI includes it);
`tests/*.sh` linted by neither. **Fix:** align the arrays.

### L — test-8: silent skips counted as passes
shellcheck-absent (`test_shellcheck.sh:16-21`) and jq-absent
(`test_uninstall.sh:146-148`) paths record PASS with no skip status;
`test_ccstatusline.sh` conversely hard-crashes without jq. **Fix:** a counted
`skip` primitive in test_framework.sh.

### L — test-9: dead `rc=$?` captures under errexit
`test_worklog.sh:49-50`, `test_ccstatusline.sh:43,67,188,201`,
`test_common.sh:64,100` — the framework's `set -e` aborts before the assert
runs; failures are detected but diagnostics and summary are lost.

### L — test-10: CI hygiene
- No `permissions:` block in ci.yml / integration.yml (review.yml has one).
- PSScriptAnalyzer/Pester installed from the gallery every run, uncached and
  unpinned; integration.yml (flakiest job) retries nothing.
- review.yml re-runs the full bash suite already run by ci.yml; its PR comment
  step 403s on forked PRs.
- powershell-lint misses `configs/pwsh/*.ps1`, `configs/aliases.ps1`,
  `tests/*.Tests.ps1`.
- yaml-validate uses PyYAML — accepts a superset of what either in-house
  parser handles (anchors/tabs/flow style pass CI, break production).
- `tests/run_e2e.sh:110`: `command -v rg || command -v rg` (duplicated
  alternative, copy-paste no-op).
- Bash unit suites require bash ≥ 4 (`declare -A`) — the documented
  `bash tests/run_all.sh` fails on stock macOS bash 3.2 and there is no macOS
  unit lane.
- `test_framework.sh:24` hardcodes `/tmp`; `test_ccstatusline.sh:15` leaks its
  first tmpdir; `Uninstall.Tests.ps1:34` sets `$env:ENVSETUP_DRY_RUN` in
  BeforeAll without AfterAll reset.

### Top 5 coverage gaps (ranked by risk)
1. Bash regression test for quoted-`#` + inline comment (`lib/yaml.sh`) — the
   PS engine has the exact test, bash has the exact bug.
2. `restore_configs` / uninstall-restore flow — zero tests on both engines
   (the data-loss-adjacent path).
3. Functional test of the zsh self-update cadence gate (PS twin has real logic
   tests; zsh has only string greps).
4. Bash env-var overrides in `lib/config.sh:90-108` (PS side tested, bash not).
5. Uninstall reverse-order (09→01) contract — asserted nowhere; a dry-run
   header-order assertion is cheap.

### Highest-value additions
- **Engine parity test**: parse `config.yaml.example` (plus a shared
  edge-case fixture) with both `lib/yaml.sh` and `lib/Config.psm1`, normalize
  to sorted KEY=VALUE, diff. One ubuntu job; mechanically catches every parser
  divergence, past and future.
- Promote the orphaned roundtrip e2e into run_all.sh.
- Cache + pin PSScriptAnalyzer/Pester in CI.
- PowerShell equivalent of `test_config_consistency.sh` (bash-only today).

---

## 8. Suggested fix roadmap (one concern per PR)

| # | PR | Contents | Findings addressed |
|---|----|----------|--------------------|
| 1 | `fix(uninstall): data-safety` | hash compare on Windows; `50-tools.zsh` managed removal; `is_protected_path` empty-input | ps-core-1, bash-mod-3, bash-core-13 |
| 2 | `fix(package): honest failure reporting` | had_failure on all branches; scoop exit check; module error counters | bash-core-1/2, ps-core-5 |
| 3 | `fix(shell): fragment versioning + self-update hardening` | shared `write_generated_fragment` with content compare; GIT_TERMINAL_PROMPT=0; prompt-after-init | bash-mod-1, cfg-2, cfg-3 |
| 4 | `fix(windows): 5.1 path` | bootstrap re-exec into pwsh; BOM-less JSON writer; Invoke-Native stderr helper; PATH refresh | ps-core-2/3, ps-mod-1 |
| 5 | `fix(tmux): drop bc version detection` | assume ≥ 3.0, `-style` options only | cfg-1 |
| 6 | `feat(claude-code): harness` | per the harness design spec | see spec |
| 7 | `test(ci): parity + roundtrip + result checks` | yaml parity test; roundtrip into run_all; Pester Result check; paths filters; permissions blocks | test-1..7, coverage gaps |

Remaining M/L findings can trail as small follow-up PRs grouped by scope
(`fix(modules)`, `fix(configs)`, `chore(tests)`).
