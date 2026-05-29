#!/usr/bin/env pwsh
# 06-Shell.ps1 — PowerShell 7, Oh My Posh, PSGallery modules, $PROFILE assembly
# (from configs/pwsh fragments), and a gated Windows Terminal font merge.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/../lib/Common.psm1"
Import-Module "$PSScriptRoot/../lib/Config.psm1"
Import-Module "$PSScriptRoot/../lib/Package.psm1"
Import-Module "$PSScriptRoot/../lib/DryRun.psm1"
Import-Module "$PSScriptRoot/../lib/Backup.psm1"
Import-Module "$PSScriptRoot/../lib/WindowsTerminal.psm1"

function Install-PsModule {
    param([Parameter(Mandatory)][string]$Name)
    if (Test-DryRun) { Write-Info "[DRY-RUN] Would run: Install-Module $Name -Scope CurrentUser"; return }
    if (Get-Module -ListAvailable $Name) { return }
    try { Install-Module $Name -Scope CurrentUser -Force -AcceptLicense }
    catch { Write-Warn "Failed to install module ${Name}: $_" }
}

function Build-Profile {
    # Deploy the $PROFILE skeleton + numbered fragments (mirrors deploy_shell_config).
    param(
        [Parameter(Mandatory)][string]$ProfilePath,
        [Parameter(Mandatory)][string]$FragmentsDir
    )
    $cfg = (Resolve-Path (Join-Path $PSScriptRoot '../configs')).Path
    New-DirOrDryRun -Path (Split-Path $ProfilePath -Parent)
    New-DirOrDryRun -Path $FragmentsDir
    Deploy-Config -Source (Join-Path $cfg 'pwsh.profile.base') -Destination $ProfilePath -Label 'PowerShell profile'
    Get-ChildItem (Join-Path $cfg 'pwsh') -Filter *.ps1 | Sort-Object Name | ForEach-Object {
        Copy-OrDryRun -Source $_.FullName -Destination (Join-Path $FragmentsDir $_.Name)
    }
    $aliasDest = Join-Path (Split-Path $FragmentsDir -Parent) 'aliases.ps1'
    Deploy-Config -Source (Join-Path $cfg 'aliases.ps1') -Destination $aliasDest -Label 'aliases.ps1'
}

function Set-WindowsTerminalFont {
    if (-not $env:LOCALAPPDATA) { Write-Info 'No LOCALAPPDATA — skipping Windows Terminal config'; return }
    $wt = Join-Path $env:LOCALAPPDATA 'Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json'
    if (-not (Test-Path $wt)) { Write-Info 'Windows Terminal settings not found — skipping font config'; return }
    if (Test-DryRun) { Write-Info "[DRY-RUN] Would merge Nerd Font into $wt"; return }
    Backup-File -Path $wt -Stamp (Get-Date -Format 'yyyyMMdd_HHmmss') | Out-Null
    $merged = Merge-WtSettings -CurrentJson (Get-Content -Raw -LiteralPath $wt) -FontFace 'MesloLGS NF'
    Set-Content -LiteralPath $wt -Value $merged -Encoding utf8
    Write-Success 'Configured Windows Terminal font'
}

function Install-Shell {
    Write-Header 'Shell (PowerShell 7 + Oh My Posh)'
    Install-App -Id 'Microsoft.PowerShell'
    Install-App -Id 'JanDeDobbeleer.OhMyPosh'
    foreach ($m in (Get-CfgList 'windows.powershell.modules')) { Install-PsModule -Name $m }

    $cfg = (Resolve-Path (Join-Path $PSScriptRoot '../configs')).Path
    $ompName = Get-CfgValue 'windows.powershell.omp_theme'
    if (-not $ompName) { $ompName = 'envsetup.omp.json' }
    New-DirOrDryRun -Path (Join-Path $HOME '.config/oh-my-posh')
    Deploy-Config -Source (Join-Path $cfg "omp/$ompName") -Destination (Join-Path $HOME ".config/oh-my-posh/$ompName") -Label 'Oh My Posh theme'

    Build-Profile -ProfilePath $PROFILE.CurrentUserAllHosts -FragmentsDir (Join-Path $HOME '.config/powershell/fragments')

    if (Test-CfgEnabled 'windows.windows_terminal') { Set-WindowsTerminalFont }
}
