# env-setup

Config-driven development environment setup for macOS, Ubuntu (including WSL),
and native Windows (PowerShell).

All available configuration options: @config.yaml.example

## Architecture

`setup.sh` is the entrypoint. It reads `config.yaml` using a pure Bash/AWK
YAML parser (`lib/yaml.sh`), then runs each module in numeric order.
Users customise behaviour by editing `config.yaml` — no code changes required.

Native **Windows** uses a sibling PowerShell engine: `setup.ps1` reads the
same `config.yaml` (via a pure-PowerShell reader in `lib/Config.psm1`) and
runs `modules/*.ps1` (added incrementally per stage). The two engines never
call each other — `setup.sh` for macOS/Linux/WSL, `setup.ps1` for native
Windows.

## Directory Structure

```
env-setup/
├── bootstrap.sh          # One-liner remote installer (Unix)
├── bootstrap.ps1         # One-liner remote installer (Windows / PowerShell)
├── setup.sh              # Main entrypoint (Unix) — orchestrates module execution
├── setup.ps1             # Main entrypoint (Windows) — PowerShell module runner
├── config.yaml           # User configuration (sensible defaults)
├── config.yaml.example   # Fully commented reference config
├── lib/                  # Bash engine (*.sh) + Windows engine (*.psm1) siblings
│   ├── common.sh         # Logging, colours, platform detection, helpers
│   ├── yaml.sh           # Pure bash/awk YAML parser (no external deps)
│   ├── config.sh         # Config loader with env-var overrides
│   ├── package.sh        # Cross-platform package management (brew/apt)
│   ├── dryrun.sh         # Dry-run wrappers for commands and file ops
│   ├── backup.sh         # Backup and restore shell/tool configs
│   ├── Common.psm1       # (Windows) logging, $IsWindows guard, helpers
│   ├── Config.psm1       # (Windows) pure-PowerShell config.yaml reader
│   ├── Package.psm1      # (Windows) scoop/winget + no-admin defer
│   ├── DryRun.psm1       # (Windows) dry-run + deploy wrappers
│   ├── Backup.psm1       # (Windows) timestamped backups
│   └── WindowsTerminal.psm1  # (Windows) Windows Terminal settings merge
├── modules/              # Numbered scripts run in dependency order
│   ├── 01-core.sh        # Homebrew, git config, build tools
│   ├── 02-languages.sh   # Node (nvm), Python (pyenv), Conda
│   ├── 03-python-tools.sh # Jupyter, Poetry, uv
│   ├── 04-docker.sh      # Docker Engine / Desktop
│   ├── 05-cli-tools.sh   # fzf, ripgrep, bat, fd, eza, zoxide, etc.
│   ├── 06-shell.sh       # Zsh, Oh My Zsh, Powerlevel10k, plugins
│   ├── 07-tmux.sh        # tmux + TPM
│   ├── 08-claude-code.sh # Claude Code CLI (native installer)
│   └── 09-user-dirs.sh   # Create personal directories under $HOME
│                         # Windows modules: 01-03, 05-07 as NN-Name.ps1 (08-09 pending)
├── configs/              # Dotfile templates and fragments
│   ├── zshrc/            # .zshrc fragments (numbered for load order)
│   ├── zshrc.base        # Skeleton .zshrc that sources fragments
│   ├── aliases.zsh       # Custom shell aliases
│   ├── tmux/             # tmux.conf + macOS overrides + dev layout
│   ├── p10k/             # Powerlevel10k configuration
│   ├── ccstatusline/     # ccstatusline widget config (deployed by 08-claude-code)
│   ├── pwsh/             # (Windows) $PROFILE fragments (numbered)
│   ├── pwsh.profile.base # (Windows) skeleton $PROFILE that sources fragments
│   ├── aliases.ps1       # (Windows) PowerShell function aliases
│   ├── omp/              # (Windows) Oh My Posh theme
│   └── zellij/           # (Windows) zellij config + dev layout
├── scripts/              # Maintenance and helper scripts
│   └── verify.sh         # Post-install verification
├── PSScriptAnalyzerSettings.psd1  # Windows engine lint config
└── .github/workflows/    # CI — Unix: shellcheck+dry-run; Windows: PSScriptAnalyzer+Pester+dry-run
```

