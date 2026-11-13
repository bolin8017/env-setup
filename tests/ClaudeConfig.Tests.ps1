BeforeAll { Import-Module "$PSScriptRoot/../lib/ClaudeConfig.psm1" -Force }

Describe 'Merge-ClaudeSettings' {
    It 'copies whitelisted keys from source and preserves non-whitelisted current keys' {
        $cur = '{"env":{"A":"1"},"keep":"me"}'
        $src = '{"env":{"A":"2","B":"3"},"statusLine":{"x":1},"other":"ignored"}'
        $o = (Merge-ClaudeSettings -CurrentJson $cur -SourceJson $src -WhitelistKeys @('env','statusLine')) | ConvertFrom-Json
        $o.env.B | Should -Be '3'        # env replaced from source
        $o.statusLine.x | Should -Be 1   # added from source
        $o.keep | Should -Be 'me'        # current-only key preserved
        $o.PSObject.Properties['other'] | Should -BeNullOrEmpty  # not whitelisted -> not copied
    }
    It 'is idempotent' {
        $o = (Merge-ClaudeSettings -CurrentJson '{"env":{"A":"1"}}' -SourceJson '{"env":{"A":"1"}}' -WhitelistKeys @('env')) | ConvertFrom-Json
        $o.env.A | Should -Be '1'
    }
    It 'writes a seed key only while the machine has no value for it' {
        $src = '{"env":{"A":"2"},"effortLevel":"high","modelSettings":{"m1":{"effortLevel":"high"}}}'
        # The app already saved its own choice for both seed keys: left alone.
        $cur = '{"env":{"A":"1"},"effortLevel":"xhigh","modelSettings":{"m2":{"effortLevel":"xhigh"}}}'
        $o = (Merge-ClaudeSettings -CurrentJson $cur -SourceJson $src -WhitelistKeys @('env') -SeedKeys @('effortLevel','modelSettings')) | ConvertFrom-Json
        $o.env.A | Should -Be '2'
        $o.effortLevel | Should -Be 'xhigh'
        $o.modelSettings.m2.effortLevel | Should -Be 'xhigh'
        $o.modelSettings.PSObject.Properties['m1'] | Should -BeNullOrEmpty
        # A machine with no value yet starts from the repo's.
        $o = (Merge-ClaudeSettings -CurrentJson '{"env":{"A":"1"}}' -SourceJson $src -WhitelistKeys @('env') -SeedKeys @('effortLevel','modelSettings')) | ConvertFrom-Json
        $o.effortLevel | Should -Be 'high'
        $o.modelSettings.m1.effortLevel | Should -Be 'high'
    }
    It 'does not invent a seed key the source lacks' {
        $o = (Merge-ClaudeSettings -CurrentJson '{"env":{"A":"1"}}' -SourceJson '{"env":{"A":"1"}}' -WhitelistKeys @('env') -SeedKeys @('effortLevel')) | ConvertFrom-Json
        $o.PSObject.Properties['effortLevel'] | Should -BeNullOrEmpty
    }
}

Describe 'Merge-McpServers' {
    It 'merges servers and preserves other keys' {
        $cur = '{"mcpServers":{"a":{"u":1}},"projects":{"p":1}}'
        $src = '{"mcpServers":{"b":{"u":2}}}'
        $o = (Merge-McpServers -CurrentJson $cur -SourceJson $src) | ConvertFrom-Json
        $o.mcpServers.a.u | Should -Be 1   # existing preserved
        $o.mcpServers.b.u | Should -Be 2   # new added
        $o.projects.p | Should -Be 1       # other top-level key preserved
    }
    It 'handles a current file with no mcpServers' {
        $o = (Merge-McpServers -CurrentJson '{"x":1}' -SourceJson '{"mcpServers":{"a":{"u":1}}}') | ConvertFrom-Json
        $o.mcpServers.a.u | Should -Be 1
        $o.x | Should -Be 1
    }
}


Describe 'Set-ClaudeStatusLineCommand' {
    It 'rewrites an existing statusLine.command and keeps sibling keys' {
        $cur = '{"statusLine":{"type":"command","command":"npx -y ccstatusline@latest","refreshInterval":10},"keep":"me"}'
        $o = (Set-ClaudeStatusLineCommand -CurrentJson $cur -Command 'node C:/x/ccstatusline.js') | ConvertFrom-Json
        $o.statusLine.command | Should -Be 'node C:/x/ccstatusline.js'
        $o.statusLine.refreshInterval | Should -Be 10
        $o.keep | Should -Be 'me'
    }
    It 'never injects statusLine into a file that lacks it' {
        $o = (Set-ClaudeStatusLineCommand -CurrentJson '{"env":{"A":"1"}}' -Command 'node x') | ConvertFrom-Json
        $o.PSObject.Properties['statusLine'] | Should -BeNullOrEmpty
    }
}

