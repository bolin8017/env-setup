Describe 'bootstrap.ps1 is dot-sourceable and defines helpers' {
    BeforeAll {
        $env:ENVSETUP_BOOTSTRAP_NORUN = '1'   # suppress the main entrypoint
        . (Join-Path $PSScriptRoot '..' 'bootstrap.ps1')
    }
    AfterAll { $env:ENVSETUP_BOOTSTRAP_NORUN = $null }
    It 'defines Initialize-Scoop' { Get-Command Initialize-Scoop -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty }
    It 'defines Sync-Repo'        { Get-Command Sync-Repo -ErrorAction SilentlyContinue        | Should -Not -BeNullOrEmpty }
}
