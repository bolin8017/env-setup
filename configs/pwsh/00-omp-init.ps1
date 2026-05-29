# Oh My Posh prompt.
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    $ompTheme = Join-Path $HOME '.config/oh-my-posh/envsetup.omp.json'
    if (Test-Path $ompTheme) {
        oh-my-posh init pwsh --config $ompTheme | Invoke-Expression
    } else {
        oh-my-posh init pwsh | Invoke-Expression
    }
}
