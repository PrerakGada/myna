"""Lightweight language detection for synthesize requests.

The daemon never *switches* voices on its own — it only annotates the
response so the Swift client can surface "Detected: Spanish — switch
voice?" UX. This module is intentionally tiny: it returns the
ISO-639-1 code (or None) and never raises.

We use `langid` because:
  - it's deterministic (a fixed pretrained model, no network calls);
  - faster than `langdetect` on short strings (no Monte-Carlo sampling);
  - confidence scores are exposed, which we use to suppress noise on
    very short / gibberish inputs.

If `langid` isn't installed (e.g. local dev without the dev extras),
`detect_language` quietly returns None and the synthesize path skips
the language headers — no behaviour change for the user.
"""

from __future__ import annotations

# Minimum character count before we trust the detector. Below this the
# detector flips between English/French/Spanish on the same input and
# produces more confusion than signal.
_MIN_CHARS = 20

# Floor for langid's raw log-probability. langid scores are deeply
# negative log-probs that grow roughly linearly with text length, so an
# absolute threshold isn't useful here — we just use a generous floor
# (anything close to -inf is the "didn't really match anything" tail
# and we discard those). For most natural-language inputs ≥20 chars
# this lets the top language through.
_MIN_CONFIDENCE = -10_000.0


def detect_language(text: str) -> str | None:
    """Best-effort language detection.

    Returns the ISO-639-1 two-letter code (e.g. ``"en"``, ``"es"``,
    ``"ja"``) when the detector is confident enough, otherwise None.

    Never raises — returns None on any failure (missing dep, empty
    input, langid internal error).
    """
    if not text:
        return None
    cleaned = text.strip()
    if len(cleaned) < _MIN_CHARS:
        return None

    try:
        import langid  # type: ignore[import-not-found]
    except ImportError:
        return None

    try:
        lang, confidence = langid.classify(cleaned)
    except Exception:
        return None

    if not isinstance(lang, str) or len(lang) != 2:
        return None
    if confidence < _MIN_CONFIDENCE:
        return None
    return lang


def map_voice_lang_to_iso(voice_lang: str | None) -> str | None:
    """Map a Kokoro voice lang string to an ISO-639-1 code.

    Kokoro voices use one-letter lang codes ("a" = American English,
    "b" = British English, etc.) and ``_voice_lang`` in app.py turns
    those into "en"/"unknown". This helper takes either form and
    returns an ISO code or None.
    """
    if not voice_lang:
        return None
    voice_lang = voice_lang.lower().strip()
    # Already ISO-639-1.
    if len(voice_lang) == 2 and voice_lang != "un":
        return voice_lang
    # Kokoro single-letter language code.
    mapping = {
        "a": "en",  # American English
        "b": "en",  # British English
        "j": "ja",  # Japanese
        "z": "zh",  # Mandarin
        "e": "es",  # Spanish
        "f": "fr",  # French
        "h": "hi",  # Hindi
        "i": "it",  # Italian
        "p": "pt",  # Portuguese
    }
    return mapping.get(voice_lang)
