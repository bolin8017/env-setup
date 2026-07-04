# Common.psm1 - logging, platform detection, shared helpers for the Windows engine.
# Cross-module flags travel via ENVSETUP_* environment variables (mirrors the
# Bash engine's exported DRY_RUN / AUTO_YES / KEEP_EXISTING).

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info    { param([string]$Message) Write-Host "[INFO] $Message"    -ForegroundColor Cyan }
function Write-Success { param([string]$Message) Write-Host "[OK] $Message"      -ForegroundColor Green }
function Write-Warn    { param([string]$Message) Write-Host "[WARN] $Message"    -ForegroundColor Yellow }
function Write-Err     { param([string]$Message) Write-Host "[ERROR] $Message"   -ForegroundColor Red }
function Write-Header {
    param([string]$Title)
    Write-Host ''
    Write-Host ('=' * 60) -ForegroundColor Blue
    Write-Host "  $Title" -ForegroundColor Blue
    Write-Host ('=' * 60) -ForegroundColor Blue
}

function Test-Command {
    param([Parameter(Mandatory)][string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-IsWindows {
    # $IsWindows exists only on pwsh 6+. On Windows PowerShell 5.1 it is *unset*
    # (not $null) - and under Set-StrictMode -Version Latest, reading an unset
    # variable is a terminating error (VariableIsUndefined). Probe with
    # Get-Variable instead of referencing $IsWindows directly, then fall back to
    # $env:OS (5.1 only ever runs on Windows, where $env:OS is 'Windows_NT').
    $isWin = Get-Variable -Name IsWindows -ValueOnly -ErrorAction Ignore
    if ($null -ne $isWin) { return [bool]$isWin }
    return ($env:OS -eq 'Windows_NT')
}

function Assert-Windows {
    if (-not (Test-IsWindows)) {
        throw 'The PowerShell engine only runs on native Windows. Use setup.sh on macOS/Linux/WSL.'
    }
}

function Test-DryRun       { return ($env:ENVSETUP_DRY_RUN -eq 'true') }
function Test-AutoYes      { return ($env:ENVSETUP_AUTO_YES -eq 'true') }
function Test-KeepExisting { return ($env:ENVSETUP_KEEP_EXISTING -eq 'true') }
function Test-KeepTools    { return ($env:ENVSETUP_KEEP_TOOLS -eq 'true') }
function Test-Purge        { return ($env:ENVSETUP_PURGE -eq 'true') }
function Test-NoRestore    { return ($env:ENVSETUP_NO_RESTORE -eq 'true') }

function Confirm-Action {
    param([Parameter(Mandatory)][string]$Prompt)
    if (Test-AutoYes) { return $true }
    $answer = Read-Host "$Prompt [y/N]"
    return ($answer -match '^[Yy]')
}

function Invoke-WithRetry {
    # Retry a transient-failure-prone action - typically a GitHub download. Some
    # corporate networks intermittently reset the TLS connection to GitHub hosts
    # (get.scoop.sh / raw.githubusercontent.com / github.com) mid-handshake, so a
    # lone attempt can fail spuriously while the same call succeeds seconds later.
    # Returns the action's output; rethrows the last error once attempts are spent.
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
            Write-Warn "$What failed (attempt $attempt/$MaxAttempts): $($_.Exception.Message). Retrying in ${DelaySeconds}s..."
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

function Write-Utf8NoBom {
    # Windows PowerShell 5.1's `Set-Content -Encoding utf8` writes a BOM, which
    # strict JSON consumers (e.g. Node reading ~/.claude.json) reject. One
    # BOM-less writer for every JSON/state file, identical on both PS editions.
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content
    )
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}

function Invoke-Native {
    # Run a native command with stderr merged into the output stream WITHOUT
    # tripping Windows PowerShell 5.1's RemoteException: under EAP=Stop, 5.1
    # throws the moment a native command writes to a redirected stderr. Takes
    # exe + args (not a scriptblock) so the invocation happens in THIS scope,
    # where EAP is relaxed — a caller-defined scriptblock would still run under
    # the caller's EAP=Stop. $LASTEXITCODE is preserved for the caller's own
    # success check. Quote literal dash-flags ('-x') so they don't bind as
    # parameters.
    param(
        [Parameter(Mandatory, Position = 0)][string]$Exe,
        [Parameter(Position = 1, ValueFromRemainingArguments)][object[]]$Arguments = @()
    )
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $Exe @Arguments 2>&1 }
    finally { $ErrorActionPreference = $prev }
}

function Test-FileContentEqual {
    # Byte-exact file comparison (the Windows analog of `cmp -s`). Line-based
    # Compare-Object is an unordered multiset diff and must not be used to
    # decide whether a managed file was user-modified.
    param(
        [Parameter(Mandatory)][string]$PathA,
        [Parameter(Mandatory)][string]$PathB
    )
    if (-not (Test-Path -LiteralPath $PathA) -or -not (Test-Path -LiteralPath $PathB)) { return $false }
    try {
        $ha = (Get-FileHash -LiteralPath $PathA -Algorithm SHA256).Hash
        $hb = (Get-FileHash -LiteralPath $PathB -Algorithm SHA256).Hash
        return ($ha -eq $hb)
    } catch { return $false }
}

function Send-EnvironmentChanged {
    # User-scope env writes go to the registry, which running processes never
    # re-read; Explorer only refreshes its copy on WM_SETTINGCHANGE. Broadcast
    # it so shells launched from the taskbar pick up PATH edits without a
    # re-logon. (06-Shell's Enable-SessionFonts does the same for fonts.)
    if (-not ([System.Management.Automation.PSTypeName]'EnvSetup.NativeEnv').Type) {
        Add-Type -Namespace EnvSetup -Name NativeEnv -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
    }
    $res = [UIntPtr]::Zero
    # 0xFFFF = HWND_BROADCAST, 0x001A = WM_SETTINGCHANGE, 2 = SMTO_ABORTIFHUNG
    [void][EnvSetup.NativeEnv]::SendMessageTimeout([IntPtr]0xFFFF, 0x001A, [UIntPtr]::Zero, 'Environment', 2, 1000, [ref]$res)
}

Export-ModuleMember -Function `
    Write-Info, Write-Success, Write-Warn, Write-Err, Write-Header, `
    Test-Command, Test-IsWindows, Assert-Windows, Invoke-WithRetry, `
    Test-DryRun, Test-AutoYes, Test-KeepExisting, Confirm-Action, `
    Test-KeepTools, Test-Purge, Test-NoRestore, Test-FileContentEqual, `
    Write-Utf8NoBom, Invoke-Native, Send-EnvironmentChanged
