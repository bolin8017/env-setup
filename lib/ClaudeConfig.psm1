# ClaudeConfig.psm1 — PowerShell-native JSON merges for Claude Code config sync.
# Replaces the Bash engine's jq usage (08-claude-code.sh) with ConvertFrom/To-Json.
# Pure (string in / string out) so they are fully unit-testable; callers read,
# back up, and write the files.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Merge-ClaudeSettings {
    # Copy each whitelisted top-level key from Source into Current, preserving
    # all other Current keys. Idempotent. Mirrors _merge_claude_settings's
    # `reduce $ARGS.positional[] as $k (.; .[$k] = $src[0][$k])`.
    param(
        [Parameter(Mandatory)][string]$CurrentJson,
        [Parameter(Mandatory)][string]$SourceJson,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$WhitelistKeys
    )
    $cur = $CurrentJson | ConvertFrom-Json
    $src = $SourceJson | ConvertFrom-Json
    foreach ($k in $WhitelistKeys) {
        if ($src.PSObject.Properties[$k]) {
            if ($cur.PSObject.Properties[$k]) { $cur.$k = $src.$k }
            else { $cur | Add-Member -NotePropertyName $k -NotePropertyValue $src.$k }
        }
    }
    return ($cur | ConvertTo-Json -Depth 32)
}

function Merge-McpServers {
    # Merge Source.mcpServers into Current.mcpServers (source wins per server),
    # preserving every other Current key. Mirrors the jq `(.mcpServers // {}) *
    # ($src[0].mcpServers // {})` merge.
    param(
        [Parameter(Mandatory)][string]$CurrentJson,
        [Parameter(Mandatory)][string]$SourceJson
    )
    $cur = $CurrentJson | ConvertFrom-Json
    $src = $SourceJson | ConvertFrom-Json
    $srcServers = if ($src.PSObject.Properties['mcpServers'] -and $null -ne $src.mcpServers) { $src.mcpServers } else { [pscustomobject]@{} }
    if ((-not $cur.PSObject.Properties['mcpServers']) -or ($null -eq $cur.mcpServers)) {
        if ($cur.PSObject.Properties['mcpServers']) { $cur.mcpServers = [pscustomobject]@{} }
        else { $cur | Add-Member -NotePropertyName mcpServers -NotePropertyValue ([pscustomobject]@{}) }
    }
    foreach ($p in $srcServers.PSObject.Properties) {
        if ($cur.mcpServers.PSObject.Properties[$p.Name]) { $cur.mcpServers.($p.Name) = $p.Value }
        else { $cur.mcpServers | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value }
    }
    return ($cur | ConvertTo-Json -Depth 32)
}

Export-ModuleMember -Function Merge-ClaudeSettings, Merge-McpServers
