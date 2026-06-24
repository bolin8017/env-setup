BeforeDiscovery {
    # $env:OS is 'Windows_NT' on both Windows PowerShell 5.1 and pwsh-on-Windows and
    # is StrictMode-safe to read - used to gate the 5.1-only regression test below.
    $onWindows = ($env:OS -eq 'Windows_NT')
}

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

    It 'resolves a junction under Windows PowerShell 5.1 without ResolveLinkTarget (regression)' -Skip:(-not $onWindows) {
        # modules/02-Languages.ps1 runs under Windows PowerShell 5.1 (the bootstrap
        # shell), where FileSystemInfo.ResolveLinkTarget does NOT exist and used to
        # throw - aborting the whole module before its pyenv MSI workaround. CI runs
        # this suite under pwsh (Core), where the method exists and the bug is
        # invisible, so reproduce the real engine via powershell.exe (always present
        # on Windows). Old code => non-zero exit; fix => 0.
        $mod = (Resolve-Path "$PSScriptRoot/../modules/02-Languages.ps1").Path
        $probe = @"
Set-StrictMode -Version Latest
. '$mod'
`$real = Join-Path `$env:TEMP ('jf_' + [guid]::NewGuid().ToString('N'))
`$link = `$real + '_link'
New-Item -ItemType Directory -Path `$real | Out-Null
New-Item -ItemType Junction -Path `$link -Target `$real | Out-Null
try {
    if ((Resolve-JunctionFreePath -Path `$link) -ne (Get-Item `$real).FullName) { exit 3 }
} finally { Remove-Item `$real, `$link -Recurse -Force -ErrorAction SilentlyContinue }
"@
        $out = & powershell.exe -NoProfile -NonInteractive -Command $probe 2>&1
        $LASTEXITCODE | Should -Be 0 -Because "powershell.exe (5.1) output: $out"
    }
}
