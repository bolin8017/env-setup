# env-setup self-update check (cadence-gated, oh-my-zsh-style).
# Reads ~/.env-setup/update.ps1 (written by the shell module at install time).
# On a new interactive shell, at most once per ENVSETUP_UPDATE_FREQ_DAYS: git
# fetch; if behind upstream, pull --ff-only and offer to re-run setup. Soft-fails;
# never breaks the profile.

$envsetupState = Join-Path $HOME '.env-setup/update.ps1'
if (Test-Path -LiteralPath $envsetupState) { . $envsetupState }

function Test-EnvSetupShouldCheck {
    param([long]$Last, [long]$Now, [int]$FreqDays)
    if ($FreqDays -le 0) { return $true }      # 0 = check every shell
    if ($Last -le 0) { return $true }          # missing/invalid stamp -> due
    return (($Now - $Last) -ge ($FreqDays * 86400))
}

function Invoke-EnvSetupUpdateCheck {
    if ($Env:ENVSETUP_UPDATE_ENABLED -ne '1') { return }
    if (-not [Environment]::UserInteractive) { return }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return }
    $repo = $Env:ENVSETUP_REPO_DIR
    if (-not $repo -or -not (Test-Path -LiteralPath (Join-Path $repo '.git'))) { return }

    $stamp = Join-Path $HOME '.env-setup/.update-last-check'
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $last = [long]0
    if (Test-Path -LiteralPath $stamp) {
        [void][long]::TryParse((Get-Content -LiteralPath $stamp -Raw).Trim(), [ref]$last)
    }
    $freq = [int]7
    [void][int]::TryParse($Env:ENVSETUP_UPDATE_FREQ_DAYS, [ref]$freq)
    if (-not (Test-EnvSetupShouldCheck -Last $last -Now $now -FreqDays $freq)) { return }

    # Stamp up-front so a failing fetch doesn't retry on every shell.
    Set-Content -LiteralPath $stamp -Value ([string]$now) -ErrorAction SilentlyContinue

    try {
        git -C "$repo" fetch --quiet 2>$null
        if ($LASTEXITCODE -ne 0) { return }
        $behind = git -C "$repo" rev-list --count 'HEAD..@{u}' 2>$null
        $cnt = 0
        if (-not [int]::TryParse("$behind".Trim(), [ref]$cnt) -or $cnt -le 0) { return }

        git -C "$repo" pull --ff-only --quiet 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "env-setup: update available but fast-forward failed; resolve $repo by hand." -ForegroundColor Yellow
            return
        }

        Write-Host "env-setup updated ($cnt new commit(s))." -ForegroundColor Cyan
        $reply = Read-Host 'Apply now (re-run setup)? [y/N]'
        if ($reply -match '^[yY]') {
            $Env:ENVSETUP_UPDATE_RUNNING = '1'
            & (Join-Path $repo 'setup.ps1')
            $Env:ENVSETUP_UPDATE_RUNNING = $null
        } else {
            Write-Host 'Run env-update to apply later.' -ForegroundColor Green
        }
    } catch {
        # Never let an update check break the shell.
    }
}

# Don't recurse while a triggered setup re-run is in progress.
if ($Env:ENVSETUP_UPDATE_RUNNING -ne '1') { Invoke-EnvSetupUpdateCheck }
