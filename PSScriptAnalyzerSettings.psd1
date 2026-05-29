@{
    # Rules excluded for this installer project, each with a deliberate reason.
    ExcludeRules = @(
        # Colored installer output uses Write-Host intentionally (parity with the
        # Bash engine's `echo -e`); these are user-facing messages, not data.
        'PSAvoidUsingWriteHost'

        # Cross-platform repo (edited on Linux/macOS, run on Windows). BOM-free
        # UTF-8 is intentional; a BOM breaks tooling and diffs on Unix.
        'PSUseBOMForUnicodeEncodedFile'

        # bootstrap.ps1 installs scoop via the official `irm get.scoop.sh | iex`
        # pattern — the PowerShell analog of the Bash engine's `curl | bash`.
        'PSAvoidUsingInvokeExpression'

        # Dry-run is centralized via ENVSETUP_DRY_RUN / Invoke-OrDryRun rather than
        # per-function -WhatIf. These are internal helpers, not public cmdlets.
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
