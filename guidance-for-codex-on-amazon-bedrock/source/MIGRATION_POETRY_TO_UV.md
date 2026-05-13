# Migration Plan: Poetry → uv

## Executive Summary

**Migration Complexity:** ⭐⭐ (Low-Medium)  
**Estimated Effort:** 2-3 hours  
**Impact:** Low (mostly documentation changes)  
**Recommendation:** ✅ Safe to proceed

---

## Why Migrate to uv?

| Aspect | Poetry | uv | Winner |
|--------|--------|----|----|
| **Speed** | ~5-10s install | <1s install | uv (10-50x faster) |
| **Size** | 20-30MB + virtualenv | 13MB single binary | uv (smaller) |
| **Dependency Resolution** | Can be slow | Rust-based, very fast | uv |
| **Lock Files** | poetry.lock | uv.lock | Both supported |
| **Script Running** | `poetry run <cmd>` | `uv run <cmd>` | uv (simpler) |
| **PEP 723 Inline Scripts** | ❌ No | ✅ Yes | uv |
| **Build Backend** | poetry-core | hatchling/setuptools | uv (standard) |
| **Maturity** | Stable (v1.8+) | Stable (v0.5+) | Poetry (older) |

**Key Benefits for This Project:**
- ✅ Faster CI/CD builds (uv is 10-50x faster)
- ✅ Simpler developer onboarding (single binary, no pip/venv setup)
- ✅ Better for scripts (PEP 723 inline dependencies)
- ✅ Drop-in replacement for most poetry commands
- ✅ Compatible with existing pyproject.toml (minimal changes)

---

## Current Poetry Usage

### 1. Package Management (cxwb CLI)
**File:** `source/pyproject.toml`

```toml
[tool.poetry]
name = "cxwb"
version = "0.1.0"
packages = [{ include = "cxwb" }]

[tool.poetry.dependencies]
python = ">=3.10,<3.14"
click = "^8.1"
questionary = "^2.0"
boto3 = "^1.34"

[tool.poetry.scripts]
cxwb = "cxwb.cli:main"

[build-system]
requires = ["poetry-core>=1.5"]
build-backend = "poetry.core.masonry.api"
```

**Usage:**
- `poetry install` - Install dependencies and create virtualenv
- `poetry run cxwb <command>` - Run CLI commands
- `poetry build` - Build wheel/sdist (not currently used)

### 2. Documentation References
**Files:** All quickstart guides and README files

**Commands:**
- `poetry install`
- `poetry run cxwb init`
- `poetry run cxwb build`
- `poetry run cxwb deploy`
- `poetry run cxwb distribute`

### 3. Error Messages in Code
**Files:**
- `source/cxwb/paths.py` - Installation error message
- `source/cxwb/commands/distribute.py` - Example command

---

## Migration Steps

### Phase 1: Update pyproject.toml (5 minutes)

**Before:**
```toml
[tool.poetry]
name = "cxwb"
version = "0.1.0"
description = "Guided CLI for deploying Codex on Amazon Bedrock (IAM Identity Center or LiteLLM Gateway)."
authors = ["AWS Solutions Library"]
readme = "README.md"
packages = [{ include = "cxwb" }]

[tool.poetry.dependencies]
python = ">=3.10,<3.14"
click = "^8.1"
questionary = "^2.0"
boto3 = "^1.34"

[tool.poetry.scripts]
cxwb = "cxwb.cli:main"

[build-system]
requires = ["poetry-core>=1.5"]
build-backend = "poetry.core.masonry.api"
```

**After:**
```toml
[project]
name = "cxwb"
version = "0.1.0"
description = "Guided CLI for deploying Codex on Amazon Bedrock (IAM Identity Center or LiteLLM Gateway)."
authors = [{ name = "AWS Solutions Library" }]
readme = "README.md"
requires-python = ">=3.10,<3.14"
dependencies = [
    "click>=8.1,<9.0",
    "questionary>=2.0,<3.0",
    "boto3>=1.34,<2.0",
]

[project.scripts]
cxwb = "cxwb.cli:main"

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.hatch.build.targets.wheel]
packages = ["cxwb"]
```

