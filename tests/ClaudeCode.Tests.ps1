BeforeAll {
    Import-Module "$PSScriptRoot/../lib/Common.psm1"
    Import-Module "$PSScriptRoot/../lib/Config.psm1"
    Import-Module "$PSScriptRoot/../lib/DryRun.psm1"
    Import-Module "$PSScriptRoot/../lib/Backup.psm1"
    Import-Module "$PSScriptRoot/../lib/ClaudeConfig.psm1"
    . "$PSScriptRoot/../modules/08-ClaudeCode.ps1"
}

Describe 'Install-ClaudeCode dispatch (dry-run)' {
    BeforeEach {
        $env:ENVSETUP_DRY_RUN = 'true'
        $yaml = @'
claude_code:
  enabled: true
  ccstatusline:
    enabled: true
  sync_global_md: true
  sync_rules: true
  sync_commands: true
  sync_agents: true
  sync_skills: true
  settings_merge_keys:
    - env
  register_marketplaces: true
  install_enabled_plugins: true
  sync_mcp_servers: true
  profiles:
    - work
'@
        $f = Join-Path $TestDrive 'c.yaml'; Set-Content -Path $f -Value $yaml
        Import-Config -Path $f
        # Mock the deploy/dir helpers so the test never touches the real ~/.claude.
        Mock Deploy-Config { }
        Mock New-DirOrDryRun { }
    }
    AfterEach { $env:ENVSETUP_DRY_RUN = $null }

    It 'runs all enabled sync steps under dry-run without throwing' {
        { Install-ClaudeCode } | Should -Not -Throw
    }
    It 'deploys the global CLAUDE.md when sync_global_md is true' {
        Install-ClaudeCode
        Should -Invoke Deploy-Config -ParameterFilter { $Label -eq 'CLAUDE.md' }
    }
    It 'deploys skills when sync_skills is true' {
        Install-ClaudeCode
        Should -Invoke Deploy-Config -ParameterFilter { $Label -like 'skills/weekly-review/*' }
    }
    It 'syncs harness assets into each declared profile dir' {
        Install-ClaudeCode
        Should -Invoke Deploy-Config -ParameterFilter { $Destination -like '*.claude-work*' }
    }
    It 'deploys the claude-swap helper and its PowerShell shim onto PATH' {
        Install-ClaudeCode
        Should -Invoke Deploy-Config -ParameterFilter { $Label -eq 'claude-swap' }
        Should -Invoke Deploy-Config -ParameterFilter { $Label -eq 'claude-swap.ps1' }
    }
    It 'skips entirely when claude_code.enabled is false' {
        $yaml = @'
claude_code:
  enabled: false
'@
        $f = Join-Path $TestDrive 'c2.yaml'; Set-Content -Path $f -Value $yaml
        Import-Config -Path $f
        Install-ClaudeCode
        Should -Invoke Deploy-Config -Times 0
    }
}


Describe 'Uninstall-ClaudeCode version store (dry-run)' {
    BeforeEach {
        $env:ENVSETUP_DRY_RUN = 'true'
        $yaml = @'
claude_code:
  enabled: true
'@
        $f = Join-Path $TestDrive 'c.yaml'; Set-Content -Path $f -Value $yaml
        Import-Config -Path $f
        Mock Uninstall-ClaudeAssets { }
        Mock Uninstall-ClaudeSettings { }
        Mock Uninstall-ClaudeMcp { }
        Mock Remove-ManagedFile { }
        Mock Remove-OrDryRun { }
        Mock Remove-ClaudeBinFromPath { }
        Mock Remove-ManagedDir { }
        Mock Test-Command { $false }
        Mock Write-Info { }
    }
    AfterEach { $env:ENVSETUP_DRY_RUN = $null }

    It 'removes the native installer version store like the Bash engine' {
        Uninstall-ClaudeCode
        Should -Invoke Remove-ManagedDir -Times 1 -ParameterFilter {
            $Dir -like '*.local*claude' -and $Label -like '*store*'
        }
    }
}

