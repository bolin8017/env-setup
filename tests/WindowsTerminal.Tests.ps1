BeforeAll { Import-Module "$PSScriptRoot/../lib/WindowsTerminal.psm1" -Force }

Describe 'Merge-WtSettings' {
    It 'sets the font face and preserves every other key' {
        $cur = '{"defaultProfile":"{abc}","profiles":{"list":[{"name":"X"}]},"theme":"dark"}'
        $o = (Merge-WtSettings -CurrentJson $cur -FontFace 'MesloLGS NF') | ConvertFrom-Json
        $o.profiles.defaults.font.face | Should -Be 'MesloLGS NF'
        $o.defaultProfile             | Should -Be '{abc}'
        $o.theme                      | Should -Be 'dark'
        $o.profiles.list[0].name      | Should -Be 'X'
    }
    It 'is idempotent on an already-configured file' {
        $cur = '{"profiles":{"defaults":{"font":{"face":"MesloLGS NF"}}}}'
        $o = (Merge-WtSettings -CurrentJson $cur -FontFace 'MesloLGS NF') | ConvertFrom-Json
        $o.profiles.defaults.font.face | Should -Be 'MesloLGS NF'
    }
    It 'creates the font block from minimal settings' {
        $o = (Merge-WtSettings -CurrentJson '{"x":1}' -FontFace 'MesloLGS NF') | ConvertFrom-Json
        $o.profiles.defaults.font.face | Should -Be 'MesloLGS NF'
        $o.x | Should -Be 1
    }
}
