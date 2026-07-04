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

    It 'repairs with a junction when nvm use leaves node inactive' {
        $env:ENVSETUP_DRY_RUN = $null
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
        function global:nvm { 'Now using node v9.9.9 (64-bit)'; $global:LASTEXITCODE = 0 }
        try {
            Mock Test-NodeActivation { $false }
            Mock Repair-NodeActivation { $true }
            Mock Write-Warn { }
            Install-Languages
            Should -Invoke Repair-NodeActivation -Times 1 -ParameterFilter {
                $Version -eq '9.9.9'
            }
            Should -Invoke Write-Warn -Times 0
        } finally {
            Remove-Item function:global:nvm
        }
    }

    It 'warns with remediation when the junction repair also fails' {
        $env:ENVSETUP_DRY_RUN = $null
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
        function global:nvm { 'Now using node v9.9.9 (64-bit)'; $global:LASTEXITCODE = 0 }
        try {
            Mock Test-NodeActivation { $false }
            Mock Repair-NodeActivation { $false }
            Mock Write-Warn { }
            Install-Languages
            Should -Invoke Write-Warn -Times 1 -ParameterFilter {
                $Message -like '*Developer Mode*'
            }
        } finally {
            Remove-Item function:global:nvm
        }
    }

    It 'stays quiet when nvm use activated node' {
        $env:ENVSETUP_DRY_RUN = $null
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
        function global:nvm { 'Now using node v9.9.9 (64-bit)'; $global:LASTEXITCODE = 0 }
        try {
            Mock Test-NodeActivation { $true }
            Mock Repair-NodeActivation { $true }
            Mock Write-Warn { }
            Install-Languages
            Should -Invoke Repair-NodeActivation -Times 0
            Should -Invoke Write-Warn -Times 0
        } finally {
            Remove-Item function:global:nvm
        }
    }

    It 'strips legacy pyenv PATH entries after the uv install' {
        $env:ENVSETUP_DRY_RUN = $null
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
        function global:uv { $global:LASTEXITCODE = 0 }
        try {
            Mock Remove-LegacyPyenvPath { }
            Install-Languages
            Should -Invoke Remove-LegacyPyenvPath -Times 1
        } finally {
            Remove-Item function:global:uv
        }
    }

    It 'tells the user conda is unmanaged on Windows instead of ignoring it' {
        $yaml = @'
languages:
  node:
    enabled: false
  python:
    enabled: false
  conda:
    enabled: true
'@
        $f = Join-Path $TestDrive 'c.yaml'; Set-Content -Path $f -Value $yaml
        Import-Config -Path $f
        Install-Languages
        Should -Invoke Write-Info -Times 1 -ParameterFilter {
            $Message -like '*conda*'
        }
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

Describe 'Get-PathWithoutLegacyPyenv' {
    # Pure filter behind Remove-LegacyPyenvPath: pyenv-win's scoop manifest
    # wrote bin/shims into the user PATH; after the uv migration they only
    # shadow pip into the dead pyenv tree (Windows sibling of #67).

    It 'strips scoop pyenv-win bin and shims entries' {
        $in = 'C:\foo;C:\Users\u\scoop\apps\pyenv\current\pyenv-win\bin;C:\Users\u\scoop\apps\pyenv\current\pyenv-win\shims;C:\bar'
        Get-PathWithoutLegacyPyenv -Path $in | Should -Be 'C:\foo;C:\bar'
    }

    It 'strips pyenv-win under a plain .pyenv root too' {
        Get-PathWithoutLegacyPyenv -Path 'C:\x;%USERPROFILE%\.pyenv\pyenv-win\shims' | Should -Be 'C:\x'
    }

    It 'keeps unrelated and unexpanded %VAR% entries untouched' {
        $in = '%USERPROFILE%\bin;C:\tools;C:\Users\u\scoop\shims'
        Get-PathWithoutLegacyPyenv -Path $in | Should -Be $in
    }
}

Describe 'Test-NodeActivation' {
    # nvm-windows exits 0 even when 'nvm use' fails to create the node
    # symlink, so the check inspects the symlink target directly.

    It 'returns true when settings.txt path points at a dir with node.exe' {
        $link = Join-Path $TestDrive 'active'
        New-Item -ItemType Directory -Path $link | Out-Null
        Set-Content -Path (Join-Path $link 'node.exe') -Value ''
        Set-Content -Path (Join-Path $TestDrive 'settings.txt') -Value "root: $TestDrive`npath: $link"
        Test-NodeActivation -NvmHome $TestDrive -Symlink '' | Should -BeTrue
    }

    It 'returns false when settings.txt path has no node.exe' {
        Set-Content -Path (Join-Path $TestDrive 'settings.txt') -Value "root: $TestDrive`npath: $(Join-Path $TestDrive 'missing')"
        Test-NodeActivation -NvmHome $TestDrive -Symlink '' | Should -BeFalse
    }

    It 'falls back to the NVM_SYMLINK location when settings.txt has no path line' {
        # scoop's nvm manifest omits 'path:' and sets NVM_SYMLINK instead
        Set-Content -Path (Join-Path $TestDrive 'settings.txt') -Value "root: $TestDrive`narch: 64"
        $link = Join-Path $TestDrive 'symlinked'
        New-Item -ItemType Directory -Path $link | Out-Null
        Set-Content -Path (Join-Path $link 'node.exe') -Value ''
        Test-NodeActivation -NvmHome $TestDrive -Symlink $link | Should -BeTrue
    }

    It 'returns false when the NVM_SYMLINK location has no node.exe' {
        Test-NodeActivation -NvmHome (Join-Path $TestDrive 'nowhere') -Symlink (Join-Path $TestDrive 'gone') | Should -BeFalse
    }

    It 'returns true when the symlink location is unknowable' {
        Test-NodeActivation -NvmHome '' -Symlink '' | Should -BeTrue
    }
}

Describe 'Repair-NodeActivation' {
    # Junctions need no elevation, so they replace nvm's symlink when the
    # machine has no Developer Mode. Real junctions in TestDrive.

    BeforeEach {
        $script:root = Join-Path $TestDrive 'nvmroot'
        New-Item -ItemType Directory -Path (Join-Path $script:root 'v9.9.9') -Force | Out-Null
        Set-Content -Path (Join-Path $script:root 'v9.9.9\node.exe') -Value ''
        Set-Content -Path (Join-Path $TestDrive 'settings.txt') -Value "root: $script:root`narch: 64"
        $script:link = Join-Path $script:root 'nodejs'
        # TestDrive persists across Its in a Describe - drop leftover links
        if (Test-Path $script:link) { [System.IO.Directory]::Delete($script:link, $true) }
    }

    It 'creates a junction to the version dir and reports node active' {
        Repair-NodeActivation -Version '9.9.9' -NvmHome $TestDrive -Symlink $script:link | Should -BeTrue
        (Get-Item $script:link).LinkType | Should -Be 'Junction'
        Test-Path (Join-Path $script:link 'node.exe') | Should -BeTrue
    }

    It 'replaces a stale link at the symlink location' {
        New-Item -ItemType Junction -Path $script:link -Target (Join-Path $script:root 'v9.9.9') | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:root 'v9.10.0') | Out-Null
        Set-Content -Path (Join-Path $script:root 'v9.10.0\node.exe') -Value ''
        Repair-NodeActivation -Version '9.10.0' -NvmHome $TestDrive -Symlink $script:link | Should -BeTrue
        (Get-Item $script:link).Target | Should -Be (Join-Path $script:root 'v9.10.0')
    }

    It 'returns false when the requested version is not installed' {
        Repair-NodeActivation -Version '1.0.0' -NvmHome $TestDrive -Symlink $script:link | Should -BeFalse
    }

    It 'refuses to touch a plain directory at the symlink location' {
        New-Item -ItemType Directory -Path $script:link | Out-Null
        Set-Content -Path (Join-Path $script:link 'keep.txt') -Value 'data'
        Repair-NodeActivation -Version '9.9.9' -NvmHome $TestDrive -Symlink $script:link | Should -BeFalse
        Test-Path (Join-Path $script:link 'keep.txt') | Should -BeTrue
    }

    It 'returns false when the symlink location is unknowable' {
        Repair-NodeActivation -Version '9.9.9' -NvmHome '' -Symlink '' | Should -BeFalse
    }

    It 'reports the final state instead of throwing when the junction cannot be created' {
        # Losing the race with nvm's elevate helper surfaces as New-Item
        # blowing up on a link path that just became occupied. Simulate an
        # uncreatable link path (parent is a file) - the function must not
        # throw (a crash kills the whole module under EAP=Stop) and must
        # answer from the final node.exe probe.
        $blocker = Join-Path $TestDrive 'blocker'
        Set-Content -Path $blocker -Value ''
        $badLink = Join-Path $blocker 'nodejs'
        { Repair-NodeActivation -Version '9.9.9' -NvmHome $TestDrive -Symlink $badLink } | Should -Not -Throw
        Repair-NodeActivation -Version '9.9.9' -NvmHome $TestDrive -Symlink $badLink | Should -BeFalse
    }
}