**Changes:**
- ✅ `[tool.poetry]` → `[project]` (PEP 621 standard)
- ✅ `[tool.poetry.dependencies]` → `[project.dependencies]`
- ✅ `[tool.poetry.scripts]` → `[project.scripts]`
- ✅ Poetry caret ranges (`^8.1`) → pip-style (`>=8.1,<9.0`)
- ✅ Build backend: `poetry-core` → `hatchling` (faster, standard)
- ✅ Remove `poetry.lock` (replaced by `uv.lock`)

### Phase 2: Update Documentation (30 minutes)

**Replace all instances:**

| Before | After |
|--------|-------|
| `poetry install` | `uv sync` |
| `poetry run cxwb <cmd>` | `uv run cxwb <cmd>` |
| `poetry add <pkg>` | `uv add <pkg>` |
| `poetry remove <pkg>` | `uv remove <pkg>` |
| Install Poetry link | Install uv link |

**Files to update:**
- ✅ README.md
- ✅ QUICKSTART_PATTERN_IDC.md
- ✅ QUICKSTART_PATTERN_GATEWAY.md
- ✅ QUICKSTART_PATTERN_HYBRID.md
- ✅ QUICK_START.md
- ✅ deployment/litellm/jwt-middleware/README.md

**Prerequisites section:**
```diff
- - [ ] Python 3.10-3.13 + Poetry ([install poetry](https://python-poetry.org/docs/#installation))
+ - [ ] Python 3.10-3.13 + uv ([install uv](https://docs.astral.sh/uv/getting-started/installation/))
```

**Installation section:**
```diff
- poetry install
+ uv sync
```

**Usage examples:**
```diff
- poetry run cxwb init
+ uv run cxwb init

- poetry run cxwb build --profile <profile-name>
+ uv run cxwb build --profile <profile-name>

- poetry run cxwb deploy --profile <profile-name>
+ uv run cxwb deploy --profile <profile-name>
```

### Phase 3: Update Code Error Messages (5 minutes)

**File:** `source/cxwb/paths.py`

```diff
    raise RuntimeError(
        f"cxwb expects to run from the repo checkout; templates not found at {INFRA_DIR}. "
-       "Install with `poetry install` inside the repo, not `pip install cxwb` from a wheel."
+       "Install with `uv sync` inside the repo, not `pip install cxwb` from a wheel."
    )
```

**File:** `source/cxwb/commands/distribute.py`

```diff
-       click.echo(f"  poetry run cxwb distribute --profile {profile_name} --bucket {suggested_bucket}")
+       click.echo(f"  uv run cxwb distribute --profile {profile_name} --bucket {suggested_bucket}")
```

### Phase 4: Test Migration (30 minutes)

**1. Install uv:**
```bash
# macOS/Linux
curl -LsSf https://astral.sh/uv/install.sh | sh

# Or via Homebrew
brew install uv

# Verify
uv --version
```

**2. Clean old Poetry artifacts:**
```bash
cd source/
rm -rf .venv poetry.lock
```

**3. Initialize uv project:**
```bash
# This reads pyproject.toml and creates uv.lock
uv sync
```

**4. Test CLI commands:**
```bash
# Should work identically
uv run cxwb --help
uv run cxwb init
uv run cxwb build --profile test
```

**5. Verify virtualenv isolation:**
```bash
# uv creates .venv/ automatically
ls .venv/

# Check installed packages
uv pip list
```

### Phase 5: Update CI/CD (if exists)

**GitHub Actions example:**

```diff
- - name: Install Poetry
-   run: pipx install poetry
-
- - name: Install dependencies
-   run: poetry install

+ - name: Install uv
+   run: curl -LsSf https://astral.sh/uv/install.sh | sh
+
+ - name: Install dependencies
+   run: uv sync
```

