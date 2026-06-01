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

Describe 'Resolve-PyenvVersion' {
    BeforeAll {
        $script:list = @(' 3.11.8', '3.11.9', '3.12.9', '3.12.10', '3.12.0a1', '3.13.1', '  ')
    }
    It 'resolves a major.minor to the newest stable patch' {
        Resolve-PyenvVersion -Requested '3.12' -Available $script:list | Should -Be '3.12.10'
    }
    It 'sorts numerically, not lexically (3.12.10 > 3.12.9)' {
        Resolve-PyenvVersion -Requested '3.12' -Available @('3.12.9', '3.12.10') | Should -Be '3.12.10'
    }
    It 'leaves an exact patch version untouched' {
        Resolve-PyenvVersion -Requested '3.11.7' -Available $script:list | Should -Be '3.11.7'
    }
    It 'returns the request unchanged when nothing matches' {
        Resolve-PyenvVersion -Requested '3.9' -Available $script:list | Should -Be '3.9'
    }
    It 'ignores prereleases' {
        Resolve-PyenvVersion -Requested '3.12' -Available @('3.12.0a1', '3.12.0') | Should -Be '3.12.0'
    }
}

Describe 'Resolve-JunctionFreePath' {
    It 'returns a plain directory unchanged' {
        $d = Join-Path $TestDrive 'plain'
        New-Item -ItemType Directory -Path $d | Out-Null
        Resolve-JunctionFreePath -Path $d | Should -Be ((Get-Item $d).FullName)
    }
    It 'resolves a directory junction to its real target' {
        $real = Join-Path $TestDrive 'real'
        New-Item -ItemType Directory -Path $real | Out-Null
        $link = Join-Path $TestDrive 'link'
        New-Item -ItemType Junction -Path $link -Target $real | Out-Null
        Resolve-JunctionFreePath -Path $link | Should -Be ((Get-Item $real).FullName)
    }
    It 'returns a non-existent path unchanged' {
        $p = Join-Path $TestDrive 'does-not-exist'
        Resolve-JunctionFreePath -Path $p | Should -Be $p
    }
}
