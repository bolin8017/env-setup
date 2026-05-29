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

Describe 'Install-Pkg surfaces failure instead of silently succeeding' {
    AfterEach { $env:ENVSETUP_DRY_RUN = $null }
    It 'is a no-op under dry-run' {
        $env:ENVSETUP_DRY_RUN = 'true'
        { Install-Pkg -Name 'ripgrep' } | Should -Not -Throw
    }
    It 'throws when scoop is unavailable (not dry-run)' {
        $env:ENVSETUP_DRY_RUN = $null
        # Neither this Linux dev box nor the windows-latest runner has scoop,
        # so Test-ScoopAvailable is false and Install-Pkg throws before any
        # real install — never silently reporting success.
        { Install-Pkg -Name 'ripgrep' } | Should -Throw
    }
}
