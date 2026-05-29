# UTF-8 console output so Nerd Font glyphs and rg/bat output render correctly.
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# pyenv-win shims on PATH (nvm-windows registers its own shim via scoop).
if ($env:PYENV) {
    foreach ($sub in 'bin', 'shims') {
        $p = Join-Path $env:PYENV $sub
        if ((Test-Path $p) -and ($env:Path -notlike "*$p*")) { $env:Path = "$p;$env:Path" }
    }
}
