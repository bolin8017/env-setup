Describe 'bootstrap.ps1 is dot-sourceable and defines helpers' {
    BeforeAll {
        $env:ENVSETUP_BOOTSTRAP_NORUN = '1'   # suppress the main entrypoint
        . (Join-Path $PSScriptRoot '../bootstrap.ps1')
    }
    AfterAll { $env:ENVSETUP_BOOTSTRAP_NORUN = $null }
    It 'defines Initialize-Scoop' { Get-Command Initialize-Scoop -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty }
    It 'defines Sync-Repo'        { Get-Command Sync-Repo -ErrorAction SilentlyContinue        | Should -Not -BeNullOrEmpty }
    It 'defines Invoke-WithRetry' { Get-Command Invoke-WithRetry -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty }
}

Describe 'bootstrap Invoke-WithRetry' {
    BeforeAll {
        $env:ENVSETUP_BOOTSTRAP_NORUN = '1'   # suppress the main entrypoint
        . (Join-Path $PSScriptRoot '../bootstrap.ps1')
    }
    AfterAll { $env:ENVSETUP_BOOTSTRAP_NORUN = $null }

    It 'retries a transient failure, then returns the eventual result' {
        $script:calls = 0
        $r = Invoke-WithRetry -DelaySeconds 0 -MaxAttempts 4 -Action {
            $script:calls++; if ($script:calls -lt 3) { throw 'transient' }; 'done'
        }
        $r | Should -Be 'done'
        $script:calls | Should -Be 3
    }
    It 'rethrows after exhausting attempts' {
        { Invoke-WithRetry -DelaySeconds 0 -MaxAttempts 2 -Action { throw 'always' } } | Should -Throw
    }
}
