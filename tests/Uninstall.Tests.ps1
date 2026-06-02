# Pester 5: all setup/teardown lives inside Describe/Context blocks.

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
