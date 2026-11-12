BeforeAll {
    Import-Module "$PSScriptRoot/../lib/Common.psm1"
    Import-Module "$PSScriptRoot/../lib/Config.psm1"
    Import-Module "$PSScriptRoot/../lib/DryRun.psm1"
    Import-Module "$PSScriptRoot/../lib/Backup.psm1"
    Import-Module "$PSScriptRoot/../lib/ClaudeConfig.psm1"
    . "$PSScriptRoot/../modules/08-ClaudeCode.ps1"
}

Describe 'Get-CcstatuslineCommand' {
    It 'renders the pinned install with node through the throttle, never npx' {
        $f = Join-Path $TestDrive 'sl.yaml'; Set-Content -Path $f -Value "claude_code:`n  enabled: true"
        Import-Config -Path $f
        $cmd = Get-CcstatuslineCommand
        $cmd | Should -Match '^\. \S*statusline-throttle\.sh node \S*ccstatusline/dist/ccstatusline\.js$'
        $cmd | Should -Not -Match 'npx'
        $cmd.Contains([string][char]92) | Should -BeFalse   # forward slashes for the bash launcher
    }
    It 'keeps the plain node form when account-swap wraps the status line' {
        $yaml = @'
claude_code:
  enabled: true
  account_swap:
    enabled: true
'@
        $f = Join-Path $TestDrive 'sl2.yaml'; Set-Content -Path $f -Value $yaml
        Import-Config -Path $f
        $cmd = Get-CcstatuslineCommand
        $cmd | Should -Match '^node \S*ccstatusline/dist/ccstatusline\.js$'
    }
}

Describe 'Install-Ccstatusline (dry-run)' {
    BeforeEach {
        $env:ENVSETUP_DRY_RUN = 'true'
        $yaml = @'
claude_code:
  enabled: true
  ccstatusline:
    enabled: true
'@
        $f = Join-Path $TestDrive 'sl3.yaml'; Set-Content -Path $f -Value $yaml
        Import-Config -Path $f
        Mock Deploy-Config { }
        Mock New-DirOrDryRun { }
        Mock Install-CcstatuslinePackage { }
    }
    AfterEach { $env:ENVSETUP_DRY_RUN = $null }

    It 'deploys the render throttle next to the widget template' {
        Install-Ccstatusline
        Should -Invoke Deploy-Config -Times 1 -ParameterFilter {
            $Label -eq 'ccstatusline throttle' -and $Destination -like '*ccstatusline*statusline-throttle.sh'
        }
    }
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
  sync_guides: true
  sync_hooks: true
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
    It 'deploys guides when sync_guides is true' {
        Install-ClaudeCode
        Should -Invoke Deploy-Config -ParameterFilter { $Label -eq 'guides/delegation.md' }
    }
    It 'skips guides when sync_guides is false' {
        $yaml = @'
claude_code:
  enabled: true
  sync_guides: false
'@
        $f = Join-Path $TestDrive 'c4.yaml'; Set-Content -Path $f -Value $yaml
        Import-Config -Path $f
        Install-ClaudeCode
        Should -Invoke Deploy-Config -Times 0 -ParameterFilter { $Label -like 'guides/*' }
    }
    It 'deploys hook scripts when sync_hooks is true' {
        Install-ClaudeCode
        Should -Invoke Deploy-Config -ParameterFilter { $Label -eq 'hooks/check_commit_msg.py' }
    }
    It 'skips hook scripts when sync_hooks is false' {
        $yaml = @'
claude_code:
  enabled: true
  sync_hooks: false
'@
        $f = Join-Path $TestDrive 'c5.yaml'; Set-Content -Path $f -Value $yaml
        Import-Config -Path $f
        Install-ClaudeCode
        Should -Invoke Deploy-Config -Times 0 -ParameterFilter { $Label -like 'hooks/*' }
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
