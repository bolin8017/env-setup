BeforeAll {
    Import-Module "$PSScriptRoot/../lib/Common.psm1"
    Import-Module "$PSScriptRoot/../lib/Config.psm1"
    Import-Module "$PSScriptRoot/../lib/Package.psm1"
    . "$PSScriptRoot/../modules/03-PythonTools.ps1"
}

Describe 'Install-PythonTools dispatch' {
    AfterEach { $env:ENVSETUP_DRY_RUN = $null }

    It 'installs uv and pipx (for poetry) when python is enabled' {
        $env:ENVSETUP_DRY_RUN = 'true'
        $yaml = @'
languages:
  python:
    enabled: true
python_tools:
  uv: true
  poetry: true
  jupyter: false
'@
        $f = Join-Path $TestDrive 'c1.yaml'; Set-Content -Path $f -Value $yaml
        Import-Config -Path $f
        Mock Install-Pkg { }
        Install-PythonTools
        Should -Invoke Install-Pkg -ParameterFilter { $Name -eq 'uv' }
        Should -Invoke Install-Pkg -ParameterFilter { $Name -eq 'pipx' }
    }

    It 'skips everything when python is disabled' {
        $env:ENVSETUP_DRY_RUN = 'true'
        $yaml = @'
languages:
  python:
    enabled: false
python_tools:
  uv: true
'@
        $f = Join-Path $TestDrive 'c2.yaml'; Set-Content -Path $f -Value $yaml
        Import-Config -Path $f
        Mock Install-Pkg { }
        Install-PythonTools
        Should -Invoke Install-Pkg -Times 0
    }
}
