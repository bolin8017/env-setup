# env-setup

Config-driven development environment setup for macOS and Ubuntu (including WSL).

All available configuration options: @config.yaml.example

## Architecture

`setup.sh` is the entrypoint. It reads `config.yaml` using a pure Bash/AWK
YAML parser (`lib/yaml.sh`), then runs each module in numeric order.
Users customise behaviour by editing `config.yaml` — no code changes required.

## Directory Structure

```
env-setup/
├── bootstrap.sh          # One-liner remote installer
├── setup.sh              # Main entrypoint — orchestrates module execution
├── config.yaml           # User configuration (sensible defaults)
├── config.yaml.example   # Fully commented reference config
├── lib/
│   ├── common.sh         # Logging, colours, platform detection, helpers
│   ├── yaml.sh           # Pure bash/awk YAML parser (no external deps)
│   ├── config.sh         # Config loader with env-var overrides
│   ├── package.sh        # Cross-platform package management (brew/apt)
│   ├── dryrun.sh         # Dry-run wrappers for commands and file ops
│   └── backup.sh         # Backup and restore shell/tool configs
├── modules/              # Numbered scripts run in dependency order
│   ├── 01-core.sh        # Homebrew, git config, build tools
│   ├── 02-languages.sh   # Node (nvm), Python (pyenv), Conda
│   ├── 03-python-tools.sh # Jupyter, Poetry, uv
│   ├── 04-docker.sh      # Docker Engine / Desktop
│   ├── 05-cli-tools.sh   # fzf, ripgrep, bat, fd, eza, zoxide, etc.
│   ├── 06-shell.sh       # Zsh, Oh My Zsh, Powerlevel10k, plugins
│   └── 07-tmux.sh        # tmux + TPM
├── configs/              # Dotfile templates and fragments
│   ├── zshrc/            # .zshrc fragments (numbered for load order)
│   ├── zshrc.base        # Skeleton .zshrc that sources fragments
│   ├── aliases.zsh       # Custom shell aliases
│   ├── tmux/             # tmux.conf + macOS overrides + dev layout
│   └── p10k/             # Powerlevel10k configuration
├── scripts/              # Maintenance and helper scripts
│   └── verify.sh         # Post-install verification
└── .github/workflows/    # CI — shellcheck + dry-run on macOS & Ubuntu
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

## Commit Conventions

Follow [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/):

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

Common types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `ci`, `chore`.
Scope examples: `core`, `shell`, `tmux`, `docker`, `cli-tools`, `bootstrap`, `ci`.

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

## Branch Rules

- Never push directly to `main` — always use a feature branch.
- Branch naming: `<type>/<short-description>` (e.g. `feat/add-rust-module`).
- Squash-merge PRs; delete branch after merge.
