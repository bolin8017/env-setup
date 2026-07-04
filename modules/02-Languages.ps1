#!/usr/bin/env pwsh
# 02-Languages.ps1 - nvm-windows + uv-managed Python. PATH wiring comes from the
# scoop manifests: nvm registers a shim; uv's manifest persists the python/tools
# shim dirs (UV_PYTHON_BIN_DIR et al.) and adds them to the user PATH.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/../lib/Common.psm1"
Import-Module "$PSScriptRoot/../lib/Config.psm1"
Import-Module "$PSScriptRoot/../lib/Package.psm1"
Import-Module "$PSScriptRoot/../lib/Uninstall.psm1"

function Get-NvmSettingValue {
    # nvm-windows keeps root/path in settings.txt next to nvm.exe; scoop's
    # manifest omits 'path:' and pins the link via the NVM_SYMLINK env var.
    param(
        [Parameter(Mandatory)][string]$Key,
        [string]$NvmHome = $env:NVM_HOME
    )
    if (-not $NvmHome) { return $null }
    $settings = Join-Path $NvmHome 'settings.txt'
    if (-not (Test-Path $settings)) { return $null }
    $m = Select-String -Path $settings -Pattern "^${Key}:\s*(\S.*?)\s*$" | Select-Object -First 1
    if ($m) { return $m.Matches[0].Groups[1].Value }
    return $null
}

function Test-NodeActivation {
    # 'nvm use' exits 0 even when it cannot create the node symlink (no
    # Developer Mode, no elevation), so exit codes never catch the failure.
    # Look for node.exe at the symlink target instead. Unknowable location
    # -> $true, so we never cry wolf.
    param(
        [string]$NvmHome = $env:NVM_HOME,
        [string]$Symlink = $env:NVM_SYMLINK
    )
    $link = Get-NvmSettingValue -Key 'path' -NvmHome $NvmHome
    if (-not $link) { $link = $Symlink }
    if (-not $link) { return $true }
    return [bool](Test-Path (Join-Path $link 'node.exe'))
}

function Repair-NodeActivation {
    # Junctions need no privilege on NTFS (scoop's own 'current' links rely
    # on this), so when nvm's symlink silently failed, link the version dir
    # with a junction instead. nvm happily removes/replaces it on the next
    # 'nvm use'.
    param(
        [Parameter(Mandatory)][string]$Version,
        [string]$NvmHome = $env:NVM_HOME,
        [string]$Symlink = $env:NVM_SYMLINK
    )
    $link = Get-NvmSettingValue -Key 'path' -NvmHome $NvmHome
    if (-not $link) { $link = $Symlink }
    if (-not $link) { return $false }
    $root = Get-NvmSettingValue -Key 'root' -NvmHome $NvmHome
    if (-not $root) { $root = Split-Path $link }
    $target = Join-Path $root "v$Version"
    if (-not (Test-Path (Join-Path $target 'node.exe'))) { return $false }
    try {
        if (Test-Path $link) {
            # only ever replace a link - a real directory here is not ours
            $item = Get-Item $link -Force
            if (-not ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) { return $false }
            [System.IO.Directory]::Delete($link, $false)
        }
        New-Item -ItemType Junction -Path $link -Target $target | Out-Null
    } catch {
        # nvm's elevate helper can land its symlink between our check and
        # the mklink (seen live: "directory cannot be removed because it is
        # not empty"). Whoever won, the probe below is the verdict - a
        # throw here would kill the whole module under EAP=Stop.
        Write-Info "node link changed underneath the repair ($($_.Exception.Message)) - probing the result"
    }
    return [bool](Test-Path (Join-Path $link 'node.exe'))
}

function Get-PathWithoutLegacyPyenv {
    # Pure filter: drop pyenv-win bin/shims entries; everything else (incl.
    # unexpanded %VAR% forms) passes through untouched.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Path)
    $kept = $Path -split ';' | Where-Object { $_ -ne '' -and $_ -notmatch '\\pyenv-win\\(bin|shims)\\?$' }
    return ($kept -join ';')
}

