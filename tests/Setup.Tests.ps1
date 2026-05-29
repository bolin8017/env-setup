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
