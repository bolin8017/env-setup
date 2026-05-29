BeforeAll {
    Import-Module "$PSScriptRoot/../lib/Config.psm1" -Force
    $script:Yaml = @'
general:
  auto_yes: true
  dry_run: false
languages:
  python:
    version: "3.12"
cli_tools:
  btop: true
windows:
  windows_terminal: true
  powershell:
    modules:
      - Terminal-Icons
      - PSFzf
      - posh-git
'@
    $script:Fixture = Join-Path $TestDrive 'config.yaml'
    Set-Content -Path $script:Fixture -Value $script:Yaml -Encoding utf8
    Import-Config -Path $script:Fixture
}

Describe 'Get-CfgValue' {
    It 'reads a top-level nested scalar' {
        Get-CfgValue 'languages.python.version' | Should -Be '3.12'
    }
    It 'reads a boolean as its string form' {
        Get-CfgValue 'general.auto_yes' | Should -Be 'true'
    }
    It 'returns empty string for a missing key' {
        Get-CfgValue 'does.not.exist' | Should -Be ''
    }
}

Describe 'Test-CfgEnabled' {
    It 'true for a true boolean' { Test-CfgEnabled 'cli_tools.btop' | Should -BeTrue }
    It 'false for a false boolean' { Test-CfgEnabled 'general.dry_run' | Should -BeFalse }
    It 'false for a missing key' { Test-CfgEnabled 'nope.nope' | Should -BeFalse }
}

Describe 'Get-CfgList' {
    It 'returns sequence items in order' {
        Get-CfgList 'windows.powershell.modules' | Should -Be @('Terminal-Icons','PSFzf','posh-git')
    }
    It 'returns an empty array for a missing list' {
        (Get-CfgList 'no.such.list').Count | Should -Be 0
    }
}

Describe 'Import-Config env overrides' {
    AfterEach { $env:NODE_VERSION = $null }
    It 'NODE_VERSION overrides languages.node.version' {
        $env:NODE_VERSION = '22.0.0'
        Import-Config -Path $script:Fixture
        Get-CfgValue 'languages.node.version' | Should -Be '22.0.0'
    }
}
