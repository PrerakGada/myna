"""Tests for the /v2/voice_wardrobe endpoints + bundle_id wiring into
/v2/synthesize.
"""

from .v2_helpers import make_client, parse_multipart


# ----- GET /v2/voice_wardrobe -----


def test_get_wardrobe_empty():
    client, _, _ = make_client()
    r = client.get("/v2/voice_wardrobe")
    assert r.status_code == 200
    assert r.json() == {"mappings": {}}


def test_get_wardrobe_returns_known_entries():
    client, _, app = make_client()
    app.state.wardrobe.set("com.apple.Safari", "af_bella")
    app.state.wardrobe.set("com.tinyspeck.slackmacgap", "am_michael")

    r = client.get("/v2/voice_wardrobe")
    assert r.status_code == 200
    assert r.json() == {
        "mappings": {
            "com.apple.Safari": "af_bella",
            "com.tinyspeck.slackmacgap": "am_michael",
        }
    }


# ----- POST /v2/voice_wardrobe -----


def test_post_wardrobe_upsert():
    client, _, app = make_client()

    r = client.post(
        "/v2/voice_wardrobe",
        json={"bundle_id": "com.apple.Safari", "voice_id": "af_bella"},
    )
    assert r.status_code == 200
    assert r.json() == {"mappings": {"com.apple.Safari": "af_bella"}}
    assert app.state.wardrobe.get("com.apple.Safari") == "af_bella"


def test_post_wardrobe_remove():
    client, _, app = make_client()
    app.state.wardrobe.set("com.apple.Safari", "af_bella")

    # Removing is signalled by voice_id=null.
    r = client.post(
        "/v2/voice_wardrobe",
        json={"bundle_id": "com.apple.Safari", "voice_id": None},
    )
    assert r.status_code == 200
    assert r.json() == {"mappings": {}}
    assert app.state.wardrobe.get("com.apple.Safari") is None


def test_post_wardrobe_rejects_empty_bundle_id():
    client, _, _ = make_client()
    r = client.post(
        "/v2/voice_wardrobe",
        json={"bundle_id": "   ", "voice_id": "af_bella"},
    )
    assert r.status_code == 400
    body = r.json().get("detail", r.json())
    assert body["reason"] == "missing_bundle_id"


def test_post_wardrobe_missing_bundle_id():
    # Pydantic validation: bundle_id is required.
    client, _, _ = make_client()
    r = client.post("/v2/voice_wardrobe", json={"voice_id": "af_bella"})
    assert r.status_code == 422


# ----- /v2/synthesize honours bundle_id -----


def _capture_voice(app):
    """Replace app.state.synthesize so we can inspect what voice it received."""
    captured = []

    def fake_synth(text, **kw):
        captured.append(kw.get("voice"))
        return b"RIFFfake"

    app.state.synthesize = fake_synth
    return captured


def test_synthesize_uses_wardrobe_for_bundle():
    client, _, app = make_client()
    app.state.wardrobe.set("com.apple.Safari", "am_michael")
    voices = _capture_voice(app)

    r = client.post(
        "/v2/synthesize",
        json={"text": "Hello there.", "bundle_id": "com.apple.Safari"},
    )
    assert r.status_code == 200
    # Every chunk should have used the wardrobe voice.
    assert voices, "synthesize was never called"
    for v in voices:
        assert v == "am_michael"


def test_synthesize_explicit_voice_overrides_wardrobe():
    client, _, app = make_client()
    app.state.wardrobe.set("com.apple.Safari", "am_michael")
    voices = _capture_voice(app)

    r = client.post(
        "/v2/synthesize",
        json={
            "text": "Hello there.",
            "bundle_id": "com.apple.Safari",
            "voice": "af_bella",
        },
    )
    assert r.status_code == 200
    for v in voices:
        assert v == "af_bella"


def test_synthesize_no_wardrobe_match_falls_back_to_default():
    client, _, app = make_client()
    # No mapping for this bundle.
    voices = _capture_voice(app)

    r = client.post(
        "/v2/synthesize",
        json={"text": "Hello there.", "bundle_id": "com.unknown.Thing"},
    )
    assert r.status_code == 200
    # Falls back to the configured default (af_heart in test config).
    for v in voices:
        assert v == "af_heart"


def test_synthesize_no_bundle_id_uses_default():
    client, _, app = make_client()
    voices = _capture_voice(app)

    r = client.post("/v2/synthesize", json={"text": "Hello there."})
    assert r.status_code == 200
    for v in voices:
        assert v == "af_heart"


def test_wardrobe_lookup_failure_doesnt_break_synthesize():
    """Even if the wardrobe blows up, synthesize still works."""

    class BrokenWardrobe:
        def get(self, bundle_id):
            raise RuntimeError("wardrobe on fire")

        def all(self):
            return {}

    client, _, app = make_client()
    app.state.wardrobe = BrokenWardrobe()
    voices = _capture_voice(app)

    r = client.post(
        "/v2/synthesize",
        json={"text": "Hello there.", "bundle_id": "com.apple.Safari"},
    )
    assert r.status_code == 200
    # Falls back gracefully — request voice was None, default applies.
    for v in voices:
        assert v == "af_heart"


# Just to be exhaustive: verify multipart parsing still works with the
# wardrobe path.
def test_synthesize_with_wardrobe_returns_valid_multipart():
    client, _, app = make_client(config_overrides={"chunk_chars": 20})
    app.state.wardrobe.set("com.apple.Safari", "am_michael")
    r = client.post(
        "/v2/synthesize",
        json={
            "text": "First one. Second one. Third one.",
            "bundle_id": "com.apple.Safari",
        },
    )
    parts = parse_multipart(r.content)
    audio = [p for p in parts if p["headers"].get("Content-Type") == "audio/wav"]
    assert len(audio) == 3
