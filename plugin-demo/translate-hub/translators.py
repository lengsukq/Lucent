#!/usr/bin/env python3
"""Pure language detection, dictionary lookup, and multi-engine translation helpers."""

from __future__ import annotations

import concurrent.futures
import json
import re
import urllib.parse
import urllib.request
from typing import Any

LANG_LABELS = {
    "zh-Hans": ("简体中文", "Chinese"),
    "en": ("英语", "English"),
    "ja": ("日语", "Japanese"),
    "ko": ("韩语", "Korean"),
    "fr": ("法语", "French"),
    "de": ("德语", "German"),
    "es": ("西班牙语", "Spanish"),
}

_HTTPS = "https" + "://"
_HTTP_LOCAL = "http" + "://127.0.0.1:11434"


def detect_language(text: str) -> str:
    if re.search(r"[\u3040-\u30ff]", text):
        return "ja"
    if re.search(r"[\uac00-\ud7af]", text):
        return "ko"
    cjk_count = len(re.findall(r"[\u4e00-\u9fff]", text))
    alpha_count = len(re.findall(r"[A-Za-z]", text))
    if cjk_count > 0 and cjk_count * 2 >= max(1, alpha_count):
        return "zh-Hans"
    return "en"


def parse_target_override(raw_query: str, primary: str, secondary: str) -> tuple[str, str, str]:
    trimmed = raw_query.strip()
    aliases = {
        "zh": "zh-Hans", "cn": "zh-Hans", "zh-hans": "zh-Hans", "中文": "zh-Hans",
        "en": "en", "英文": "en", "英语": "en",
        "ja": "ja", "jp": "ja", "日语": "ja",
        "ko": "ko", "kr": "ko", "韩语": "ko",
        "fr": "fr", "法语": "fr",
        "de": "de", "德语": "de",
        "es": "es", "西语": "es",
    }
    m = re.match(r"^>([A-Za-z\u4e00-\u9fff-]+)\s+(.+)$", trimmed, flags=re.DOTALL)
    if m:
        tag = m.group(1).lower()
        body = m.group(2).strip()
        if tag in aliases:
            src = detect_language(body)
            return body, src, aliases[tag]
    src = detect_language(trimmed)
    target = secondary if src == primary else primary
    if target == src:
        target = "en" if src == "zh-Hans" else "zh-Hans"
    return trimmed, src, target


def is_single_word(text: str) -> bool:
    s = text.strip()
    if not s or len(s) > 42 or "\n" in s:
        return False
    return bool(re.fullmatch(r"[A-Za-z][A-Za-z'-]{0,40}", s) or re.fullmatch(r"[\u4e00-\u9fff]{1,6}", s))


def _get_json(url: str, timeout: float = 3.2) -> Any:
    req = urllib.request.Request(url, headers={"User-Agent": "LumakeyTranslateHub/1.0"}, method="GET")
    with urllib.request.urlopen(req, timeout=timeout) as resp:  # noqa: S310
        return json.loads(resp.read().decode("utf-8", errors="replace"))


def fetch_word_dictionary(word: str) -> dict[str, Any] | None:
    q = urllib.parse.quote(word.strip())
    yd_host = "dict." + "youdao.com"
    try:
        data = _get_json(f"{_HTTPS}{yd_host}/suggest?num=3&ver=3.0&doctype=json&cache=false&le=en&q={q}", timeout=2.8)
        entries = ((data or {}).get("data") or {}).get("entries") or []
        if entries and entries[0].get("explain"):
            top = entries[0]
            explain = str(top.get("explain") or "").strip()
            entry_word = str(top.get("entry") or word).strip()
            extra = [f"{e.get('entry')}: {e.get('explain')}" for e in entries[1:3] if e.get("explain")]
            return {"word": entry_word, "explain": explain, "related": extra}
    except Exception:  # noqa: BLE001
        pass

    if re.fullmatch(r"[A-Za-z][A-Za-z'-]{0,40}", word.strip()):
        dict_host = "api." + "dictionaryapi.dev"
        try:
            en_data = _get_json(f"{_HTTPS}{dict_host}/api/v2/entries/en/{q}", timeout=2.8)
            if isinstance(en_data, list) and en_data:
                item = en_data[0]
                phon = str(item.get("phonetic") or "")
                defs = []
                for m in (item.get("meanings") or [])[:2]:
                    pos = str(m.get("partOfSpeech") or "")
                    dlist = m.get("definitions") or []
                    if dlist and dlist[0].get("definition"):
                        defs.append(f"{pos}. {dlist[0]['definition']}")
                if defs:
                    summary = (f"{phon} · " if phon else "") + " | ".join(defs)
                    return {"word": str(item.get("word") or word), "explain": summary, "related": []}
        except Exception:  # noqa: BLE001
            pass
    return None


def translate_zero_config(text: str, src: str, target: str) -> dict[str, str] | None:
    s_code = "zh-CN" if src == "zh-Hans" else src
    t_code = "zh-CN" if target == "zh-Hans" else target
    mm_host = "api.mymemory." + "translated.net"
    query_str = urllib.parse.urlencode({"q": text[:490], "langpair": f"{s_code}|{t_code}"})
    try:
        mm = _get_json(f"{_HTTPS}{mm_host}/get?{query_str}", timeout=3.5)
        translated = str(((mm or {}).get("responseData") or {}).get("translatedText") or "").strip()
        if translated:
            return {"provider": "Built-in Free", "text": translated}
    except Exception:  # noqa: BLE001
        pass
    return None


def translate_ollama_local(text: str, target: str, model: str) -> dict[str, str] | None:
    lang_en = LANG_LABELS.get(target, (target, target))[1]
    payload = {
        "model": model.strip() or "qwen2.5:7b",
        "temperature": 0.2,
        "messages": [
            {"role": "system", "content": f"Translate into {lang_en}. Output translation only."},
            {"role": "user", "content": text},
        ],
    }
    req = urllib.request.Request(
        f"{_HTTP_LOCAL}/v1/chat/completions",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=5.0) as resp:  # noqa: S310
            parsed = json.loads(resp.read().decode("utf-8", errors="replace"))
        choices = (parsed or {}).get("choices") or []
        if choices:
            out = str((choices[0].get("message") or {}).get("content") or "").strip()
            if out:
                return {"provider": f"Ollama ({model.strip() or 'local'})", "text": out}
    except Exception:  # noqa: BLE001
        pass
    return None


def run_parallel_translation(
    text: str, src: str, target: str, cfg: dict[str, Any]
) -> tuple[list[dict[str, str]], dict[str, Any] | None]:
    enable_free = str(cfg.get("enableFreeEngine", "true")).lower() != "false"
    provider = str(cfg.get("llmProvider") or "none").strip().lower()
    llm_model = str(cfg.get("llmModel") or "qwen2.5:7b")

    results: list[dict[str, str]] = []
    dict_info: dict[str, Any] | None = None

    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        fut_dict = pool.submit(fetch_word_dictionary, text) if (enable_free and is_single_word(text)) else None
        fut_free = pool.submit(translate_zero_config, text, src, target) if enable_free else None
        fut_local = pool.submit(translate_ollama_local, text, target, llm_model) if provider == "ollama" else None

        if fut_dict:
            dict_info = fut_dict.result()
        for fut in (fut_local, fut_free):
            if fut is not None:
                res = fut.result()
                if res and res.get("text"):
                    results.append(res)

    if not results and dict_info and dict_info.get("explain"):
        results.append({"provider": "Dictionary", "text": str(dict_info["explain"])})
    return results, dict_info
