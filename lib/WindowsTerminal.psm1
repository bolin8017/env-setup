# WindowsTerminal.psm1 - whitelisted merge into Windows Terminal settings.json.
# Pure (string in / string out) so it is fully unit-testable; the caller reads,
# backs up, and writes the file. Mirrors the claude settings merge: it sets the
# default font face and preserves every other key.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Merge-WtSettings {
    param(
        [Parameter(Mandatory)][string]$CurrentJson,
        [string]$FontFace = 'MesloLGS NF'
    )
    $s = $CurrentJson | ConvertFrom-Json

    if (-not $s.PSObject.Properties['profiles']) { $s | Add-Member -NotePropertyName profiles -NotePropertyValue ([pscustomobject]@{}) }
    if (-not $s.profiles.PSObject.Properties['defaults']) { $s.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([pscustomobject]@{}) }
    if (-not $s.profiles.defaults.PSObject.Properties['font']) { $s.profiles.defaults | Add-Member -NotePropertyName font -NotePropertyValue ([pscustomobject]@{}) }

    if ($s.profiles.defaults.font.PSObject.Properties['face']) { $s.profiles.defaults.font.face = $FontFace }
    else { $s.profiles.defaults.font | Add-Member -NotePropertyName face -NotePropertyValue $FontFace }

    return ($s | ConvertTo-Json -Depth 32)
}

Export-ModuleMember -Function Merge-WtSettings