Describe 'aliases.ps1 claude-as profile wrapper' {
    BeforeAll {
        # Extract just the claude-as function so dot-sourcing the aliases file
        # cannot shadow ls/cat/etc. for the rest of the test run.
        $aliasesPath = Join-Path $PSScriptRoot '../configs/aliases.ps1'
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $aliasesPath).Path, [ref]$tokens, [ref]$errors)
        $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'claude-as' }, $true)
        if ($fn) { Invoke-Expression $fn.Extent.Text }
    }

    It 'defines claude-as routing through CLAUDE_CONFIG_DIR' {
        $aliases = Get-Content -Raw (Join-Path $PSScriptRoot '../configs/aliases.ps1')
        $aliases | Should -Match 'function claude-as'
        $aliases | Should -Match 'CLAUDE_CONFIG_DIR'
    }

    It 'guards claude-as against checked-out credentials and wraps claude-swap' {
        $aliases = Get-Content -Raw (Join-Path $PSScriptRoot '../configs/aliases.ps1')
        $aliases | Should -Match '\.credential-owner'
        $aliases | Should -Match 'function claude-swap'
        $aliases | Should -Match '\.credential-stash'
    }

    It 'delegates claude-swap to the deployed shim, never a bare bash (WSL launcher)' {
        $aliases = Get-Content -Raw (Join-Path $PSScriptRoot '../configs/aliases.ps1')
        $aliases | Should -Match 'claude-swap\.ps1'
        $aliases | Should -Not -Match '& bash '
    }

    It 'shim resolves Git Bash explicitly and hands it a forward-slash path' {
        $shim = Get-Content -Raw (Join-Path $PSScriptRoot '../scripts/claude-swap.ps1')
        $shim | Should -Match 'bash\.exe'
        $shim | Should -Match ('-replace ' + [regex]::Escape("'\\', '/'"))
        $shim | Should -Not -Match '& bash '
    }

    It 'passes claude single-dash flags through instead of binding them' {
        function global:claude { $global:CapturedArgs = $args; $global:CapturedDir = $env:CLAUDE_CONFIG_DIR }
        try {
            claude-as work -p 'do the thing'
            @($global:CapturedArgs) | Should -Be @('-p', 'do the thing')
            $global:CapturedDir | Should -Be (Join-Path $HOME '.claude-work')
        } finally {
            Remove-Item Function:\claude -ErrorAction Ignore
            Remove-Variable -Name CapturedArgs, CapturedDir -Scope Global -ErrorAction Ignore
        }
    }

    It 'restores CLAUDE_CONFIG_DIR after the call' {
        function global:claude { }
        try {
            $before = $env:CLAUDE_CONFIG_DIR
            claude-as work
            $env:CLAUDE_CONFIG_DIR | Should -Be $before
        } finally { Remove-Item Function:\claude -ErrorAction Ignore }
    }
}

Describe 'aliases.ps1 claude-logout' {
    BeforeAll {
        $aliasesPath = Join-Path $PSScriptRoot '../configs/aliases.ps1'
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $aliasesPath).Path, [ref]$tokens, [ref]$errors)
        foreach ($name in @('claude-logout', 'Remove-ClaudeCredential')) {
            $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
            if ($fn) { Invoke-Expression $fn.Extent.Text }
        }
    }

    It 'removes the credential file and scrubs identity keys, keeping the rest' {
        $root = Join-Path $TestDrive 'croot'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        Set-Content (Join-Path $root '.credentials.json') '{"claudeAiOauth":{"accessToken":"x"}}'
        $state = Join-Path $TestDrive 'state.json'
        Set-Content $state '{"oauthAccount":{"emailAddress":"a@b.c"},"userID":"u1","theme":"dark"}'

        Remove-ClaudeCredential -Root $root -StateJson $state | Should -BeTrue
        Test-Path (Join-Path $root '.credentials.json') | Should -BeFalse
        $j = Get-Content -Raw $state | ConvertFrom-Json
        $j.PSObject.Properties.Match('oauthAccount').Count | Should -Be 0
        $j.PSObject.Properties.Match('userID').Count | Should -Be 0
        $j.theme | Should -Be 'dark'
    }

    It 'returns false when there is no stored credential' {
        $root = Join-Path $TestDrive 'empty-root'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        Remove-ClaudeCredential -Root $root -StateJson (Join-Path $TestDrive 'nope.json') | Should -BeFalse
    }

    It 'does not write a UTF-8 BOM when scrubbing state json' {
        $root = Join-Path $TestDrive 'bom-root'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $state = Join-Path $TestDrive 'bom-state.json'
        Set-Content $state '{"oauthAccount":{"e":"x"},"k":1}'
        Remove-ClaudeCredential -Root $root -StateJson $state | Out-Null
        $bytes = [System.IO.File]::ReadAllBytes($state)
        ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse
    }
}

