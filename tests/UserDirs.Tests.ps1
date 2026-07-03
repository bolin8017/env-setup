BeforeAll {
    Import-Module "$PSScriptRoot/../lib/Common.psm1"
    Import-Module "$PSScriptRoot/../lib/Config.psm1"
    Import-Module "$PSScriptRoot/../lib/DryRun.psm1"
    . "$PSScriptRoot/../modules/09-UserDirs.ps1"
}

Describe 'Install-UserDirs' {
    BeforeEach {
        $yaml = @'
user_dirs:
  enabled: true
  paths:
    - Documents
    - Tools
'@
        $f = Join-Path $TestDrive 'c.yaml'; Set-Content -Path $f -Value $yaml
        Import-Config -Path $f
        Mock New-DirOrDryRun { }   # don't touch the real $HOME
    }

    It 'creates each configured path under $HOME' {
        Install-UserDirs
        Should -Invoke New-DirOrDryRun -ParameterFilter { $Path -eq (Join-Path $HOME 'Documents') }
        Should -Invoke New-DirOrDryRun -ParameterFilter { $Path -eq (Join-Path $HOME 'Tools') }
    }

    It 'skips when disabled' {
        $yaml = @'
user_dirs:
  enabled: false
  paths:
    - X
'@
        $f = Join-Path $TestDrive 'c2.yaml'; Set-Content -Path $f -Value $yaml
        Import-Config -Path $f
        Install-UserDirs
        Should -Invoke New-DirOrDryRun -Times 0
    }
}


Describe 'user_dirs path safety (parity with 09-user-dirs.sh)' {
    It 'accepts plain relative paths and rejects absolute, tilde, and dot-dot' {
        Test-SafeUserDirRel 'ok/dir'   | Should -BeTrue
        Test-SafeUserDirRel 'C:\abs'   | Should -BeFalse
        Test-SafeUserDirRel '/rooted'  | Should -BeFalse
        Test-SafeUserDirRel '~/tilde'  | Should -BeFalse
        Test-SafeUserDirRel '../up'    | Should -BeFalse
        Test-SafeUserDirRel 'a/../up'  | Should -BeFalse
        Test-SafeUserDirRel ''         | Should -BeFalse
    }

    It 'creates only the safe configured paths' {
        $yaml = @'
user_dirs:
  enabled: true
  paths:
    - SafeDir
    - ../escape
'@
        $f = Join-Path $TestDrive 'c3.yaml'; Set-Content -Path $f -Value $yaml
        Import-Config -Path $f
        Mock New-DirOrDryRun { }
        Install-UserDirs
        Should -Invoke New-DirOrDryRun -Times 1 -Exactly
        Should -Invoke New-DirOrDryRun -ParameterFilter { $Path -eq (Join-Path $HOME 'SafeDir') }
    }
}
