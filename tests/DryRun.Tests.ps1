BeforeAll {
    Import-Module "$PSScriptRoot/../lib/Common.psm1" -Force
    Import-Module "$PSScriptRoot/../lib/DryRun.psm1" -Force
}

Describe 'DryRun.psm1' {
    BeforeEach {
        $env:ENVSETUP_DRY_RUN = $null
        $env:ENVSETUP_AUTO_YES = $null
        $env:ENVSETUP_KEEP_EXISTING = $null
    }

    Context 'Invoke-OrDryRun' {
        # The action path is baked into the scriptblock string (no variable capture),
        # so behavior is observed via a file side-effect — robust under Pester scoping.
        It 'does not run the action under dry-run' {
            $env:ENVSETUP_DRY_RUN = 'true'
            $marker = Join-Path $TestDrive 'dry.txt'
            Invoke-OrDryRun -Description 'x' -Action ([scriptblock]::Create("Set-Content -LiteralPath '$marker' -Value ok"))
            Test-Path $marker | Should -BeFalse
        }
        It 'runs the action when not dry-run' {
            $marker = Join-Path $TestDrive 'real.txt'
            Invoke-OrDryRun -Description 'x' -Action ([scriptblock]::Create("Set-Content -LiteralPath '$marker' -Value ok"))
            Test-Path $marker | Should -BeTrue
        }
    }

    Context 'Copy-OrDryRun + New-DirOrDryRun' {
        It 'copies a file for real' {
            $src = Join-Path $TestDrive 'a.txt'; Set-Content $src 'hi'
            $dstDir = Join-Path $TestDrive 'sub'
            New-DirOrDryRun -Path $dstDir
            $dst = Join-Path $dstDir 'a.txt'
            Copy-OrDryRun -Source $src -Destination $dst
            Get-Content $dst | Should -Be 'hi'
        }
    }

    Context 'Deploy-Config' {
        It 'creates destination when absent' {
            $src = Join-Path $TestDrive 'src1'; Set-Content $src 'v1'
            $dst = Join-Path $TestDrive 'dst1'
            Deploy-Config -Source $src -Destination $dst
            Get-Content $dst | Should -Be 'v1'
        }
        It 'keeps existing under KeepExisting' {
            $src = Join-Path $TestDrive 'src2'; Set-Content $src 'new'
            $dst = Join-Path $TestDrive 'dst2'; Set-Content $dst 'old'
            $env:ENVSETUP_KEEP_EXISTING = 'true'
            Deploy-Config -Source $src -Destination $dst
            Get-Content $dst | Should -Be 'old'
        }
        It 'overwrites under AutoYes' {
            $src = Join-Path $TestDrive 'src3'; Set-Content $src 'new'
            $dst = Join-Path $TestDrive 'dst3'; Set-Content $dst 'old'
            $env:ENVSETUP_AUTO_YES = 'true'
            Deploy-Config -Source $src -Destination $dst
            Get-Content $dst | Should -Be 'new'
        }
        It 'skips when destination is byte-identical to source' {
            # No env flags (not AutoYes/KeepExisting): the identical-content check
            # short-circuits before any Confirm-Action prompt would fire.
            $src = Join-Path $TestDrive 'idsrc'; Set-Content $src 'same line'
            $dst = Join-Path $TestDrive 'iddst'; Set-Content $dst 'same line'
            Deploy-Config -Source $src -Destination $dst
            Get-Content $dst | Should -Be 'same line'
        }
    }
}
