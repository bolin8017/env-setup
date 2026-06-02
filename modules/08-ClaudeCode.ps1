#!/usr/bin/env pwsh
# 08-ClaudeCode.ps1 — install Claude Code (native) and sync personal config.
# Mirrors 08-claude-code.sh, but every JSON merge is PowerShell-native
# (ConvertFrom/To-Json via lib/ClaudeConfig.psm1) instead of jq. Reuses the same
# configs/claude/* sources as the Bash engine.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/../lib/Common.psm1"
Import-Module "$PSScriptRoot/../lib/Config.psm1"
Import-Module "$PSScriptRoot/../lib/DryRun.psm1" -DisableNameChecking  # WinPS 5.1: 'Deploy' is an unapproved verb
Import-Module "$PSScriptRoot/../lib/Backup.psm1"
Import-Module "$PSScriptRoot/../lib/ClaudeConfig.psm1"
Import-Module "$PSScriptRoot/../lib/Uninstall.psm1"

$script:ClaudeCfg = (Resolve-Path (Join-Path $PSScriptRoot '../configs/claude')).Path

function Install-ClaudeNative {
    if (Test-Command 'claude') { Write-Success 'Claude Code already installed'; return }
    if (Test-DryRun) { Write-Info '[DRY-RUN] Would run: irm https://claude.ai/install.ps1 | iex'; return }
    Write-Info 'Installing Claude Code (native installer)...'
    Invoke-RestMethod -Uri 'https://claude.ai/install.ps1' | Invoke-Expression
}

function Sync-ClaudeFile {
    param([Parameter(Mandatory)][string]$RelSource, [Parameter(Mandatory)][string]$RelDest)
    $src = Join-Path $script:ClaudeCfg $RelSource
    $dest = Join-Path $HOME ".claude/$RelDest"
    New-DirOrDryRun -Path (Split-Path $dest -Parent)
    Deploy-Config -Source $src -Destination $dest -Label $RelDest
}

function Sync-ClaudeDir {
    param([Parameter(Mandatory)][string]$SubDir)
    $srcDir = Join-Path $script:ClaudeCfg $SubDir
    if (-not (Test-Path $srcDir)) { Write-Info "$SubDir source missing — skipping"; return }
    $destDir = Join-Path $HOME ".claude/$SubDir"
    New-DirOrDryRun -Path $destDir
    Get-ChildItem $srcDir -Filter *.md -ErrorAction Ignore | ForEach-Object {
        Deploy-Config -Source $_.FullName -Destination (Join-Path $destDir $_.Name) -Label "$SubDir/$($_.Name)"
    }
}

function Sync-ClaudeSettings {
    $src = Join-Path $script:ClaudeCfg 'settings.json'
    $dest = Join-Path $HOME '.claude/settings.json'
    if (-not (Test-Path $src)) { return }
    # @() guard: Get-CfgList unrolls to a scalar for a single-key list, and
    # $scalar.Count then throws under StrictMode.
    $keys = @(Get-CfgList 'claude_code.settings_merge_keys')
    if (Test-DryRun) { Write-Info "[DRY-RUN] Would merge $($keys.Count) whitelisted key(s) into $dest"; return }
    if ((Test-KeepExisting) -and (Test-Path $dest)) { Write-Info '[SKIP] Keeping existing settings.json (KeepExisting)'; return }
    New-DirOrDryRun -Path (Split-Path $dest -Parent)
    if (-not (Test-Path $dest)) { Copy-Item -LiteralPath $src -Destination $dest; Write-Success "Created $dest from repo template"; return }
    $merged = Merge-ClaudeSettings -CurrentJson (Get-Content -Raw $dest) -SourceJson (Get-Content -Raw $src) -WhitelistKeys $keys
    $curNorm = (Get-Content -Raw $dest | ConvertFrom-Json | ConvertTo-Json -Depth 32 -Compress)
    $newNorm = ($merged | ConvertFrom-Json | ConvertTo-Json -Depth 32 -Compress)
    if ($curNorm -eq $newNorm) { Write-Info 'claude settings already in sync — skipping'; return }
    Backup-File -Path $dest -Stamp (Get-Date -Format 'yyyyMMdd_HHmmss') | Out-Null
    Set-Content -LiteralPath $dest -Value $merged -Encoding utf8
    Write-Success "Merged $($keys.Count) whitelisted key(s) into settings.json"
}

