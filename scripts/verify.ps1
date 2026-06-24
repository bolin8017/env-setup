#!/usr/bin/env pwsh
# verify.ps1 - post-install check of the Windows engine's tools (analog of verify.sh).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/../lib/Common.psm1"

$checks = @(
    @{ Name = 'PowerShell 7'; Cmd = 'pwsh' }
    @{ Name = 'git';          Cmd = 'git' }
    @{ Name = 'scoop';        Cmd = 'scoop' }
    @{ Name = 'Oh My Posh';   Cmd = 'oh-my-posh' }
    @{ Name = 'zoxide';       Cmd = 'zoxide' }
    @{ Name = 'ripgrep';      Cmd = 'rg' }
    @{ Name = 'zellij';       Cmd = 'zellij' }
    @{ Name = 'claude';       Cmd = 'claude' }
)

Write-Header 'Verification'
$missing = 0
foreach ($c in $checks) {
    if (Test-Command $c.Cmd) { Write-Success "$($c.Name) ($($c.Cmd))" }
    else { Write-Warn "$($c.Name) ($($c.Cmd)) not found"; $missing++ }
}
Write-Host ''
if ($missing -gt 0) { Write-Warn "$missing tool(s) missing"; exit 1 }
Write-Success 'All checked tools present'
