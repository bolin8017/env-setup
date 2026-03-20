---
paths:
  - "config.yaml"
  - "config.yaml.example"
---

# YAML Configuration Rules

- `config.yaml.example` is the single source of truth for all available options — every key must be documented with an inline comment
- `config.yaml` is the user's active config; it only needs keys that differ from defaults
- When adding a new config key, update BOTH files
- Booleans: `true` / `false` (no quotes)
- Strings: quoted (`"lts"`, `"3.12"`)
- Lists: YAML sequences (`- item`)
- Use dashed separator comments between sections:
  ```yaml
  # -----------------------------------------------------------------------------
  # Section Name — brief description
  # -----------------------------------------------------------------------------
  ```
- The YAML parser (`lib/yaml_parser.sh`) is pure bash/awk — do not use advanced YAML features (anchors, merge keys, multi-line strings)
