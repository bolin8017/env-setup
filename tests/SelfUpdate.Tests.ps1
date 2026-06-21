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

Describe 'Test-EnvSetupShouldCheck' {
    BeforeAll {
        $env:ENVSETUP_UPDATE_RUNNING = '1'   # suppress the top-level check on dot-source
        . "$PSScriptRoot/../configs/pwsh/45-self-update.ps1"
        $env:ENVSETUP_UPDATE_RUNNING = $null
    }
    It 'is due when there is no prior check'      { Test-EnvSetupShouldCheck -Last 0 -Now 1000000 -FreqDays 7 | Should -BeTrue }
    It 'is not due within the window'             { Test-EnvSetupShouldCheck -Last 1000000 -Now 1000001 -FreqDays 7 | Should -BeFalse }
    It 'is due once the window has elapsed'       { Test-EnvSetupShouldCheck -Last 0 -Now (8*86400) -FreqDays 7 | Should -BeTrue }
    It 'freq 0 means check every shell'           { Test-EnvSetupShouldCheck -Last 9999999 -Now 9999999 -FreqDays 0 | Should -BeTrue }
}

Describe '45-self-update.ps1 content' {
    It 'sources state, quotes upstream, ff-only, guards interactive' {
        $f = Get-Content -Raw "$PSScriptRoot/../configs/pwsh/45-self-update.ps1"
        $f | Should -Match 'update\.ps1'
        $f | Should -Match "'HEAD\.\.@\{u\}'"
        $f | Should -Match 'pull --ff-only'
        $f | Should -Match 'UserInteractive'
        $f | Should -Match 'git -C "\$repo"'
    }
}

Describe 'Remove-UpdateState' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../lib/Common.psm1" -Force
        Import-Module "$PSScriptRoot/../lib/Uninstall.psm1" -Force -DisableNameChecking
        . "$PSScriptRoot/../modules/06-Shell.ps1"
    }
    It 'removes both generated state files' {
        $sd = Join-Path $TestDrive 'teardown'
        New-Item -ItemType Directory -Path $sd -Force | Out-Null
        Set-Content -Path (Join-Path $sd 'update.ps1') -Value 'x'
        Set-Content -Path (Join-Path $sd '.update-last-check') -Value '123'
        Remove-UpdateState -StateDir $sd
        Test-Path (Join-Path $sd 'update.ps1') | Should -BeFalse
        Test-Path (Join-Path $sd '.update-last-check') | Should -BeFalse
    }
}
