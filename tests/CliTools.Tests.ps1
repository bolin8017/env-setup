BeforeAll {
    Import-Module "$PSScriptRoot/../lib/Common.psm1"
    Import-Module "$PSScriptRoot/../lib/Config.psm1"
    Import-Module "$PSScriptRoot/../lib/Package.psm1"
    . "$PSScriptRoot/../modules/05-CliTools.ps1"
}

Describe 'Get-CliScoopPackage' {
    It 'maps btop to bottom (no native btop on Windows)' { Get-CliScoopPackage -Key 'btop' | Should -Be 'bottom' }
    It 'maps tldr to tealdeer' { Get-CliScoopPackage -Key 'tldr' | Should -Be 'tealdeer' }
    It 'is identity for tools with native builds' { Get-CliScoopPackage -Key 'ripgrep' | Should -Be 'ripgrep' }
    It 'is identity for an unknown key' { Get-CliScoopPackage -Key 'whatever' | Should -Be 'whatever' }
}

Describe 'Install-CliTools dispatch' {
    BeforeEach {
        # Throwaway config: only ripgrep + btop enabled, bat disabled.
        $yaml = "cli_tools:`n  ripgrep: true`n  bat: false`n  btop: true`n"
        $f = Join-Path $TestDrive 'c.yaml'; Set-Content $f $yaml
        Import-Config -Path $f
        # Install-CliTools runs in this (dot-sourced) scope, so mock here — not -ModuleName.
        Mock Install-Pkg { }
    }
    It 'installs only enabled tools and applies the mapping' {
        Install-CliTools
        Should -Invoke Install-Pkg -Times 1 -ParameterFilter { $Name -eq 'ripgrep' }
        Should -Invoke Install-Pkg -Times 1 -ParameterFilter { $Name -eq 'bottom' }   # btop -> bottom
        Should -Invoke Install-Pkg -Times 0 -ParameterFilter { $Name -eq 'bat' }      # disabled
    }
}
