BeforeAll {
    Import-Module "$PSScriptRoot/../lib/Common.psm1" -Force
    Import-Module "$PSScriptRoot/../lib/DryRun.psm1" -Force
    Import-Module "$PSScriptRoot/../lib/Package.psm1" -Force
}

Describe 'missing-admin bookkeeping' {
    BeforeEach { Clear-MissingAdmin }
    It 'records and de-dupes packages' {
        Add-MissingAdminPackage 'Foo.Bar'
        Add-MissingAdminPackage 'Foo.Bar'
        Add-MissingAdminPackage 'Baz.Qux'
        (Get-MissingAdminPackage) | Should -Be @('Foo.Bar','Baz.Qux')
    }
    It 'starts empty after Clear' {
        (Get-MissingAdminPackage).Count | Should -Be 0
    }
}

Describe 'Install-App under dry-run records nothing and runs nothing' {
    AfterEach { $env:ENVSETUP_DRY_RUN = $null }
    BeforeEach { Clear-MissingAdmin }
    It 'prints intent without invoking winget' {
        $env:ENVSETUP_DRY_RUN = 'true'
        { Install-App -Id 'Some.App' } | Should -Not -Throw
        (Get-MissingAdminPackage).Count | Should -Be 0
    }
}

Describe 'Install-App no-admin defer' {
    AfterEach { $env:ENVSETUP_DRY_RUN = $null }
    BeforeEach { Clear-MissingAdmin }
    It 'records the package when RequiresAdmin and not elevated' {
        $env:ENVSETUP_DRY_RUN = $null        # not dry-run
        # Force the not-elevated path regardless of the runner's real elevation
        # (GitHub's Windows runner runs elevated), so winget is never invoked.
        Mock -ModuleName Package Test-Elevated { $false }
        Install-App -Id 'Some.App' -RequiresAdmin
        (Get-MissingAdminPackage) | Should -Be @('Some.App')
    }
}

Describe 'Test-WingetSucceeded' {
    It 'treats a fresh install (0) as success' { Test-WingetSucceeded 0 | Should -BeTrue }
    It 'treats "already current" 0x8A15002B (-1978335189) as success' {
        Test-WingetSucceeded -1978335189 | Should -BeTrue
    }
    It 'treats a real failure code as failure' { Test-WingetSucceeded 1 | Should -BeFalse }
    It 'treats another winget error code as failure' { Test-WingetSucceeded -1978335212 | Should -BeFalse }
}

Describe 'Install-Pkg surfaces failure instead of silently succeeding' {
    AfterEach { $env:ENVSETUP_DRY_RUN = $null }
    It 'is a no-op under dry-run' {
        $env:ENVSETUP_DRY_RUN = 'true'
        { Install-Pkg -Name 'ripgrep' } | Should -Not -Throw
    }
    It 'throws when scoop is unavailable (not dry-run)' {
        $env:ENVSETUP_DRY_RUN = $null
        # Force the unavailable path so the test is hermetic even on a dev box
        # that actually has scoop (a real `scoop install` must never run here).
        Mock -ModuleName Package Test-ScoopAvailable { $false }
        { Install-Pkg -Name 'ripgrep' } | Should -Throw
    }
}

Describe 'Install-Pkg gates on scoop exit code' {
    AfterEach {
        $env:ENVSETUP_DRY_RUN = $null
        Remove-Item function:global:scoop -ErrorAction Ignore
    }
    It 'throws when scoop exits non-zero' {
        $env:ENVSETUP_DRY_RUN = $null
        # A global function shadows any real scoop, so this runs nothing real
        # and also satisfies Test-ScoopAvailable on scoop-less CI runners.
        function global:scoop { $global:LASTEXITCODE = 1; "Couldn't find manifest" }
        { Install-Pkg -Name 'no-such-pkg' } | Should -Throw -ExpectedMessage '*exit 1*'
    }
    It 'does not throw when scoop exits zero (fresh or already installed)' {
        $env:ENVSETUP_DRY_RUN = $null
        function global:scoop { $global:LASTEXITCODE = 0; 'ok' }
        { Install-Pkg -Name 'fine-pkg' } | Should -Not -Throw
    }
}