Describe 'plugin/marketplace idempotency pre-checks' {
    It 'detects an already-registered marketplace from known_marketplaces.json' {
        $j = Join-Path $TestDrive 'known.json'
        Set-Content $j '{"superpowers-marketplace":{"source":{"repo":"obra/superpowers-marketplace"}}}'
        Test-ClaudeMarketplaceRegistered -Repo 'obra/superpowers-marketplace' -JsonPath $j | Should -BeTrue
        Test-ClaudeMarketplaceRegistered -Repo 'other/repo' -JsonPath $j | Should -BeFalse
        Test-ClaudeMarketplaceRegistered -Repo 'x/y' -JsonPath (Join-Path $TestDrive 'missing.json') | Should -BeFalse
    }
    It 'detects an already-installed plugin from installed_plugins.json' {
        $j = Join-Path $TestDrive 'installed.json'
        Set-Content $j '{"plugins":{"superpowers@superpowers-marketplace":[{"scope":"user"}]}}'
        Test-ClaudePluginInstalled -Name 'superpowers@superpowers-marketplace' -JsonPath $j | Should -BeTrue
        Test-ClaudePluginInstalled -Name 'nope@nowhere' -JsonPath $j | Should -BeFalse
    }
}

Describe 'Repair-EpisodicMemoryDeps' {
    # The episodic-memory plugin nests onnxruntime-common under onnxruntime-node/
    # instead of hoisting it, breaking its SessionStart hook. The repair hoists
    # the nested copy to top-level node_modules with an NTFS junction. Junction
    # creation is Windows-only, so those cases are skipped off-Windows; the
    # cross-platform guard/dry-run logic still runs everywhere.
    BeforeAll {
        # Defined in BeforeAll (run phase) so It blocks can see it — a function
        # in the Describe body only exists during Pester 5's discovery phase.
        function New-FakePlugin {
            param([string]$Base, [string]$Version, [bool]$WithNested = $true)
            $nm = Join-Path $Base "$Version/node_modules"
            New-Item -ItemType Directory -Path $nm -Force | Out-Null
            if ($WithNested) {
                $nested = Join-Path $nm 'onnxruntime-node/node_modules/onnxruntime-common'
                New-Item -ItemType Directory -Path $nested -Force | Out-Null
                Set-Content -Path (Join-Path $nested 'package.json') -Value '{}'
            }
        }
    }
    BeforeEach {
        $env:ENVSETUP_DRY_RUN = $null
        $script:emBase = Join-Path $TestDrive 'em'
        if (Test-Path -LiteralPath $emBase) { Remove-Item -LiteralPath $emBase -Recurse -Force }
    }
    AfterEach { $env:ENVSETUP_DRY_RUN = $null }

    It 'no-ops when the plugin is not installed' {
        { Repair-EpisodicMemoryDeps -Base (Join-Path $TestDrive 'missing-plugin') } | Should -Not -Throw
    }

    It 'does nothing when the nested copy is absent' {
        New-FakePlugin -Base $emBase -Version '1.4.2' -WithNested:$false
        Repair-EpisodicMemoryDeps -Base $emBase
        Join-Path $emBase '1.4.2/node_modules/onnxruntime-common' | Should -Not -Exist
    }

    It 'never clobbers a real top-level onnxruntime-common dir' {
        New-FakePlugin -Base $emBase -Version '1.4.2'
        $real = Join-Path $emBase '1.4.2/node_modules/onnxruntime-common'
        New-Item -ItemType Directory -Path $real -Force | Out-Null
        Set-Content -Path (Join-Path $real 'REAL_MARKER') -Value 'x'
        Repair-EpisodicMemoryDeps -Base $emBase
        ((Get-Item $real -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint) | Should -Be 0
        Join-Path $real 'REAL_MARKER' | Should -Exist
    }

    It 'announces intent under dry-run and creates nothing' {
        Mock Write-Info { }
        New-FakePlugin -Base $emBase -Version '1.4.2'
        $env:ENVSETUP_DRY_RUN = 'true'
        Repair-EpisodicMemoryDeps -Base $emBase
        Join-Path $emBase '1.4.2/node_modules/onnxruntime-common' | Should -Not -Exist
        Should -Invoke Write-Info -ParameterFilter { $Message -match 'DRY-RUN' }
    }

    It 'hoists onnxruntime-common via a junction' -Skip:(-not $IsWindows) {
        New-FakePlugin -Base $emBase -Version '1.4.2'
        Repair-EpisodicMemoryDeps -Base $emBase
        $dest = Join-Path $emBase '1.4.2/node_modules/onnxruntime-common'
        $dest | Should -Exist
        ((Get-Item $dest -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint) | Should -Not -Be 0
        Join-Path $dest 'package.json' | Should -Exist
    }

    It 'patches every installed version dir' -Skip:(-not $IsWindows) {
        New-FakePlugin -Base $emBase -Version '1.4.2'
        New-FakePlugin -Base $emBase -Version '1.5.0'
        Repair-EpisodicMemoryDeps -Base $emBase
        Join-Path $emBase '1.4.2/node_modules/onnxruntime-common' | Should -Exist
        Join-Path $emBase '1.5.0/node_modules/onnxruntime-common' | Should -Exist
    }
}
