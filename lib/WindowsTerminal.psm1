# WindowsTerminal.psm1 - whitelisted merge into Windows Terminal settings.json.
# Pure (string in / string out) so it is fully unit-testable; the caller reads,
# backs up, and writes the file. Mirrors the claude settings merge: it sets the
# default font face (and size when asked) and preserves every other key.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Merge-WtSettings {
    param(
        [Parameter(Mandatory)][string]$CurrentJson,
        [string]$FontFace = 'MesloLGS NF',
        # 0 (the default) leaves profiles.defaults.font.size exactly as it is.
        [int]$FontSize = 0
    )
    $s = $CurrentJson | ConvertFrom-Json

    if ($s.PSObject.Properties['profiles'] -and $s.profiles -is [System.Collections.IList]) {
        # Legacy array-form "profiles": [...] - Add-Member below would pipeline
        # over the elements and inject a bogus "defaults" into every profile.
        throw 'settings.json uses the legacy array form of "profiles" - set the default font manually'
    }
    if (-not $s.PSObject.Properties['profiles']) { $s | Add-Member -NotePropertyName profiles -NotePropertyValue ([pscustomobject]@{}) }
    if (-not $s.profiles.PSObject.Properties['defaults']) { $s.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([pscustomobject]@{}) }
    if (-not $s.profiles.defaults.PSObject.Properties['font']) { $s.profiles.defaults | Add-Member -NotePropertyName font -NotePropertyValue ([pscustomobject]@{}) }

    if ($s.profiles.defaults.font.PSObject.Properties['face']) { $s.profiles.defaults.font.face = $FontFace }
    else { $s.profiles.defaults.font | Add-Member -NotePropertyName face -NotePropertyValue $FontFace }

    if ($FontSize -gt 0) {
        if ($s.profiles.defaults.font.PSObject.Properties['size']) { $s.profiles.defaults.font.size = $FontSize }
        else { $s.profiles.defaults.font | Add-Member -NotePropertyName size -NotePropertyValue $FontSize }
    }

    return ($s | ConvertTo-Json -Depth 32)
}

function Set-WtDefaultProfile {
    # Point defaultProfile at the PowerShell 7 profile Windows Terminal generated
    # for the winget/MSIX install. WT's PowershellCore generator derives each guid
    # from the install path, so there is no constant to match on - only the
    # source + name it emits. Refuse to guess when the match is not unique:
    # silently repointing the user's default shell at the wrong pwsh (a scoop
    # copy, a Preview build) is worse than leaving the setting alone.
    param([Parameter(Mandatory)][string]$CurrentJson)
    $s = $CurrentJson | ConvertFrom-Json

    if ($s.PSObject.Properties['profiles'] -and $s.profiles -is [System.Collections.IList]) {
        throw 'settings.json uses the legacy array form of "profiles" - set defaultProfile manually'
    }
    if (-not $s.PSObject.Properties['profiles'] -or -not $s.profiles.PSObject.Properties['list']) {
        throw 'settings.json has no "profiles.list" - set defaultProfile manually'
    }

    $candidates = @($s.profiles.list | Where-Object {
        $_.PSObject.Properties['guid'] -and
        $_.PSObject.Properties['source'] -and $_.source -eq 'Windows.Terminal.PowershellCore' -and
        $_.PSObject.Properties['name']  -and $_.name -notmatch '\(scoop\)|Preview' -and
        -not ($_.PSObject.Properties['hidden'] -and $_.hidden)
    })
    if ($candidates.Count -ne 1) {
        throw "expected exactly 1 PowerShell 7 profile in settings.json, found $($candidates.Count) - set defaultProfile manually"
    }

    $guid = $candidates[0].guid
    if ($s.PSObject.Properties['defaultProfile']) { $s.defaultProfile = $guid }
    else { $s | Add-Member -NotePropertyName defaultProfile -NotePropertyValue $guid }

    return ($s | ConvertTo-Json -Depth 32)
}

Export-ModuleMember -Function Merge-WtSettings, Set-WtDefaultProfile
