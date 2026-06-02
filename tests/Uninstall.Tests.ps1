# Pester 5: all setup/teardown lives inside Describe/Context blocks.
Import-Module "$PSScriptRoot/../lib/Common.psm1" -Force
$OnWindows = Test-IsWindows

Describe 'Test-ProtectedPath' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../lib/Uninstall.psm1" -Force
    }
    AfterAll { $env:ENVSETUP_PROTECTED_EXTRA = $null }

    It 'protects $HOME itself' {
        Test-ProtectedPath -Path $HOME | Should -BeTrue
    }
    It 'protects claude credentials' {
        Test-ProtectedPath -Path (Join-Path $HOME '.claude/.credentials.json') | Should -BeTrue
    }
    It 'protects under claude projects' {
        Test-ProtectedPath -Path (Join-Path $HOME '.claude/projects/x') | Should -BeTrue
    }
    It 'does not protect ~/.claude/CLAUDE.md' {
        Test-ProtectedPath -Path (Join-Path $HOME '.claude/CLAUDE.md') | Should -BeFalse
    }
    It 'honours ENVSETUP_PROTECTED_EXTRA' {
        $env:ENVSETUP_PROTECTED_EXTRA = (Join-Path $HOME 'Documents')
        Test-ProtectedPath -Path (Join-Path $HOME 'Documents/repos/x') | Should -BeTrue
        Test-ProtectedPath -Path (Join-Path $HOME 'Tools') | Should -BeFalse
        $env:ENVSETUP_PROTECTED_EXTRA = $null
    }
}

Describe 'Remove-ManagedFile' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../lib/Uninstall.psm1" -Force
        $env:ENVSETUP_DRY_RUN = 'false'
        $script:Tmp = Join-Path ([IO.Path]::GetTempPath()) ("envsetup-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:Tmp -Force | Out-Null
    }
    AfterAll { Remove-Item -Recurse -Force $script:Tmp -ErrorAction Ignore }

    It 'removes a file identical to the repo source' {
        $src = Join-Path $script:Tmp 'src.txt'; Set-Content $src "a`nb"
        $dst = Join-Path $script:Tmp 'dst.txt'; Set-Content $dst "a`nb"
        Remove-ManagedFile -Dest $dst -RepoSrc $src -Label 'x' | Out-Null
        Test-Path $dst | Should -BeFalse
    }
    It 'preserves a locally-modified file' {
        $src = Join-Path $script:Tmp 'src2.txt'; Set-Content $src "a`nb"
        $dst = Join-Path $script:Tmp 'dst2.txt'; Set-Content $dst "a`nCHANGED"
        Remove-ManagedFile -Dest $dst -RepoSrc $src -Label 'x' | Out-Null
        Test-Path $dst | Should -BeTrue
    }
}

Describe 'Remove-ManagedSettingsKeys' {
    BeforeAll { Import-Module "$PSScriptRoot/../lib/ClaudeConfig.psm1" -Force }

    It 'removes a whitelisted key equal to repo but keeps user keys' {
        $cur = '{"env":{"X":"1"},"authToken":"keep"}'
        $src = '{"env":{"X":"1"}}'
        $out = Remove-ManagedSettingsKeys -CurrentJson $cur -SourceJson $src -WhitelistKeys @('env')
        $obj = $out | ConvertFrom-Json
        $obj.PSObject.Properties['env'] | Should -BeNullOrEmpty
        $obj.authToken | Should -Be 'keep'
    }
    It 'keeps a whitelisted key whose value diverged from repo' {
        $cur = '{"env":{"X":"2"}}'
        $src = '{"env":{"X":"1"}}'
        $out = Remove-ManagedSettingsKeys -CurrentJson $cur -SourceJson $src -WhitelistKeys @('env')
        ($out | ConvertFrom-Json).env.X | Should -Be '2'
    }
}

Describe 'uninstall.ps1 CLI' {
    It 'prints usage with -Help and exits 0' {
        $u = Join-Path $PSScriptRoot '..' 'uninstall.ps1'
        $out = pwsh -NoProfile -File $u -Help
        $LASTEXITCODE | Should -Be 0
        ($out -join "`n") | Should -Match 'Usage'
    }
    It 'rejects -KeepTools with -Purge' -Skip:(-not $OnWindows) {
        $u = Join-Path $PSScriptRoot '..' 'uninstall.ps1'
        pwsh -NoProfile -File $u -KeepTools -Purge | Out-Null
        $LASTEXITCODE | Should -Be 1
    }
    It 'runs a dry-run to completion and exits 0' -Skip:(-not $OnWindows) {
        $u = Join-Path $PSScriptRoot '..' 'uninstall.ps1'
        pwsh -NoProfile -File $u -DryRun -AutoYes | Out-Null
        $LASTEXITCODE | Should -Be 0
    }
}

Describe 'module Uninstall-* functions are defined' {
    BeforeAll {
        $env:ENVSETUP_UNINSTALL_NORUN = '1'
        Import-Module "$PSScriptRoot/../lib/Uninstall.psm1" -Force
    }
    AfterAll { $env:ENVSETUP_UNINSTALL_NORUN = $null }

    $cases = @(
        @{ M = '01-Core';        Fn = 'Uninstall-Core' }
        @{ M = '02-Languages';   Fn = 'Uninstall-Languages' }
        @{ M = '03-PythonTools'; Fn = 'Uninstall-PythonTools' }
        @{ M = '05-CliTools';    Fn = 'Uninstall-CliTools' }
        @{ M = '06-Shell';       Fn = 'Uninstall-Shell' }
        @{ M = '07-Multiplexer'; Fn = 'Uninstall-Multiplexer' }
        @{ M = '08-ClaudeCode';  Fn = 'Uninstall-ClaudeCode' }
        @{ M = '09-UserDirs';    Fn = 'Uninstall-UserDirs' }
    )
    It '<M> defines <Fn>' -ForEach $cases {
        . (Join-Path $PSScriptRoot '..' "modules/$M.ps1")
        Get-Command $Fn -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
}