**Speedup:** Poetry ~10-20s → uv ~1-2s per CI run

### Phase 6: Update .gitignore (1 minute)

```diff
  # Python
  __pycache__/
  *.pyc
  .venv/
- poetry.lock
+ uv.lock

  # IDE
  .idea/
  .vscode/
```

**Note:** You may want to commit `uv.lock` for reproducible builds (like `poetry.lock`).

---

## Command Mapping Reference

| Task | Poetry | uv | Notes |
|------|--------|----|----|
| **Install** | `poetry install` | `uv sync` | uv is 10-50x faster |
| **Run script** | `poetry run <cmd>` | `uv run <cmd>` | Identical behavior |
| **Add dependency** | `poetry add <pkg>` | `uv add <pkg>` | Updates pyproject.toml + lock |
| **Remove dependency** | `poetry remove <pkg>` | `uv remove <pkg>` | Updates pyproject.toml + lock |
| **Update all** | `poetry update` | `uv lock --upgrade` | Regenerates lock file |
| **Show deps** | `poetry show` | `uv pip list` | List installed packages |
| **Build package** | `poetry build` | `uv build` | Creates wheel/sdist |
| **Publish** | `poetry publish` | `uv publish` | Upload to PyPI |
| **Shell** | `poetry shell` | `source .venv/bin/activate` | uv doesn't have shell cmd |

---

## Breaking Changes / Gotchas

### 1. Dependency Version Syntax

**Poetry uses caret ranges:**
```toml
click = "^8.1"  # Means >=8.1.0,<9.0.0
```

**uv uses pip-style:**
```toml
click = ">=8.1,<9.0"  # Explicit range
```

**Solution:** Convert all `^X.Y` to `>=X.Y,<(X+1).0` in pyproject.toml

### 2. Build Backend Change

**Poetry uses poetry-core:**
```toml
[build-system]
requires = ["poetry-core>=1.5"]
build-backend = "poetry.core.masonry.api"
```

**uv recommends hatchling:**
```toml
[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"
```

**Impact:** None for runtime usage, only affects `uv build` (not currently used in this project)

### 3. Lock File Format

- Poetry: `poetry.lock` (custom TOML format)
- uv: `uv.lock` (custom format, faster parsing)

**Impact:** Cannot reuse existing `poetry.lock`, must regenerate with `uv sync`

### 4. No `poetry shell` Equivalent

**Poetry:**
```bash
poetry shell  # Activates virtualenv in new subshell
```

**uv:**
```bash
source .venv/bin/activate  # Standard virtualenv activation
# Or just use `uv run` prefix for commands
```

**Impact:** Minimal - `uv run` is simpler and works everywhere

### 5. Script Metadata (PEP 723)

**New capability in uv** - inline dependencies in Python scripts:

```python
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "click>=8.1",
#   "boto3>=1.34",
# ]
# ///

import click
import boto3

# Script code here...
```

**Run with:**
```bash
uv run my_script.py  # Auto-installs deps in isolated env
```

**Benefit:** Great for one-off deployment scripts (e.g., `generate-codex-gateway-config.sh` → `.py`)

---

## Impact Analysis

### ✅ Zero Impact (No Code Changes)

- **Python code:** No changes needed to `cxwb/*.py` files
- **CLI interface:** `cxwb` commands work identically
- **Docker images:** LiteLLM/JWT middleware use requirements.txt (unchanged)
- **CloudFormation:** No dependencies on Poetry

### ⚠️ Low Impact (Documentation Only)

- **Quickstart guides:** Replace `poetry install` → `uv sync`, `poetry run` → `uv run`
- **README:** Update prerequisites section
- **Error messages:** Update 2 strings in Python code

### 🔧 Medium Impact (One-Time Migration)

