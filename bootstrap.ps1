#!/usr/bin/env pwsh
# bootstrap.ps1 - one-liner installer for the Windows engine.
# Usage: irm https://raw.githubusercontent.com/bolin8017/env-setup/main/bootstrap.ps1 | iex

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoUrl    = 'https://github.com/bolin8017/env-setup.git'
$InstallDir = Join-Path $HOME '.local/share/env-setup'

function Invoke-WithRetry {
    # bootstrap runs BEFORE the repo is cloned, so it cannot import
    # lib/Common.psm1 - this mirrors that module's Invoke-WithRetry. Some corporate
    # networks intermittently reset the TLS connection to GitHub mid-handshake, so a
    # lone attempt can fail spuriously while the same call succeeds seconds later;
    # under $ErrorActionPreference='Stop' that one failure aborts the whole install.
    param(
        [Parameter(Mandatory)][scriptblock]$Action,
        [string]$What = 'operation',
        [int]$MaxAttempts = 5,
        [int]$DelaySeconds = 3
    )
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try { return & $Action }
        catch {
            if ($attempt -ge $MaxAttempts) { throw }
            Write-Warning "$What failed (attempt $attempt/$MaxAttempts): $($_.Exception.Message). Retrying in ${DelaySeconds}s..."
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

function Set-LocalExecutionPolicy {
    # Best-effort: some managed environments forbid changing this. Warn rather
    # than aborting the whole bootstrap over a policy we can run without.
    try { Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force }
    catch { Write-Warning "Could not set execution policy (continuing): $_" }
}

function Update-SessionPath {
    # winget installs update the registry PATH, not this session's copy; without
    # a refresh the very next `git`/`pwsh` call is CommandNotFound and the
    # one-liner aborts on a truly fresh box.
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($machine, $user, $env:Path) | Where-Object { $_ }) -join ';'
}

function Initialize-Git {
    if (Get-Command git -ErrorAction SilentlyContinue) { return }
    Write-Host 'Installing Git via winget...'
    winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "winget install Git.Git failed (exit $LASTEXITCODE) - install Git manually, then re-run this one-liner"
    }
    Update-SessionPath
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw 'git is still not on PATH after install - open a new terminal and re-run this one-liner'
    }
}

function Initialize-Pwsh {
    # The engine's JSON handling (JSONC comments, BOM-less writes, native
    # stderr redirects) assumes PowerShell 7, while the pasted one-liner
    # usually starts in Windows PowerShell 5.1. Best-effort install so setup
    # can re-exec under pwsh (Select-EngineRuntime); on failure continue under
    # 5.1 rather than blocking the bootstrap.
    if ($PSVersionTable.PSVersion.Major -ge 6) { return }
    if (Get-Command pwsh -ErrorAction SilentlyContinue) { return }
    Write-Host 'Installing PowerShell 7 via winget...'
    winget install --id Microsoft.PowerShell -e --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) {
        Write-Warning 'PowerShell 7 install failed; continuing under Windows PowerShell 5.1'
        return
    }
    Update-SessionPath
}

function Select-EngineRuntime {
    # The pwsh CommandInfo to re-exec setup under, or $null to run in-process
    # (already on 6+, or pwsh unavailable).
    if ($PSVersionTable.PSVersion.Major -ge 6) { return $null }
    return (Get-Command pwsh -ErrorAction SilentlyContinue)
}

function Initialize-Scoop {
    if (Get-Command scoop -ErrorAction SilentlyContinue) { return }
    Write-Host 'Installing scoop...'
    # Retry the download, then run the installer once. This lone irm - under
    # $ErrorActionPreference='Stop' - is what a single TLS reset used to abort on.
    $installer = Invoke-WithRetry -What 'scoop download' -Action { Invoke-RestMethod -Uri 'https://get.scoop.sh' }
    Invoke-Expression $installer
}

function Sync-Repo {
    if (Test-Path (Join-Path $InstallDir '.git')) {
        Write-Host 'Updating existing installation...'
        git -C $InstallDir pull --ff-only
        if ($LASTEXITCODE -ne 0) { throw "git pull failed (exit $LASTEXITCODE) - resolve $InstallDir by hand" }
    } else {
        Write-Host 'Cloning env-setup...'
        New-Item -ItemType Directory -Path (Split-Path $InstallDir -Parent) -Force | Out-Null
        Invoke-WithRetry -What 'git clone' -Action {
            # A failed clone can leave a partial dir that blocks the next attempt.
            if (Test-Path $InstallDir) { Remove-Item -Recurse -Force $InstallDir }
            git clone $RepoUrl $InstallDir
            if ($LASTEXITCODE -ne 0) { throw "git clone failed (exit $LASTEXITCODE)" }
        }
    }
}

function Invoke-Bootstrap {
    param([string[]]$ForwardArgs)
    # Windows PowerShell 5.1 (where a pasted one-liner usually runs) defaults to
    # TLS 1.0 for .NET web requests; GitHub requires TLS 1.2+. Opt in before any
    # download so the scoop/Git fetches below don't fail the handshake on older boxes.
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Set-LocalExecutionPolicy
    Initialize-Git
    Initialize-Pwsh
    Initialize-Scoop
    Sync-Repo
    $setup = Join-Path $InstallDir 'setup.ps1'
    $runtime = Select-EngineRuntime
    if ($runtime) {
        Write-Host 'Re-launching setup under PowerShell 7...'
        # No `exit` here: the one-liner runs via `irm | iex` inside the user's
        # interactive session, and exiting would close their console.
        & $runtime.Source -NoProfile -ExecutionPolicy Bypass -File $setup @ForwardArgs
        return
    }
    & $setup @ForwardArgs
}

# Guarded entrypoint: skipped when dot-sourced by tests.
if (-not $env:ENVSETUP_BOOTSTRAP_NORUN) {
    Invoke-Bootstrap -ForwardArgs $args
}
