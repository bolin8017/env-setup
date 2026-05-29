BeforeAll {
    Import-Module "$PSScriptRoot/../lib/Common.psm1" -Force
    Import-Module "$PSScriptRoot/../lib/Backup.psm1" -Force
}

Describe 'Backup-File' {
    It 'creates a timestamped copy next to the original' {
        $f = Join-Path $TestDrive 'profile.ps1'; Set-Content $f 'original'
        $bak = Backup-File -Path $f -Stamp '20260529_120000'
        $bak | Should -Be "$f.bak.20260529_120000"
        Get-Content $bak | Should -Be 'original'
    }
    It 'returns $null when the source is missing' {
        $missing = Join-Path $TestDrive 'nope.ps1'
        Backup-File -Path $missing -Stamp '20260529_120000' | Should -BeNullOrEmpty
    }
}
