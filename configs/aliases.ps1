# env-setup aliases - functions (PowerShell aliases can't take arguments).

if (Get-Command eza -ErrorAction SilentlyContinue) {
    function ls { eza --icons @args }
    function ll { eza -lah --git --icons @args }
    function la { eza -a --icons @args }
    function lt { eza --tree --level=2 --icons @args }
}

if (Get-Command bat -ErrorAction SilentlyContinue) {
    function cat { bat @args }
}

function .. { Set-Location .. }
function ... { Set-Location ../.. }
function g { git @args }

# Claude Code account profiles: run claude under an alternate account, with
# config/credentials/history isolated in ~/.claude-<name> per the official
# CLAUDE_CONFIG_DIR contract. First use of a profile: `claude-as <name>` then
# /login. ($ProfileName, not $Profile: $PROFILE is a PowerShell automatic
# variable and must not be shadowed.)
function claude-as {
    param(
        [Parameter(Mandatory, Position = 0)][string]$ProfileName,
        [Parameter(ValueFromRemainingArguments)][string[]]$ClaudeArgs
    )
    $prev = $env:CLAUDE_CONFIG_DIR
    $env:CLAUDE_CONFIG_DIR = Join-Path $HOME ".claude-$ProfileName"
    try { & claude @ClaudeArgs }
    finally { $env:CLAUDE_CONFIG_DIR = $prev }
}

# env-setup self-update: pull latest and re-apply. Works on any machine
# regardless of update.enabled. Resolves the repo from the state file written at
# install time ($Env:ENVSETUP_REPO_DIR), falling back to the bootstrap default.
function Update-EnvSetup {
    $repo = $Env:ENVSETUP_REPO_DIR
    if (-not $repo) { $repo = Join-Path $HOME '.local/share/env-setup' }
    if (-not (Test-Path -LiteralPath (Join-Path $repo '.git'))) {
        Write-Error "env-update: env-setup repo not found at $repo"; return
    }
    git -C "$repo" pull --ff-only
    if ($LASTEXITCODE -ne 0) { return }
    & (Join-Path $repo 'setup.ps1') @args
}
Set-Alias env-update Update-EnvSetup
