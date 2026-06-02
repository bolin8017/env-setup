#!/usr/bin/env bash
# 04-docker.sh — Docker Engine (Linux) / Docker Desktop (macOS)
# All lib/ files are sourced by setup.sh before this module runs.

# =============================================================================
# Main entry point
# =============================================================================
install_docker() {
    print_header "Docker"

    if ! cfg_enabled "docker.enabled"; then
        log_info "Docker is disabled in config, skipping"
        return 0
    fi

    if command_exists docker; then
        log_success "Docker already installed ($(docker --version))"
        return 0
    fi

    if is_macos; then
        log_info "Installing Docker Desktop..."
        dry_run_cmd brew install --cask docker
        log_success "Docker Desktop installed"
        log_info "Open Docker Desktop app to complete setup"
    elif is_linux; then
        log_info "Installing Docker Engine..."
        if ! sudo_available; then
            record_missing_apt_note "Docker Engine: follow https://docs.docker.com/engine/install/ubuntu/ (also add your user to the docker group: sudo usermod -aG docker ${USER:-$(whoami)})"
            log_warn "Docker install deferred to administrator"
            return 0
        fi
        pkg_update
        dry_run_cmd sudo apt-get install -y ca-certificates curl gnupg
        dry_run_cmd sudo install -m 0755 -d /etc/apt/keyrings
        # shellcheck disable=SC2016  # single quotes are intentional (deferred expansion)
        dry_run_cmd bash -c '
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
                | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null || true
            sudo chmod a+r /etc/apt/keyrings/docker.gpg
            echo \
                "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
                $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
                | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        '
        dry_run_cmd sudo apt-get update
        dry_run_cmd sudo apt-get install -y \
            docker-ce docker-ce-cli containerd.io \
            docker-buildx-plugin docker-compose-plugin
        dry_run_cmd sudo usermod -aG docker "${USER:-$(whoami)}" || true
        log_success "Docker Engine installed"
        log_info "Log out and back in for Docker group permissions"
    fi
}

# =============================================================================
# uninstall_docker — Docker is system-level; removed only under --purge.
# =============================================================================
uninstall_docker() {
    print_header "Uninstall: Docker"

    if [[ "${PURGE:-false}" != "true" ]]; then
        log_info "Docker removal requires --purge (system-level; no user config deployed)"
        return 0
    fi

    if is_macos; then
        pkg_remove_cask docker
    elif is_linux; then
        if sudo_available && command_exists apt-get; then
            dry_run_cmd sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y \
                docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            dry_run_cmd sudo gpasswd -d "${USER:-$(whoami)}" docker 2>/dev/null || true
            dry_run_cmd sudo rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.gpg
        else
            record_missing_apt_note "Remove Docker: sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
            log_warn "Docker removal deferred to administrator"
        fi
    fi

    log_success "Docker uninstall complete"
}
