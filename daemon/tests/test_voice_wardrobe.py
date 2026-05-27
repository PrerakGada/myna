"""Tests for myna.voice_wardrobe — the {bundle_id -> voice_id} store."""

import json
import pathlib

import pytest

from myna.voice_wardrobe import VoiceWardrobe, resolve_voice


@pytest.fixture
def wardrobe_path(tmp_path: pathlib.Path) -> pathlib.Path:
    return tmp_path / "voice_wardrobe.json"


@pytest.fixture
def wardrobe(wardrobe_path: pathlib.Path) -> VoiceWardrobe:
    return VoiceWardrobe(path=wardrobe_path)


# ----- get / set roundtrip -----


def test_empty_wardrobe_returns_none(wardrobe):
    assert wardrobe.get("com.apple.Safari") is None
    assert wardrobe.all() == {}


def test_set_then_get(wardrobe):
    wardrobe.set("com.apple.Safari", "af_bella")
    assert wardrobe.get("com.apple.Safari") == "af_bella"


def test_set_overwrites(wardrobe):
    wardrobe.set("com.apple.Safari", "af_bella")
    wardrobe.set("com.apple.Safari", "am_michael")
    assert wardrobe.get("com.apple.Safari") == "am_michael"


def test_set_none_removes(wardrobe):
    wardrobe.set("com.apple.Safari", "af_bella")
    wardrobe.set("com.apple.Safari", None)
    assert wardrobe.get("com.apple.Safari") is None
    assert wardrobe.all() == {}


def test_remove_missing_is_noop(wardrobe):
    # Should not raise even if the key isn't present.
    wardrobe.set("com.apple.Safari", None)
    assert wardrobe.all() == {}


def test_blank_bundle_id_is_rejected(wardrobe):
    wardrobe.set("", "af_bella")
    wardrobe.set("   ", "af_bella")
    assert wardrobe.all() == {}


def test_none_bundle_id_for_get(wardrobe):
    # Defensive — many callers will pass `nil`/None when the frontmost
    # app has no bundle id (e.g. CLI tool).
    assert wardrobe.get(None) is None
    assert wardrobe.get("") is None


# ----- persistence -----


def test_persistence_across_instances(wardrobe_path):
    w1 = VoiceWardrobe(path=wardrobe_path)
    w1.set("com.tinyspeck.slackmacgap", "am_michael")
    w1.set("org.mozilla.firefox", "af_bella")

    # Fresh instance should see the same mapping.
    w2 = VoiceWardrobe(path=wardrobe_path)
    assert w2.get("com.tinyspeck.slackmacgap") == "am_michael"
    assert w2.get("org.mozilla.firefox") == "af_bella"


def test_persistence_after_remove(wardrobe_path):
    w1 = VoiceWardrobe(path=wardrobe_path)
    w1.set("a", "v1")
    w1.set("b", "v2")
    w1.set("a", None)

    w2 = VoiceWardrobe(path=wardrobe_path)
    assert w2.get("a") is None
    assert w2.get("b") == "v2"


def test_file_format_is_versioned(wardrobe_path):
    w = VoiceWardrobe(path=wardrobe_path)
    w.set("com.apple.Safari", "af_bella")

    raw = json.loads(wardrobe_path.read_text())
    assert raw["version"] == 1
    assert raw["mappings"] == {"com.apple.Safari": "af_bella"}


def test_atomic_write_no_tempfile_left_behind(wardrobe_path):
    w = VoiceWardrobe(path=wardrobe_path)
    w.set("com.apple.Safari", "af_bella")
    # After a successful write the directory should hold the wardrobe
    # and no stray tempfiles.
    siblings = list(wardrobe_path.parent.iterdir())
    assert len(siblings) == 1
    assert siblings[0].name == "voice_wardrobe.json"


# ----- corrupt / unknown-version file handling -----


def test_corrupt_json_treated_as_empty(wardrobe_path):
    wardrobe_path.write_text("not json at all {{{")
    w = VoiceWardrobe(path=wardrobe_path)
    assert w.all() == {}


def test_wrong_version_treated_as_empty(wardrobe_path):
    wardrobe_path.write_text(
        json.dumps({"version": 99, "mappings": {"x": "y"}})
    )
    w = VoiceWardrobe(path=wardrobe_path)
    assert w.all() == {}


def test_non_string_entries_dropped(wardrobe_path):
    wardrobe_path.write_text(
        json.dumps(
            {
                "version": 1,
                "mappings": {
                    "ok": "af_bella",
                    "bad_value": 42,
                    "": "x",
                },
            }
        )
    )
    w = VoiceWardrobe(path=wardrobe_path)
    assert w.all() == {"ok": "af_bella"}


# ----- resolve_voice -----


def test_resolve_voice_explicit_wins(wardrobe):
    wardrobe.set("com.apple.Safari", "af_bella")
    assert (
        resolve_voice(wardrobe, "com.apple.Safari", "am_michael", "af_heart")
        == "am_michael"
    )


def test_resolve_voice_wardrobe_when_no_explicit(wardrobe):
    wardrobe.set("com.apple.Safari", "af_bella")
    assert (
        resolve_voice(wardrobe, "com.apple.Safari", None, "af_heart") == "af_bella"
    )


def test_resolve_voice_default_when_no_match(wardrobe):
    assert (
        resolve_voice(wardrobe, "com.apple.Safari", None, "af_heart") == "af_heart"
    )


def test_resolve_voice_default_when_no_bundle(wardrobe):
    wardrobe.set("com.apple.Safari", "af_bella")
    assert resolve_voice(wardrobe, None, None, "af_heart") == "af_heart"
