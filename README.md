# env-setup

一鍵設定完整開發環境的自動化工具，支援 **macOS**、**Ubuntu**（含 WSL）與**原生 Windows**（PowerShell）。

透過一份 `config.yaml` 設定清單驅動，修改設定後執行一個指令即可完成所有安裝。macOS／Linux／WSL 走 Bash 引擎（`setup.sh`），原生 Windows 走獨立的 PowerShell 引擎（`setup.ps1`），兩者共用同一份設定。

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

### 原生 Windows（PowerShell）

原生 Windows 走獨立的 PowerShell 引擎（`setup.ps1` / `bootstrap.ps1`），與 WSL2 完全脫鉤，並與 macOS/Linux 共用同一份 `config.yaml`。涵蓋：核心引擎、套件安裝（scoop/winget、git/gh、現代 CLI 工具）、語言（nvm-windows、pyenv-win、uv/poetry/jupyter）、shell 體驗（PowerShell 7、Oh My Posh prompt、PSReadLine 預測、模組、zellij 多工器、Windows Terminal 字型）、Claude Code（原生安裝 + 設定同步）、個人目錄與安裝後驗證。

全新系統（一行安裝，在 PowerShell 7 執行）：

```powershell
irm https://raw.githubusercontent.com/bolin8017/env-setup/main/bootstrap.ps1 | iex
```

手動安裝與常用指令：

```powershell
git clone https://github.com/bolin8017/env-setup.git
cd env-setup

./setup.ps1                          # 完整安裝
./setup.ps1 -DryRun -AutoYes         # 預覽安裝內容，不實際執行
./setup.ps1 -Modules 06-Shell        # 只執行指定模組
./scripts/verify.ps1                 # 安裝驗證
```

非系統管理員也能執行：scoop 與多數 winget 套件以使用者身分安裝，需要提權的 winget 套件會被延後，並在結束時印出一段管理員指令清單（對應 Unix 的無 sudo 流程）。

重度 Linux 開發仍建議留在 WSL2（在 WSL2 裡用上面的 `bootstrap.sh`）。

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

