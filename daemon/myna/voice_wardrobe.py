"""Per-app voice wardrobe — `{bundle_id: voice_id}` overrides.

Lives in `~/.config/myna/voice_wardrobe.json` rather than `config.json`
so the main config stays clean and the wardrobe can grow large without
making `cfg` dumps noisy.

Wire shape on disk::

    {
      "version": 1,
      "mappings": {
        "com.apple.MobileSafari": "af_bella",
        "com.tinyspeck.slackmacgap": "am_michael"
      }
    }

The version field is bumped if we ever need to change the shape. Today
we read version-1 files only; missing/unknown versions fall back to an
empty mapping (the file isn't authoritative for the user's preferences;
losing it is a soft failure).
"""

from __future__ import annotations

import json
import os
import pathlib
import tempfile
import threading
from typing import Optional

# Re-use the same CONFIG_DIR convention as myna.config so all per-user
# Myna state lives under ~/.config/myna/.
_CONFIG_DIR = pathlib.Path(os.path.expanduser("~/.config/myna"))
_WARDROBE_PATH = _CONFIG_DIR / "voice_wardrobe.json"

_WARDROBE_VERSION = 1

# Process-wide lock — the daemon is single-process FastAPI but
# /v2/voice_wardrobe POST + GET can race in async workers, and the JSON
# file is small enough that a fat lock around all I/O is fine.
_lock = threading.Lock()


class VoiceWardrobe:
    """In-memory wardrobe + lazy-persisted on disk.

    Construction reads the file (if present); subsequent mutations
    rewrite the whole file atomically via a tempfile + rename. Reads
    are O(1) on a dict, writes are O(n) on the wardrobe size — fine for
    even pathological wardrobes (it'd take hundreds of thousands of
    bundle IDs to matter).
    """

    def __init__(self, path: pathlib.Path = _WARDROBE_PATH):
        self._path = path
        self._mappings: dict[str, str] = {}
        self._load()

    # ----- public API -----

    def get(self, bundle_id: str | None) -> str | None:
        """Return the voice id mapped to ``bundle_id``, or None."""
        if not bundle_id:
            return None
        with _lock:
            return self._mappings.get(bundle_id)

    def set(self, bundle_id: str, voice_id: str | None) -> None:
        """Upsert (voice_id=str) or remove (voice_id=None) a mapping.

        Persists to disk before returning. Empty/blank bundle_id is
        rejected silently — a caller that passes ``""`` almost
        certainly has a bug, and we don't want to write a "" key.
        """
        if not bundle_id or not bundle_id.strip():
            return
        with _lock:
            if voice_id is None:
                self._mappings.pop(bundle_id, None)
            else:
                self._mappings[bundle_id] = voice_id
            self._persist()

    def all(self) -> dict[str, str]:
        """Snapshot copy of the current mapping."""
        with _lock:
            return dict(self._mappings)

    def reload(self) -> None:
        """Re-read the file from disk, dropping the in-memory cache.

        Mainly used in tests; production lifecycle holds one wardrobe
        for the daemon's lifetime.
        """
        with _lock:
            self._mappings = {}
            self._load_locked()

    # ----- internals -----

    def _load(self) -> None:
        with _lock:
            self._load_locked()

    def _load_locked(self) -> None:
        if not self._path.exists():
            return
        try:
            data = json.loads(self._path.read_text())
        except (OSError, json.JSONDecodeError):
            # Corrupt file? Treat as empty. The next set() will
            # overwrite with a valid v1 blob.
            return
        if not isinstance(data, dict):
            return
        if data.get("version") != _WARDROBE_VERSION:
            return
        mappings = data.get("mappings")
        if not isinstance(mappings, dict):
            return
        # Trust the keys/values are strings; coerce defensively.
        cleaned: dict[str, str] = {}
        for k, v in mappings.items():
            if isinstance(k, str) and isinstance(v, str) and k and v:
                cleaned[k] = v
        self._mappings = cleaned

    def _persist(self) -> None:
        """Write the wardrobe atomically.

        Uses a tempfile + os.replace so a crash mid-write doesn't leave
        a half-written file behind (which `_load` would happily treat
        as empty, losing every mapping the user had set).
        """
        self._path.parent.mkdir(parents=True, exist_ok=True)
        body = json.dumps(
            {
                "version": _WARDROBE_VERSION,
                "mappings": self._mappings,
            },
            indent=2,
            sort_keys=True,
        )
        # Same directory so os.replace stays atomic on the same filesystem.
        fd, tmp = tempfile.mkstemp(
            prefix=".voice_wardrobe-",
            suffix=".json.tmp",
            dir=self._path.parent,
        )
        try:
            with os.fdopen(fd, "w") as fh:
                fh.write(body)
            os.replace(tmp, self._path)
        except Exception:
            # Best-effort cleanup of the tempfile if anything went wrong.
            try:
                os.unlink(tmp)
            except FileNotFoundError:
                pass
            raise


def resolve_voice(
    wardrobe: VoiceWardrobe,
    bundle_id: Optional[str],
    request_voice: Optional[str],
    default_voice: str,
) -> str:
    """Pick the voice for a synthesize request.

    Resolution order:
      1. The explicit ``voice`` passed in the request (caller override).
      2. The wardrobe mapping for ``bundle_id`` if present.
      3. ``default_voice`` (typically ``cfg["voice"]``).

    Step 1 wins because a caller explicitly setting voice=X almost
    always means "I really want X" (e.g. a settings-tab voice preview).
    """
    if request_voice:
        return request_voice
    if bundle_id:
        wardrobe_voice = wardrobe.get(bundle_id)
        if wardrobe_voice:
            return wardrobe_voice
    return default_voice
