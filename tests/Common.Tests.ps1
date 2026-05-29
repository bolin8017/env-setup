BeforeAll {
    Import-Module "$PSScriptRoot/../lib/Common.psm1" -Force
}

Describe 'Test-Command' {
    It 'is true for an existing command' {
        Test-Command 'Get-Command' | Should -BeTrue
    }
    It 'is false for a missing command' {
        Test-Command 'definitely-not-a-real-cmd-xyz' | Should -BeFalse
    }
}

Describe 'Test-IsWindows' {
    It 'returns a boolean' {
        Test-IsWindows | Should -BeOfType [bool]
    }
}

Describe 'flag helpers read ENVSETUP_* env vars' {
    AfterEach { $env:ENVSETUP_DRY_RUN = $null; $env:ENVSETUP_AUTO_YES = $null }
    It 'Test-DryRun true when env is true' {
        $env:ENVSETUP_DRY_RUN = 'true'
        Test-DryRun | Should -BeTrue
    }
    It 'Test-DryRun false when env unset' {
        Test-DryRun | Should -BeFalse
    }
    It 'Confirm-Action auto-confirms under AutoYes' {
        $env:ENVSETUP_AUTO_YES = 'true'
        Confirm-Action 'anything?' | Should -BeTrue
    }
}
