BeforeAll {
    Import-Module "$PSScriptRoot/../lib/Common.psm1"
    Import-Module "$PSScriptRoot/../lib/Config.psm1"
    Import-Module "$PSScriptRoot/../lib/Package.psm1"
    . "$PSScriptRoot/../modules/02-Languages.ps1"
}

Describe 'Install-Languages dispatch' {
    BeforeEach {
        $env:ENVSETUP_DRY_RUN = 'true'
        Mock Install-Pkg { }
        Mock Write-Info { }
    }
    AfterEach { $env:ENVSETUP_DRY_RUN = $null }

    It 'installs nvm when node enabled and skips uv when python disabled' {
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
        Install-Languages
        Should -Invoke Install-Pkg -Times 1 -ParameterFilter { $Name -eq 'nvm' }
        Should -Invoke Install-Pkg -Times 0 -ParameterFilter { $Name -eq 'uv' }
    }

    It 'installs uv and announces the managed-python install when python enabled' {
        $yaml = @'
languages:
  node:
    enabled: false
  python:
    enabled: true
    version: "3.12"
'@
        $f = Join-Path $TestDrive 'c.yaml'; Set-Content -Path $f -Value $yaml
        Import-Config -Path $f
        Install-Languages
        Should -Invoke Install-Pkg -Times 1 -ParameterFilter { $Name -eq 'uv' }
        Should -Invoke Install-Pkg -Times 0 -ParameterFilter { $Name -eq 'pyenv' }
        # uv resolves "3.12" to the newest patch itself - the module must pass the
        # request through untouched and ask for the default python/python3 shims.
        Should -Invoke Write-Info -Times 1 -ParameterFilter {
            $Message -like '*uv python install 3.12 --default*'
        }
    }
}
