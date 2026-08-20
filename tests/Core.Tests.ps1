BeforeAll {
    Import-Module "$PSScriptRoot/../lib/Common.psm1"
    Import-Module "$PSScriptRoot/../lib/Config.psm1"
    Import-Module "$PSScriptRoot/../lib/Package.psm1"
    . "$PSScriptRoot/../modules/01-Core.ps1"
}

Describe 'Install-Core dispatch' {
    BeforeEach {
        $env:ENVSETUP_DRY_RUN = 'true'
        $yaml = @'
core:
  github_cli: true
  git: false
'@
        $f = Join-Path $TestDrive 'c.yaml'; Set-Content -Path $f -Value $yaml
        Import-Config -Path $f
        Mock Install-App { }
    }
    AfterEach { $env:ENVSETUP_DRY_RUN = $null }

    It 'installs gh when github_cli is true and skips git when false' {
        Install-Core
        Should -Invoke Install-App -Times 1 -ParameterFilter { $Id -eq 'GitHub.cli' }
        Should -Invoke Install-App -Times 0 -ParameterFilter { $Id -eq 'Git.Git' }
    }
    It 'does not throw under dry-run' { { Install-Core } | Should -Not -Throw }
}

Describe 'Install-Core wires git defaults' {
    BeforeEach {
        $env:ENVSETUP_DRY_RUN = 'true'
        Mock Install-App { }
        Mock Set-GitDefaults { }
    }
    AfterEach { $env:ENVSETUP_DRY_RUN = $null }

    It 'configures git defaults when core.git is true' {
        $f = Join-Path $TestDrive 'g1.yaml'; Set-Content -Path $f -Value "core:`n  git: true"
        Import-Config -Path $f
        Install-Core
        Should -Invoke Set-GitDefaults -Times 1
    }
    It 'skips git defaults when core.git is false' {
        $f = Join-Path $TestDrive 'g2.yaml'; Set-Content -Path $f -Value "core:`n  git: false"
        Import-Config -Path $f
        Install-Core
        Should -Invoke Set-GitDefaults -Times 0
    }
}

Describe 'Get-GitGlobalIgnorePath' {
    BeforeEach {
        # TestDrive persists across the Its of one Describe; give each test its
        # own root so git config written by an earlier It cannot leak in.
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $env:GIT_CONFIG_GLOBAL = Join-Path $root 'gitconfig'
        Set-Content -Path $env:GIT_CONFIG_GLOBAL -Value ''
        $script:xdg = Join-Path $root 'xdg'
        $env:XDG_CONFIG_HOME = $script:xdg
        $script:root = $root
    }
    AfterEach { $env:GIT_CONFIG_GLOBAL = $null; $env:XDG_CONFIG_HOME = $null }

    It 'falls back to $XDG_CONFIG_HOME/git/ignore when core.excludesFile is unset' {
        Get-GitGlobalIgnorePath | Should -Be (Join-Path $script:xdg 'git/ignore')
    }
    It 'honours core.excludesFile' {
        $custom = Join-Path $script:root 'custom-ignore'
        git config --global core.excludesFile $custom
        Get-GitGlobalIgnorePath | Should -Be $custom
    }
}

Describe 'Set-GitDefaults / Remove-GitDefaults roundtrip' {
    BeforeEach {
        $env:ENVSETUP_DRY_RUN = $null
        # TestDrive persists across the Its of one Describe; give each test its
        # own root so state from an earlier It cannot leak in.
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $env:GIT_CONFIG_GLOBAL = Join-Path $root 'gitconfig'
        Set-Content -Path $env:GIT_CONFIG_GLOBAL -Value ''
        $env:XDG_CONFIG_HOME = Join-Path $root 'xdg'
        $script:ignore = Join-Path (Join-Path $root 'xdg') 'git/ignore'
        $script:marker = Join-Path $root 'state/.git-rerere-set'
        # Keep the developer's real ~/.env-setup out of the test.
        Mock Get-GitRerereMarkerPath { $script:marker }
    }
    AfterEach { $env:ENVSETUP_DRY_RUN = $null; $env:GIT_CONFIG_GLOBAL = $null; $env:XDG_CONFIG_HOME = $null }

    It 'adds the ignore block, enables rerere and records the marker' {
        Set-GitDefaults
        Get-Content -Raw $script:ignore | Should -Match ([regex]::Escape('**/.claude/settings.local.json'))
        (git config --global --get rerere.enabled) | Should -Be 'true'
        Test-Path $script:marker | Should -BeTrue
    }
    It 'is idempotent on a second run' {
        Set-GitDefaults
        Set-GitDefaults
        @(Select-String -Path $script:ignore -Pattern 'env-setup managed').Count | Should -Be 2
    }
    It 'leaves a pre-set rerere alone and records no marker' {
        git config --global rerere.enabled false
        Set-GitDefaults
        (git config --global --get rerere.enabled) | Should -Be 'false'
        Test-Path $script:marker | Should -BeFalse
    }
    It 'mutates nothing under dry-run' {
        $env:ENVSETUP_DRY_RUN = 'true'
        Set-GitDefaults
        Test-Path $script:ignore | Should -BeFalse
        (git config --global --get rerere.enabled) | Should -BeNullOrEmpty
    }
    It 'uninstall strips only the managed block and unsets only a marked rerere' {
        New-Item -ItemType Directory -Path (Split-Path $script:ignore -Parent) -Force | Out-Null
        Set-Content -Path $script:ignore -Value 'user-line'
        Set-GitDefaults
        Remove-GitDefaults
        $c = Get-Content -Raw $script:ignore
        $c | Should -Match 'user-line'
        $c | Should -Not -Match 'settings\.local\.json'
        (git config --global --get rerere.enabled) | Should -BeNullOrEmpty
        Test-Path $script:marker | Should -BeFalse
    }
    It 'uninstall leaves a user-set rerere alone' {
        git config --global rerere.enabled false
        Remove-GitDefaults
        (git config --global --get rerere.enabled) | Should -Be 'false'
    }
}
