BeforeAll {
    Import-Module "$PSScriptRoot/../lib/Common.psm1"
    Import-Module "$PSScriptRoot/../lib/Config.psm1"
    Import-Module "$PSScriptRoot/../lib/Package.psm1"
    . "$PSScriptRoot/../modules/03-PythonTools.ps1"
}

Describe 'Install-PythonTools dispatch' {
    AfterEach { $env:ENVSETUP_DRY_RUN = $null }

    It 'installs poetry and jupyterlab as isolated uv tools when python is enabled' {
        $env:ENVSETUP_DRY_RUN = 'true'
        $yaml = @'
languages:
  python:
    enabled: true
python_tools:
  poetry: true
  jupyter: true
'@
        $f = Join-Path $TestDrive 'c1.yaml'; Set-Content -Path $f -Value $yaml
        Import-Config -Path $f
        Mock Install-Pkg { }
        Mock Write-Info { }
        Mock Test-Command { $false }   # force the not-yet-installed path
        Install-PythonTools
        # uv itself comes from 02-Languages (it is the Python manager) and
        # pipx is gone - this module must not install any package manager.
        Should -Invoke Install-Pkg -Times 0
        Should -Invoke Write-Info -ParameterFilter { $Message -like '*uv tool install poetry*' }
        Should -Invoke Write-Info -ParameterFilter { $Message -like '*uv tool install jupyterlab*' }
    }

    It 'skips everything when python is disabled' {
        $env:ENVSETUP_DRY_RUN = 'true'
        $yaml = @'
languages:
  python:
    enabled: false
python_tools:
  poetry: true
'@
        $f = Join-Path $TestDrive 'c2.yaml'; Set-Content -Path $f -Value $yaml
        Import-Config -Path $f
        Mock Install-Pkg { }
        Install-PythonTools
        Should -Invoke Install-Pkg -Times 0
    }
}
