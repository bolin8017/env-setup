BeforeAll {
    Import-Module "$PSScriptRoot/../lib/Common.psm1"
    Import-Module "$PSScriptRoot/../lib/Config.psm1"
    Import-Module "$PSScriptRoot/../lib/Package.psm1"
    . "$PSScriptRoot/../modules/02-Languages.ps1"
}

Describe 'Install-Languages dispatch' {
    BeforeEach {
        $env:ENVSETUP_DRY_RUN = 'true'
        $yaml = @'
languages:
  node:
    enabled: true
    version: lts
  python:
    enabled: false
'@
        $f = Join-Path $TestDrive 'c.yaml'; Set-Content -Path $f -Value $yaml
        Import-Config -Path $f
        Mock Install-Pkg { }
    }
    AfterEach { $env:ENVSETUP_DRY_RUN = $null }

    It 'installs nvm when node enabled and skips pyenv when python disabled' {
        Install-Languages
        Should -Invoke Install-Pkg -Times 1 -ParameterFilter { $Name -eq 'nvm' }
        Should -Invoke Install-Pkg -Times 0 -ParameterFilter { $Name -eq 'pyenv' }
    }
}
