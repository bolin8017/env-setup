# CLI tool integrations: zoxide (smarter cd) + PSFzf key bindings.
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    (zoxide init powershell | Out-String) | Invoke-Expression
}
if (Get-Module -ListAvailable PSFzf) {
    Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r' -ErrorAction SilentlyContinue
}
