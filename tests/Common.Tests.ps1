BeforeDiscovery {
    # $env:OS is 'Windows_NT' on BOTH Windows PowerShell 5.1 and pwsh-on-Windows,
    # and reading it is StrictMode-safe — unlike the $IsWindows automatic variable,
    # which is unset on 5.1. Used to gate the 5.1-only regression test below.
    $onWindows = ($env:OS -eq 'Windows_NT')
}

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

    It 'is StrictMode-safe on Windows PowerShell 5.1 (regression)' -Skip:(-not $onWindows) {
        # Regression for the VariableIsUndefined crash: on Windows PowerShell 5.1
        # the $IsWindows automatic variable is *unset* (it exists only on pwsh 6+),
        # so the old `if ($null -ne $IsWindows)` guard threw under StrictMode. CI
        # runs this suite under pwsh (Core), where $IsWindows exists and the bug is
        # invisible — so reproduce the real engine by shelling out to powershell.exe
        # (5.1 is always present on Windows). Old code => non-zero exit; fix => 0.
        $module = (Resolve-Path "$PSScriptRoot/../lib/Common.psm1").Path
        $probe  = "Set-StrictMode -Version Latest; Import-Module '$module' -Force; if ((Test-IsWindows) -isnot [bool]) { exit 2 }"
        $out = & powershell.exe -NoProfile -NonInteractive -Command $probe 2>&1
        $LASTEXITCODE | Should -Be 0 -Because "powershell.exe (5.1) output: $out"
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
