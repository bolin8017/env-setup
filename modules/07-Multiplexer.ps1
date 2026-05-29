#!/usr/bin/env pwsh
# 07-Multiplexer.ps1 — zellij (the tmux role on native Windows) + config/layout.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/../lib/Common.psm1"
Import-Module "$PSScriptRoot/../lib/Config.psm1"
Import-Module "$PSScriptRoot/../lib/Package.psm1"
Import-Module "$PSScriptRoot/../lib/DryRun.psm1"

function Install-Multiplexer {
    Write-Header 'Multiplexer (zellij)'
    if (-not (Test-CfgEnabled 'windows.multiplexer.zellij')) {
        Write-Info 'zellij disabled — skipping'
        return
    }
    Install-Pkg -Name 'zellij'

    $cfg = (Resolve-Path (Join-Path $PSScriptRoot '../configs/zellij')).Path
    $dest = if ($env:APPDATA) { Join-Path $env:APPDATA 'zellij' } else { Join-Path $HOME '.config/zellij' }
    New-DirOrDryRun -Path $dest
    New-DirOrDryRun -Path (Join-Path $dest 'layouts')
    Deploy-Config -Source (Join-Path $cfg 'config.kdl') -Destination (Join-Path $dest 'config.kdl') -Label 'zellij config.kdl'
    Deploy-Config -Source (Join-Path $cfg 'dev-layout.kdl') -Destination (Join-Path $dest 'layouts/dev-layout.kdl') -Label 'zellij dev layout'
}
