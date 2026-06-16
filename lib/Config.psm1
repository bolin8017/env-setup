# Config.psm1 — pure-PowerShell reader for the restricted config.yaml subset
# used by lib/yaml.sh + lib/config.sh: scalars, nested maps (2-space indent),
# lists (`- item` one level deeper than their key), `#` comments, optional quotes.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Parsed config lives in module scope.
$script:Config = [ordered]@{}

function Remove-YamlQuote {
    param([string]$Value)
    if ($Value.Length -ge 2) {
        if (($Value[0] -eq '"' -and $Value[-1] -eq '"') -or
            ($Value[0] -eq "'" -and $Value[-1] -eq "'")) {
            return $Value.Substring(1, $Value.Length - 2)
        }
    }
    return $Value
}

function Remove-InlineComment {
    # Cut at the first '#' preceded by whitespace and sitting OUTSIDE any quoted
    # span, so a value such as "#ff0000" or "a # b" keeps its '#'. This is the
    # quote-aware intent of lib/yaml.sh done correctly per character (the awk
    # version mishandles ' #' inside a quoted value; this one does not).
    param([string]$Line)
    $quote = $null
    for ($i = 0; $i -lt $Line.Length; $i++) {
        $ch = $Line[$i]
        if ($quote) {
            if ($ch -eq $quote) { $quote = $null }
        }
        elseif ($ch -eq '"' -or $ch -eq "'") { $quote = $ch }
        elseif ($ch -eq '#' -and $i -gt 0 -and [char]::IsWhiteSpace($Line[$i - 1])) {
            return $Line.Substring(0, $i)
        }
    }
    return $Line
}

function ConvertFrom-SimpleYaml {
    # AllowEmptyString: Get-Content yields '' for blank config lines and the loop
    # skips them. Without it, a Mandatory [string[]] rejects the whole array.
    param([Parameter(Mandatory)][AllowEmptyString()][string[]]$Lines)

    $root = [ordered]@{}
    # Frame: Indent = level at which this container's keys/items appear.
    # Owner* lets a list item retype its key's slot from map to list.
    $stack = [System.Collections.Generic.Stack[psobject]]::new()
    $stack.Push([pscustomobject]@{ Indent = 0; Container = $root; OwnerContainer = $null; OwnerKey = $null })

    foreach ($raw in $Lines) {
        if ($raw -match '^\s*$' -or $raw -match '^\s*#') { continue }

        $leading = ($raw -replace '^( *).*$', '$1').Length
        $indent  = [int]([math]::Floor($leading / 2))

        $line = (Remove-InlineComment $raw.Trim()).Trim()
        if ($line -eq '') { continue }

        while ($stack.Peek().Indent -gt $indent) { [void]$stack.Pop() }
        $frame = $stack.Peek()

        if ($line -match '^-\s*(.*)$') {
            $val = Remove-YamlQuote ($Matches[1].Trim())
            if ($frame.Container -isnot [System.Collections.IList]) {
                $list = [System.Collections.ArrayList]::new()
                if ($null -ne $frame.OwnerContainer) { $frame.OwnerContainer[$frame.OwnerKey] = $list }
                $frame.Container = $list
            }
            [void]$frame.Container.Add($val)
            continue
        }

        if ($line -match '^([A-Za-z_][A-Za-z0-9_-]*):\s*(.*)$') {
            $key = $Matches[1]
            $val = $Matches[2].Trim()
            if ($val -ne '') {
                $frame.Container[$key] = Remove-YamlQuote $val
            }
            else {
                $child = [ordered]@{}
                $frame.Container[$key] = $child
                $stack.Push([pscustomobject]@{
                    Indent = $indent + 1; Container = $child
                    OwnerContainer = $frame.Container; OwnerKey = $key
                })
            }
        }
    }
    return $root
}

function Find-ConfigFile {
    param([string]$Path)
    if ($Path -and (Test-Path -LiteralPath $Path)) { return (Resolve-Path -LiteralPath $Path).Path }
    $root = Resolve-Path (Join-Path $PSScriptRoot '..')
    $candidate = Join-Path $root 'config.yaml'
    if (Test-Path -LiteralPath $candidate) { return $candidate }
    throw "No config file found (searched: -Path, $candidate)"
}

