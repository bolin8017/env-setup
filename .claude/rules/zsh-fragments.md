---
paths:
  - "configs/zshrc/*.zsh"
  - "configs/aliases.zsh"
  - "configs/zshrc.base"
---

# Zsh Fragment Rules

- Fragments in `configs/zshrc/` are concatenated in numeric order to build `.zshrc`
- Naming convention: `NN-description.zsh` where NN is a two-digit sort prefix
- Current sequence: 00 (p10k instant prompt) → 10 (omz) → 20 (history) → 30 (completion) → 40 (env) → 50 (tools) → 60 (aliases) → 99 (p10k config)
- Leave gaps between numbers for future insertions
- Each fragment must be self-contained — no dependencies on variables defined in later fragments
- Guard external tool integrations with `command -v` checks so the shell doesn't error when a tool isn't installed
