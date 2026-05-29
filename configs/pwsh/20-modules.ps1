# Productivity modules (loaded if installed).
foreach ($m in 'Terminal-Icons', 'posh-git', 'PSFzf') {
    if (Get-Module -ListAvailable $m) { Import-Module $m -ErrorAction SilentlyContinue }
}
