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

function Initialize-Git {
    if (Get-Command git -ErrorAction SilentlyContinue) { return }
    Write-Host 'Installing Git via winget...'
    winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements
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
    Initialize-Scoop
    Sync-Repo
    & (Join-Path $InstallDir 'setup.ps1') @ForwardArgs
}

# Guarded entrypoint: skipped when dot-sourced by tests.
if (-not $env:ENVSETUP_BOOTSTRAP_NORUN) {
    Invoke-Bootstrap -ForwardArgs $args
}
