# `cxwb` — Codex-with-Bedrock wizard

Guided deploy + bundle generator for the four shapes this repo supports:

| | Deploy new | BYO (bundle only) |
|---|---|---|
| IdC auth | `auth=idc, manages_infra=true` | `auth=idc, manages_infra=false` |
| Gateway auth | `auth=gateway, manages_infra=true` | `auth=gateway, manages_infra=false` |

Install:

```bash
poetry install
poetry run cxwb --help
```

Commands: `init`, `deploy`, `status`, `distribute`, `destroy`, `list`.

Walkthrough: [`../QUICK_START.md`](../QUICK_START.md).
