#!/usr/bin/env pwsh
# 08-ClaudeCode.ps1 - install Claude Code (native) and sync personal config.
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
    $installer = Invoke-WithRetry -What 'Claude Code download' -Action { Invoke-RestMethod -Uri 'https://claude.ai/install.ps1' }
    Invoke-Expression $installer
}

function Add-ClaudeBinToPath {
    # The native installer drops claude.exe in ~/.local/bin but does NOT put it on
    # PATH (it only prints a manual instruction). Two consequences we fix here:
    #   1. `claude` is unusable in new shells until the user edits PATH by hand.
    #   2. Register-ClaudeMarketplaces / Install-ClaudePlugins below gate on
    #      Test-Command 'claude' and therefore silently skip in this same run.
    # Prepend it to the *session* PATH (so the steps that follow find claude) and
    # persist it to the *user* PATH (no admin) for future shells. Idempotent.
    $bin = Join-Path $HOME '.local/bin'
    if (Test-DryRun) { Write-Info "[DRY-RUN] Would add $bin to the user PATH"; return }
    if (-not (Test-Path -LiteralPath $bin)) { return }

    if (($env:Path -split ';') -notcontains $bin) { $env:Path = "$bin;$env:Path" }
    $marker = Join-Path $HOME '.env-setup/.claude-bin-path-added'

    # Read/write the RAW user PATH (DoNotExpandEnvironmentNames) and preserve the
    # value kind, so we never freeze a %VAR% in another entry into a literal.
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    try {
        $raw  = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $kind = if ($null -ne $key.GetValue('Path')) { $key.GetValueKind('Path') } else { [Microsoft.Win32.RegistryValueKind]::ExpandString }
        $entries = $raw -split ';' | Where-Object { $_ -ne '' }
        if ($entries | Where-Object { $_.TrimEnd('\') -ieq $bin.TrimEnd('\') }) { return }
        $newRaw = if ([string]::IsNullOrEmpty($raw)) { $bin } else { $raw.TrimEnd(';') + ';' + $bin }
        $key.SetValue('Path', $newRaw, $kind)
        Send-EnvironmentChanged
        # Marker: uninstall must only remove the entry WE added - ~/.local/bin
        # is a shared convention dir (pipx uses it too).
        New-Item -ItemType Directory -Path (Split-Path $marker -Parent) -Force | Out-Null
        Set-Content -LiteralPath $marker -Value 'added by env-setup 08-ClaudeCode'
        Write-Success "Added $bin to the user PATH (open a new terminal to pick it up)"
    } finally { $key.Close() }
}

function Remove-ClaudeBinFromPath {
    # Reverse Add-ClaudeBinToPath: drop ~/.local/bin from the user PATH on
    # uninstall - but only when the install marker says WE added it. The dir
    # is a shared convention (pipx et al.); pre-existing entries stay.
    $bin = Join-Path $HOME '.local/bin'
    $marker = Join-Path $HOME '.env-setup/.claude-bin-path-added'
    if (-not (Test-Path -LiteralPath $marker)) {
        Write-Info "$bin was on the user PATH before env-setup - leaving it"
        return
    }
    if (Test-DryRun) { Write-Info "[DRY-RUN] Would remove $bin from the user PATH"; return }
    Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    try {
        if ($null -eq $key.GetValue('Path')) { return }
        $raw  = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $kind = $key.GetValueKind('Path')
        $kept = $raw -split ';' | Where-Object { $_ -ne '' -and $_.TrimEnd('\') -ine $bin.TrimEnd('\') }
        if (($raw -split ';' | Where-Object { $_ -ne '' }).Count -eq $kept.Count) { return }
        $key.SetValue('Path', ($kept -join ';'), $kind)
        Send-EnvironmentChanged
        Write-Success "Removed $bin from the user PATH"
    } finally { $key.Close() }
}

# All Sync-Claude* helpers take an optional -Root (default ~/.claude) so
# Sync-ClaudeProfiles can mirror the same assets into per-account
# ~/.claude-<profile> dirs.
function Sync-ClaudeFile {
    param(
        [Parameter(Mandatory)][string]$RelSource,
        [Parameter(Mandatory)][string]$RelDest,
        [string]$Root = (Join-Path $HOME '.claude')
    )
    $src = Join-Path $script:ClaudeCfg $RelSource
    $dest = Join-Path $Root $RelDest
    New-DirOrDryRun -Path (Split-Path $dest -Parent)
    Deploy-Config -Source $src -Destination $dest -Label $RelDest
}

function Sync-ClaudeDir {
    param(
        [Parameter(Mandatory)][string]$SubDir,
        [string]$Root = (Join-Path $HOME '.claude')
    )
    $srcDir = Join-Path $script:ClaudeCfg $SubDir
    if (-not (Test-Path $srcDir)) { Write-Info "$SubDir source missing - skipping"; return }
    $destDir = Join-Path $Root $SubDir
    New-DirOrDryRun -Path $destDir
    Get-ChildItem $srcDir -Filter *.md -ErrorAction Ignore | ForEach-Object {
        Deploy-Config -Source $_.FullName -Destination (Join-Path $destDir $_.Name) -Label "$SubDir/$($_.Name)"
    }
}

function Sync-ClaudeSkills {
    # Skills are directories (SKILL.md + optional support files); each file is
    # deployed individually so user modifications keep overwrite protection.
    # Additive: machine-only skills are preserved.
    param([string]$Root = (Join-Path $HOME '.claude'))
    $srcRoot = Join-Path $script:ClaudeCfg 'skills'
    if (-not (Test-Path $srcRoot)) { Write-Info 'skills source missing - skipping'; return }
    foreach ($skill in @(Get-ChildItem $srcRoot -Directory -ErrorAction Ignore)) {
        $destDir = Join-Path $Root "skills/$($skill.Name)"
        New-DirOrDryRun -Path $destDir
        foreach ($f in @(Get-ChildItem $skill.FullName -File)) {
            Deploy-Config -Source $f.FullName -Destination (Join-Path $destDir $f.Name) -Label "skills/$($skill.Name)/$($f.Name)"
        }
    }
}

function Test-ClaudeProfileName {
    # Profile names become path components (~/.claude-<name> on install,
    # uninstall, and the claude-as alias), so anything path-like would
    # desynchronize those three consumers. Restrict to a safe charset.
    param([string]$Name)
    return $Name -match '^[A-Za-z0-9_-]+$'
}

function Sync-ClaudeAssets {
    # Deploy the file-based harness (CLAUDE.md, rules, commands, agents,
    # skills) into one config root. The single authoritative asset list: both
    # the default ~/.claude sync and every profile sync go through here, so a
    # new asset type cannot reach one and miss the other.
    param([Parameter(Mandatory)][string]$Root)
    if (Test-CfgEnabled 'claude_code.sync_global_md') { Sync-ClaudeFile -RelSource 'CLAUDE.md' -RelDest 'CLAUDE.md' -Root $Root }
    if (Test-CfgEnabled 'claude_code.sync_rules')    { Sync-ClaudeDir -SubDir 'rules' -Root $Root }
    if (Test-CfgEnabled 'claude_code.sync_commands') { Sync-ClaudeDir -SubDir 'commands' -Root $Root }
    if (Test-CfgEnabled 'claude_code.sync_agents')   { Sync-ClaudeDir -SubDir 'agents' -Root $Root }
    if (Test-CfgEnabled 'claude_code.sync_skills')   { Sync-ClaudeSkills -Root $Root }
}

function Sync-ClaudeProfiles {
    # Mirror the harness into each ~/.claude-<name> declared in
    # claude_code.profiles. Profiles are alternate Claude Code accounts
    # selected via CLAUDE_CONFIG_DIR (`claude-as <name>` in
    # configs/aliases.ps1); each keeps its own credentials/settings/plugins,
    # so only static assets are synced - settings.json merge and plugin
    # installs stay per-profile manual.
    $profiles = @(Get-CfgList 'claude_code.profiles')
    if ($profiles.Count -eq 0) { Write-Info 'no claude profiles declared - skipping'; return }
    foreach ($p in $profiles) {
        if (-not (Test-ClaudeProfileName $p)) {
            Write-Warn "invalid profile name '$p' (use letters/digits/-/_) - skipping"
            continue
        }
        Write-Info "Syncing claude account profile: $p"
        Sync-ClaudeAssets -Root (Join-Path $HOME ".claude-$p")
    }
}

function Install-ClaudeSwap {
    # Put the credential check-out helper on PATH. It is a bash script (runs
    # under Git Bash on Windows; claude sessions call it via their Bash tool).
    # claude-swap.ps1 is its PowerShell entry: it locates Git Bash explicitly,
    # because a bare `bash` resolves to the WSL launcher when WSL is
    # installed. The claude-swap function in aliases.ps1 delegates to it.
    $src = Resolve-Path (Join-Path $PSScriptRoot '../scripts/claude-swap.sh') -ErrorAction Ignore
    if (-not $src) { Write-Warn 'claude-swap source not found - skipping'; return }
    $bin = Join-Path $HOME '.local/bin'
    New-DirOrDryRun -Path $bin
    Deploy-Config -Source $src.Path -Destination (Join-Path $bin 'claude-swap') -Label 'claude-swap'
    $shim = Resolve-Path (Join-Path $PSScriptRoot '../scripts/claude-swap.ps1') -ErrorAction Ignore
    if (-not $shim) { Write-Warn 'claude-swap.ps1 source not found - skipping'; return }
    Deploy-Config -Source $shim.Path -Destination (Join-Path $bin 'claude-swap.ps1') -Label 'claude-swap.ps1'
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
    if (-not (Test-Path $dest)) {
        # Seed the template but pin teammateMode to in-process: native Windows
        # can't run the shared repo value "tmux" (no tmux/iTerm2), so a verbatim
        # copy would seed an unusable config that Claude Code flags.
        Write-Utf8NoBom -Path $dest -Content (Set-ClaudeTeammateMode -CurrentJson (Get-Content -Raw $src))
        Write-Success "Created $dest from repo template"; return
    }
    # A corrupted user file must degrade to a warning (the Bash twin jq-empty
    # checks first) - under EAP=Stop a parse throw would abort the module and
    # skip every later step (marketplaces, plugins, ccstatusline).
    try { $null = Get-Content -Raw $dest | ConvertFrom-Json }
    catch { Write-Warn "$dest is not valid JSON - skipping merge. Fix manually."; return }
    $merged = Merge-ClaudeSettings -CurrentJson (Get-Content -Raw $dest) -SourceJson (Get-Content -Raw $src) -WhitelistKeys $keys
    # Native Windows can't use the shared "tmux" teammateMode (no tmux/iTerm2);
    # pin it to in-process before the idempotency compare. Also heals files
    # merged with "tmux" before this fix.
    $merged = Set-ClaudeTeammateMode -CurrentJson $merged
    $curNorm = (Get-Content -Raw $dest | ConvertFrom-Json | ConvertTo-Json -Depth 32 -Compress)
    $newNorm = ($merged | ConvertFrom-Json | ConvertTo-Json -Depth 32 -Compress)
    if ($curNorm -eq $newNorm) { Write-Info 'claude settings already in sync - skipping'; return }
    Backup-File -Path $dest -Stamp (Get-Date -Format 'yyyyMMdd_HHmmss') | Out-Null
    Write-Utf8NoBom -Path $dest -Content $merged
    Write-Success "Merged $($keys.Count) whitelisted key(s) into settings.json"
}

function Sync-ClaudeMcp {
    $src = Join-Path $script:ClaudeCfg 'mcp-servers.json'
    $dest = Join-Path $HOME '.claude.json'
    if (-not (Test-Path $src)) { return }
    $srcObj = Get-Content -Raw $src | ConvertFrom-Json
    $count = if ($srcObj.PSObject.Properties['mcpServers']) { @($srcObj.mcpServers.PSObject.Properties).Count } else { 0 }
    if ($count -eq 0) { Write-Info 'no MCP servers declared in repo - skipping'; return }
    if (Test-DryRun) { Write-Info "[DRY-RUN] Would merge $count MCP server(s) into $dest"; return }
    if ((Test-KeepExisting) -and (Test-Path $dest)) { Write-Info '[SKIP] Keeping existing MCP servers (KeepExisting)'; return }
    if (-not (Test-Path $dest)) { Write-Warn "$dest not found - run Claude Code once first; skipping MCP sync"; return }
    try { $null = Get-Content -Raw $dest | ConvertFrom-Json }
    catch { Write-Warn "$dest is not valid JSON - skipping MCP sync. Fix manually."; return }
    $merged = Merge-McpServers -CurrentJson (Get-Content -Raw $dest) -SourceJson (Get-Content -Raw $src)
    # Idempotency (the Bash twin has this): without it every setup run backed
    # up and rewrote the live ~/.claude.json, so the "newest backup" converged
    # to already-merged content and the uninstall restore became a no-op.
    $curNorm = (Get-Content -Raw $dest | ConvertFrom-Json | ConvertTo-Json -Depth 32 -Compress)
    $newNorm = ($merged | ConvertFrom-Json | ConvertTo-Json -Depth 32 -Compress)
    if ($curNorm -eq $newNorm) { Write-Info 'MCP servers already in sync - skipping'; return }
    Backup-File -Path $dest -Stamp (Get-Date -Format 'yyyyMMdd_HHmmss') | Out-Null
    Write-Utf8NoBom -Path $dest -Content $merged
    Write-Success "Synced $count MCP server(s)"
}

function Test-ClaudeMarketplaceRegistered {
    # Pure pre-check against ~/.claude/plugins/known_marketplaces.json (the
    # same idempotency source the Bash twin reads) so re-runs skip the slow,
    # networked CLI call and its misleading "Failed to register" on repeats.
    param(
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][string]$JsonPath
    )
    if (-not (Test-Path -LiteralPath $JsonPath)) { return $false }
    try { $known = Get-Content -Raw $JsonPath | ConvertFrom-Json } catch { return $false }
    foreach ($m in $known.PSObject.Properties) {
        $srcNode = $m.Value.PSObject.Properties['source']
        if ($srcNode -and $srcNode.Value.PSObject.Properties['repo'] -and $srcNode.Value.repo -eq $Repo) { return $true }
    }
    return $false
}

function Test-ClaudePluginInstalled {
    # Pure pre-check against ~/.claude/plugins/installed_plugins.json.
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$JsonPath
    )
    if (-not (Test-Path -LiteralPath $JsonPath)) { return $false }
    try { $installed = Get-Content -Raw $JsonPath | ConvertFrom-Json } catch { return $false }
    $plugins = $installed.PSObject.Properties['plugins']
    if (-not $plugins) { return $false }
    $entry = $plugins.Value.PSObject.Properties[$Name]
    return ($null -ne $entry -and @($entry.Value).Count -gt 0)
}

function Register-ClaudeMarketplaces {
    if (-not (Test-CfgEnabled 'claude_code.register_marketplaces')) { return }
    if (-not (Test-Command 'claude')) { Write-Warn 'claude CLI not found - skipping marketplace registration'; return }
    $known = Join-Path $HOME '.claude/plugins/known_marketplaces.json'
    foreach ($repo in (Get-CfgList 'claude_code.marketplaces')) {
        if (Test-ClaudeMarketplaceRegistered -Repo $repo -JsonPath $known) {
            Write-Info "marketplace $repo already registered - skipping"; continue
        }
        if (Test-DryRun) { Write-Info "[DRY-RUN] Would run: claude plugin marketplace add $repo"; continue }
        Invoke-Native claude plugin marketplace add $repo | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Success "Registered marketplace: $repo" } else { Write-Warn "Failed to register marketplace: $repo" }
    }
}

function Install-ClaudePlugins {
    if (-not (Test-CfgEnabled 'claude_code.install_enabled_plugins')) { return }
    if (-not (Test-Command 'claude')) { Write-Warn 'claude CLI not found - skipping plugin install'; return }
    $src = Join-Path $script:ClaudeCfg 'settings.json'
    if (-not (Test-Path $src)) { return }
    $settings = Get-Content -Raw $src | ConvertFrom-Json
    if (-not $settings.PSObject.Properties['enabledPlugins']) { return }
    $installedJson = Join-Path $HOME '.claude/plugins/installed_plugins.json'
    foreach ($p in $settings.enabledPlugins.PSObject.Properties) {
        if ($p.Value -ne $true) { continue }
        if (Test-ClaudePluginInstalled -Name $p.Name -JsonPath $installedJson) {
            Write-Info "plugin $($p.Name) already installed - skipping"; continue
        }
        if (Test-DryRun) { Write-Info "[DRY-RUN] Would run: claude plugin install $($p.Name)"; continue }
        Invoke-Native claude plugin install $p.Name | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Success "Installed plugin: $($p.Name)" } else { Write-Warn "Failed to install plugin: $($p.Name)" }
    }
}

function Repair-EpisodicMemoryDeps {
    # Work around a broken dependency in the episodic-memory marketplace plugin
    # we install above (mirror of the Bash _patch_episodic_memory_deps). Its
    # lockfile nests onnxruntime-common under onnxruntime-node/ instead of
    # hoisting it to top-level node_modules, so @huggingface/transformers' bare
    # `import "onnxruntime-common"` can't resolve it and the plugin's
    # SessionStart hook errors out with "Failed with non-blocking status code:
    # node:internal/modules/...". Non-blocking but noisy on every fresh machine.
    # Upstream fix is to declare onnxruntime-common as a direct dep; until then
    # we hoist the nested copy with an NTFS junction (needs no privilege, same
    # trick as nvm activation). Version-agnostic and self-detecting: no-op when
    # the plugin is absent, and a cache-regenerating plugin update is re-patched
    # on the next run.
    param(
        [string]$Base = (Join-Path $HOME '.claude/plugins/cache/superpowers-marketplace/episodic-memory')
    )
    if (-not (Test-Path -LiteralPath $Base)) {
        Write-Info 'episodic-memory plugin not installed - skipping onnxruntime-common patch'
        return
    }
    foreach ($verdir in Get-ChildItem -LiteralPath $Base -Directory -ErrorAction Ignore) {
        $nm   = Join-Path $verdir.FullName 'node_modules'
        $src  = Join-Path $nm 'onnxruntime-node/node_modules/onnxruntime-common'
        $dest = Join-Path $nm 'onnxruntime-common'

        # Nothing to hoist for this version (structure changed / not the buggy build).
        if (-not (Test-Path -LiteralPath $src -PathType Container)) { continue }

        # Only fill an empty slot — anything already there (a real dir or a
        # junction) is left untouched: any resolvable onnxruntime-common
        # satisfies the plugin, and re-pointing an existing entry risks
        # clobbering a real dir. (Same policy as the Bash engine.) Test-Path
        # here is deliberate: -PathType Container and Directory.Exists both
        # report a dangling junction as absent/present inconsistently across
        # PS/.NET, so we treat "anything present" as leave-alone.
        if (Test-Path -LiteralPath $dest) { continue }
        if (Test-DryRun) { Write-Info "[DRY-RUN] Would junction $dest -> $src"; continue }

        try {
            New-Item -ItemType Junction -Path $dest -Target $src | Out-Null
            Write-Success "Patched episodic-memory ($($verdir.Name)): hoisted onnxruntime-common"
        } catch {
            Write-Warn "Failed to hoist onnxruntime-common for $($verdir.Name): $_"
        }
    }
}

function Install-Ccstatusline {
    if (-not (Test-CfgEnabled 'claude_code.ccstatusline.enabled')) { return }
    $src = (Resolve-Path (Join-Path $PSScriptRoot '../configs/ccstatusline/settings.json') -ErrorAction Ignore)
    if (-not $src) { Write-Info 'ccstatusline template missing - skipping'; return }
    $dest = Join-Path $HOME '.config/ccstatusline/settings.json'
    New-DirOrDryRun -Path (Split-Path $dest -Parent)
    Deploy-Config -Source $src.Path -Destination $dest -Label 'ccstatusline settings.json'
}

function Install-ClaudeCode {
    if (-not (Test-CfgEnabled 'claude_code.enabled')) { Write-Info 'Claude Code disabled - skipping'; return }
    Write-Header 'Claude Code'
    Install-ClaudeNative
    Add-ClaudeBinToPath
    Sync-ClaudeAssets -Root (Join-Path $HOME '.claude')
    Sync-ClaudeProfiles
    Install-ClaudeSwap
    Sync-ClaudeSettings
    if (Test-CfgEnabled 'claude_code.sync_mcp_servers') { Sync-ClaudeMcp }
    Register-ClaudeMarketplaces
    Install-ClaudePlugins
    Repair-EpisodicMemoryDeps
    Install-Ccstatusline
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
    try { $null = Get-Content -Raw $dest | ConvertFrom-Json }
    catch { Write-Warn "$dest is not valid JSON - leaving it. Fix manually."; return }
    $keys = @(Get-CfgList 'claude_code.settings_merge_keys')
    if (Test-DryRun) { Write-Info "[DRY-RUN] Would strip $($keys.Count) env-setup key(s) from settings.json"; return }
    $stripped = Remove-ManagedSettingsKeys -CurrentJson (Get-Content -Raw $dest) -SourceJson (Get-Content -Raw $src) -WhitelistKeys $keys
    Write-Utf8NoBom -Path $dest -Content $stripped
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
    Write-Info 'No ~/.claude.json backup - leaving MCP servers intact'
}

function Uninstall-ClaudeAssets {
    # Remove the managed file-based harness from one config root (~/.claude or
    # a ~/.claude-<profile> dir). User-edited copies preserved by Remove-ManagedFile.
    param([Parameter(Mandatory)][string]$Root)
    Remove-ManagedFile -Dest (Join-Path $Root 'CLAUDE.md') `
        -RepoSrc (Join-Path $script:ClaudeCfg 'CLAUDE.md') -Label 'global CLAUDE.md'
    foreach ($sub in @('rules', 'commands', 'agents')) {
        $srcDir = Join-Path $script:ClaudeCfg $sub
        if (-not (Test-Path $srcDir)) { continue }
        Get-ChildItem $srcDir -Filter *.md -ErrorAction Ignore | ForEach-Object {
            Remove-ManagedFile -Dest (Join-Path $Root "$sub/$($_.Name)") -RepoSrc $_.FullName -Label "$sub/$($_.Name)"
        }
    }
    $skillsRoot = Join-Path $script:ClaudeCfg 'skills'
    if (Test-Path $skillsRoot) {
        foreach ($skill in @(Get-ChildItem $skillsRoot -Directory -ErrorAction Ignore)) {
            foreach ($f in @(Get-ChildItem $skill.FullName -File)) {
                Remove-ManagedFile -Dest (Join-Path $Root "skills/$($skill.Name)/$($f.Name)") -RepoSrc $f.FullName -Label "skills/$($skill.Name)/$($f.Name)"
            }
            $destDir = Join-Path $Root "skills/$($skill.Name)"
            if (-not (Test-DryRun) -and (Test-Path $destDir) -and -not @(Get-ChildItem $destDir -Force)) {
                Remove-Item -LiteralPath $destDir
            }
        }
    }
}

function Uninstall-ClaudeCode {
    Write-Header 'Uninstall: Claude Code'

    # C - managed config files, in ~/.claude and each DECLARED profile dir.
    # Deliberately config-driven, not a ~/.claude-* glob: the prefix is no
    # proof env-setup manages a dir (a user's backup copy or a third-party
    # ~/.claude-<tool> must never be swept). Same precedent as the
    # plugin/marketplace teardown below, which also reads config.
    Uninstall-ClaudeAssets -Root (Join-Path $HOME '.claude')
    foreach ($p in @(Get-CfgList 'claude_code.profiles')) {
        if (-not (Test-ClaudeProfileName $p)) { continue }
        $proot = Join-Path $HOME ".claude-$p"
        if (-not (Test-Path -LiteralPath $proot)) { continue }
        Write-Info "Uninstalling claude profile assets: $p"
        Uninstall-ClaudeAssets -Root $proot
    }

    $swapSrc = Resolve-Path (Join-Path $PSScriptRoot '../scripts/claude-swap.sh') -ErrorAction Ignore
    if ($swapSrc) {
        Remove-ManagedFile -Dest (Join-Path $HOME '.local/bin/claude-swap') `
            -RepoSrc $swapSrc.Path -Label 'claude-swap'
    }
    $swapShim = Resolve-Path (Join-Path $PSScriptRoot '../scripts/claude-swap.ps1') -ErrorAction Ignore
    if ($swapShim) {
        Remove-ManagedFile -Dest (Join-Path $HOME '.local/bin/claude-swap.ps1') `
            -RepoSrc $swapShim.Path -Label 'claude-swap.ps1'
    }

    Uninstall-ClaudeSettings
    Uninstall-ClaudeMcp

    $cc = (Resolve-Path (Join-Path $PSScriptRoot '../configs/ccstatusline/settings.json') -ErrorAction Ignore)
    if ($cc) {
        Remove-ManagedFile -Dest (Join-Path $HOME '.config/ccstatusline/settings.json') -RepoSrc $cc.Path -Label 'ccstatusline settings.json'
        $ccDir = Join-Path $HOME '.config/ccstatusline'
        if (-not (Test-DryRun) -and (Test-Path -LiteralPath $ccDir) -and -not @(Get-ChildItem -LiteralPath $ccDir -Force)) {
            Remove-Item -LiteralPath $ccDir
        }
    }

    # T - plugins/marketplaces + CLI binary
    if (-not (Test-KeepTools)) {
        if (Test-Command 'claude') {
            $s = Join-Path $script:ClaudeCfg 'settings.json'
            if (Test-Path $s) {
                $settings = Get-Content -Raw $s | ConvertFrom-Json
                if ($settings.PSObject.Properties['enabledPlugins']) {
                    foreach ($p in $settings.enabledPlugins.PSObject.Properties) {
                        if ($p.Value -ne $true) { continue }
                        if (Test-DryRun) { Write-Info "[DRY-RUN] Would run: claude plugin uninstall $($p.Name)" }
                        else { Invoke-Native claude plugin uninstall $p.Name | Out-Null }
                    }
                }
            }
            foreach ($repo in (Get-CfgList 'claude_code.marketplaces')) {
                if (Test-DryRun) { Write-Info "[DRY-RUN] Would run: claude plugin marketplace remove $repo" }
                else { Invoke-Native claude plugin marketplace remove $repo | Out-Null }
            }
        }
        $launcher = Join-Path $HOME '.local/bin/claude.exe'
        if (Test-Path -LiteralPath $launcher) { Remove-OrDryRun -Path $launcher }
        # The native installer keeps its versioned binaries in
        # ~/.local/share/claude (can be hundreds of MB); Bash removes it too.
        Remove-ManagedDir -Dir (Join-Path $HOME '.local/share/claude') -Label 'Claude CLI store'
        Remove-ClaudeBinFromPath
        Write-Info 'Claude CLI removed where found; ~/.claude data (auth/history) preserved.'
    }
}
