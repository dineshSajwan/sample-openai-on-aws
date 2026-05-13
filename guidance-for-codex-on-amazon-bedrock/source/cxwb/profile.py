"""Profile load/save. One profile = one deployment target."""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

PROFILE_DIR = Path.home() / ".cxwb" / "profiles"


def profile_path(name: str) -> Path:
    return PROFILE_DIR / f"{name}.json"


def save(name: str, data: dict[str, Any]) -> Path:
    PROFILE_DIR.mkdir(parents=True, exist_ok=True)
    os.chmod(PROFILE_DIR, 0o700)
    path = profile_path(name)
    tmp = path.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)
    return path


def load(name: str) -> dict[str, Any]:
    path = profile_path(name)
    if not path.exists():
        raise FileNotFoundError(f"Profile '{name}' not found at {path}")
    return json.loads(path.read_text())


def list_profiles() -> list[str]:
    if not PROFILE_DIR.exists():
        return []
    return sorted(p.stem for p in PROFILE_DIR.glob("*.json"))
