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


Describe 'newest-backup selection is by filename stamp, not mtime' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../lib/Backup.psm1" -Force
        $env:ENVSETUP_DRY_RUN = $null
        $env:ENVSETUP_NO_RESTORE = $null
    }
    It 'Get-NewestBakPath picks the lexically newest stamp even with reversed mtimes' {
        $f = Join-Path $TestDrive 'x.json'
        Set-Content $f 'live'
        Set-Content "$f.bak.20250101_000000" 'old'
        Set-Content "$f.bak.20260101_000000" 'new'
        # Copy-Item preserves source mtimes in real installs; simulate the
        # hazard by making the OLD backup the most recently written file.
        (Get-Item "$f.bak.20260101_000000").LastWriteTime = (Get-Date).AddDays(-30)
        (Get-Item "$f.bak.20250101_000000").LastWriteTime = (Get-Date)
        Get-NewestBakPath -Path $f | Should -Be "$f.bak.20260101_000000"
    }
    It 'Restore-NewestBak restores the lexically newest stamp' {
        $f = Join-Path $TestDrive 'y.json'
        Set-Content $f 'live'
        Set-Content "$f.bak.20250101_000000" 'old'
        Set-Content "$f.bak.20260101_000000" 'new'
        (Get-Item "$f.bak.20260101_000000").LastWriteTime = (Get-Date).AddDays(-30)
        (Get-Item "$f.bak.20250101_000000").LastWriteTime = (Get-Date)
        Restore-NewestBak -Path $f
        (Get-Content $f) | Should -Be 'new'
    }
}
