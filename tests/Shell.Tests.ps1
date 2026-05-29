BeforeAll {
    Import-Module "$PSScriptRoot/../lib/Common.psm1"
    Import-Module "$PSScriptRoot/../lib/Config.psm1"
    Import-Module "$PSScriptRoot/../lib/Package.psm1"
    Import-Module "$PSScriptRoot/../lib/DryRun.psm1"
    Import-Module "$PSScriptRoot/../lib/Backup.psm1"
    Import-Module "$PSScriptRoot/../lib/WindowsTerminal.psm1"
    . "$PSScriptRoot/../modules/06-Shell.ps1"
}

Describe 'Build-Profile' {
    BeforeEach { $env:ENVSETUP_DRY_RUN = $null; $env:ENVSETUP_AUTO_YES = 'true' }
    AfterEach  { $env:ENVSETUP_DRY_RUN = $null; $env:ENVSETUP_AUTO_YES = $null }

    It 'deploys the profile base, all fragments, and aliases' {
        $prof = Join-Path $TestDrive 'pwsh/Microsoft.PowerShell_profile.ps1'
        $frag = Join-Path $TestDrive 'pwsh/fragments'
        Build-Profile -ProfilePath $prof -FragmentsDir $frag
        Test-Path $prof | Should -BeTrue
        (Get-Content -Raw $prof) | Should -Match 'fragments'
        (@(Get-ChildItem $frag -Filter *.ps1)).Count | Should -BeGreaterThan 4
        Test-Path (Join-Path $TestDrive 'pwsh/aliases.ps1') | Should -BeTrue
    }
}

Describe 'Install-Shell dispatch' {
    BeforeEach {
        $env:ENVSETUP_DRY_RUN = 'true'
        $yaml = @'
windows:
  windows_terminal: true
  powershell:
    modules:
      - Terminal-Icons
'@
        $f = Join-Path $TestDrive 'c.yaml'; Set-Content -Path $f -Value $yaml
        Import-Config -Path $f
        Mock Install-App { }
    }
    AfterEach { $env:ENVSETUP_DRY_RUN = $null }

    It 'requests PowerShell 7 and Oh My Posh' {
        Install-Shell
        Should -Invoke Install-App -ParameterFilter { $Id -eq 'Microsoft.PowerShell' }
        Should -Invoke Install-App -ParameterFilter { $Id -eq 'JanDeDobbeleer.OhMyPosh' }
    }
    It 'does not throw under dry-run' { { Install-Shell } | Should -Not -Throw }
}