function Sync-ClaudeMcp {
    $src = Join-Path $script:ClaudeCfg 'mcp-servers.json'
    $dest = Join-Path $HOME '.claude.json'
    if (-not (Test-Path $src)) { return }
    $srcObj = Get-Content -Raw $src | ConvertFrom-Json
    $count = if ($srcObj.PSObject.Properties['mcpServers']) { @($srcObj.mcpServers.PSObject.Properties).Count } else { 0 }
    if ($count -eq 0) { Write-Info 'no MCP servers declared in repo — skipping'; return }
    if (Test-DryRun) { Write-Info "[DRY-RUN] Would merge $count MCP server(s) into $dest"; return }
    if ((Test-KeepExisting) -and (Test-Path $dest)) { Write-Info '[SKIP] Keeping existing MCP servers (KeepExisting)'; return }
    if (-not (Test-Path $dest)) { Write-Warn "$dest not found — run Claude Code once first; skipping MCP sync"; return }
    $merged = Merge-McpServers -CurrentJson (Get-Content -Raw $dest) -SourceJson (Get-Content -Raw $src)
    Backup-File -Path $dest -Stamp (Get-Date -Format 'yyyyMMdd_HHmmss') | Out-Null
    Set-Content -LiteralPath $dest -Value $merged -Encoding utf8
    Write-Success "Synced $count MCP server(s)"
}

function Register-ClaudeMarketplaces {
    if (-not (Test-CfgEnabled 'claude_code.register_marketplaces')) { return }
    if (-not (Test-Command 'claude')) { Write-Warn 'claude CLI not found — skipping marketplace registration'; return }
    foreach ($repo in (Get-CfgList 'claude_code.marketplaces')) {
        if (Test-DryRun) { Write-Info "[DRY-RUN] Would run: claude plugin marketplace add $repo"; continue }
        claude plugin marketplace add $repo *> $null
        if ($LASTEXITCODE -eq 0) { Write-Success "Registered marketplace: $repo" } else { Write-Warn "Failed to register marketplace: $repo" }
    }
}

function Install-ClaudePlugins {
    if (-not (Test-CfgEnabled 'claude_code.install_enabled_plugins')) { return }
    if (-not (Test-Command 'claude')) { Write-Warn 'claude CLI not found — skipping plugin install'; return }
    $src = Join-Path $script:ClaudeCfg 'settings.json'
    if (-not (Test-Path $src)) { return }
    $settings = Get-Content -Raw $src | ConvertFrom-Json
    if (-not $settings.PSObject.Properties['enabledPlugins']) { return }
    foreach ($p in $settings.enabledPlugins.PSObject.Properties) {
        if ($p.Value -ne $true) { continue }
        if (Test-DryRun) { Write-Info "[DRY-RUN] Would run: claude plugin install $($p.Name)"; continue }
        claude plugin install $p.Name *> $null
        if ($LASTEXITCODE -eq 0) { Write-Success "Installed plugin: $($p.Name)" } else { Write-Warn "Failed to install plugin: $($p.Name)" }
    }
}

function Install-Ccstatusline {
    if (-not (Test-CfgEnabled 'claude_code.ccstatusline.enabled')) { return }
    $src = (Resolve-Path (Join-Path $PSScriptRoot '../configs/ccstatusline/settings.json') -ErrorAction Ignore)
    if (-not $src) { Write-Info 'ccstatusline template missing — skipping'; return }
    $dest = Join-Path $HOME '.config/ccstatusline/settings.json'
    New-DirOrDryRun -Path (Split-Path $dest -Parent)
    Deploy-Config -Source $src.Path -Destination $dest -Label 'ccstatusline settings.json'
}

function Install-ClaudeCode {
    if (-not (Test-CfgEnabled 'claude_code.enabled')) { Write-Info 'Claude Code disabled — skipping'; return }
    Write-Header 'Claude Code'
    Install-ClaudeNative
    if (Test-CfgEnabled 'claude_code.sync_global_md') { Sync-ClaudeFile -RelSource 'CLAUDE.md' -RelDest 'CLAUDE.md' }
    if (Test-CfgEnabled 'claude_code.sync_rules')    { Sync-ClaudeDir -SubDir 'rules' }
    if (Test-CfgEnabled 'claude_code.sync_commands') { Sync-ClaudeDir -SubDir 'commands' }
    if (Test-CfgEnabled 'claude_code.sync_agents')   { Sync-ClaudeDir -SubDir 'agents' }
    Sync-ClaudeSettings
    if (Test-CfgEnabled 'claude_code.sync_mcp_servers') { Sync-ClaudeMcp }
    Register-ClaudeMarketplaces
    Install-ClaudePlugins
    Install-Ccstatusline
}

function Get-NewestBakPath {
    param([Parameter(Mandatory)][string]$Path)
    $dir  = Split-Path $Path -Parent
    $leaf = Split-Path $Path -Leaf
    if (-not (Test-Path -LiteralPath $dir)) { return $null }
    $b = Get-ChildItem -LiteralPath $dir -Filter "$leaf.bak.*" -ErrorAction Ignore |
         Sort-Object LastWriteTime | Select-Object -Last 1
    if ($b) { return $b.FullName } else { return $null }
}