## Key Design Decisions

- **Fragment-based .zshrc assembly**: Instead of one monolithic `.zshrc`,
  modules drop fragments into `configs/zshrc/`. At install time they are
  concatenated in order, making it easy to add or remove sections without
  merge conflicts.
- **Pure bash/awk YAML parser**: No dependency on Python, Ruby, or `yq`.
  Keeps the bootstrap path minimal — only `bash`, `git`, and `curl` are
  required.
- **GitHub Actions CI (no Docker)**: The CI matrix runs directly on
  `macos-latest` and `ubuntu-latest` runners to match real user environments.
  No containerised builds.
- **Modules are numbered for dependency order**: `01-core.sh` runs before
  `02-languages.sh` because language installers need Homebrew / build tools.
  Adding a new module means choosing the right number.
- **Single sudo prompt with no-sudo defer**: `sudo_available()` in
  `lib/package.sh` validates elevation once via `sudo -v` (password goes
  straight to sudo's getpass; the scripts never read or store it). A
  background loop refreshes the timestamp every 60s so long installs don't
  re-prompt. If sudo is unavailable (not in sudoers, batch mode, no TTY),
  apt-needing steps call `record_missing_apt_package` / `record_missing_apt_note`
  and the run continues with user-space installs. `show_missing_apt_summary`
  prints a consolidated admin instruction block at the end. macOS skips
  this path because brew runs as the user.
- **Two sibling engines (Bash + PowerShell)**: macOS/Linux/WSL run the Bash
  engine (`setup.sh`); native Windows runs the PowerShell engine
  (`setup.ps1`). They never call each other and share one `config.yaml` plus
  the `configs/` assets. PowerShell can't use the Bash/awk parser, so
  `lib/Config.psm1` ships a pure-PowerShell reader for the same restricted
  subset. Cross-module flags travel via `ENVSETUP_*` env vars (the analog of
  the Bash engine's exported `DRY_RUN`/`AUTO_YES`/`KEEP_EXISTING`). The
  no-admin defer mirrors the no-sudo path: scoop needs no admin; winget
  installs that need elevation are deferred and summarized. Lint is
  PSScriptAnalyzer (`PSScriptAnalyzerSettings.psd1`); tests are Pester. The
  Windows engine is built up stage by stage; the foundation (lib + entrypoints
  + CI) lands first, then modules.

## Commit Conventions

Follow [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/):

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

Common types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `ci`, `chore`.
Scope examples: `core`, `shell`, `tmux`, `docker`, `cli-tools`, `bootstrap`, `ci`, `windows`, `config`.

## Development Commands

```bash
# Run all tests
bash tests/run_all.sh

# Lint all shell scripts
shellcheck -x setup.sh bootstrap.sh lib/*.sh modules/*.sh scripts/*.sh

# Dry-run (prints actions without executing)
bash setup.sh --dry-run

# Run a single module
bash modules/06-shell.sh

# Verify installed tools
bash scripts/verify.sh
```

For the native-Windows PowerShell engine (run in pwsh 7):

```powershell
# Run all PowerShell tests
Invoke-Pester -Path tests -Output Detailed

# Lint all PowerShell scripts
$t = @('setup.ps1','bootstrap.ps1') + (Get-ChildItem lib -Filter *.psm1).FullName + (Get-ChildItem modules -Filter *.ps1 -ErrorAction Ignore).FullName
$t | ForEach-Object { Invoke-ScriptAnalyzer -Path $_ -Settings ./PSScriptAnalyzerSettings.psd1 -Severity Error,Warning }

# Dry-run (prints actions without executing)
./setup.ps1 -DryRun -AutoYes

# Run a single module
./setup.ps1 -Modules 06-Shell -DryRun
```

## Branch Rules

- Never push directly to `main` — always use a feature branch.
- Branch naming: `<type>/<short-description>` (e.g. `feat/add-rust-module`).
- Squash-merge PRs; delete branch after merge.
