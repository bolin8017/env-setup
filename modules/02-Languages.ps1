#!/usr/bin/env pwsh
# 02-Languages.ps1 — nvm-windows + pyenv-win. PATH/shim wiring into $PROFILE is
# added with the shell profile in Stage 3.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/../lib/Common.psm1"
Import-Module "$PSScriptRoot/../lib/Config.psm1"
Import-Module "$PSScriptRoot/../lib/Package.psm1"

function Resolve-PyenvVersion {
    # pyenv-win needs an exact patch version. Given a major.minor request like
    # "3.12" plus the lines of `pyenv install --list`, return the newest matching
    # "3.12.<patch>" (stable only). Returns $Requested unchanged if it already
    # carries a patch component or nothing matches. Pure, so it is unit-testable.
    param(
        [Parameter(Mandatory)][string]$Requested,
        [string[]]$Available = @()
    )
    if ($Requested -notmatch '^\d+\.\d+$') { return $Requested }
    $rx = '^' + [regex]::Escape($Requested) + '\.\d+$'
    $match = $Available |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -match $rx } |
        Sort-Object { [version]$_ } |
        Select-Object -Last 1
    if ($match) { return $match }
    return $Requested
}

function Update-PyenvVersionCache {
    # pyenv-win refreshes its installable-version list with 'pyenv update', but
    # that uses an htmlfile COM object unsupported on current Windows 11
    # ("htmlfile: this method is not supported"), so it fails and the list goes
    # stale. Replace the cache file directly from the maintained source — no
    # htmlfile. Best-effort: on failure pyenv keeps its existing list.
    try {
        $cache = Join-Path (scoop prefix pyenv) 'pyenv-win\.versions_cache.xml'
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $url = 'https://raw.githubusercontent.com/pyenv-win/pyenv-win/master/pyenv-win/.versions_cache.xml'
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $cache
        Write-Info 'Refreshed pyenv-win version list (.versions_cache.xml)'
    } catch {
        Write-Warn "Could not refresh the pyenv version list (using the existing one): $_"
    }
}

function Resolve-JunctionFreePath {
    # Return the real filesystem location of $Path, resolving a directory
    # junction/symlink when present. scoop assembles pyenv-win out of junctions
    # (its `current` link, plus the persisted `install_cache`/`versions` dirs),
    # and an unelevated `msiexec /a` is refused traversal of those junctions on
    # Windows 11 (ERROR_UNTRUSTED_MOUNT_POINT). Resolving to the junction-free
    # path lets the administrative install proceed. A plain directory (e.g. a
    # git-clone pyenv) is returned unchanged. Pure, so it is unit-testable with
    # a temp junction.
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $Path }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        $target = $item.ResolveLinkTarget($true)
        if ($target) { return $target.FullName }
    }
    return $item.FullName
}

