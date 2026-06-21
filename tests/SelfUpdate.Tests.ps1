BeforeAll {
    $script:RepoRoot = (Resolve-Path "$PSScriptRoot/..").Path
}

Describe 'aliases.ps1 self-update command' {
    It 'defines Update-EnvSetup and the env-update alias' {
        $aliases = Get-Content -Raw (Join-Path $RepoRoot 'configs/aliases.ps1')
        $aliases | Should -Match 'function Update-EnvSetup'
        $aliases | Should -Match "Set-Alias.*env-update"
    }
}
