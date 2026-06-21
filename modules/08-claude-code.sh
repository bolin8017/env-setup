#!/usr/bin/env bash
# 08-claude-code.sh — Install Claude Code CLI and sync personal configuration
# Dependencies: lib/common.sh, lib/config.sh, lib/dryrun.sh, lib/yaml.sh

# =============================================================================
# _install_claude_native — Native installer (curl | bash), idempotent
# =============================================================================
_install_claude_native() {
    print_header "Claude Code"

    if command_exists claude; then
        log_success "Claude Code already installed"
        return 0
    fi

    log_info "Installing Claude Code via native installer..."

    # dry_run_cmd cannot be used here because installation is a two-step
    # process (download then execute) and we need to validate the download
    # before running it. Show the equivalent piped command for clarity.
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would run: curl -fsSL https://claude.ai/install.sh | bash"
        return 0
    fi

    local installer
    if ! installer="$(curl -fsSL https://claude.ai/install.sh)"; then
        log_error "Failed to download Claude Code installer"
        return 1
    fi

    if [[ -z "$installer" ]]; then
        log_error "Claude Code installer script is empty — download may have been intercepted"
        return 1
    fi

    local install_output
    if ! install_output="$(bash -c "$installer" 2>&1)"; then
        log_error "Claude Code installer failed:"
        log_error "$install_output"
        return 1
    fi

    # Post-install verification
    # Ensure ~/.local/bin is on PATH for the command_exists check below
    export PATH="$HOME/.local/bin:$PATH"
    if command_exists claude; then
        log_success "Claude Code installed"
    else
        log_error "Claude Code installation completed but 'claude' not found in PATH"
        return 1
    fi
}

# =============================================================================
# _deploy_ccstatusline_config — Copy ccstatusline widget template
# =============================================================================
_deploy_ccstatusline_config() {
    local src="${ENV_SETUP_DIR}/configs/ccstatusline/settings.json"
    local dest_dir="${HOME}/.config/ccstatusline"
    local dest="${dest_dir}/settings.json"

    dry_run_mkdir "$dest_dir"
    deploy_config "$src" "$dest" "ccstatusline settings.json"

    # Launcher wrapper that guarantees a node runtime is on PATH. The bare
    # `npx` in settings.json fails in Claude Code's non-interactive shell when
    # nvm is lazy-loaded (interactive-only). The Unix statusLine command is
    # repointed at this wrapper by _set_ccstatusline_command (after the merge).
    local wrapper_src="${ENV_SETUP_DIR}/configs/ccstatusline/statusline.sh"
    local wrapper_dest="${dest_dir}/statusline.sh"
    if [[ -f "$wrapper_src" ]]; then
        dry_run_cp "$wrapper_src" "$wrapper_dest"
        [[ "${DRY_RUN:-false}" == "true" ]] || chmod +x "$wrapper_dest"
    fi
}

# =============================================================================
# _install_ccstatusline — Orchestrate ccstatusline widget step.
# The ~/.claude/settings.json statusLine block is now handled uniformly by
# _merge_claude_settings via the settings_merge_keys whitelist.
# =============================================================================
_install_ccstatusline() {
    if ! cfg_enabled "claude_code.ccstatusline.enabled"; then
        log_info "ccstatusline disabled in config — skipping"
        return 0
    fi

    print_header "ccstatusline"
    _deploy_ccstatusline_config
}

# =============================================================================
# _sync_claude_global_md — Deploy ~/.claude/CLAUDE.md from repo
# =============================================================================
_sync_claude_global_md() {
    if ! cfg_enabled "claude_code.sync_global_md"; then
        log_info "sync_global_md disabled — skipping"
        return 0
    fi

    local src="${ENV_SETUP_DIR}/configs/claude/CLAUDE.md"
    local dest="${HOME}/.claude/CLAUDE.md"

    dry_run_mkdir "$(dirname "$dest")"
    deploy_config "$src" "$dest" "global CLAUDE.md"
}

