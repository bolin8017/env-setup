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
