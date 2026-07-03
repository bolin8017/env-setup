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


Describe 'bootstrap 5.1 hardening helpers' {
    BeforeAll {
        $env:ENVSETUP_BOOTSTRAP_NORUN = '1'
        . (Join-Path $PSScriptRoot '../bootstrap.ps1')
    }
    AfterAll { $env:ENVSETUP_BOOTSTRAP_NORUN = $null }

    It 'defines Update-SessionPath'   { Get-Command Update-SessionPath -ErrorAction SilentlyContinue   | Should -Not -BeNullOrEmpty }
    It 'defines Initialize-Pwsh'      { Get-Command Initialize-Pwsh -ErrorAction SilentlyContinue      | Should -Not -BeNullOrEmpty }
    It 'defines Select-EngineRuntime' { Get-Command Select-EngineRuntime -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty }

    It 'stays in-process on PowerShell 6+' -Skip:($PSVersionTable.PSVersion.Major -lt 6) {
        Select-EngineRuntime | Should -BeNullOrEmpty
    }
    It 'selects pwsh when running under 5.1 with pwsh present' -Skip:($PSVersionTable.PSVersion.Major -ge 6 -or -not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
        Select-EngineRuntime | Should -Not -BeNullOrEmpty
    }
    It 'Update-SessionPath keeps PATH non-empty and does not throw' {
        { Update-SessionPath } | Should -Not -Throw
        $env:Path | Should -Not -BeNullOrEmpty
    }
}
