# Top-level code runs during Pester discovery, so $OnWindows is available to -Skip.
# Reuse the engine's own platform check instead of duplicating its logic.
Import-Module "$PSScriptRoot/../lib/Common.psm1" -Force
$OnWindows = Test-IsWindows

Describe 'setup.ps1 smoke' {
    # setup.ps1 calls Assert-Windows, so the dry-run only runs on Windows
    # (e.g. the windows-latest CI lane). It is skipped on macOS/Linux dev boxes.
    It 'runs a dry-run to completion and exits 0' -Skip:(-not $OnWindows) {
        $setup = Join-Path $PSScriptRoot '..' 'setup.ps1'
        pwsh -NoProfile -File $setup -DryRun -AutoYes | Out-Null
        $LASTEXITCODE | Should -Be 0
    }
    It 'prints usage with -Help and exits 0' {
        # -Help returns before the Windows guard, so this runs on any platform.
        $setup = Join-Path $PSScriptRoot '..' 'setup.ps1'
        $out = pwsh -NoProfile -File $setup -Help
        $LASTEXITCODE | Should -Be 0
        ($out -join "`n") | Should -Match 'Usage'
    }
}

Describe 'Test-ModuleInFilter' {
    BeforeAll {
        # Dot-source setup.ps1 for its helpers without running the installer.
        $env:ENVSETUP_SETUP_NORUN = '1'
        . (Join-Path $PSScriptRoot '..' 'setup.ps1')
    }
    AfterAll { $env:ENVSETUP_SETUP_NORUN = $null }

    It 'an empty filter selects everything' {
        Test-ModuleInFilter -Name '06-Shell' -Filter @() | Should -BeTrue
    }
    It 'matches an exact full name' {
        Test-ModuleInFilter -Name '06-Shell' -Filter @('06-Shell') | Should -BeTrue
    }
    It 'matches a numeric prefix (06 -> 06-Shell)' {
        Test-ModuleInFilter -Name '06-Shell' -Filter @('06') | Should -BeTrue
    }
    It 'does not match an unrelated entry' {
        Test-ModuleInFilter -Name '06-Shell' -Filter @('01') | Should -BeFalse
    }
    It 'treats a wildcard-metachar entry literally without throwing' {
        { Test-ModuleInFilter -Name '06-Shell' -Filter @('[0') } | Should -Not -Throw
        Test-ModuleInFilter -Name '06-Shell' -Filter @('[0') | Should -BeFalse
    }
}
