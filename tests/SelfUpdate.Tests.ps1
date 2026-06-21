BeforeAll {
    $script:RepoRoot = (Resolve-Path "$PSScriptRoot/..").Path
}

Describe 'Write-UpdateState' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../lib/Common.psm1" -Force
        Import-Module "$PSScriptRoot/../lib/Config.psm1" -Force
        Import-Module "$PSScriptRoot/../lib/DryRun.psm1" -Force -DisableNameChecking
        Import-Module "$PSScriptRoot/../lib/Backup.psm1" -Force
        Import-Module "$PSScriptRoot/../lib/WindowsTerminal.psm1" -Force
        Import-Module "$PSScriptRoot/../lib/Package.psm1" -Force
        . "$PSScriptRoot/../modules/06-Shell.ps1"
        $cfgFile = Join-Path $TestDrive 'c.yaml'
        Set-Content -Path $cfgFile -Value "update:`n  enabled: true`n  frequency_days: 7`n"
        Import-Config -Path $cfgFile
    }
    AfterEach { $env:ENVSETUP_DRY_RUN = $null }

    It 'writes update.ps1 with repo dir, enabled flag, and cadence' {
        $sd = Join-Path $TestDrive 'state1'
        Write-UpdateState -StateDir $sd
        $state = Join-Path $sd 'update.ps1'
        Test-Path $state | Should -BeTrue
        $c = Get-Content -Raw $state
        $c | Should -Match "ENVSETUP_REPO_DIR\s*=\s*'[^']+'"
        $c | Should -Match "ENVSETUP_UPDATE_ENABLED\s*=\s*'1'"
        $c | Should -Match "ENVSETUP_UPDATE_FREQ_DAYS\s*=\s*'7'"
        Test-Path (Join-Path $sd '.update-last-check') | Should -BeTrue
    }

    It 'writes nothing under dry-run' {
        $env:ENVSETUP_DRY_RUN = 'true'
        $sd = Join-Path $TestDrive 'state2'
        Write-UpdateState -StateDir $sd
        Test-Path (Join-Path $sd 'update.ps1') | Should -BeFalse
        Test-Path $sd | Should -BeFalse
    }
}

Describe 'aliases.ps1 self-update command' {
    It 'defines Update-EnvSetup and the env-update alias' {
        $aliases = Get-Content -Raw (Join-Path $RepoRoot 'configs/aliases.ps1')
        $aliases | Should -Match 'function Update-EnvSetup'
        $aliases | Should -Match "Set-Alias.*env-update"
    }
}