function Uninstall-ClaudeSettings {
    $dest = Join-Path $HOME '.claude/settings.json'
    $src  = Join-Path $script:ClaudeCfg 'settings.json'
    if (-not (Test-Path $dest)) { Write-Info '[SKIP] settings.json not present'; return }

    $bak = Get-NewestBakPath $dest
    if ($bak -and -not (Test-NoRestore)) {
        if (Test-DryRun) { Write-Info "[DRY-RUN] Would restore settings.json from $bak"; return }
        Copy-Item -LiteralPath $bak -Destination $dest -Force
        Write-Success "Restored settings.json from $(Split-Path $bak -Leaf)"; return
    }
    if (-not (Test-Path $src)) { return }
    $keys = @(Get-CfgList 'claude_code.settings_merge_keys')
    if (Test-DryRun) { Write-Info "[DRY-RUN] Would strip $($keys.Count) env-setup key(s) from settings.json"; return }
    $stripped = Remove-ManagedSettingsKeys -CurrentJson (Get-Content -Raw $dest) -SourceJson (Get-Content -Raw $src) -WhitelistKeys $keys
    Set-Content -LiteralPath $dest -Value $stripped -Encoding utf8
    Write-Success 'Stripped env-setup keys from settings.json'
}

function Uninstall-ClaudeMcp {
    $dest = Join-Path $HOME '.claude.json'
    if (-not (Test-Path $dest)) { return }
    $bak = Get-NewestBakPath $dest
    if ($bak -and -not (Test-NoRestore)) {
        if (Test-DryRun) { Write-Info "[DRY-RUN] Would restore ~/.claude.json from $bak"; return }
        Copy-Item -LiteralPath $bak -Destination $dest -Force
        Write-Success 'Restored ~/.claude.json from backup'; return
    }
    Write-Info 'No ~/.claude.json backup — leaving MCP servers intact'
}

function Uninstall-ClaudeCode {
    Write-Header 'Uninstall: Claude Code'

    # C — managed config files (user-edited copies preserved by Remove-ManagedFile)
    Remove-ManagedFile -Dest (Join-Path $HOME '.claude/CLAUDE.md') `
        -RepoSrc (Join-Path $script:ClaudeCfg 'CLAUDE.md') -Label 'global CLAUDE.md'
    foreach ($sub in @('rules', 'commands', 'agents')) {
        $srcDir = Join-Path $script:ClaudeCfg $sub
        if (-not (Test-Path $srcDir)) { continue }
        Get-ChildItem $srcDir -Filter *.md -ErrorAction Ignore | ForEach-Object {
            Remove-ManagedFile -Dest (Join-Path $HOME ".claude/$sub/$($_.Name)") -RepoSrc $_.FullName -Label "$sub/$($_.Name)"
        }
    }

    Uninstall-ClaudeSettings
    Uninstall-ClaudeMcp

    $cc = (Resolve-Path (Join-Path $PSScriptRoot '../configs/ccstatusline/settings.json') -ErrorAction Ignore)
    if ($cc) {
        Remove-ManagedFile -Dest (Join-Path $HOME '.config/ccstatusline/settings.json') -RepoSrc $cc.Path -Label 'ccstatusline settings.json'
    }

    # T — plugins/marketplaces + CLI binary
    if (-not (Test-KeepTools)) {
        if (Test-Command 'claude') {
            $s = Join-Path $script:ClaudeCfg 'settings.json'
            if (Test-Path $s) {
                $settings = Get-Content -Raw $s | ConvertFrom-Json
                if ($settings.PSObject.Properties['enabledPlugins']) {
                    foreach ($p in $settings.enabledPlugins.PSObject.Properties) {
                        if ($p.Value -ne $true) { continue }
                        if (Test-DryRun) { Write-Info "[DRY-RUN] Would run: claude plugin uninstall $($p.Name)" }
                        else { claude plugin uninstall $p.Name *> $null }
                    }
                }
            }
            foreach ($repo in (Get-CfgList 'claude_code.marketplaces')) {
                if (Test-DryRun) { Write-Info "[DRY-RUN] Would run: claude plugin marketplace remove $repo" }
                else { claude plugin marketplace remove $repo *> $null }
            }
        }
        $launcher = Join-Path $HOME '.local/bin/claude.exe'
        if (Test-Path -LiteralPath $launcher) { Remove-OrDryRun -Path $launcher }
        Write-Info 'Claude CLI removed where found; ~/.claude data (auth/history) preserved.'
    }
}
