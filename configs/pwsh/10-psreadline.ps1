# PSReadLine: history-based predictions, history search, menu completion.
if (Get-Module -ListAvailable PSReadLine) {
    Import-Module PSReadLine
    Set-PSReadLineOption -PredictionSource HistoryAndPlugin -ErrorAction SilentlyContinue
    Set-PSReadLineOption -PredictionViewStyle ListView -ErrorAction SilentlyContinue
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd
    Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineKeyHandler -Key Tab       -Function MenuComplete
}
