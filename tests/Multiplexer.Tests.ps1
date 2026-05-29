BeforeAll {
    Import-Module "$PSScriptRoot/../lib/Common.psm1"
    Import-Module "$PSScriptRoot/../lib/Config.psm1"
    Import-Module "$PSScriptRoot/../lib/Package.psm1"
    Import-Module "$PSScriptRoot/../lib/DryRun.psm1"
    . "$PSScriptRoot/../modules/07-Multiplexer.ps1"
}

Describe 'Install-Multiplexer dispatch' {
    AfterEach { $env:ENVSETUP_DRY_RUN = $null }

    It 'installs zellij when enabled' {
        $env:ENVSETUP_DRY_RUN = 'true'
        $yaml = @'
windows:
  multiplexer:
    zellij: true
'@
        $f = Join-Path $TestDrive 'c1.yaml'; Set-Content -Path $f -Value $yaml
        Import-Config -Path $f
        Mock Install-Pkg { }
        Install-Multiplexer
        Should -Invoke Install-Pkg -ParameterFilter { $Name -eq 'zellij' }
    }

    It 'skips when disabled' {
        $env:ENVSETUP_DRY_RUN = 'true'
        $yaml = @'
windows:
  multiplexer:
    zellij: false
'@
        $f = Join-Path $TestDrive 'c2.yaml'; Set-Content -Path $f -Value $yaml
        Import-Config -Path $f
        Mock Install-Pkg { }
        Install-Multiplexer
        Should -Invoke Install-Pkg -Times 0
    }
}
