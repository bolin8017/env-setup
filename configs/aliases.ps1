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
# /login. Deliberately a simple $args function with no param() block: the
# parameter binder would otherwise intercept claude's own single-dash flags
# (`claude-as work -p "..."` must reach claude, not bind to -ProfileName).
function claude-as {
    if (-not $args -or -not $args[0]) {
        Write-Error 'usage: claude-as <profile> [claude args...]'
        return
    }
    # Refuse while this profile's credential is checked out into ~/.claude
    # (claude-swap): running both copies would rotate the same refresh-token
    # family from two files and can invalidate the account everywhere.
    $marker = Join-Path $HOME '.claude/.credential-owner'
    if ((Test-Path -LiteralPath $marker) -and ((Get-Content -LiteralPath $marker -Raw).Trim() -eq "$($args[0])")) {
        Write-Error "claude-as: '$($args[0])' credential is checked out into ~/.claude (claude-swap). Run 'claude' directly, or swap it home first: claude-swap default"
        return
    }
    $prev = $env:CLAUDE_CONFIG_DIR
    $env:CLAUDE_CONFIG_DIR = Join-Path $HOME ".claude-$($args[0])"
    $rest = @($args | Select-Object -Skip 1)
    try { & claude @rest }
    finally { $env:CLAUDE_CONFIG_DIR = $prev }
}

# Check a different account's credential into ~/.claude (move semantics; see
# scripts/claude-swap.sh). The logic lives in that bash script — Git Bash
# ships with git on Windows, so shell out to it.
function claude-swap {
    $script = Join-Path $HOME '.local/bin/claude-swap'
    if (-not (Test-Path -LiteralPath $script)) {
        Write-Error 'claude-swap: helper not deployed - run setup module 08-ClaudeCode first'
        return
    }
    # Git Bash eats backslashes in Windows paths (C:\Users\... arrives as
    # C:Users...); it accepts forward slashes for the same path.
    & bash ($script -replace '\\', '/') @args
}

# Log out one config root: remove the stored OAuth credential and scrub the
# account identity (oauthAccount/userID) from the state json. History,
# settings, and plugins are untouched. Returns $true if a credential was removed.
# Writes BOM-less UTF-8 (Set-Content under Windows PowerShell 5.1 would add a
# BOM, which breaks Claude Code's JSON parsing).
function Remove-ClaudeCredential {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$StateJson
    )
    $removed = $false
    $cred = Join-Path $Root '.credentials.json'
    if (Test-Path -LiteralPath $cred) {
        Remove-Item -LiteralPath $cred -Force
        $removed = $true
    }
    if (Test-Path -LiteralPath $StateJson) {
        try {
            $state = Get-Content -Raw -LiteralPath $StateJson | ConvertFrom-Json
            $changed = $false
            foreach ($k in @('oauthAccount', 'userID')) {
                if ($state.PSObject.Properties[$k]) { $state.PSObject.Properties.Remove($k); $changed = $true }
            }
            if ($changed) {
                $json = $state | ConvertTo-Json -Depth 64
                [System.IO.File]::WriteAllText((Resolve-Path -LiteralPath $StateJson).Path, $json)
            }
        } catch { Write-Warning "claude-logout: could not scrub $StateJson : $_" }
    }
    return $removed
}

# Clean logout without uninstalling anything — for handing the machine over.
# usage: claude-logout            log out the default account (~/.claude)
#        claude-logout <profile>  log out one profile (~/.claude-<profile>)
#        claude-logout --all      default + every ~/.claude-<name> profile
# Run it with no claude session open.
function claude-logout {
    $first = if ($args.Count -gt 0) { "$($args[0])" } else { '' }
    $marker = Join-Path $HOME '.claude/.credential-owner'
    $owner = ''
    if (Test-Path -LiteralPath $marker) { $owner = (Get-Content -LiteralPath $marker -Raw).Trim() }

    $targets = @()
    switch ($first) {
        { $_ -in '-h', '--help' } { Write-Host 'usage: claude-logout [<profile>|--all]'; return }
        '--all' {
            $targets += , @((Join-Path $HOME '.claude'), (Join-Path $HOME '.claude.json'))
            foreach ($d in @(Get-ChildItem -Path $HOME -Directory -Filter '.claude-*' -Force -ErrorAction Ignore)) {
                # Only real Claude Code config dirs (they always carry
                # .claude.json) — never touch third-party ~/.claude-* dirs.
                $state = Join-Path $d.FullName '.claude.json'
                if (Test-Path -LiteralPath $state) { $targets += , @($d.FullName, $state) }
            }
        }
        '' {
            # A checked-out profile credential lives in ~/.claude right now;
            # deleting it here would destroy that profile's freshest copy.
            if ($owner -and $owner -ne 'default') {
                Write-Error "claude-logout: '$owner' credential is checked out into ~/.claude (claude-swap). Swap it home first (claude-swap default) or use --all."
                return
            }
            $targets += , @((Join-Path $HOME '.claude'), (Join-Path $HOME '.claude.json'))
        }
        default {
            if ($owner -eq $first) {
                Write-Error "claude-logout: '$first' credential is checked out into ~/.claude (claude-swap). Swap it home first (claude-swap default) or use --all."
                return
            }
            $root = Join-Path $HOME ".claude-$first"
            $targets += , @($root, (Join-Path $root '.claude.json'))
        }
    }
    foreach ($t in $targets) {
        if (Remove-ClaudeCredential -Root $t[0] -StateJson $t[1]) { Write-Host "logged out: $($t[0])" }
        else { Write-Host "no stored credential: $($t[0])" }
    }
    if ($first -eq '--all') {
        # The swap stash holds parked credentials — a logout that leaves them
        # behind is not a logout.
        Remove-Item -Recurse -Force (Join-Path $HOME '.claude/.credential-stash') -ErrorAction Ignore
        Remove-Item -Force $marker -ErrorAction Ignore
    }
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
