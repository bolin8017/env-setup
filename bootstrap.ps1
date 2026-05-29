#!/usr/bin/env pwsh
# bootstrap.ps1 — one-liner installer for the Windows engine.
# Usage: irm https://raw.githubusercontent.com/bolin8017/env-setup/main/bootstrap.ps1 | iex

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoUrl    = 'https://github.com/bolin8017/env-setup.git'
$InstallDir = Join-Path $HOME '.local/share/env-setup'

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
    Invoke-RestMethod -Uri 'https://get.scoop.sh' | Invoke-Expression
}

function Sync-Repo {
    if (Test-Path (Join-Path $InstallDir '.git')) {
        Write-Host 'Updating existing installation...'
        git -C $InstallDir pull --ff-only
        if ($LASTEXITCODE -ne 0) { throw "git pull failed (exit $LASTEXITCODE) — resolve $InstallDir by hand" }
    } else {
        Write-Host 'Cloning env-setup...'
        New-Item -ItemType Directory -Path (Split-Path $InstallDir -Parent) -Force | Out-Null
        git clone $RepoUrl $InstallDir
        if ($LASTEXITCODE -ne 0) { throw "git clone failed (exit $LASTEXITCODE)" }
    }
}

function Invoke-Bootstrap {
    param([string[]]$ForwardArgs)
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