function Remove-LegacyPyenvPath {
    # Machines provisioned before the uv migration still have pyenv-win's
    # bin/shims on the user PATH (the scoop manifest wrote them), so pip
    # resolves into the dead pyenv tree - python wins only by PATH order.
    # Strip the entries; the pyenv install itself stays until uninstall.
    # Windows sibling of the Unix fragment cleanup (#67).
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    try {
        if ($null -eq $key.GetValue('Path')) { return }
        $raw  = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $kind = $key.GetValueKind('Path')
        $new  = Get-PathWithoutLegacyPyenv -Path $raw
        $before = @($raw -split ';' | Where-Object { $_ -ne '' })
        if (@($new -split ';' | Where-Object { $_ -ne '' }).Count -eq $before.Count) { return }
        if (Test-DryRun) { Write-Info '[DRY-RUN] Would strip pyenv-win entries from the user PATH'; return }
        $key.SetValue('Path', $new, $kind)
    } finally { $key.Close() }
    # Scrub the current session too so this run's children resolve cleanly.
    $env:Path = Get-PathWithoutLegacyPyenv -Path $env:Path
    Send-EnvironmentChanged
    Write-Success 'Stripped legacy pyenv-win entries from the user PATH'
}

function Install-Languages {
    Write-Header 'Languages'

    if (Test-CfgEnabled 'languages.node.enabled') {
        Install-Pkg -Name 'nvm'        # coreybutler/nvm-windows
        $ver = Get-CfgValue 'languages.node.version'
        if (-not $ver) { $ver = 'lts' }
        if (Test-DryRun) { Write-Info "[DRY-RUN] Would run: nvm install $ver; nvm use $ver" }
        else {
            nvm install $ver
            if ($LASTEXITCODE -ne 0) { Write-Warn "nvm install $ver exited $LASTEXITCODE" }
            $useOut = nvm use $ver 2>&1
            $useOut | ForEach-Object { Write-Host $_ }
            if ($LASTEXITCODE -ne 0) { Write-Warn "nvm use $ver exited $LASTEXITCODE (needs Developer Mode or one elevated 'nvm use')" }
            elseif (-not (Test-NodeActivation)) {
                # nvm prints the resolved version ("Now using node v24.18.0")
                # even for aliases like "lts" - that names the junction target.
                $m = [regex]::Match(($useOut -join "`n"), 'Now using node v(\d+\.\d+\.\d+)')
                if ($m.Success -and (Repair-NodeActivation -Version $m.Groups[1].Value)) {
                    Write-Info "nvm's symlink needs elevation on this machine - linked node $($m.Groups[1].Value) via an unelevated junction instead"
                } else {
                    Write-Warn "nvm use $ver reported success but node is not activated - enable Windows Developer Mode or run 'nvm use $ver' once from an elevated shell, then re-run setup"
                }
            }
        }
    }

    if (Test-CfgEnabled 'languages.python.enabled') {
        Install-Pkg -Name 'uv'
        $pyver = Get-CfgValue 'languages.python.version'
        if ($pyver) {
            if (Test-DryRun) { Write-Info "[DRY-RUN] Would run: uv python install $pyver --default" }
            else {
                # uv resolves "3.12" to its newest patch itself and installs a
                # prebuilt standalone CPython - no version-list cache, no MSI
                # admin-install, no compiler. --default (uv preview feature)
                # additionally creates bare python/python3 shims, the moral
                # equivalent of `pyenv global`. Managed versions also register
                # in the Windows registry (PEP 514), so `py` sees them.
                uv python install $pyver --default
                if ($LASTEXITCODE -ne 0) { Write-Warn "uv python install $pyver exited $LASTEXITCODE" }
            }
        }
        Remove-LegacyPyenvPath
    }
}

function Uninstall-Languages {
    Write-Header 'Uninstall: Languages'
    if (-not (Test-KeepTools)) {
        # uv-managed CPython + shims. Teardown runs modules in reverse
        # (09->01), so Uninstall-PythonTools (03) has already removed the uv
        # app by the time this runs - ask uv only if it survived, otherwise
        # fall back to the scoop persist layout the manifest pins.
        $pyDirs = @()
        if (Test-Command 'uv') {
            $pyDirs = @((& uv python dir 2>$null), (& uv python dir --bin 2>$null))
        } else {
            $persist = Join-Path $HOME 'scoop\persist\uv\python'
            if (Test-Path $persist) { $pyDirs = @($persist) }
        }
        foreach ($d in $pyDirs) {
            if ($d) { Remove-ManagedDir -Dir $d -Label 'uv-managed Python' }
        }
        # Legacy: machines provisioned before the uv migration used pyenv-win.
        Remove-Pkg -Name 'pyenv'
        Remove-ManagedDir -Dir (Join-Path $HOME '.pyenv') -Label 'pyenv-win data'
        Remove-Pkg -Name 'nvm'
    }
}
