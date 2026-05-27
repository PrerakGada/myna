"""Tests that /v2/synthesize emits language detection headers."""

from .v2_helpers import make_client


def test_lang_detect_emits_header_when_detected():
    client, _, app = make_client()
    app.state.detect_language = lambda text: "es"

    r = client.post("/v2/synthesize", json={"text": "Hola mundo."})
    assert r.status_code == 200
    assert r.headers.get("X-Myna-Detected-Lang") == "es"


def test_lang_mismatch_header_set_when_different():
    # Default config has lang_code "a" (American English == iso "en").
    # If the detector says "es", we expect both headers.
    client, _, app = make_client()
    app.state.detect_language = lambda text: "es"

    r = client.post("/v2/synthesize", json={"text": "Hola mundo."})
    assert r.status_code == 200
    assert r.headers.get("X-Myna-Detected-Lang") == "es"
    assert r.headers.get("X-Myna-Lang-Mismatch") == "1"


def test_no_mismatch_header_when_languages_match():
    client, _, app = make_client()
    # Configured lang_code "a" maps to "en"; detector also says "en".
    app.state.detect_language = lambda text: "en"

    r = client.post("/v2/synthesize", json={"text": "Hello there friend."})
    assert r.status_code == 200
    assert r.headers.get("X-Myna-Detected-Lang") == "en"
    assert "X-Myna-Lang-Mismatch" not in r.headers


def test_no_headers_when_detection_returns_none():
    client, _, app = make_client()
    app.state.detect_language = lambda text: None

    r = client.post("/v2/synthesize", json={"text": "abc"})
    assert r.status_code == 200
    assert "X-Myna-Detected-Lang" not in r.headers
    assert "X-Myna-Lang-Mismatch" not in r.headers


def test_detection_exception_doesnt_break_synthesize():
    client, _, app = make_client()

    def boom(text):
        raise RuntimeError("langid exploded")

    app.state.detect_language = boom

    r = client.post("/v2/synthesize", json={"text": "Hello."})
    assert r.status_code == 200
    assert "X-Myna-Detected-Lang" not in r.headers


def test_detection_works_with_summary_mode():
    client, _, app = make_client()
    # The summary path runs the detector against the post-summarization
    # text. The FakeSummarize replaces text with "SUMMARY"; we override
    # the detector to verify the wiring is consistent.
    app.state.detect_language = lambda text: "es"

    r = client.post(
        "/v2/synthesize", json={"text": "Original text.", "mode": "summary"}
    )
    assert r.status_code == 200
    assert r.headers.get("X-Myna-Detected-Lang") == "es"
