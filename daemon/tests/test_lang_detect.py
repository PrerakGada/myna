"""Tests for myna.lang_detect.

These exercise the *behaviour* of detect_language rather than the
exact codes langid returns — langid's training data drifts between
versions, so asserting "English == 'en'" is fine but asserting
"this single word == 'es'" would be brittle.
"""

import pytest

from myna.lang_detect import detect_language, map_voice_lang_to_iso


# Skip the whole module if langid isn't importable. The default dev
# extras include it, but a brew-installed daemon won't.
langid = pytest.importorskip("langid")


def test_detect_english_paragraph():
    text = (
        "The quick brown fox jumps over the lazy dog. "
        "Pack my box with five dozen liquor jugs."
    )
    assert detect_language(text) == "en"


def test_detect_spanish_paragraph():
    text = (
        "El veloz murciélago hindú comía feliz cardillo y kiwi. "
        "La cigüeña tocaba el saxofón detrás del palenque de paja."
    )
    assert detect_language(text) == "es"


def test_detect_japanese_paragraph():
    # Mostly hiragana/katakana/kanji — langid should call this "ja".
    text = "私は猫が大好きです。今日はとても良い天気ですね。散歩に行きましょう。"
    assert detect_language(text) == "ja"


def test_short_text_returns_none():
    # Below the _MIN_CHARS threshold detection is unreliable, so the
    # function should explicitly refuse rather than guess.
    assert detect_language("hello") is None
    assert detect_language("") is None


def test_whitespace_only_returns_none():
    assert detect_language("   \n  \t ") is None


def test_none_input_returns_none():
    # Defensive — tests we never crash if the caller passes None.
    assert detect_language(None) is None  # type: ignore[arg-type]


def test_gibberish_returns_something_or_none():
    # We don't care what langid guesses for "asdf jkl;..." — we only
    # care that the function never raises. Calling it is the test.
    result = detect_language("asdfjkl asdfjkl asdfjkl asdfjkl asdfjkl asdfjkl")
    # Either None (filtered) or a valid two-letter code.
    assert result is None or (isinstance(result, str) and len(result) == 2)


def test_mixed_language_returns_a_dominant_one():
    # A passage with a heavy Spanish lead and a trailing English line.
    # We don't care which one wins; we care that we get a single ISO code
    # or None, not a crash.
    text = (
        "Hola, ¿cómo estás? Espero que estés muy bien hoy. "
        "Hello, how are you doing today my friend?"
    )
    result = detect_language(text)
    assert result is None or (isinstance(result, str) and len(result) == 2)


# ----- map_voice_lang_to_iso -----


def test_map_kokoro_short_codes():
    assert map_voice_lang_to_iso("a") == "en"  # American English
    assert map_voice_lang_to_iso("b") == "en"  # British English
    assert map_voice_lang_to_iso("j") == "ja"


def test_map_iso_passthrough():
    assert map_voice_lang_to_iso("en") == "en"
    assert map_voice_lang_to_iso("es") == "es"
    # "unknown" placeholder -> None
    assert map_voice_lang_to_iso("unknown") is None


def test_map_handles_none_and_empty():
    assert map_voice_lang_to_iso(None) is None
    assert map_voice_lang_to_iso("") is None
    assert map_voice_lang_to_iso("   ") is None
