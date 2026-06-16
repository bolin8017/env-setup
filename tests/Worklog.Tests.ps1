# Worklog.Tests.ps1 — Pester tests for the 10-Worklog module + config.local merge
BeforeAll {
    Import-Module "$PSScriptRoot/../lib/Common.psm1" -Force
    Import-Module "$PSScriptRoot/../lib/Config.psm1" -Force
    Import-Module "$PSScriptRoot/../lib/DryRun.psm1" -Force -DisableNameChecking
    . "$PSScriptRoot/../modules/10-Worklog.ps1"

    $env:ENVSETUP_DRY_RUN = 'true'
    Import-Config -Path "$PSScriptRoot/../config.yaml"
}

AfterAll {
    $env:ENVSETUP_DRY_RUN = $null
}

Describe 'Worklog module' {
    It 'defines Install-Worklog and Uninstall-Worklog' {
        Get-Command Install-Worklog -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        Get-Command Uninstall-Worklog -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'exposes the worklog config schema with a fail-safe capture default' {
        Test-CfgEnabled 'worklog.enabled' | Should -BeTrue
        Get-CfgValue -Path 'worklog.role' | Should -Be 'capture'
        Get-CfgValue -Path 'worklog.inbox_repo' | Should -Not -BeNullOrEmpty
        Get-CfgValue -Path 'worklog.inbox_path' | Should -Not -BeNullOrEmpty
        Get-CfgValue -Path 'worklog.vault_repo' | Should -Not -BeNullOrEmpty
        Get-CfgValue -Path 'worklog.vault_path' | Should -Not -BeNullOrEmpty
    }

    It 'resolves HOME-relative paths and passes absolute paths through' {
        Resolve-WorklogPath 'Documents/x' | Should -Be (Join-Path $HOME 'Documents/x')
        Resolve-WorklogPath '/tmp/x' | Should -Be '/tmp/x'
    }

    It 'runs Install-Worklog under dry-run without throwing' {
        { Install-Worklog } | Should -Not -Throw
    }

    It 'runs Uninstall-Worklog under dry-run without throwing' {
        { Uninstall-Worklog } | Should -Not -Throw
    }
}

Describe 'config.local.yaml override (leaf merge)' {
    It 'overrides only the leaf keys present in config.local.yaml' {
        $base = @'
worklog:
  role: capture
  source: auto
  inbox_repo: "owner/inbox"
'@
        $local = @'
worklog:
  role: curator
  source: my-box
'@
        $bf = Join-Path $TestDrive 'c.yaml'
        $lf = Join-Path $TestDrive 'c.local.yaml'
        Set-Content -LiteralPath $bf -Value $base
        Set-Content -LiteralPath $lf -Value $local
        Import-Config -Path $bf
        Get-CfgValue -Path 'worklog.role' | Should -Be 'curator'           # overridden
        Get-CfgValue -Path 'worklog.source' | Should -Be 'my-box'          # overridden
        Get-CfgValue -Path 'worklog.inbox_repo' | Should -Be 'owner/inbox' # base preserved (leaf merge)
    }
}
