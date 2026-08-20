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
    It 'sets font.size when -FontSize is given' {
        $cur = '{"profiles":{"defaults":{"font":{"face":"Old","size":11}}}}'
        $o = (Merge-WtSettings -CurrentJson $cur -FontFace 'MesloLGS NF' -FontSize 14) | ConvertFrom-Json
        $o.profiles.defaults.font.size | Should -Be 14
        $o.profiles.defaults.font.face | Should -Be 'MesloLGS NF'
    }
    It 'adds font.size to a file that had none when -FontSize is given' {
        $o = (Merge-WtSettings -CurrentJson '{"x":1}' -FontFace 'MesloLGS NF' -FontSize 14) | ConvertFrom-Json
        $o.profiles.defaults.font.size | Should -Be 14
    }
    It 'leaves an existing font.size alone when -FontSize is omitted' {
        $cur = '{"profiles":{"defaults":{"font":{"size":11}}}}'
        $o = (Merge-WtSettings -CurrentJson $cur -FontFace 'MesloLGS NF') | ConvertFrom-Json
        $o.profiles.defaults.font.size | Should -Be 11
    }
    It 'does not invent font.size when -FontSize is omitted' {
        $o = (Merge-WtSettings -CurrentJson '{"x":1}' -FontFace 'MesloLGS NF') | ConvertFrom-Json
        $o.profiles.defaults.font.PSObject.Properties['size'] | Should -BeNullOrEmpty
    }
}


Describe 'Merge-WtSettings array-form profiles' {
    BeforeAll { Import-Module "$PSScriptRoot/../lib/WindowsTerminal.psm1" -Force }
    It 'refuses the legacy array form instead of corrupting every profile' {
        { Merge-WtSettings -CurrentJson '{"profiles":[{"name":"PS"}]}' } |
            Should -Throw -ExpectedMessage '*array*'
    }
}

Describe 'Set-WtDefaultProfile' {
    BeforeAll {
        # Shape mirrors a real settings.json: WT's PowershellCore generator emits
        # one entry per detected pwsh install, and derives each guid from the
        # install path - so there is no constant to match on, only source+name.
        $script:Pwsh   = '{"guid":"{574e775e}","name":"PowerShell","source":"Windows.Terminal.PowershellCore"}'
        $script:Scoop  = '{"guid":"{fe66f4b8}","name":"PowerShell (scoop)","source":"Windows.Terminal.PowershellCore"}'
        $script:Win51  = '{"guid":"{61c54bbd}","name":"Windows PowerShell","commandline":"powershell.exe"}'
        function New-Settings { param([string[]]$Profiles, [string]$Default = '{61c54bbd}')
            '{"defaultProfile":"' + $Default + '","profiles":{"list":[' + ($Profiles -join ',') + ']}}'
        }
    }

    It 'points defaultProfile at the sole PowerShell 7 profile' {
        $o = (Set-WtDefaultProfile -CurrentJson (New-Settings @($Win51, $Pwsh))) | ConvertFrom-Json
        $o.defaultProfile | Should -Be '{574e775e}'
    }

    It 'preserves every other key' {
        $cur = '{"defaultProfile":"{61c54bbd}","theme":"dark","profiles":{"defaults":{"font":{"face":"MesloLGS NF"}},"list":[' + $Pwsh + ']}}'
        $o = (Set-WtDefaultProfile -CurrentJson $cur) | ConvertFrom-Json
        $o.theme                       | Should -Be 'dark'
        $o.profiles.defaults.font.face | Should -Be 'MesloLGS NF'
        $o.profiles.list[0].guid       | Should -Be '{574e775e}'
    }

    It 'ignores a scoop-installed pwsh so the winget install wins' {
        $o = (Set-WtDefaultProfile -CurrentJson (New-Settings @($Scoop, $Pwsh))) | ConvertFrom-Json
        $o.defaultProfile | Should -Be '{574e775e}'
    }

    It 'ignores PowerShell Preview' {
        $prev = '{"guid":"{aaa}","name":"PowerShell Preview","source":"Windows.Terminal.PowershellCore"}'
        $o = (Set-WtDefaultProfile -CurrentJson (New-Settings @($prev, $Pwsh))) | ConvertFrom-Json
        $o.defaultProfile | Should -Be '{574e775e}'
    }

    It 'ignores a hidden profile' {
        $hidden = '{"guid":"{bbb}","name":"PowerShell","source":"Windows.Terminal.PowershellCore","hidden":true}'
        $o = (Set-WtDefaultProfile -CurrentJson (New-Settings @($hidden, $Pwsh))) | ConvertFrom-Json
        $o.defaultProfile | Should -Be '{574e775e}'
    }

    It 'is idempotent' {
        $once  = Set-WtDefaultProfile -CurrentJson (New-Settings @($Win51, $Pwsh))
        $twice = Set-WtDefaultProfile -CurrentJson $once
        ($twice | ConvertFrom-Json).defaultProfile | Should -Be '{574e775e}'
    }

    It 'refuses to guess when no PowerShell 7 profile is present' {
        { Set-WtDefaultProfile -CurrentJson (New-Settings @($Win51)) } |
            Should -Throw -ExpectedMessage '*found 0*'
    }

    It 'refuses to guess when several candidates tie' {
        $other = '{"guid":"{ccc}","name":"PowerShell","source":"Windows.Terminal.PowershellCore"}'
        { Set-WtDefaultProfile -CurrentJson (New-Settings @($Pwsh, $other)) } |
            Should -Throw -ExpectedMessage '*found 2*'
    }

    It 'refuses the legacy array form' {
        { Set-WtDefaultProfile -CurrentJson '{"profiles":[{"name":"PS"}]}' } |
            Should -Throw -ExpectedMessage '*array*'
    }

    It 'refuses settings with no profile list at all' {
        { Set-WtDefaultProfile -CurrentJson '{"x":1}' } | Should -Throw
    }
}
