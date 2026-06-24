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
single:
  one_item:
    - solo
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
    It 'returns a single-element list as a 1-item array (item not lost)' {
        # Consumers wrap with @() (see 08-ClaudeCode); the bug returned @() (empty)
        # because Get-CfgNode unrolled the count-1 list to a scalar.
        $r = @(Get-CfgList 'single.one_item')
        $r.Count | Should -Be 1
        $r[0] | Should -Be 'solo'
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

Describe 'ConvertFrom-SimpleYaml edge cases' {
    BeforeAll {
        $edge = @'
general:

  auto_yes: true        # inline comment on a value

shell:
  plugins:
    builtin:
      - git              # inline comment on a list item
      - extract
  oh_my_zsh: true        # sibling key AFTER a list
theme:
  name: "a # b"          # quoted value containing # must survive
'@
        $f = Join-Path $TestDrive 'edge.yaml'
        Set-Content -Path $f -Value $edge -Encoding utf8
        Import-Config -Path $f
    }
    It 'tolerates blank lines and strips inline comments on values' {
        Get-CfgValue 'general.auto_yes' | Should -Be 'true'
    }
    It 'strips inline comments on list items' {
        Get-CfgList 'shell.plugins.builtin' | Should -Be @('git', 'extract')
    }
    It 'keeps a sibling key that follows a list (list does not swallow it)' {
        Test-CfgEnabled 'shell.oh_my_zsh' | Should -BeTrue
    }
    It 'preserves a # inside a quoted value (quote-aware comment strip)' {
        Get-CfgValue 'theme.name' | Should -Be 'a # b'
    }
}

Describe 'Import-Config on the repo config.yaml' {
    It 'parses the real config (which contains blank lines) without throwing' {
        $repo = Join-Path $PSScriptRoot '../config.yaml'
        { Import-Config -Path $repo } | Should -Not -Throw
        Test-CfgEnabled 'windows.windows_terminal' | Should -BeTrue
    }
}
