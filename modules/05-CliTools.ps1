#!/usr/bin/env pwsh
# 05-CliTools.ps1 — modern CLI tools via scoop, with same-role Windows mappings.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/../lib/Common.psm1"
Import-Module "$PSScriptRoot/../lib/Config.psm1"
Import-Module "$PSScriptRoot/../lib/Package.psm1"

# cli_tools config key -> scoop package. Identity unless Windows needs a
# different tool for the same role (no native btop; tldr client = tealdeer).
$script:CliToolMap = [ordered]@{
    fzf = 'fzf'; ripgrep = 'ripgrep'; bat = 'bat'; fd = 'fd'; eza = 'eza'
    zoxide = 'zoxide'; jq = 'jq'; btop = 'bottom'; tldr = 'tealdeer'
    tree = 'tree'; httpie = 'httpie'
}

function Get-CliScoopPackage {
    param([Parameter(Mandatory)][string]$Key)
    if ($script:CliToolMap.Contains($Key)) { return $script:CliToolMap[$Key] }
    return $Key
}

function Install-CliTools {
    Write-Header 'CLI tools'
    foreach ($key in $script:CliToolMap.Keys) {
        if (Test-CfgEnabled "cli_tools.$key") {
            Install-Pkg -Name (Get-CliScoopPackage -Key $key)
        }
    }
}
