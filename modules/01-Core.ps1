#!/usr/bin/env pwsh
# 01-Core.ps1 - scoop buckets + core apps (git, gh) + the two git defaults.
# Mirrors 01-core.sh: installs git/gh/build-tools and sets a managed global
# ignore block plus rerere (it configures no git identity, so neither do we).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/../lib/Common.psm1"
Import-Module "$PSScriptRoot/../lib/Config.psm1"
Import-Module "$PSScriptRoot/../lib/Package.psm1"
Import-Module "$PSScriptRoot/../lib/DryRun.psm1" -DisableNameChecking
Import-Module "$PSScriptRoot/../lib/Uninstall.psm1"

$script:GitIgnoreBegin = '# >>> env-setup managed >>>'
$script:GitIgnoreEnd   = '# <<< env-setup managed <<<'
$script:GitIgnoreEntry = '**/.claude/settings.local.json'

function Get-GitGlobalIgnorePath {
    # The file git consults for global excludes, in git's own lookup order
    # (gitignore(5)): core.excludesFile when set, else $XDG_CONFIG_HOME/git/ignore,
    # else ~/.config/git/ignore.
    $configured = ''
    if (Test-Command 'git') {
        $configured = (Invoke-Native git config --global --get core.excludesFile | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) { $configured = '' }
    }
    if ($configured) {
        if ($configured -like '~/*') { return (Join-Path $HOME $configured.Substring(2)) }
        return $configured
    }
    $xdg = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $HOME '.config' }
    return (Join-Path $xdg 'git/ignore')
}

function Get-GitRerereMarkerPath { return (Join-Path $HOME '.env-setup/.git-rerere-set') }

function Set-GitDefaults {
    # Exactly two global settings, both reverted by Remove-GitDefaults:
    #   1. a managed block in the global ignore file listing Claude Code's
    #      per-machine settings.local.json (otherwise untracked noise everywhere)
    #   2. rerere.enabled=true, only when the user has not set it either way
    if (-not (Test-Command 'git')) {
        Write-Info 'git not on PATH yet - skipping git defaults (re-run setup from a new terminal)'
        return
    }

    $ignoreFile = Get-GitGlobalIgnorePath
    $hasBlock = (Test-Path -LiteralPath $ignoreFile) -and
        ((Get-Content -Raw -LiteralPath $ignoreFile) -like "*$script:GitIgnoreBegin*")
    if ($hasBlock) { Write-Info 'git global ignore already carries the env-setup block' }
    elseif (Test-DryRun) { Write-Info "[DRY-RUN] Would append the env-setup block to $ignoreFile" }
    else {
        New-Item -ItemType Directory -Path (Split-Path $ignoreFile -Parent) -Force | Out-Null
        $existing = if (Test-Path -LiteralPath $ignoreFile) { Get-Content -Raw -LiteralPath $ignoreFile } else { '' }
        if ($existing -and -not $existing.EndsWith("`n")) { $existing += "`n" }
        $block = "$script:GitIgnoreBegin`n$script:GitIgnoreEntry`n$script:GitIgnoreEnd`n"
        Write-Utf8NoBom -Path $ignoreFile -Content ($existing + $block)
        Write-Success "Added $script:GitIgnoreEntry to the git global ignore ($ignoreFile)"
    }

    $marker = Get-GitRerereMarkerPath
    Invoke-Native git config --global --get rerere.enabled | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Info 'rerere.enabled already set - leaving it'; return }
    if (Test-DryRun) { Write-Info '[DRY-RUN] Would run: git config --global rerere.enabled true'; return }
    Invoke-Native git config --global rerere.enabled true | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Warn 'git config --global rerere.enabled true failed - leaving it'; return }
    New-Item -ItemType Directory -Path (Split-Path $marker -Parent) -Force | Out-Null
    Write-Utf8NoBom -Path $marker -Content 'set by env-setup 01-Core'
    Write-Success "Enabled git rerere (recorded in $marker for uninstall)"
}

function Remove-GitDefaults {
    # Reverse Set-GitDefaults: strip the managed block; unset rerere only when
    # the marker proves env-setup set it.
    Remove-ManagedBlock -Path (Get-GitGlobalIgnorePath) -Begin $script:GitIgnoreBegin -End $script:GitIgnoreEnd -Label 'git global ignore'
    $marker = Get-GitRerereMarkerPath
    if (-not (Test-Path -LiteralPath $marker)) { Write-Info 'rerere.enabled was not set by env-setup - leaving it'; return }
    if (Test-DryRun) { Write-Info '[DRY-RUN] Would run: git config --global --unset rerere.enabled'; return }
    if (Test-Command 'git') { Invoke-Native git config --global --unset rerere.enabled | Out-Null }
    Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
    Write-Success 'Disabled git rerere (env-setup had enabled it)'
}

function Add-ScoopBucket {
    param([Parameter(Mandatory)][string]$Name)
    if (Test-DryRun) { Write-Info "[DRY-RUN] Would add scoop bucket: $Name"; return }
    if (-not (Test-ScoopAvailable)) { return }
    $have = (scoop bucket list 6>$null | Out-String)
    if ($have -notmatch ('(?m)^\s*' + [regex]::Escape($Name) + '\b')) { scoop bucket add $Name }
}

function Install-Core {
    Write-Header 'Core'
    if (-not (Test-DryRun) -and -not (Test-ScoopAvailable)) {
        throw 'scoop not found - run bootstrap.ps1 first'
    }
    Add-ScoopBucket -Name 'extras'   # some CLI tools (e.g. bottom) live here
    if (Test-CfgEnabled 'core.git')        { Install-App -Id 'Git.Git'; Set-GitDefaults }
    if (Test-CfgEnabled 'core.github_cli') { Install-App -Id 'GitHub.cli' }
    if (Test-CfgEnabled 'core.build_tools') {
        # The Bash engine installs build-essential; on Windows uv ships
        # prebuilt CPython, so heavy VS Build Tools are not installed by default.
        Write-Info 'build_tools: skipped on Windows (uv uses prebuilt CPython).'
    }
}

function Uninstall-Core {
    Write-Header 'Uninstall: Core'
    Remove-GitDefaults
    if (Test-Purge) {
        Write-Warn 'git and gh are widely depended on - removing them per -Purge'
        Remove-App -Id 'GitHub.cli'
        Remove-App -Id 'Git.Git'
    } else {
        Write-Info 'git/gh are system tools - use -Purge to remove them'
    }
}