Describe 'Set-ClaudeProfileStatusLine' {
    BeforeAll {
        $script:Main = '{"statusLine":{"type":"command","command":". C:/x/statusline-throttle.sh node C:/x/ccstatusline.js","padding":0}}'
    }
    It 'replaces a stale ccstatusline block as a whole and keeps other keys' {
        $cur = '{"theme":"dark","statusLine":{"type":"command","command":"npx -y ccstatusline@latest","padding":0,"refreshInterval":10}}'
        $o = (Set-ClaudeProfileStatusLine -CurrentJson $cur -SourceJson $script:Main) | ConvertFrom-Json
        $o.statusLine.command | Should -Be '. C:/x/statusline-throttle.sh node C:/x/ccstatusline.js'
        $o.statusLine.PSObject.Properties['refreshInterval'] | Should -BeNullOrEmpty
        $o.theme | Should -Be 'dark'
    }
    It 'leaves a custom (non-ccstatusline) status line alone' {
        $cur = '{"statusLine":{"type":"command","command":"my-own-line.ps1"}}'
        $o = (Set-ClaudeProfileStatusLine -CurrentJson $cur -SourceJson $script:Main) | ConvertFrom-Json
        $o.statusLine.command | Should -Be 'my-own-line.ps1'
    }
    It 'never injects statusLine into a profile that lacks it' {
        $o = (Set-ClaudeProfileStatusLine -CurrentJson '{"theme":"dark"}' -SourceJson $script:Main) | ConvertFrom-Json
        $o.PSObject.Properties['statusLine'] | Should -BeNullOrEmpty
    }
    It 'copies nothing when ~/.claude itself has a custom status line' {
        $cur = '{"statusLine":{"type":"command","command":"npx -y ccstatusline@latest"}}'
        $src = '{"statusLine":{"type":"command","command":"my-own-line.ps1"}}'
        $o = (Set-ClaudeProfileStatusLine -CurrentJson $cur -SourceJson $src) | ConvertFrom-Json
        $o.statusLine.command | Should -Be 'npx -y ccstatusline@latest'
    }
}

Describe 'Set-ClaudeTeammateMode' {
    It 'rewrites an existing teammateMode to in-process' {
        $o = (Set-ClaudeTeammateMode -CurrentJson '{"teammateMode":"tmux","keep":"me"}') | ConvertFrom-Json
        $o.teammateMode | Should -Be 'in-process'
        $o.keep | Should -Be 'me'   # other keys untouched
    }
    It 'never injects the key into a file that lacks it' {
        $o = (Set-ClaudeTeammateMode -CurrentJson '{"env":{"A":"1"}}') | ConvertFrom-Json
        $o.PSObject.Properties['teammateMode'] | Should -BeNullOrEmpty
    }
    It 'is idempotent on an already-pinned file' {
        $o = (Set-ClaudeTeammateMode -CurrentJson '{"teammateMode":"in-process"}') | ConvertFrom-Json
        $o.teammateMode | Should -Be 'in-process'
    }
    It 'honours an explicit -Mode override' {
        $o = (Set-ClaudeTeammateMode -CurrentJson '{"teammateMode":"tmux"}' -Mode 'auto') | ConvertFrom-Json
        $o.teammateMode | Should -Be 'auto'
    }
}

Describe 'Remove-ManagedSettingsKeys array-vs-scalar safety' {
    BeforeAll { Import-Module "$PSScriptRoot/../lib/ClaudeConfig.psm1" -Force }
    It 'does not treat a one-element array as equal to its bare element' {
        # Pipeline ConvertTo-Json unwraps @('x') to "x", wrongly stripping a
        # user's diverged value on uninstall.
        $out = Remove-ManagedSettingsKeys -CurrentJson '{"env":["x"]}' -SourceJson '{"env":"x"}' -WhitelistKeys @('env')
        ($out | ConvertFrom-Json).PSObject.Properties['env'] | Should -Not -BeNullOrEmpty
    }
}
