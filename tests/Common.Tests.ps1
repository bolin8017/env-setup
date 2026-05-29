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

Describe 'dependent-module imports keep Common in the caller scope' {
    # Regression: a -Force re-import of Common from inside Package/DryRun used to
    # Remove-Module Common and strip its functions from the importing script
    # (setup.ps1 then failed with "Assert-Windows is not recognized").
    It 'Common functions stay callable after importing Config and Package' {
        Import-Module "$PSScriptRoot/../lib/Common.psm1" -Force
        Import-Module "$PSScriptRoot/../lib/Config.psm1" -Force
        Import-Module "$PSScriptRoot/../lib/Package.psm1" -Force
        { Test-IsWindows } | Should -Not -Throw
        Get-Command Assert-Windows -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
}
