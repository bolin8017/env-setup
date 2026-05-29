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
  settings_merge_keys:
    - env
  register_marketplaces: true
  install_enabled_plugins: true
  sync_mcp_servers: true
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