function Set-CfgPath {
    # Set a dotted path, creating intermediate maps as needed.
    param([string]$Path, [object]$Value)
    $parts = $Path.Split('.')
    $node = $script:Config
    for ($i = 0; $i -lt $parts.Count - 1; $i++) {
        $k = $parts[$i]
        if (-not $node.Contains($k) -or $node[$k] -isnot [System.Collections.IDictionary]) {
            $node[$k] = [ordered]@{}
        }
        $node = $node[$k]
    }
    $node[$parts[-1]] = $Value
}

function Set-CfgEnvOverride {
    # Legacy env overrides — the subset of lib/config.sh::_apply_env_overrides
    # with a native-Windows target. SKIP_DOCKER and SKIP_TMUX_CONFIG are omitted
    # (no Docker; zellij replaces tmux, gated by windows.multiplexer.zellij).
    if ($env:AUTO_YES)       { Set-CfgPath 'general.auto_yes' $env:AUTO_YES }
    if ($env:NODE_VERSION)   { Set-CfgPath 'languages.node.version' $env:NODE_VERSION }
    if ($env:PYTHON_VERSION) { Set-CfgPath 'languages.python.version' $env:PYTHON_VERSION }
    if ($env:SKIP_CONDA -eq 'true')       { Set-CfgPath 'languages.conda.enabled' 'false' }
    if ($env:SKIP_CLI_TOOLS -eq 'true')   { Set-CfgPath 'cli_tools.enabled' 'false' }
    if ($env:SKIP_SHELL_SETUP -eq 'true') { Set-CfgPath 'shell.enabled' 'false' }
}

# Recursively merge $Override into $Base at the leaf level (nested dictionaries
# are merged key-by-key; scalars/lists are overwritten). Used for config.local.yaml.
function Merge-CfgLocal {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Base,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Override
    )
    foreach ($k in @($Override.Keys)) {
        if ($Base.Contains($k) -and ($Base[$k] -is [System.Collections.IDictionary]) -and ($Override[$k] -is [System.Collections.IDictionary])) {
            Merge-CfgLocal -Base $Base[$k] -Override $Override[$k]
        } else {
            $Base[$k] = $Override[$k]
        }
    }
}

function Import-Config {
    param([string]$Path)
    $file = Find-ConfigFile -Path $Path
    $lines = Get-Content -LiteralPath $file
    $script:Config = ConvertFrom-SimpleYaml -Lines $lines

    # Merge a sibling config.local.yaml (gitignored) over the base config — per
    # machine overrides such as worklog.role / worklog.source. Mirrors lib/config.sh.
    $localFile = $file -replace '\.yaml$', '.local.yaml'
    if (Test-Path -LiteralPath $localFile) {
        Write-Verbose "Merging local overrides from: $localFile"
        $localCfg = ConvertFrom-SimpleYaml -Lines (Get-Content -LiteralPath $localFile)
        if ($localCfg -is [System.Collections.IDictionary]) {
            Merge-CfgLocal -Base $script:Config -Override $localCfg
        }
    }

    Set-CfgEnvOverride
}

function Get-CfgNode {
    param([string]$Path)
    $node = $script:Config
    foreach ($k in $Path.Split('.')) {
        if ($node -is [System.Collections.IDictionary] -and $node.Contains($k)) {
            $node = $node[$k]
        } else {
            return $null
        }
    }
    return $node
}

function Get-CfgValue {
    param([Parameter(Mandatory)][string]$Path)
    $node = Get-CfgNode -Path $Path
    if ($null -eq $node -or $node -is [System.Collections.IDictionary] -or $node -is [System.Collections.IList]) {
        return ''
    }
    return [string]$node
}

function Test-CfgEnabled {
    param([Parameter(Mandatory)][string]$Path)
    $v = Get-CfgValue -Path $Path
    return ($v -eq 'true' -or $v -eq 'True' -or $v -eq 'TRUE')
}

function Get-CfgList {
    param([Parameter(Mandatory)][string]$Path)
    $node = Get-CfgNode -Path $Path
    if ($node -is [System.Collections.IList]) { return [string[]]@($node) }
    return [string[]]@()
}

Export-ModuleMember -Function Import-Config, Get-CfgValue, Test-CfgEnabled, Get-CfgList
