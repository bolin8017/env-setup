# ================================================================
# zsh-completions fpath — MUST run before Oh My Zsh's compinit (10-omz)
# ================================================================
# OMZ adds plugin roots to fpath before compinit, but zsh-completions keeps
# its functions under src/, and its plugin.zsh only runs after compinit —
# so loading it as a plugin registers nothing (the documented OMZ pitfall in
# the zsh-completions README). Register src/ here and keep it OUT of the
# plugins=() array in 10-omz.zsh.
_envsetup_zc="${ZSH_CUSTOM:-${ZSH:-$HOME/.oh-my-zsh}/custom}/plugins/zsh-completions/src"
[[ -d "$_envsetup_zc" ]] && fpath+=("$_envsetup_zc")
unset _envsetup_zc
