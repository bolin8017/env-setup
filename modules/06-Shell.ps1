#!/usr/bin/env pwsh
# 06-Shell.ps1 — PowerShell 7, Oh My Posh, PSGallery modules, $PROFILE assembly
# (from configs/pwsh fragments), and a gated Windows Terminal font merge.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/../lib/Common.psm1"
Import-Module "$PSScriptRoot/../lib/Config.psm1"
Import-Module "$PSScriptRoot/../lib/Package.psm1"
Import-Module "$PSScriptRoot/../lib/DryRun.psm1" -DisableNameChecking  # WinPS 5.1: 'Deploy' is an unapproved verb
Import-Module "$PSScriptRoot/../lib/Backup.psm1"
Import-Module "$PSScriptRoot/../lib/WindowsTerminal.psm1"

function Install-PsModule {
    param([Parameter(Mandatory)][string]$Name)
    if (Test-DryRun) { Write-Info "[DRY-RUN] Would run: Install-Module $Name -Scope CurrentUser"; return }
    if (Get-Module -ListAvailable $Name) { return }
    # -AcceptLicense was added in PowerShellGet 1.6.0. Windows PowerShell 5.1 ships
    # 1.0.0.1, which rejects it ("A parameter cannot be found that matches parameter
    # name 'AcceptLicense'") and the install fails. Pass it only where supported so
    # both 5.1 and pwsh 7 install cleanly.
    $params = @{ Scope = 'CurrentUser'; Force = $true }
    if ((Get-Command Install-Module).Parameters.ContainsKey('AcceptLicense')) { $params['AcceptLicense'] = $true }
    try { Install-Module $Name @params }
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

function Enable-SessionFonts {
    # Make freshly-registered fonts usable in the CURRENT login session without a
    # sign-out. Copying the .ttf and writing the HKCU registry key persists the
    # font, but the live GDI/DirectWrite font tables are only rebuilt at next
    # logon — so a fresh box keeps showing "couldn't find MesloLGS NF" until the
    # user signs out. AddFontResourceW loads each file into the session font
    # table; a WM_FONTCHANGE broadcast asks running apps to re-enumerate.
    # Best-effort and idempotent.
    param([Parameter(Mandatory)][string[]]$Path)
    if (-not ([System.Management.Automation.PSTypeName]'EnvSetup.NativeFont').Type) {
        Add-Type -Namespace EnvSetup -Name NativeFont -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("gdi32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern int AddFontResourceW(string lpFileName);
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern System.IntPtr SendMessageTimeout(System.IntPtr hWnd, uint Msg, System.IntPtr wParam, System.IntPtr lParam, uint flags, uint timeout, out System.IntPtr result);
'@
    }
    foreach ($p in $Path) {
        if (Test-Path -LiteralPath $p) { [void][EnvSetup.NativeFont]::AddFontResourceW($p) }
    }
    # HWND_BROADCAST = 0xFFFF, WM_FONTCHANGE = 0x001D, SMTO_ABORTIFHUNG = 0x0002
    $res = [IntPtr]::Zero
    [void][EnvSetup.NativeFont]::SendMessageTimeout([IntPtr]0xFFFF, 0x001D, [IntPtr]::Zero, [IntPtr]::Zero, 2, 1000, [ref]$res)
}

function Install-NerdFont {
    # The Oh My Posh prompt and the Windows Terminal face we set both need
    # MesloLGS NF, but nothing here installed it — so a fresh box shows
    # "couldn't find MesloLGS NF" and renders prompt glyphs as tofu. Install the
    # exact "MesloLGS NF" family (Powerlevel10k's fonts, whose face name matches
    # what Set-WindowsTerminalFont writes) per-user: no admin, no name guessing.
    if (Test-DryRun) { Write-Info '[DRY-RUN] Would install the MesloLGS NF Nerd Font'; return }
    if (-not $env:LOCALAPPDATA) { Write-Info 'No LOCALAPPDATA — skipping Nerd Font install'; return }
    $fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    $regKey  = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
    $base    = 'https://github.com/romkatv/powerlevel10k-media/raw/master'
    $files   = 'MesloLGS NF Regular.ttf', 'MesloLGS NF Bold.ttf',
               'MesloLGS NF Italic.ttf', 'MesloLGS NF Bold Italic.ttf'
    try {
        # WinPS 5.1 defaults to TLS 1.0 for web requests; GitHub requires 1.2.
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        New-Item -ItemType Directory -Path $fontDir -Force | Out-Null
        $added = 0
        foreach ($f in $files) {
            $dest = Join-Path $fontDir $f
            if (-not (Test-Path -LiteralPath $dest)) {
                Invoke-WebRequest -UseBasicParsing -Uri "$base/$([uri]::EscapeDataString($f))" -OutFile $dest
                $added++
            }
            # Register per-user so Windows Terminal resolves the face by name.
            $face = [IO.Path]::GetFileNameWithoutExtension($f)
            New-ItemProperty -Path $regKey -Name "$face (TrueType)" -Value $dest -PropertyType String -Force | Out-Null
        }
        # Activate in the current session so glyphs render without a sign-out.
        Enable-SessionFonts -Path ($files | ForEach-Object { Join-Path $fontDir $_ })
        if ($added -gt 0) { Write-Success "Installed MesloLGS NF ($added file(s)) — open a new terminal to apply" }
        else { Write-Info 'MesloLGS NF already installed (re-activated for this session)' }
    } catch {
        Write-Warn "Could not install MesloLGS NF (prompt glyphs may not render): $_"
    }
}

function Initialize-PSGallery {
    # The first Install-Module on Windows PowerShell 5.1 interactively prompts to
    # bootstrap the NuGet provider and to trust PSGallery, which hangs an
    # unattended bootstrap. Provision both non-interactively up front; pwsh 7
    # ships the provider so this is effectively a no-op there.
    if (Test-DryRun) { return }
    try {
        if (-not (Get-PackageProvider -Name NuGet -ErrorAction Ignore)) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
        }
        if ((Get-PSRepository -Name PSGallery -ErrorAction Ignore).InstallationPolicy -ne 'Trusted') {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        }
    } catch { Write-Warn "Could not pre-provision NuGet/PSGallery (module installs may prompt): $_" }
}

function Install-Shell {
    Write-Header 'Shell (PowerShell 7 + Oh My Posh)'
    Install-App -Id 'Microsoft.PowerShell'
    Install-App -Id 'JanDeDobbeleer.OhMyPosh'
    Initialize-PSGallery
    foreach ($m in (Get-CfgList 'windows.powershell.modules')) { Install-PsModule -Name $m }

    $cfg = (Resolve-Path (Join-Path $PSScriptRoot '../configs')).Path
    $ompName = Get-CfgValue 'windows.powershell.omp_theme'
    if (-not $ompName) { $ompName = 'envsetup.omp.json' }
    New-DirOrDryRun -Path (Join-Path $HOME '.config/oh-my-posh')
    Deploy-Config -Source (Join-Path $cfg "omp/$ompName") -Destination (Join-Path $HOME ".config/oh-my-posh/$ompName") -Label 'Oh My Posh theme'

    Build-Profile -ProfilePath $PROFILE.CurrentUserAllHosts -FragmentsDir (Join-Path $HOME '.config/powershell/fragments')

    Install-NerdFont
    if (Test-CfgEnabled 'windows.windows_terminal') { Set-WindowsTerminalFont }
}
