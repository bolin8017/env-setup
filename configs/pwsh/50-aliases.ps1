# Load shared aliases/functions.
$aliasFile = Join-Path $HOME '.config/powershell/aliases.ps1'
if (Test-Path $aliasFile) { . $aliasFile }