function Install-PyenvPython {
    # Install one CPython version with pyenv-win, working around a scoop +
    # Windows 11 incompatibility.
    #
    # pyenv-win installs CPython by running, for each component MSI:
    #     msiexec /quiet /a <core>.msi TargetDir=<PYENV>\versions\<ver>
    # an *unelevated administrative install*. Installed via scoop, that path is
    # reached through directory junctions (scoop's `current` link and the
    # persisted `install_cache`/`versions` dirs). Windows 11 refuses an
    # unelevated process traversal of a junction (ERROR_UNTRUSTED_MOUNT_POINT,
    # 0x800701C0); msiexec then fails with MSI 2203 "cannot open database" and
    # pyenv reports:  :: [Error] :: error installing "core" component MSI.
    #
    # pyenv's earlier `/layout` download is plain file I/O and still succeeds, so
    # the component MSIs are left cached. We detect the missing interpreter and
    # finish the install ourselves against the junction-FREE real paths, mirroring
    # pyenv-win's own steps (admin-install each component, ensurepip, create the
    # pythonX[.Y] aliases, rehash). On setups without junctions (git-clone pyenv,
    # older Windows, or a future pyenv that avoids /a) `pyenv install` already
    # produced python.exe and the workaround is skipped.
    param([Parameter(Mandatory)][string]$Version)

    pyenv install $Version

    $root = $env:PYENV
    if (-not $root) { $root = Join-Path (scoop prefix pyenv) 'pyenv-win' }
    $dst = Join-Path (Resolve-JunctionFreePath (Join-Path $root 'versions')) $Version
    if (Test-Path (Join-Path $dst 'python.exe')) { return }   # pyenv's own install worked

    Write-Warn "pyenv MSI install was blocked by a scoop junction (Win11); finishing on junction-free paths"
    $src = Join-Path (Resolve-JunctionFreePath (Join-Path $root 'install_cache')) $Version
    if (-not (Test-Path $src)) {
        Write-Warn "No cached component MSIs at ${src} - cannot finish Python $Version"
        return
    }
    $null = New-Item -ItemType Directory -Path $dst -Force

    # Install the same components pyenv would: skip its four non-components
    # (appendpath/launcher/path/pip) and the optional debug/symbol payloads.
    foreach ($msi in (Get-ChildItem $src -Filter '*.msi' -ErrorAction SilentlyContinue)) {
        if ($msi.BaseName -match '^(appendpath|launcher|path|pip)$|_d$|_pdb$') { continue }
        $msiArgs = '/quiet /a "{0}" TargetDir="{1}"' -f $msi.FullName, $dst
        $proc = Start-Process msiexec -Wait -PassThru -ArgumentList $msiArgs
        if ($proc.ExitCode -ne 0) { Write-Warn "  component $($msi.BaseName) -> exit $($proc.ExitCode)" }
        $copied = Join-Path $dst $msi.Name      # /a copies the source msi into TargetDir
        if (Test-Path $copied) { Remove-Item $copied -Force }
    }

    $python = Join-Path $dst 'python.exe'
    if (-not (Test-Path $python)) { Write-Warn "Python $Version still missing after workaround"; return }

    # msiexec /a does not run ensurepip; bootstrap pip as pyenv would. A non-zero
    # exit must not abort the run, so swallow it and verify via pip.exe below.
    try { & $python -E -s -m ensurepip -U --default-pip *> $null }
    catch { Write-Warn "ensurepip raised an error: $_" }
    if (Test-Path (Join-Path $dst 'Scripts\pip.exe')) { Write-Info "pip ready for Python $Version" }
    else { Write-Warn "pip not bootstrapped for Python $Version" }

    # pyenv's pythonX / pythonXY / pythonX.Y aliases (pyenv-install.vbs).
    $pythonw = Join-Path $dst 'pythonw.exe'
    $parts = $Version.Split('.')
    if ($parts.Count -ge 2) {
        foreach ($suffix in @($parts[0], ($parts[0] + $parts[1]), ($parts[0] + '.' + $parts[1]))) {
            Copy-Item $python (Join-Path $dst "python$suffix.exe") -Force
            if (Test-Path $pythonw) { Copy-Item $pythonw (Join-Path $dst "pythonw$suffix.exe") -Force }
        }
    }
    try { pyenv rehash } catch { Write-Warn "pyenv rehash: $_" }
    Write-Info "Python $Version installed via junction-free workaround"
}

function Install-Languages {
    Write-Header 'Languages'

    if (Test-CfgEnabled 'languages.node.enabled') {
        Install-Pkg -Name 'nvm'        # coreybutler/nvm-windows
        $ver = Get-CfgValue 'languages.node.version'
        if (-not $ver) { $ver = 'lts' }
        if (Test-DryRun) { Write-Info "[DRY-RUN] Would run: nvm install $ver; nvm use $ver" }
        else { nvm install $ver; nvm use $ver }
    }

    if (Test-CfgEnabled 'languages.python.enabled') {
        Install-Pkg -Name 'pyenv'      # pyenv-win
        $pyver = Get-CfgValue 'languages.python.version'
        if ($pyver) {
            if (Test-DryRun) { Write-Info "[DRY-RUN] Would run: pyenv install $pyver; pyenv global $pyver" }
            else {
                # pyenv-win, unlike *nix pyenv, won't resolve "3.12" to its newest
                # patch ("definition not found: 3.12"). Map major.minor to an exact
                # patch from the available list before installing.
                if ($pyver -match '^\d+\.\d+$') {
                    Update-PyenvVersionCache
                    $resolved = Resolve-PyenvVersion -Requested $pyver -Available (pyenv install --list)
                    if ($resolved -eq $pyver) {
                        Write-Warn "No pyenv-win definition for $pyver.* — the version list may be stale. Pin an exact version in config.yaml."
                        $pyver = $null
                    } else {
                        Write-Info "Resolved Python $pyver -> $resolved"
                        $pyver = $resolved
                    }
                }
                if ($pyver) { Install-PyenvPython -Version $pyver; pyenv global $pyver }
            }
        }
    }

    Write-Info 'nvm/pyenv PATH wiring is added with the PowerShell profile in Stage 3.'
}