**原生 Windows** 安裝對應的同類工具：套件來源用 scoop／winget，prompt 用 Oh My Posh（取代 Powerlevel10k），多工器用 zellij（取代 tmux），Node／Python 用 nvm-windows／pyenv-win，並設定 PSReadLine 預測與 Windows Terminal 字型。詳見上方 [原生 Windows（PowerShell）](#原生-windowspowershell)。

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

本專案是兩個平行引擎：macOS／Linux／WSL 用 Bash 引擎，原生 Windows 用 PowerShell 引擎。兩者互不呼叫，共用同一份 `config.yaml` 與 `configs/` 資產。

**Bash 引擎（macOS／Linux／WSL）**

```
setup.sh 讀取 config.yaml → 依序執行模組
 │
 ├─ 01-core         Homebrew → Git → gh → build tools
 ├─ 02-languages    nvm/Node.js → pyenv/Python → Conda
 ├─ 03-python-tools Jupyter → Poetry → uv
 ├─ 04-docker       Docker
 ├─ 05-cli-tools    11 個 CLI 工具
 ├─ 06-shell        Zsh → Oh My Zsh → P10k → plugins → .zshrc 組裝
 ├─ 07-tmux         tmux → TPM → config → plugins
 ├─ 08-claude-code  Claude Code CLI（原生安裝 + 設定同步）
 └─ 09-user-dirs    在 $HOME 下建立個人目錄
```

**PowerShell 引擎（原生 Windows）**

```
setup.ps1 讀取 config.yaml → 依序執行模組
 │
 ├─ 01-Core         scoop/winget → Git → gh
 ├─ 02-Languages    nvm-windows/Node.js → pyenv-win/Python
 ├─ 03-PythonTools  Jupyter → Poetry → uv
 ├─ 05-CliTools     現代 CLI 工具
 ├─ 06-Shell        PowerShell 7 → Oh My Posh → PSReadLine → 模組 → $PROFILE 組裝 → WT 字型
 ├─ 07-Multiplexer  zellij + dev layout
 ├─ 08-ClaudeCode   Claude Code CLI（原生安裝 + 設定同步）
 └─ 09-UserDirs     在 $HOME 下建立個人目錄
```

PowerShell 沒有 Bash/awk YAML 解析器，因此 `lib/Config.psm1` 提供同一份設定子集的純 PowerShell 讀取器。跨模組旗標透過 `ENVSETUP_*` 環境變數傳遞（對應 Bash 引擎匯出的 `DRY_RUN`／`AUTO_YES`／`KEEP_EXISTING`）。原生 Windows 沒有 Docker 模組。

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

### 無 sudo 環境（Ubuntu / WSL）

在共用伺服器或受管理的工作機等沒有 sudo 權限的環境下：

- 首次需要 sudo 時會跳一次 `sudo -v` 密碼提示；密碼由 sudo 直接從 TTY 讀取，env-setup 不會看到、紀錄或傳遞它
- 通過後背景會定期刷新 sudo timestamp，後續安裝不會再被問
- 若驗證失敗（不在 sudoers、密碼錯誤、Ctrl+C、`--auto-yes` / 無 TTY）會自動轉成「跳過 apt」模式，繼續完成所有 user-space 工具（nvm、pyenv、Oh My Zsh、Claude Code…）的安裝
- 安裝結束時印出一段 admin 指令清單，可以拿給系統管理員裝缺漏的 apt 套件，再重跑 `./setup.sh` 即可繼續

macOS 不會走這條路徑：brew 安裝以使用者身份執行，初次安裝 Homebrew 時由官方 installer 自行處理授權。

## 目錄結構

`*.sh` / `*.psm1` 為兩個引擎的同名手足，`setup.sh` 與 `setup.ps1` 為各自入口。

```
env-setup/
├── setup.sh                  # 主入口（Unix）
├── setup.ps1                 # 主入口（Windows）
├── bootstrap.sh              # 全新系統一行安裝（Unix）
├── bootstrap.ps1             # 全新系統一行安裝（Windows）
├── config.yaml               # 設定檔（兩平台共用）
├── lib/                      # Bash 引擎（*.sh）+ Windows 引擎（*.psm1）
│   ├── common.sh / Common.psm1     #   平台偵測、logging
│   ├── yaml.sh                      #   YAML 解析器（Bash）
│   ├── config.sh / Config.psm1      #   設定載入／純 PowerShell 讀取器
│   ├── package.sh / Package.psm1    #   套件管理（brew/apt｜scoop/winget）
│   ├── dryrun.sh / DryRun.psm1      #   dry-run + deploy
│   ├── backup.sh / Backup.psm1      #   備份/還原
│   ├── WindowsTerminal.psm1         #   Windows Terminal 設定合併
│   └── ClaudeConfig.psm1            #   Claude Code 設定 JSON 合併
├── modules/                  # 安裝模組（按依賴順序編號）
│   ├── 01-core.sh  …  09-user-dirs.sh        # Unix（含 04-docker）
│   └── 01-Core.ps1 …  09-UserDirs.ps1        # Windows（無 docker）
├── configs/                  # 設定檔模板
│   ├── zshrc/ , tmux/ , p10k/ , aliases.zsh  #   Unix
│   └── pwsh/ , omp/ , zellij/ , aliases.ps1  #   Windows
├── scripts/
│   ├── verify.sh             # 安裝驗證（Unix）
│   └── verify.ps1            # 安裝驗證（Windows）
├── PSScriptAnalyzerSettings.psd1   # Windows 引擎 lint 設定
└── .github/workflows/        # CI（Unix：ShellCheck + dry-run｜Windows：PSScriptAnalyzer + Pester + dry-run）
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
| Windows 11（原生 PowerShell） | ✅ |

## License

[MIT](LICENSE)