- **pyproject.toml:** Convert from Poetry format to PEP 621 format (~10 lines)
- **Lock file:** Regenerate with `uv sync` (auto-generated)
- **Developer workflow:** Team needs to install `uv` instead of Poetry

---

## Rollout Strategy

### Option A: Big Bang (Recommended)

**Pros:**
- ✅ Clean cutover, no confusion
- ✅ Simpler documentation (one tool, not two)
- ✅ Faster to complete (1 PR)

**Cons:**
- ❌ All developers must switch at once

**Steps:**
1. Update pyproject.toml
2. Update all documentation
3. Update error messages
4. Generate uv.lock
5. Delete poetry.lock
6. Commit and merge
7. Notify team: "Run `uv sync` instead of `poetry install`"

### Option B: Gradual Migration

**Pros:**
- ✅ Developers can switch when ready
- ✅ Supports both tools temporarily

**Cons:**
- ❌ Confusing documentation ("use poetry OR uv")
- ❌ Maintenance overhead (keep two lock files in sync)
- ❌ Longer migration period

**Not recommended for this project** - small team, simple tooling.

---

## Verification Checklist

After migration, verify:

- [ ] `uv sync` creates `.venv/` with all dependencies
- [ ] `uv run cxwb --help` shows CLI help
- [ ] `uv run cxwb init` starts wizard successfully
- [ ] `uv run cxwb build --profile test` can build Docker images
- [ ] `uv run cxwb deploy --profile test` can deploy stacks
- [ ] All quickstart guides have correct `uv` commands
- [ ] Error messages reference `uv sync` not `poetry install`
- [ ] `uv.lock` is committed to repo
- [ ] `.gitignore` excludes `poetry.lock`

---

## Migration Timeline

| Phase | Duration | Blocker? |
|-------|----------|----------|
| 1. Update pyproject.toml | 5 min | No |
| 2. Update documentation | 30 min | No |
| 3. Update code error messages | 5 min | No |
| 4. Test migration locally | 30 min | **YES** |
| 5. Update CI/CD (if exists) | 10 min | No |
| 6. Update .gitignore | 1 min | No |
| **Total** | **~1.5 hours** | |

**Additional time for review and testing:** +30-60 minutes

**Total effort:** 2-3 hours

---

## Recommendation

✅ **PROCEED with migration**

**Reasoning:**
1. **Low risk:** No Python code changes, only tooling
2. **High value:** 10-50x faster installs, simpler onboarding
3. **Easy rollback:** Keep this branch, revert if issues
4. **Modern standard:** uv is the future (Rust-based, PEP 723, faster)
5. **Good timing:** Project is early-stage, small team

**Best approach:** Big bang migration (Option A)

**When NOT to migrate:**
- ❌ If using Poetry plugins (not applicable here)
- ❌ If distributing as PyPI package and users expect Poetry (not applicable)
- ❌ If CI/CD tightly coupled to Poetry (not applicable)

---

## Questions?

### Q: Can we still use pip?

**A:** Yes! uv is pip-compatible. You can still:
```bash
uv pip install <package>
uv pip freeze > requirements.txt
```

### Q: What if a developer doesn't want to install uv?

**A:** They can use standard pip/venv:
```bash
python -m venv .venv
source .venv/bin/activate
pip install -e .
```

But `uv` is strongly recommended (10-50x faster).

### Q: Do Docker images need uv?

**A:** No! JWT middleware and LiteLLM use `requirements.txt` + `pip install`, which is standard and doesn't require uv.

### Q: Will this break existing deployments?

**A:** No! This only affects the `cxwb` CLI development/deployment tooling. Already-deployed gateways are unaffected.

---

## Next Steps

1. Review this plan
2. Create branch `feature/migrate-poetry-to-uv`
3. Execute Phase 1-6
4. Test locally
5. Commit and push
6. Merge after review
7. Update team: "Use `uv sync` instead of `poetry install`"
