# PSReadLine: history-based predictions, history search, menu completion.
if (Get-Module -ListAvailable PSReadLine) {
    Import-Module PSReadLine
    # Predictions need PSReadLine >= 2.2 AND a non-redirected console:
    #  - -PredictionSource (2.1) / -PredictionViewStyle (2.2) don't exist on the
    #    PSReadLine 2.0 in Windows PowerShell 5.1; a missing parameter is a
    #    binding-time failure that -ErrorAction can't suppress -> gate on version.
    #  - with output redirected/piped the same options throw a "console doesn't
    #    support virtual terminal" error -> gate on [Console]::IsOutputRedirected
    #    so we don't call them there.
    if ((Get-Module PSReadLine).Version -ge [version]'2.2.0' -and -not [Console]::IsOutputRedirected) {
        Set-PSReadLineOption -PredictionSource HistoryAndPlugin -ErrorAction SilentlyContinue
        Set-PSReadLineOption -PredictionViewStyle ListView -ErrorAction SilentlyContinue
    }
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd
    Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineKeyHandler -Key Tab       -Function MenuComplete
}