# =============================================================================
# _sync_claude_rules — Sync ~/.claude/rules/ from configs/claude/rules/
# Additive: only deploys files present in the repo; existing user-only rules
# are preserved.
# =============================================================================
_sync_claude_rules() {
    if ! cfg_enabled "claude_code.sync_rules"; then
        log_info "sync_rules disabled — skipping"
        return 0
    fi

    local src_dir="${ENV_SETUP_DIR}/configs/claude/rules"
    local dest_dir="${HOME}/.claude/rules"

    if [[ ! -d "$src_dir" ]]; then
        log_warn "rules source dir not found: ${src_dir}"
        return 0
    fi

    dry_run_mkdir "$dest_dir"

    local f
    shopt -s nullglob
    for f in "$src_dir"/*.md; do
        deploy_config "$f" "${dest_dir}/$(basename "$f")" "rule $(basename "$f")"
    done
    shopt -u nullglob
}

# =============================================================================
# _sync_claude_commands — Sync ~/.claude/commands/ from configs/claude/commands/
# Additive: existing user-only command files are preserved.
# =============================================================================
_sync_claude_commands() {
    if ! cfg_enabled "claude_code.sync_commands"; then
        log_info "sync_commands disabled — skipping"
        return 0
    fi

    local src_dir="${ENV_SETUP_DIR}/configs/claude/commands"
    local dest_dir="${HOME}/.claude/commands"

    if [[ ! -d "$src_dir" ]]; then
        log_warn "commands source dir not found: ${src_dir}"
        return 0
    fi

    dry_run_mkdir "$dest_dir"

    local f
    shopt -s nullglob
    for f in "$src_dir"/*.md; do
        deploy_config "$f" "${dest_dir}/$(basename "$f")" "command $(basename "$f")"
    done
    shopt -u nullglob
}

# =============================================================================
# _sync_claude_agents — Sync ~/.claude/agents/ from configs/claude/agents/
# Additive: existing user-only agent files are preserved.
# =============================================================================
_sync_claude_agents() {
    if ! cfg_enabled "claude_code.sync_agents"; then
        log_info "sync_agents disabled — skipping"
        return 0
    fi

    local src_dir="${ENV_SETUP_DIR}/configs/claude/agents"
    local dest_dir="${HOME}/.claude/agents"

    if [[ ! -d "$src_dir" ]]; then
        log_warn "agents source dir not found: ${src_dir}"
        return 0
    fi

    dry_run_mkdir "$dest_dir"

    local f
    shopt -s nullglob
    for f in "$src_dir"/*.md; do
        deploy_config "$f" "${dest_dir}/$(basename "$f")" "agent $(basename "$f")"
    done
    shopt -u nullglob
}

# =============================================================================
# _merge_claude_settings — Whitelist jq-merge of ~/.claude/settings.json.
# For each top-level key in claude_code.settings_merge_keys, copies that field
# from the repo's settings.json into the user's. Other keys (e.g. internal
# experimental flags) are preserved verbatim. Idempotent: skips if the merged
# result equals the current file. Backs up before any mutation.
# =============================================================================
_merge_claude_settings() {
    local src="${ENV_SETUP_DIR}/configs/claude/settings.json"
    local dest="${HOME}/.claude/settings.json"

    if [[ ! -f "$src" ]]; then
        log_warn "claude settings source not found: ${src}"
        return 0
    fi

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would merge whitelisted keys into ${dest}"
        return 0
    fi

    # KEEP_EXISTING mode: bail out before mutating anything
    if [[ "${KEEP_EXISTING:-false}" == "true" ]] && [[ -f "$dest" ]]; then
        log_info "[SKIP] Keeping existing settings.json (--keep-existing)"
        return 0
    fi

    dry_run_mkdir "$(dirname "$dest")"

    # Case 1: dest does not exist — copy the source as-is (already whitelisted)
    if [[ ! -f "$dest" ]]; then
        cp -p "$src" "$dest"
        log_success "Created ${dest} from repo template"
        return 0
    fi

    # Case 2: jq missing — degrade gracefully
    if ! command_exists jq; then
        log_warn "jq not found — skipping ~/.claude/settings.json merge"
        return 0
    fi

    # Case 3: malformed JSON — refuse to guess
    if ! jq empty "$dest" 2>/dev/null; then
        log_error "${dest} is not valid JSON — skipping merge. Fix manually."
        return 0
    fi

    # Collect whitelist from config.yaml
    local keys=()
    while IFS= read -r k; do
        [[ -n "$k" ]] && keys+=("$k")
    done < <(cfg_list "claude_code.settings_merge_keys")

    if [[ ${#keys[@]} -eq 0 ]]; then
        log_warn "settings_merge_keys is empty in config.yaml — skipping merge"
        return 0
    fi

    # Pass keys as data (--args) instead of building the jq filter via string
    # concatenation. This avoids any quoting / injection surface if a key
    # contains characters like " or \, and is the idiomatic jq pattern for
    # "operate on a list of keys".
    # shellcheck disable=SC2016  # $ARGS, $k, $src are jq variables, not shell
    local jq_filter='reduce $ARGS.positional[] as $k (.; .[$k] = $src[0][$k])'

    # Idempotency check: would the merged result equal the current file?
    local current expected
    current=$(jq -S . "$dest" 2>/dev/null)
    expected=$(jq -S --slurpfile src "$src" "$jq_filter" "$dest" --args "${keys[@]}" 2>/dev/null) || {
        log_error "jq merge dry-evaluation failed — skipping (no changes made)"
        return 0
    }
    # On Unix the deployed statusLine points at the ccstatusline launcher wrapper
    # (node-on-PATH guarantee), not the repo's portable `npx ...`. Fold that into
    # the idempotency baseline so an already-synced file isn't re-merged (and
    # re-backed-up) on every run; the actual repoint is _set_ccstatusline_command.
    if cfg_enabled "claude_code.ccstatusline.enabled"; then
        local _cc_expected
        if _cc_expected=$(printf '%s' "$expected" | jq -S --arg cmd "${HOME}/.config/ccstatusline/statusline.sh" \
                'if .statusLine then .statusLine.command = $cmd else . end' 2>/dev/null); then
            expected="$_cc_expected"
        fi
    fi
    if [[ "$current" == "$expected" ]]; then
        log_info "claude settings already in sync — skipping"
        return 0
    fi

    # Interactive mode: show per-key diff summary then prompt
    if [[ "${AUTO_YES:-false}" != "true" ]]; then
        log_info "Settings merge preview (will apply to ${dest}):"
        local changing=0
        for k in "${keys[@]}"; do
            local src_v dst_v
            src_v=$(jq -Sc --arg k "$k" '.[$k] // null' "$src" 2>/dev/null)
            dst_v=$(jq -Sc --arg k "$k" '.[$k] // null' "$dest" 2>/dev/null)
            if [[ "$src_v" != "$dst_v" ]]; then
                log_info "  ${k}: will change"
                (( changing += 1 ))
            else
                log_info "  ${k}: unchanged"
            fi
        done
        if [[ $changing -eq 0 ]]; then
            log_info "no whitelisted keys actually changing — skipping"
            return 0
        fi
        if ! ask_yes_no "Apply merge to ${dest}?"; then
            log_info "[SKIP] Keeping existing settings.json"
            return 0
        fi
    fi

    # Backup before mutation
    local ts bak
    ts="$(date +%Y%m%d_%H%M%S)"
    bak="${dest}.bak.${ts}"
    if ! cp -p "$dest" "$bak"; then
        log_error "Failed to create backup ${bak} — aborting merge"
        return 0
    fi
    log_info "Backed up existing settings.json to ${bak}"

    # Apply merge atomically
    local tmp="${dest}.tmp.$$"
    if jq --slurpfile src "$src" "$jq_filter" "$dest" --args "${keys[@]}" > "$tmp"; then
        if mv "$tmp" "$dest"; then
            log_success "Merged ${#keys[@]} whitelisted keys into ${dest}"
        else
            log_error "Failed to move ${tmp} into place — backup at ${bak}"
            rm -f "$tmp"
        fi
    else
        log_error "jq merge failed — original preserved, backup at ${bak}"
        rm -f "$tmp"
    fi
}

# =============================================================================
# _set_ccstatusline_command — Repoint ~/.claude/settings.json's statusLine at the
# deployed launcher wrapper (Unix only; node-on-PATH guarantee under lazy nvm).
# The shared configs/claude/settings.json keeps the portable `npx ...` command
# for the Windows engine. Runs AFTER _merge_claude_settings so the whitelist
# merge doesn't clobber it. Idempotent; honours DRY_RUN.
# =============================================================================
_set_ccstatusline_command() {
    cfg_enabled "claude_code.ccstatusline.enabled" || return 0

    local dest="${HOME}/.claude/settings.json"
    local wrapper="${HOME}/.config/ccstatusline/statusline.sh"

    [[ -f "$dest" ]] || return 0

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would point statusLine.command at ${wrapper}"
        return 0
    fi

    command_exists jq || { log_warn "jq not found — leaving statusLine.command as-is"; return 0; }
    jq empty "$dest" 2>/dev/null || { log_warn "${dest} not valid JSON — leaving statusLine.command as-is"; return 0; }

    # Idempotent: nothing to do if already pointed at the wrapper.
    local cur
    cur=$(jq -r '.statusLine.command // ""' "$dest" 2>/dev/null)
    [[ "$cur" == "$wrapper" ]] && return 0

    local tmp="${dest}.tmp.$$"
    if jq --arg cmd "$wrapper" 'if .statusLine then .statusLine.command = $cmd else . end' "$dest" > "$tmp" && mv "$tmp" "$dest"; then
        log_success "Pointed statusLine.command at ${wrapper}"
    else
        rm -f "$tmp"
        log_warn "Failed to update statusLine.command — left as-is"
    fi
}

# =============================================================================
# _register_plugin_marketplaces — Run `claude plugin marketplace add` for each
# entry in claude_code.marketplaces. Idempotent via known_marketplaces.json.
# =============================================================================
_register_plugin_marketplaces() {
    if ! cfg_enabled "claude_code.register_marketplaces"; then
        log_info "register_marketplaces disabled — skipping"
        return 0
    fi

    if ! command_exists claude; then
        log_warn "claude CLI not found — cannot register marketplaces"
        return 0
    fi

    local marketplaces=()
    while IFS= read -r m; do
        [[ -n "$m" ]] && marketplaces+=("$m")
    done < <(cfg_list "claude_code.marketplaces")

    if [[ ${#marketplaces[@]} -eq 0 ]]; then
        log_info "no marketplaces declared in config — skipping"
        return 0
    fi

    local known="${HOME}/.claude/plugins/known_marketplaces.json"
    local repo
    for repo in "${marketplaces[@]}"; do
        # Idempotency: already registered?
        if [[ -f "$known" ]] && command_exists jq; then
            local already
            already=$(jq -r --arg r "$repo" \
                '[to_entries[] | select(.value.source.repo == $r)] | length' \
                "$known" 2>/dev/null || echo 0)
            if [[ "${already:-0}" -gt 0 ]]; then
                log_info "marketplace ${repo} already registered — skipping"
                continue
            fi
        fi

        if [[ "${DRY_RUN:-false}" == "true" ]]; then
            log_info "[DRY-RUN] Would run: claude plugin marketplace add ${repo}"
            continue
        fi

        if claude plugin marketplace add "$repo" >/dev/null 2>&1; then
            log_success "Registered marketplace: ${repo}"
        else
            log_warn "Failed to register marketplace: ${repo}"
        fi
    done
}

# =============================================================================
# _install_enabled_plugins — Ensure every plugin marked `true` in
# configs/claude/settings.json is actually downloaded and present in
# ~/.claude/plugins/cache/. Without this, enabledPlugins entries on a fresh
# machine resolve to "not installed" errors until the user manually runs
# `/plugin install` for each. Idempotent via installed_plugins.json.
# =============================================================================
_install_enabled_plugins() {
    if ! cfg_enabled "claude_code.install_enabled_plugins"; then
        log_info "install_enabled_plugins disabled — skipping"
        return 0
    fi

    if ! command_exists claude; then
        log_warn "claude CLI not found — cannot install plugins"
        return 0
    fi

    if ! command_exists jq; then
        log_warn "jq not found — cannot read enabledPlugins"
        return 0
    fi

    local src="${ENV_SETUP_DIR}/configs/claude/settings.json"
    if [[ ! -f "$src" ]]; then
        log_warn "settings template not found: ${src}"
        return 0
    fi

    local installed="${HOME}/.claude/plugins/installed_plugins.json"

    local plugin
    while IFS= read -r plugin; do
        [[ -z "$plugin" ]] && continue

        # Idempotency: skip if already in installed_plugins.json
        if [[ -f "$installed" ]]; then
            local already
            already=$(jq -r --arg p "$plugin" \
                '.plugins[$p] // [] | length' \
                "$installed" 2>/dev/null || echo 0)
            if [[ "${already:-0}" -gt 0 ]]; then
                log_info "plugin ${plugin} already installed — skipping"
                continue
            fi
        fi

        if [[ "${DRY_RUN:-false}" == "true" ]]; then
            log_info "[DRY-RUN] Would run: claude plugin install ${plugin}"
            continue
        fi

        if claude plugin install "$plugin" >/dev/null 2>&1; then
            log_success "Installed plugin: ${plugin}"
        else
            log_warn "Failed to install plugin: ${plugin}"
        fi
    done < <(jq -r '.enabledPlugins | to_entries[] | select(.value == true) | .key' "$src" 2>/dev/null)
}

# =============================================================================
# _sync_mcp_servers — Future-proof sync of user-scoped MCP servers.
# Source: configs/claude/mcp-servers.json — typically {"mcpServers": {}} until
# the user starts adding entries. Merges the mcpServers object into
# ~/.claude.json. No-op when source declares no servers.
# =============================================================================
_sync_mcp_servers() {
    if ! cfg_enabled "claude_code.sync_mcp_servers"; then
        log_info "sync_mcp_servers disabled — skipping"
        return 0
    fi

    local src="${ENV_SETUP_DIR}/configs/claude/mcp-servers.json"
    local dest="${HOME}/.claude.json"

    if [[ ! -f "$src" ]]; then
        log_info "no mcp-servers.json in repo — skipping"
        return 0
    fi

    if ! command_exists jq; then
        log_warn "jq not found — skipping MCP servers sync"
        return 0
    fi

    # No-op when source declares zero servers (placeholder mode)
    local count
    count=$(jq -r '.mcpServers // {} | length' "$src" 2>/dev/null || echo 0)
    if [[ "${count:-0}" -eq 0 ]]; then
        log_info "no MCP servers declared in repo — skipping"
        return 0
    fi

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would merge ${count} MCP server(s) into ${dest}"
        return 0
    fi

    if [[ ! -f "$dest" ]]; then
        log_warn "${dest} does not exist — run Claude Code at least once first; skipping MCP sync"
        return 0
    fi

    # KEEP_EXISTING mode: bail out
    if [[ "${KEEP_EXISTING:-false}" == "true" ]]; then
        log_info "[SKIP] Keeping existing MCP servers (--keep-existing)"
        return 0
    fi

    if ! jq empty "$dest" 2>/dev/null; then
        log_error "${dest} is not valid JSON — skipping MCP sync. Fix manually."
        return 0
    fi

    # Idempotency: compare merged result with current
    local current expected
    current=$(jq -S '.mcpServers // {}' "$dest" 2>/dev/null)
    expected=$(jq -S --slurpfile src "$src" \
        '(.mcpServers // {}) * ($src[0].mcpServers // {})' \
        "$dest" 2>/dev/null) || {
        log_error "jq dry-evaluation failed — skipping (no changes made)"
        return 0
    }
    if [[ "$current" == "$expected" ]]; then
        log_info "MCP servers already in sync — skipping"
        return 0
    fi

    # Interactive mode: show what's changing and prompt
    if [[ "${AUTO_YES:-false}" != "true" ]]; then
        log_info "MCP servers merge preview (will apply to ${dest}):"
        local added_keys
        added_keys=$(jq -r --slurpfile src "$src" \
            '(($src[0].mcpServers // {}) | keys) - ((.mcpServers // {}) | keys) | .[]' \
            "$dest" 2>/dev/null)
        if [[ -n "$added_keys" ]]; then
            log_info "  adding:"
            while IFS= read -r k; do log_info "    - ${k}"; done <<< "$added_keys"
        fi
        if ! ask_yes_no "Apply MCP merge to ${dest}?"; then
            log_info "[SKIP] Keeping existing MCP servers"
            return 0
        fi
    fi

    # Backup before mutation
    local ts bak
    ts="$(date +%Y%m%d_%H%M%S)"
    bak="${dest}.bak.${ts}"
    if ! cp -p "$dest" "$bak"; then
        log_error "Failed to create backup ${bak} — aborting MCP sync"
        return 0
    fi
    log_info "Backed up ${dest} to ${bak}"

    # Apply merge atomically
    local tmp="${dest}.tmp.$$"
    if jq --slurpfile src "$src" \
        '.mcpServers = ((.mcpServers // {}) * ($src[0].mcpServers // {}))' \
        "$dest" > "$tmp"; then
        if mv "$tmp" "$dest"; then
            log_success "Synced ${count} MCP server(s) into ${dest}"
        else
            log_error "Failed to move ${tmp} into place — backup at ${bak}"
            rm -f "$tmp"
        fi
    else
        log_error "jq merge failed — original preserved, backup at ${bak}"
        rm -f "$tmp"
    fi
}

# =============================================================================
# install_claude_code — Main entry point
# =============================================================================
install_claude_code() {
    if ! cfg_enabled "claude_code.enabled"; then
        log_info "Claude Code disabled in config — skipping"
        return 0
    fi

    _install_claude_native
    _install_ccstatusline

    print_header "Claude Code config sync"
    _sync_claude_global_md
    _sync_claude_rules
    _sync_claude_commands
    _sync_claude_agents
    _merge_claude_settings
    _set_ccstatusline_command
    _register_plugin_marketplaces
    _install_enabled_plugins
    _sync_mcp_servers
}

# =============================================================================
# _latest_bak <basefile> — echo the newest <basefile>.bak.* (empty if none).
# =============================================================================
_latest_bak() {
    local base="$1" newest="" f
    shopt -s nullglob
    for f in "${base}".bak.*; do
        [[ -z "$newest" || "$f" -nt "$newest" ]] && newest="$f"
    done
    shopt -u nullglob
    echo "$newest"
}

# =============================================================================
# _uninstall_claude_settings — Restore ~/.claude/settings.json from the newest
# install-created .bak; failing that, delete only the whitelisted keys whose
# value still equals the repo's. Never touches other (user/auth) keys.
# =============================================================================
_uninstall_claude_settings() {
    local dest="${HOME}/.claude/settings.json"
    local src="${ENV_SETUP_DIR}/configs/claude/settings.json"

    [[ -f "$dest" ]] || { log_info "[SKIP] settings.json not present"; return 0; }

    local bak
    bak="$(_latest_bak "$dest")"
    if [[ -n "$bak" ]]; then
        log_info "Restoring settings.json from ${bak}"
        dry_run_cp "$bak" "$dest"
        return 0
    fi

    command_exists jq || { log_warn "jq not found — leaving settings.json"; return 0; }
    jq empty "$dest" 2>/dev/null || { log_warn "settings.json is invalid JSON — leaving it"; return 0; }

    local keys=() k
    while IFS= read -r k; do [[ -n "$k" ]] && keys+=("$k"); done \
        < <(cfg_list "claude_code.settings_merge_keys")
    [[ ${#keys[@]} -eq 0 ]] && return 0

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo "[DRY-RUN] Would strip env-setup keys from ${dest} (where equal to repo)"
        return 0
    fi

    local tmp="${dest}.tmp.$$"
    # shellcheck disable=SC2016  # $k, $src, $ARGS are jq variables, not shell
    if jq --slurpfile src "$src" \
        'reduce ($ARGS.positional[]) as $k (.; if (.[$k] == $src[0][$k]) then del(.[$k]) else . end)' \
        "$dest" --args "${keys[@]}" > "$tmp"; then
        mv "$tmp" "$dest"
        log_success "Stripped env-setup keys from settings.json"
    else
        rm -f "$tmp"
        log_warn "jq strip failed — settings.json left intact"
    fi
}

# =============================================================================
# _uninstall_claude_mcp — Restore ~/.claude.json from the newest install .bak;
# failing that, remove only the repo-declared mcpServers keys.
# =============================================================================
_uninstall_claude_mcp() {
    local dest="${HOME}/.claude.json"
    local src="${ENV_SETUP_DIR}/configs/claude/mcp-servers.json"

    [[ -f "$dest" ]] || return 0
    [[ -f "$src" ]] || return 0
    command_exists jq || return 0

    local bak
    bak="$(_latest_bak "$dest")"
    if [[ -n "$bak" ]]; then
        log_info "Restoring ~/.claude.json from ${bak}"
        dry_run_cp "$bak" "$dest"
        return 0
    fi

    local count
    count=$(jq -r '.mcpServers // {} | length' "$src" 2>/dev/null || echo 0)
    [[ "${count:-0}" -eq 0 ]] && return 0

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo "[DRY-RUN] Would remove repo-declared MCP servers from ${dest}"
        return 0
    fi

    local tmp="${dest}.tmp.$$"
    if jq --slurpfile src "$src" \
        '.mcpServers = ((.mcpServers // {}) | with_entries(select(.key as $k | (($src[0].mcpServers // {}) | has($k)) | not)))' \
        "$dest" > "$tmp"; then
        mv "$tmp" "$dest"
        log_success "Removed env-setup MCP servers from ~/.claude.json"
    else
        rm -f "$tmp"
        log_warn "jq MCP strip failed — ~/.claude.json left intact"
    fi
}

# =============================================================================
# _remove_claude_cli — Remove the native-installer launcher + version store.
# The ~/.claude data tree (auth/history/projects) is intentionally preserved.
# =============================================================================
_remove_claude_cli() {
    dry_run_rm "${HOME}/.local/bin/claude"
    remove_managed_dir "${HOME}/.local/share/claude" "Claude CLI store"
    log_success "Removed Claude CLI binary (config/auth preserved)"
}

# =============================================================================
# uninstall_claude_code — Reverse install_claude_code (surgical).
# =============================================================================
uninstall_claude_code() {
    print_header "Uninstall: Claude Code"

    local cdir="${ENV_SETUP_DIR}/configs/claude"

    # C — managed config files (user-edited copies are preserved by remove_managed_file)
    remove_managed_file "${HOME}/.claude/CLAUDE.md" "${cdir}/CLAUDE.md" "global CLAUDE.md"
    local f
    shopt -s nullglob
    for f in "${cdir}/rules"/*.md;    do remove_managed_file "${HOME}/.claude/rules/$(basename "$f")"    "$f" "rule $(basename "$f")"; done
    for f in "${cdir}/commands"/*.md; do remove_managed_file "${HOME}/.claude/commands/$(basename "$f")" "$f" "command $(basename "$f")"; done
    for f in "${cdir}/agents"/*.md;   do remove_managed_file "${HOME}/.claude/agents/$(basename "$f")"   "$f" "agent $(basename "$f")"; done
    shopt -u nullglob

    _uninstall_claude_settings
    _uninstall_claude_mcp

    remove_managed_file "${HOME}/.config/ccstatusline/settings.json" \
        "${ENV_SETUP_DIR}/configs/ccstatusline/settings.json" "ccstatusline settings.json"
    remove_managed_file "${HOME}/.config/ccstatusline/statusline.sh" \
        "${ENV_SETUP_DIR}/configs/ccstatusline/statusline.sh" "ccstatusline launcher"
    if [[ "${DRY_RUN:-false}" != "true" ]]; then
        rmdir "${HOME}/.config/ccstatusline" 2>/dev/null || true
    fi

    # T — plugins/marketplaces + CLI binary
    if [[ "${KEEP_TOOLS:-false}" != "true" ]]; then
        if command_exists claude && command_exists jq; then
            local plugin repo
            while IFS= read -r plugin; do
                [[ -z "$plugin" ]] && continue
                dry_run_cmd claude plugin uninstall "$plugin" >/dev/null 2>&1 || true
            done < <(jq -r '.enabledPlugins | to_entries[] | select(.value == true) | .key' "${cdir}/settings.json" 2>/dev/null)
            while IFS= read -r repo; do
                [[ -z "$repo" ]] && continue
                dry_run_cmd claude plugin marketplace remove "$repo" >/dev/null 2>&1 || true
            done < <(cfg_list "claude_code.marketplaces")
        fi
        _remove_claude_cli
    fi

    log_success "Claude Code uninstall complete"
}
