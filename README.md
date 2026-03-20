# env-setup

一鍵設定完整開發環境的自動化工具，支援 **macOS** 和 **Ubuntu**（含 WSL）。

透過一份 `config.yaml` 設定清單驅動，修改設定後執行一個指令即可完成所有安裝。

## 快速開始

### 全新系統（一行安裝）

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/bolin8017/env-setup/main/bootstrap.sh)"
```

### 手動安裝

```bash
git clone https://github.com/bolin8017/env-setup.git
cd env-setup

# 修改設定（選用，預設值已可直接使用）
vim config.yaml

# 執行安裝
./setup.sh
```

### 常用指令

```bash
./setup.sh                        # 完整安裝
./setup.sh --dry-run              # 預覽安裝內容，不實際執行
./setup.sh --modules 06-shell     # 只執行指定模組
./setup.sh --verify               # 只跑驗證檢查
./setup.sh --help                 # 顯示所有選項
```

## 安裝內容

| 類別 | 工具 |
|------|------|
| **核心** | Homebrew (macOS)、Git、GitHub CLI、build tools |
| **語言** | Node.js (nvm)、Python (pyenv)、Conda (選用) |
| **Python 工具** | JupyterLab、Poetry、uv |
| **容器** | Docker Engine / Desktop |
| **CLI 工具** | fzf、ripgrep、bat、fd、eza、zoxide、jq、btop、tldr、tree、httpie |
| **Shell** | Zsh、Oh My Zsh、Powerlevel10k、zsh-autosuggestions、zsh-syntax-highlighting、zsh-completions |
| **終端機** | tmux + TPM + 9 個外掛（Tokyo Night 主題） |
| **AI 工具** | Claude Code CLI |

每個項目都可以在 `config.yaml` 中個別開關。

## 設定

編輯 `config.yaml` 控制所有安裝行為：

```yaml
# 範例：最小安裝（只裝核心 + Shell）
general:
  auto_yes: true

core:
  homebrew: true
  git: true
  github_cli: true
  build_tools: false

languages:
  node:
    enabled: false
  python:
    enabled: false
  conda:
    enabled: false

python_tools:
  jupyter: false
  poetry: false
  uv: false

docker:
  enabled: false

cli_tools:
  fzf: true
  ripgrep: true
  bat: true
  fd: true
  eza: true
  zoxide: true
  jq: false
  btop: false
  tldr: false
  tree: false
  httpie: false

shell:
  install_zsh: true
  set_default_shell: true
  oh_my_zsh: true
  powerlevel10k: true

tmux:
  enabled: false

claude_code:
  enabled: false
```

完整設定說明請參考 [`config.yaml.example`](config.yaml.example)。

## 架構

```
setup.sh 讀取 config.yaml → 依序執行 8 個模組
 │
 ├─ 01-core         Homebrew → Git → gh → build tools
 ├─ 02-languages    nvm/Node.js → pyenv/Python → Conda
 ├─ 03-python-tools Jupyter → Poetry → uv
 ├─ 04-docker       Docker
 ├─ 05-cli-tools    11 個 CLI 工具
 ├─ 06-shell        Zsh → Oh My Zsh → P10k → plugins → .zshrc 組裝
 ├─ 07-tmux         tmux → TPM → config → plugins
 └─ 08-claude-code  Claude Code CLI（原生安裝）
```

### .zshrc Fragment 系統

`.zshrc` 不再是一整份覆蓋，而是由多個 fragment 片段組成：

```
~/.zshrc                            ← 骨架（source fragments）
~/.config/zsh/fragments/
  ├── 00-p10k-instant-prompt.zsh    ← P10k（最先載入）
  ├── 10-omz.zsh                    ← Oh My Zsh
  ├── 15-pyenv.zsh                  ← pyenv init（自動生成）
  ├── 16-nvm.zsh                    ← nvm init（自動生成）
  ├── 20-history.zsh                ← 歷史設定
  ├── 30-completion.zsh             ← 補全設定
  ├── 40-env.zsh                    ← 環境變數
  ├── 50-tools.zsh                  ← CLI 工具整合
  ├── 60-aliases.zsh                ← aliases
  └── 99-p10k-config.zsh           ← P10k 主題（最後載入）
~/.config/zsh/custom/               ← 你的自訂設定（不會被覆蓋）
```

### 冪等設計

- 已安裝的工具會自動跳過（顯示 `[SKIP]`）
- 已存在的設定檔會詢問是否覆蓋（`--auto-yes` 時自動覆蓋）
- Fragment 片段是 managed files，每次執行都會更新
- `~/.config/zsh/custom/` 目錄永遠不會被觸碰

## 目錄結構

```
env-setup/
├── setup.sh                  # 主入口
├── config.yaml               # 設定檔
├── bootstrap.sh              # 全新系統一行安裝
├── lib/                      # 共用函式庫
│   ├── common.sh             #   平台偵測、logging
│   ├── yaml.sh               #   YAML 解析器
│   ├── config.sh             #   設定載入
│   ├── package.sh            #   跨平台套件管理
│   ├── dryrun.sh             #   dry-run + deploy_config
│   └── backup.sh             #   備份/還原
├── modules/                  # 安裝模組（按依賴順序編號）
│   ├── 01-core.sh
│   ├── 02-languages.sh
│   ├── 03-python-tools.sh
│   ├── 04-docker.sh
│   ├── 05-cli-tools.sh
│   ├── 06-shell.sh
│   ├── 07-tmux.sh
│   └── 08-claude-code.sh
├── configs/                  # 設定檔模板
│   ├── zshrc/                #   .zshrc fragments
│   ├── tmux/                 #   tmux 設定
│   ├── p10k/                 #   Powerlevel10k 設定
│   └── aliases.zsh           #   shell aliases
├── scripts/verify.sh         # 安裝驗證
└── .github/workflows/        # CI（ShellCheck + 整合測試）
```

## 備份與還原

安裝前會自動備份現有設定到 `~/.env-setup/backups/`：

```bash
# 列出所有備份
bash lib/backup.sh list

# 還原最新備份
bash lib/backup.sh restore

# 還原指定備份
bash lib/backup.sh restore backup_20240207_120000
```

## 自訂

### 自訂 Shell 設定

在 `~/.config/zsh/custom/` 建立 `.zsh` 檔案即可，例如：

```bash
# ~/.config/zsh/custom/work.zsh
export WORK_DIR="$HOME/work"
alias proj="cd $WORK_DIR/project"
```

### 自訂 tmux

編輯 `~/.tmux.conf.local`（不會被 env-setup 覆蓋）。

## 支援平台

| 平台 | 狀態 |
|------|------|
| macOS (Apple Silicon) | ✅ |
| macOS (Intel) | ✅ |
| Ubuntu 22.04 | ✅ |
| Ubuntu 24.04 | ✅ |
| WSL2 (Ubuntu) | ✅ |

## License

[MIT](LICENSE)
