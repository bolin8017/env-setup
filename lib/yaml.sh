#!/usr/bin/env bash
# yaml.sh — Lightweight YAML parser using awk
# Parses simple YAML into flat CFG_* shell variables.
# Supports scalars, nested keys (2-space indent, up to 4 levels), lists, booleans, comments.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
fi

[[ -n "${_ENV_SETUP_YAML_LOADED:-}" ]] && return 0
_ENV_SETUP_YAML_LOADED=1

# =============================================================================
# yaml_parse — Parse a YAML file into CFG_* variables
# Usage: eval "$(yaml_parse config.yaml)"
# =============================================================================
yaml_parse() {
    local file="$1"

    [[ -f "$file" ]] || { echo "echo 'yaml_parse: file not found: $file' >&2; return 1"; return 1; }

    # shellcheck disable=SC1003
    awk '
    BEGIN {
        depth = 0
        list_counts_len = 0
    }

    # Skip blank lines and pure comment lines
    /^[[:space:]]*$/ { next }
    /^[[:space:]]*#/ { next }

    {
        # Calculate indentation level (2 spaces per level)
        match($0, /^[[:space:]]*/);
        indent = int(RLENGTH / 2);

        # Strip leading/trailing whitespace
        line = $0
        sub(/^[[:space:]]+/, "", line)
        sub(/[[:space:]]+$/, "", line)

        # Strip inline comments (not inside quotes)
        if (match(line, /[^"'\''#]*#/)) {
            # Only strip if # is not inside quotes
            tmp = line
            gsub(/"[^"]*"/, "", tmp)
            gsub(/'\''[^'\'']*'\''/, "", tmp)
            if (match(tmp, /[[:space:]]+#/)) {
                sub(/[[:space:]]+#.*$/, "", line)
            }
        }

        # Trim depth stack to current level
        if (indent < depth) {
            depth = indent
        }

        # List item: "- value"
        if (match(line, /^- /)) {
            value = substr(line, 3)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            value = strip_quotes(value)

            # Build key path
            key = build_key(depth)

            # Track array count
            count_key = key "_COUNT"
            if (!(count_key in counts)) {
                counts[count_key] = 0
            }
            idx = counts[count_key]
            counts[count_key] = idx + 1

            item_key = key "_" idx
            printf "CFG_%s=%s\n", item_key, shell_quote(value)
            printf "CFG_%s=%d\n", count_key, idx + 1
            next
        }

        # Key-value or section header
        if (match(line, /^[A-Za-z_][A-Za-z0-9_-]*:/)) {
            colon_pos = index(line, ":")
            key_part = substr(line, 1, colon_pos - 1)
            val_part = substr(line, colon_pos + 1)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", val_part)

            # Normalize key: replace hyphens with underscores, uppercase
            gsub(/-/, "_", key_part)
            key_part = toupper(key_part)

            # Set current level key
            keys[indent] = key_part
            depth = indent + 1

            if (val_part != "") {
                # Scalar value
                val_part = strip_quotes(val_part)
                full_key = build_key(indent + 1)
                # Remove trailing key we just set since this is a leaf
                full_key = build_key(indent) "_" key_part
                # Actually just build from 0..indent
                full_key = ""
                for (i = 0; i <= indent; i++) {
                    if (i > 0) full_key = full_key "_"
                    full_key = full_key keys[i]
                }
                printf "CFG_%s=%s\n", full_key, shell_quote(val_part)
            }
            # else: section header, children will follow
            next
        }
    }

    function build_key(d,    k, i) {
        k = ""
        for (i = 0; i < d; i++) {
            if (i > 0) k = k "_"
            k = k keys[i]
        }
        return k
    }

    function strip_quotes(s) {
        if (match(s, /^".*"$/) || match(s, /^'\''.*'\''$/)) {
            s = substr(s, 2, length(s) - 2)
        }
        return s
    }

    function shell_quote(s) {
        gsub(/'\''/, "'\''\\'\'''\''", s)
        return "'\''" s "'\''"
    }
    ' "$file"
}

# =============================================================================
# cfg_get — Get a config value by dot-path
# Usage: cfg_get "languages.python.version"
# =============================================================================
cfg_get() {
    local dotpath="$1"
    local varname
    varname="CFG_$(echo "$dotpath" | tr '.' '_' | tr '-' '_' | tr '[:lower:]' '[:upper:]')"
    echo "${!varname:-}"
}

# =============================================================================
# cfg_enabled — Check if a boolean config is "true"
# Returns 0 (true) or 1 (false)
# =============================================================================
cfg_enabled() {
    local val
    val="$(cfg_get "$1")"
    [[ "${val,,}" == "true" ]]
}

# =============================================================================
# cfg_list — Output list items one per line
# Usage: cfg_list "cli_tools.packages"
# =============================================================================
cfg_list() {
    local dotpath="$1"
    local base_var
    base_var="CFG_$(echo "$dotpath" | tr '.' '_' | tr '-' '_' | tr '[:lower:]' '[:upper:]')"
    local count_var="${base_var}_COUNT"
    local count="${!count_var:-0}"

    local i=0
    while [[ $i -lt $count ]]; do
        local item_var="${base_var}_${i}"
        echo "${!item_var:-}"
        (( i += 1 ))
    done
}
