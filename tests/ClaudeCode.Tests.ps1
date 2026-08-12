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
    It 'deploys skill subdirectory files (references/) recursively' {
        Install-ClaudeCode
        Should -Invoke Deploy-Config -ParameterFilter { $Label -like 'skills/speak-human-tw/references/*' }
    }
    It 'syncs harness assets into each declared profile dir' {
        Install-ClaudeCode
        Should -Invoke Deploy-Config -ParameterFilter { $Destination -like '*.claude-work*' }
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

# claude-as / claude-swap / claude-logout / Copy-ClaudeStatusLine moved out of
# configs/aliases.ps1 into bolin8017/claude-account-swap; their coverage moved
# with them (that repo's own Pester/bash suites).

Describe 'Install-AccountSwap (dry-run)' {
    BeforeEach {
        $env:ENVSETUP_DRY_RUN = 'true'
        Mock Invoke-Native { }
    }
    AfterEach { $env:ENVSETUP_DRY_RUN = $null }

    It 'is a no-op when claude_code.account_swap.enabled is false (default)' {
        $yaml = @'
claude_code:
  account_swap:
    enabled: false
    repo: "https://github.com/bolin8017/claude-account-swap.git"
    ref: "main"
'@
        $f = Join-Path $TestDrive 'c.yaml'; Set-Content -Path $f -Value $yaml
        Import-Config -Path $f
        { Install-AccountSwap } | Should -Not -Throw
        Should -Invoke Invoke-Native -Times 0
    }

    It 'warns instead of cloning when enabled but no repo is configured' {
        $yaml = @'
claude_code:
  account_swap:
    enabled: true
'@
        $f = Join-Path $TestDrive 'c2.yaml'; Set-Content -Path $f -Value $yaml
        Import-Config -Path $f
        Mock Write-Warn { }
        Install-AccountSwap
        Should -Invoke Write-Warn -ParameterFilter { $Message -match 'no repo is configured' }
        Should -Invoke Invoke-Native -Times 0
    }

    It 'announces the clone/update under dry-run without touching git' {
        $yaml = @'
claude_code:
  account_swap:
    enabled: true
    repo: "https://github.com/bolin8017/claude-account-swap.git"
    ref: "main"
'@
        $f = Join-Path $TestDrive 'c3.yaml'; Set-Content -Path $f -Value $yaml
        Import-Config -Path $f
        Mock Write-Info { }
        Install-AccountSwap
        Should -Invoke Write-Info -ParameterFilter { $Message -match 'DRY-RUN' -and $Message -match 'claude-account-swap' }
        Should -Invoke Invoke-Native -Times 0
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
