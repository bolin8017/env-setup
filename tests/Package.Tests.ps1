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
