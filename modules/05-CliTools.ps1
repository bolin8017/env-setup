#!/usr/bin/env pwsh
# 05-CliTools.ps1 - modern CLI tools via scoop, with same-role Windows mappings.
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
}

# cli_tools keys with no scoop manifest on Windows. Listing them here instead of
# mapping them in CliToolMap avoids scoop's "Couldn't find manifest for ..."
# noise; Install-CliTools prints the alternative when the key is enabled.
$script:CliToolWindowsSkip = [ordered]@{
    tree   = 'use the built-in `tree` or `eza --tree`'
    httpie = 'install with `pipx install httpie` after Python is set up'
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
    foreach ($key in $script:CliToolWindowsSkip.Keys) {
        if (Test-CfgEnabled "cli_tools.$key") {
            Write-Info "Skipping '$key' on Windows (no scoop manifest) - $($script:CliToolWindowsSkip[$key])"
        }
    }
}

function Uninstall-CliTools {
    Write-Header 'Uninstall: CLI tools'
    if (Test-Purge) {
        foreach ($key in $script:CliToolMap.Keys) {
            Remove-Pkg -Name (Get-CliScoopPackage -Key $key)
        }
    } else {
        Write-Info 'CLI tools are scoop packages - use -Purge to remove them'
    }
}
