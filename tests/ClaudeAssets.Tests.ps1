# Consistency checks for configs/claude/ assets — the Windows twin of
# tests/test_claude_assets.sh. Catches broken JSON, whitelist typos,
# unregistered plugin marketplaces, and missing frontmatter before install.
BeforeAll {
    Import-Module "$PSScriptRoot/../lib/Common.psm1" -Force
    Import-Module "$PSScriptRoot/../lib/Config.psm1" -Force
    $script:RepoRoot  = (Resolve-Path "$PSScriptRoot/..").Path
    $script:ClaudeDir = Join-Path $script:RepoRoot 'configs/claude'
    Import-Config -Path (Join-Path $script:RepoRoot 'config.yaml')
    $script:Settings = Get-Content -Raw (Join-Path $script:ClaudeDir 'settings.json') | ConvertFrom-Json
}

Describe 'JSON assets parse' {
    It 'settings.json is valid JSON' {
        { Get-Content -Raw (Join-Path $script:ClaudeDir 'settings.json') | ConvertFrom-Json } | Should -Not -Throw
    }
    It 'mcp-servers.json is valid JSON' {
        { Get-Content -Raw (Join-Path $script:ClaudeDir 'mcp-servers.json') | ConvertFrom-Json } | Should -Not -Throw
    }
}

Describe 'settings_merge_keys whitelist matches settings.json' {
    It 'every whitelist key exists as a top-level key' {
        foreach ($k in @(Get-CfgList 'claude_code.settings_merge_keys')) {
            $script:Settings.PSObject.Properties[$k] | Should -Not -BeNullOrEmpty -Because "whitelist key '$k' must exist in settings.json"
        }
    }
}

Describe 'enabledPlugins marketplaces are registered' {
    It 'every enabled plugin has its marketplace in claude_code.marketplaces' {
        $registered = @(Get-CfgList 'claude_code.marketplaces') | ForEach-Object { ($_ -split '/')[-1] }
        foreach ($p in $script:Settings.enabledPlugins.PSObject.Properties) {
            if ($p.Value -ne $true) { continue }
            $mp = ($p.Name -split '@')[-1]
            $registered | Should -Contain $mp -Because "plugin '$($p.Name)' cannot resolve on a fresh machine otherwise"
        }
    }
}

Describe 'markdown assets carry frontmatter' {
    It 'commands and skills start with frontmatter carrying a description' {
        $files = @(Get-ChildItem (Join-Path $script:ClaudeDir 'commands') -Filter *.md -ErrorAction Ignore)
        $skillsRoot = Join-Path $script:ClaudeDir 'skills'
        if (Test-Path $skillsRoot) {
            $files += Get-ChildItem $skillsRoot -Directory | ForEach-Object {
                Get-ChildItem $_.FullName -Filter 'SKILL.md' -ErrorAction Ignore
            }
        }
        $files | Should -Not -BeNullOrEmpty
        foreach ($f in $files) {
            $lines = Get-Content $f.FullName
            $lines[0] | Should -Be '---' -Because "$($f.Name) must start with YAML frontmatter"
            $end = ($lines | Select-Object -Skip 1 | Select-String -Pattern '^---$' | Select-Object -First 1).LineNumber
            $end | Should -Not -BeNullOrEmpty
            ($lines[1..$end] -join "`n") | Should -Match 'description:' -Because "$($f.Name) frontmatter needs a description"
        }
    }
}

Describe 'output styles carry frontmatter' {
    It 'ships at least one output style whose frontmatter has a name and a description' {
        # Claude Code selects a style by its frontmatter `name:` (settings.json
        # outputStyle), so a style without one can be deployed but never chosen.
        $stylesRoot = Join-Path $script:ClaudeDir 'output-styles'
        Test-Path $stylesRoot | Should -BeTrue -Because 'output-styles/ must exist'
        $files = @(Get-ChildItem $stylesRoot -Filter *.md -ErrorAction Ignore)
        $files | Should -Not -BeNullOrEmpty
        foreach ($f in $files) {
            $lines = Get-Content $f.FullName
            $lines[0] | Should -Be '---' -Because "$($f.Name) must start with YAML frontmatter"
            $end = ($lines | Select-Object -Skip 1 | Select-String -Pattern '^---$' | Select-Object -First 1).LineNumber
            $end | Should -Not -BeNullOrEmpty
            $fm = ($lines[1..$end] -join "`n")
            $fm | Should -Match '(?m)^name:' -Because "$($f.Name) frontmatter needs a name"
            $fm | Should -Match '(?m)^description:' -Because "$($f.Name) frontmatter needs a description"
        }
    }
}

Describe 'skills tree shape' {
    It 'every skill directory contains SKILL.md' {
        $skillsRoot = Join-Path $script:ClaudeDir 'skills'
        if (-not (Test-Path $skillsRoot)) { Set-ItResult -Skipped -Because 'no skills directory yet'; return }
        foreach ($d in (Get-ChildItem $skillsRoot -Directory)) {
            Test-Path (Join-Path $d.FullName 'SKILL.md') | Should -BeTrue -Because "skill '$($d.Name)' needs a SKILL.md entry point"
        }
    }
}
