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
