#!/usr/bin/env python3
"""Local CLI & session-telemetry collectors for Codex, Claude Code, AGY, and DSH."""

from __future__ import annotations

import datetime as dt
import glob
import json
import os
import re
import shutil
import sqlite3
import subprocess
import tempfile
import threading
import time
from pathlib import Path
from typing import Any

ANSI_ESCAPE_RE = re.compile(r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])")


def clamp_pct(val: float) -> float:
    return max(0.0, min(100.0, float(val)))


def parse_timestamp(raw: Any) -> float:
    if raw is None:
        return 0.0
    if isinstance(raw, (int, float)):
        v = float(raw)
        return v / 1000.0 if v > 10_000_000_000 else v
    s = str(raw).strip()
    if not s:
        return 0.0
    try:
        v = float(s)
        return v / 1000.0 if v > 10_000_000_000 else v
    except ValueError:
        pass
    try:
        iso = s.replace("Z", "+00:00")
        parsed = dt.datetime.fromisoformat(iso)
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=dt.timezone.utc)
        return parsed.timestamp()
    except ValueError:
        return 0.0


def build_cli_env(home: Path, extra_paths: str = "") -> dict[str, str]:
    candidate_dirs: list[str] = []
    for raw_p in (extra_paths or "").split(":"):
        clean = raw_p.strip()
        if clean:
            candidate_dirs.append(str(Path(clean).expanduser()))

    static_bins = [
        home / ".local" / "bin",
        home / ".bun" / "bin",
        home / ".volta" / "bin",
        home / ".npm-global" / "bin",
        home / "Library" / "pnpm",
        home / ".pnpm-global" / "bin",
        home / ".asdf" / "shims",
        home / ".local" / "share" / "mise" / "shims",
        home / ".cargo" / "bin",
        Path("/opt/homebrew/bin"),
        Path("/usr/local/bin"),
    ]
    for p in static_bins:
        candidate_dirs.append(str(p))

    for pattern in (
        str(home / ".nvm" / "versions" / "node" / "*" / "bin"),
        str(home / ".fnm" / "node-versions" / "*" / "installation" / "bin"),
        str(home / "Library" / "Application Support" / "fnm" / "node-versions" / "*" / "installation" / "bin"),
    ):
        matched = sorted(glob.glob(pattern), reverse=True)
        candidate_dirs.extend(matched[:4])

    existing_path = os.environ.get("PATH", "/usr/bin:/bin:/usr/sbin:/sbin")
    seen: set[str] = set()
    merged: list[str] = []
    for d in [*candidate_dirs, *existing_path.split(":")]:
        if d and d not in seen:
            seen.add(d)
            merged.append(d)

    env = dict(os.environ)
    env["HOME"] = str(home)
    env["PATH"] = ":".join(merged)
    env["NO_COLOR"] = "1"
    env["TERM"] = "dumb"
    return env


def locate_cli(name: str, env: dict[str, str]) -> tuple[str | None, str]:
    resolved = shutil.which(name, path=env.get("PATH"))
    if not resolved:
        return (None, "")
    run_env = dict(env)
    if name == "agy":
        run_env["AGY_CLI_DISABLE_AUTO_UPDATE"] = "true"
    try:
        proc = subprocess.run(
            [resolved, "--version"],
            env=run_env,
            capture_output=True,
            text=True,
            timeout=1.6,
        )
        raw_out = ANSI_ESCAPE_RE.sub("", (proc.stdout or proc.stderr or "")).strip()
        first_line = raw_out.splitlines()[0].strip() if raw_out else ""
        ver_match = re.search(r"v?\d+\.\d+(?:\.\d+)?(?:-[A-Za-z0-9.]+)?", first_line)
        ver = ver_match.group(0) if ver_match else first_line[:24]
        return (resolved, ver)
    except Exception:
        return (resolved, "")


def _probe_codex_app_server(codex_bin: str, env: dict[str, str], timeout: float = 2.4) -> dict[str, Any] | None:
    try:
        proc = subprocess.Popen(
            [codex_bin, "app-server"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            env=env,
        )
    except Exception:
        return None

    responses: dict[int, dict[str, Any]] = {}
    got_init = threading.Event()
    got_limits = threading.Event()

    def _reader() -> None:
        assert proc.stdout is not None
        for line in proc.stdout:
            s = line.strip()
            if not s.startswith("{"):
                continue
            try:
                msg = json.loads(s)
            except Exception:
                continue
            msg_id = msg.get("id")
            if msg_id == 0:
                responses[0] = msg
                got_init.set()
            elif msg_id == 1:
                responses[1] = msg
                got_limits.set()
                break

    t = threading.Thread(target=_reader, daemon=True)
    t.start()
    try:
        if proc.stdin is None:
            return None
        init_req = {
            "jsonrpc": "2.0",
            "id": 0,
            "method": "initialize",
            "params": {"clientInfo": {"name": "lumakey-ai-quota", "title": "Lumakey AI Quota", "version": "1.0.0"}},
        }
        proc.stdin.write(json.dumps(init_req) + "\n")
        proc.stdin.flush()
        if not got_init.wait(timeout=0.55):
            time.sleep(0.25)
        read_req = {"jsonrpc": "2.0", "id": 1, "method": "account/rateLimits/read", "params": {}}
        proc.stdin.write(json.dumps(read_req) + "\n")
        proc.stdin.flush()
        got_limits.wait(timeout=max(0.4, timeout - 0.6))
    except Exception:
        pass
    finally:
        try:
            if proc.stdin:
                proc.stdin.close()
        except Exception:
            pass
        try:
            proc.kill()
            proc.wait(timeout=0.5)
        except Exception:
            pass
        try:
            if proc.stdout:
                proc.stdout.close()
        except Exception:
            pass

    msg = responses.get(1)
    if not isinstance(msg, dict):
        return None
    res = msg.get("result")
    return res if isinstance(res, dict) else None


def _normalize_codex_window(win: dict[str, Any] | None, default_zh: str, default_en: str) -> dict[str, Any] | None:
    if not isinstance(win, dict):
        return None
    raw_used = win.get("used_percent")
    if raw_used is None:
        raw_used = win.get("usedPercent")
    if raw_used is None:
        return None
    try:
        used_pct = clamp_pct(float(raw_used))
    except (TypeError, ValueError):
        return None
    win_sec = win.get("limit_window_seconds") or win.get("limitWindowSeconds")
    if not win_sec:
        w_mins = win.get("window_minutes") or win.get("windowDurationMins")
        if w_mins:
            try:
                win_sec = float(w_mins) * 60.0
            except (TypeError, ValueError):
                win_sec = None
    reset_ts = parse_timestamp(win.get("reset_at") or win.get("resets_at") or win.get("resetsAt"))
    if reset_ts <= 0 and win.get("reset_after_seconds"):
        try:
            reset_ts = time.time() + float(win["reset_after_seconds"])
        except (TypeError, ValueError):
            pass
    return {
        "used_pct": used_pct,
        "window_seconds": win_sec,
        "default_zh": default_zh,
        "default_en": default_en,
        "reset_ts": reset_ts,
    }


def _scan_codex_local_logs(codex_dir: Path) -> tuple[list[dict[str, Any]], str, int, int]:
    sessions_dir = codex_dir / "sessions"
    windows: list[dict[str, Any]] = []
    plan_type = ""
    today_tokens = 0
    today_sessions = 0
    today_start = dt.datetime.now().replace(hour=0, minute=0, second=0, microsecond=0).timestamp()

    if sessions_dir.is_dir():
        rollout_files: list[tuple[float, Path]] = []
        for root, _, files in os.walk(sessions_dir):
            for fn in files:
                if fn.endswith(".jsonl"):
                    fp = Path(root) / fn
                    try:
                        st = fp.stat()
                        rollout_files.append((st.st_mtime, fp))
                    except OSError:
                        continue
        rollout_files.sort(key=lambda x: x[0], reverse=True)

        for mtime, fp in rollout_files[:30]:
            is_today = mtime >= today_start
            session_max_tok = 0
            try:
                with fp.open("rb") as fh:
                    fh.seek(0, os.SEEK_END)
                    size = fh.tell()
                    fh.seek(max(0, size - 131_072), os.SEEK_SET)
                    tail_lines = fh.read().decode("utf-8", errors="replace").splitlines()
            except OSError:
                continue

            for line in reversed(tail_lines):
                if "rate_limits" not in line and "token_count" not in line:
                    continue
                try:
                    obj = json.loads(line)
                except Exception:
                    continue
                payload = obj.get("payload") if isinstance(obj.get("payload"), dict) else obj
                if is_today and session_max_tok == 0:
                    info = payload.get("info") if isinstance(payload.get("info"), dict) else {}
                    tot_usage = info.get("total_token_usage") if isinstance(info.get("total_token_usage"), dict) else {}
                    tok = int(tot_usage.get("total_tokens") or 0)
                    if tok > 0:
                        session_max_tok = tok
                if not windows:
                    rl = payload.get("rate_limits")
                    if isinstance(rl, dict):
                        p_win = _normalize_codex_window(rl.get("primary"), "5h", "5h")
                        s_win = _normalize_codex_window(rl.get("secondary"), "周限", "7d")
                        cand = [w for w in (p_win, s_win) if w is not None]
                        if cand:
                            windows = cand
                            plan_type = str(rl.get("plan_type") or "")
            if is_today:
                today_sessions += 1
                today_tokens += session_max_tok

    if today_tokens == 0 and codex_dir.is_dir():
        sqlite_candidates = sorted(codex_dir.glob("state_*.sqlite"), reverse=True)
        for db_path in sqlite_candidates[:1]:
            scratch = Path(tempfile.mkdtemp(prefix="lk-aq-cdx-"))
            try:
                staged = scratch / db_path.name
                shutil.copyfile(db_path, staged)
                for suf in ("-wal", "-shm"):
                    sc = Path(str(db_path) + suf)
                    if sc.is_file():
                        shutil.copyfile(sc, Path(str(staged) + suf))
                conn = sqlite3.connect(str(staged), timeout=1.5)
                try:
                    cur = conn.execute(
                        "SELECT COUNT(id), COALESCE(SUM(tokens_used), 0) FROM threads WHERE created_at >= ?",
                        (int(today_start),),
                    )
                    row = cur.fetchone()
                    if row and int(row[0] or 0) > 0:
                        today_sessions = max(today_sessions, int(row[0]))
                        today_tokens = max(today_tokens, int(row[1] or 0))
                finally:
                    conn.close()
            except Exception:
                pass
            finally:
                shutil.rmtree(scratch, ignore_errors=True)

    return (windows, plan_type, today_tokens, today_sessions)


def collect_codex(home: Path, env: dict[str, str]) -> dict[str, Any]:
    codex_dir = Path(os.environ.get("CODEX_HOME") or (home / ".codex"))
    cli_bin, cli_ver = locate_cli("codex", env)
    windows: list[dict[str, Any]] = []
    plan_type = ""
    credits_txt = ""
    source_tag = ""

    if cli_bin:
        rpc_res = _probe_codex_app_server(cli_bin, env)
        if isinstance(rpc_res, dict):
            rl = rpc_res.get("rateLimits") if isinstance(rpc_res.get("rateLimits"), dict) else rpc_res
            p_win = _normalize_codex_window(rl.get("primary"), "5h", "5h")
            s_win = _normalize_codex_window(rl.get("secondary"), "周限", "7d")
            cand = [w for w in (p_win, s_win) if w is not None]
            if cand:
                windows = cand
                plan_type = str(rl.get("planType") or rl.get("plan_type") or "")
                cred_obj = rl.get("credits") if isinstance(rl.get("credits"), dict) else {}
                if cred_obj.get("balance"):
                    credits_txt = str(cred_obj["balance"])
                source_tag = "CLI RPC"

    log_windows, log_plan, today_tokens, today_sessions = _scan_codex_local_logs(codex_dir)
    if not windows and log_windows:
        windows = log_windows
        source_tag = "Session Log"
    if not plan_type and log_plan:
        plan_type = log_plan

    installed = bool(cli_bin or codex_dir.is_dir())
    return {
        "provider": "codex",
        "installed": installed,
        "cliVersion": cli_ver,
        "plan": plan_type.upper() if plan_type else "",
        "windows": windows,
        "credits": credits_txt,
        "todayTokens": today_tokens,
        "todaySessions": today_sessions,
        "source": source_tag or ("CLI" if cli_bin else ""),
    }


def _extract_claude_pct(win: dict[str, Any], scale_100: bool) -> float | None:
    for k in ("used_percentage", "used_percent", "usedPercent"):
        if win.get(k) is not None:
            try:
                return clamp_pct(float(win[k]))
            except (TypeError, ValueError):
                pass
    if win.get("utilization") is not None:
        try:
            raw = float(win["utilization"])
            return clamp_pct(raw * 100.0 if scale_100 else raw)
        except (TypeError, ValueError):
            pass
    return None


def _parse_claude_usage_dict(data: dict[str, Any]) -> list[dict[str, Any]]:
    win_specs = [
        ("five_hour", "5h", "5h", 18000),
        ("seven_day", "周限", "7d", 604800),
        ("seven_day_sonnet", "Sonnet周", "Sonnet 7d", 604800),
        ("seven_day_opus", "Opus周", "Opus 7d", 604800),
    ]
    raw_utils: list[float] = []
    has_explicit_pct_key = False
    for key, _, _, _ in win_specs:
        w = data.get(key)
        if isinstance(w, dict):
            if any(k in w for k in ("used_percentage", "used_percent", "usedPercent")):
                has_explicit_pct_key = True
            if w.get("utilization") is not None:
                try:
                    raw_utils.append(float(w["utilization"]))
                except (TypeError, ValueError):
                    pass

    non_zero = [v for v in raw_utils if v > 0]
    scale_100 = (
        not has_explicit_pct_key
        and bool(non_zero)
        and max(non_zero) <= 1.0
        and any(round(v, 4) != round(v, 0) for v in non_zero)
    )

    out: list[dict[str, Any]] = []
    for key, zh_lbl, en_lbl, sec in win_specs:
        w = data.get(key)
        if not isinstance(w, dict):
            continue
        used_pct = _extract_claude_pct(w, scale_100=scale_100)
        if used_pct is None:
            continue
        out.append(
            {
                "used_pct": used_pct,
                "window_seconds": None if key.startswith("seven_day_") else sec,
                "default_zh": zh_lbl,
                "default_en": en_lbl,
                "reset_ts": parse_timestamp(w.get("resets_at") or w.get("reset_at")),
            }
        )
    return out


def _scan_claude_today_tokens(claude_dir: Path) -> tuple[int, int, float]:
    projects_dir = claude_dir / "projects"
    if not projects_dir.is_dir():
        return (0, 0, 0.0)

    today_start = dt.datetime.now().replace(hour=0, minute=0, second=0, microsecond=0).timestamp()
    recent_files: list[tuple[float, Path]] = []
    for root, _, files in os.walk(projects_dir):
        for fn in files:
            if fn.endswith(".jsonl"):
                fp = Path(root) / fn
                try:
                    mtime = fp.stat().st_mtime
                    if mtime >= today_start:
                        recent_files.append((mtime, fp))
                except OSError:
                    continue

    recent_files.sort(key=lambda x: x[0], reverse=True)
    input_tok = 0
    output_tok = 0
    cache_read_tok = 0
    cache_write_tok = 0
    seen_ids: set[str] = set()
    active_sessions = 0

    for _, fp in recent_files[:50]:
        file_had_today = False
        try:
            with fp.open("r", encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    if '"usage"' not in line:
                        continue
                    try:
                        obj = json.loads(line)
                    except Exception:
                        continue
                    ts = parse_timestamp(obj.get("timestamp"))
                    if ts > 0 and ts < today_start:
                        continue
                    msg = obj.get("message") if isinstance(obj.get("message"), dict) else obj
                    msg_id = str(msg.get("id") or obj.get("requestId") or "")
                    if msg_id and msg_id in seen_ids:
                        continue
                    usage = msg.get("usage")
                    if not isinstance(usage, dict):
                        continue
                    if msg_id:
                        seen_ids.add(msg_id)
                    file_had_today = True
                    input_tok += int(usage.get("input_tokens") or 0)
                    output_tok += int(usage.get("output_tokens") or 0)
                    cache_read_tok += int(usage.get("cache_read_input_tokens") or 0)
                    cache_write_tok += int(usage.get("cache_creation_input_tokens") or 0)
        except OSError:
            continue
        if file_had_today:
            active_sessions += 1

    total = input_tok + output_tok + cache_read_tok + cache_write_tok
    denom = input_tok + cache_read_tok + cache_write_tok
    hit_pct = (cache_read_tok / denom * 100.0) if denom > 0 else 0.0
    return (total, active_sessions, hit_pct)


def collect_claude(home: Path, env: dict[str, str]) -> dict[str, Any]:
    claude_dir = Path(os.environ.get("CLAUDE_CONFIG_DIR") or (home / ".claude"))
    cli_bin, cli_ver = locate_cli("claude", env)
    windows: list[dict[str, Any]] = []
    source_tag = ""

    for cache_name in (".usage-remote-cache.json", "quota-data.json", "usage.json"):
        cf = claude_dir / cache_name
        try:
            if cf.is_file():
                c_obj = json.loads(cf.read_text(encoding="utf-8"))
                if isinstance(c_obj, dict):
                    windows = _parse_claude_usage_dict(c_obj)
                    if windows:
                        source_tag = "Statusline Cache"
                        break
        except Exception:
            pass

    if not windows and cli_bin:
        try:
            proc = subprocess.run(
                [cli_bin, "-p", "/status", "--no-session-persistence"],
                env=env,
                capture_output=True,
                text=True,
                timeout=2.6,
            )
            clean_txt = ANSI_ESCAPE_RE.sub("", (proc.stdout or "") + "\n" + (proc.stderr or ""))
            for m in re.finditer(
                r"(5[- ]?hour|session|weekly|7[- ]?day)[^\n%]{0,42}?(\d{1,3}(?:\.\d+)?)\s*%",
                clean_txt,
                re.I,
            ):
                lbl_raw = m.group(1).lower()
                pct_val = clamp_pct(float(m.group(2)))
                tail_words = clean_txt[m.start() : m.end() + 16].lower()
                is_left = ("left" in tail_words) or ("remaining" in tail_words)
                used_val = (100.0 - pct_val) if is_left else pct_val
                is_5h = ("5" in lbl_raw) or ("session" in lbl_raw)
                windows.append(
                    {
                        "used_pct": used_val,
                        "window_seconds": 18000 if is_5h else 604800,
                        "default_zh": "5h" if is_5h else "周限",
                        "default_en": "5h" if is_5h else "7d",
                        "reset_ts": 0.0,
                    }
                )
            if windows:
                source_tag = "CLI /status"
        except Exception:
            pass

    today_tokens, today_sessions, cache_hit_pct = _scan_claude_today_tokens(claude_dir)
    installed = bool(cli_bin or claude_dir.is_dir())
    return {
        "provider": "claude",
        "installed": installed,
        "cliVersion": cli_ver,
        "plan": "",
        "windows": windows,
        "todayTokens": today_tokens,
        "todaySessions": today_sessions,
        "cacheHitPct": cache_hit_pct,
        "source": source_tag or ("JSONL Logs" if today_tokens > 0 else ("CLI" if cli_bin else "")),
    }


def _parse_agy_cli_usage_text(raw_text: str) -> list[dict[str, Any]]:
    clean = ANSI_ESCAPE_RE.sub("", raw_text or "")
    if clean.strip().startswith("{"):
        try:
            obj = json.loads(clean)
            if isinstance(obj, dict) and isinstance(obj.get("models"), list):
                out_json: list[dict[str, Any]] = []
                for m in obj["models"][:4]:
                    if not isinstance(m, dict):
                        continue
                    rem = m.get("remaining_percent")
                    if rem is None and m.get("remaining_fraction") is not None:
                        rem = float(m["remaining_fraction"]) * 100.0
                    if rem is not None:
                        mid = str(m.get("model_id") or m.get("modelId") or "Pool")
                        out_json.append(
                            {
                                "used_pct": clamp_pct(100.0 - float(rem)),
                                "window_seconds": None,
                                "default_zh": mid[:16],
                                "default_en": mid[:16],
                                "reset_ts": parse_timestamp(m.get("reset_time") or m.get("resetTime")),
                            }
                        )
                if out_json:
                    return out_json
        except Exception:
            pass

    windows: list[dict[str, Any]] = []
    line_re = re.compile(
        r"^\s*([A-Za-z0-9 _.·/-]{3,42}?)\s*:\s*(\d{1,3}(?:\.\d+)?)\s*%\s*(remaining|left|used)?(?:.*?(?:resets?|↻)\s*([0-9T:+-]{10,25}))?",
        re.I,
    )
    for line in clean.splitlines():
        m = line_re.search(line)
        if not m:
            continue
        raw_label = m.group(1).strip()
        pct = float(m.group(2))
        mode_word = (m.group(3) or "remaining").lower()
        used = pct if mode_word == "used" else (100.0 - pct)
        short = (
            raw_label.replace("Gemini Models", "Gemini")
            .replace("Five Hour Limit", "5h")
            .replace("Weekly", "7d")
            .strip()
        )
        windows.append(
            {
                "used_pct": clamp_pct(used),
                "window_seconds": None,
                "default_zh": short[:16],
                "default_en": short[:16],
                "reset_ts": parse_timestamp(m.group(4)) if m.group(4) else 0.0,
            }
        )
    return windows[:4]


def collect_agy(home: Path, env: dict[str, str]) -> dict[str, Any]:
    gemini_dir = home / ".gemini"
    agy_dir = gemini_dir / "antigravity-cli"
    cli_bin, cli_ver = locate_cli("agy", env)
    windows: list[dict[str, Any]] = []
    source_tag = ""

    if cli_bin:
        run_env = dict(env)
        run_env["AGY_CLI_DISABLE_AUTO_UPDATE"] = "true"
        try:
            proc = subprocess.run(
                [cli_bin, "-p", "/usage"],
                env=run_env,
                capture_output=True,
                text=True,
                timeout=2.8,
            )
            windows = _parse_agy_cli_usage_text((proc.stdout or "") + "\n" + (proc.stderr or ""))
            if windows:
                source_tag = "agy CLI"
        except Exception:
            pass

    today_tokens = 0
    today_sessions = 0
    today_str = dt.datetime.now().strftime("%Y-%m-%d")
    tmp_chats = gemini_dir / "tmp"
    if tmp_chats.is_dir():
        for chat_file in glob.glob(str(tmp_chats / "*" / "chats" / f"session-{today_str}*.json"))[:40]:
            today_sessions += 1
            try:
                c_data = json.loads(Path(chat_file).read_text(encoding="utf-8"))
                for msg in c_data.get("messages") or []:
                    if isinstance(msg, dict) and isinstance(msg.get("tokens"), dict):
                        today_tokens += int(msg["tokens"].get("total") or 0)
            except Exception:
                continue

    installed = bool(cli_bin or agy_dir.is_dir() or gemini_dir.is_dir())
    return {
        "provider": "agy",
        "installed": installed,
        "cliVersion": cli_ver,
        "plan": "",
        "windows": windows,
        "todayTokens": today_tokens,
        "todaySessions": today_sessions,
        "source": source_tag or ("CLI" if cli_bin else ""),
    }


def collect_dsh(home: Path, env: dict[str, str]) -> dict[str, Any]:
    dsh_home = Path(os.environ.get("DSH_HOME") or (home / ".dsh"))
    cli_bin, cli_ver = locate_cli("dsh", env)

    profiles: list[str] = []
    prof_root = dsh_home / "profiles"
    if prof_root.is_dir():
        try:
            profiles = sorted(p.name for p in prof_root.iterdir() if p.is_dir())
        except OSError:
            pass

    today_start = dt.datetime.now().replace(hour=0, minute=0, second=0, microsecond=0).timestamp()
    today_calls = 0
    today_tokens = 0
    cache_hit_tokens = 0
    input_total_tokens = 0
    today_cost_cny = 0.0

    usage_candidates: list[Path] = []
    env_usage_dir = os.environ.get("DSH_USAGE_DATA_DIR", "").strip()
    if env_usage_dir:
        usage_candidates.append(Path(env_usage_dir) / "dsh-usage" / "usage-records.json")
    usage_candidates.extend(
        [
            home / "dsh-usage-data" / "dsh-usage" / "usage-records.json",
            dsh_home / "dsh-usage" / "usage-records.json",
        ]
    )

    for rec_file in usage_candidates:
        if not rec_file.is_file():
            continue
        try:
            raw_obj = json.loads(rec_file.read_text(encoding="utf-8"))
            records = raw_obj.get("records") if isinstance(raw_obj, dict) else raw_obj
            if isinstance(records, list):
                for rec in reversed(records[-3000:]):
                    if not isinstance(rec, dict):
                        continue
                    ts = parse_timestamp(rec.get("timestamp") or rec.get("time") or rec.get("createdAt"))
                    if ts > 0 and ts < today_start:
                        continue
                    today_calls += 1
                    in_miss = int(rec.get("inputMissTokens") or rec.get("inputTokens") or rec.get("input_tokens") or 0)
                    c_hit = int(rec.get("cacheHitTokens") or rec.get("cache_hit_tokens") or 0)
                    out_t = int(rec.get("outputTokens") or rec.get("output_tokens") or 0)
                    tot_t = int(rec.get("totalTokens") or (in_miss + c_hit + out_t))
                    today_tokens += tot_t
                    cache_hit_tokens += c_hit
                    input_total_tokens += in_miss + c_hit
                    if rec.get("cost") is not None:
                        today_cost_cny += float(rec["cost"])
                break
        except Exception:
            continue

    day_quota_file = dsh_home / "storages" / "deepseek-quota-day.json"
    if today_cost_cny == 0.0 and day_quota_file.is_file():
        try:
            dq = json.loads(day_quota_file.read_text(encoding="utf-8"))
            if isinstance(dq, dict) and dq.get("date") == dt.datetime.now().strftime("%Y-%m-%d"):
                today_cost_cny = float(dq.get("cost") or dq.get("spent") or 0.0)
                today_calls = max(today_calls, int(dq.get("calls") or 0))
        except Exception:
            pass

    windows: list[dict[str, Any]] = []
    quota_limits_file = dsh_home / "quota-limits.json"
    if quota_limits_file.is_file():
        try:
            ql = json.loads(quota_limits_file.read_text(encoding="utf-8"))
            if isinstance(ql, dict) and ql.get("usedPercent") is not None:
                windows.append(
                    {
                        "used_pct": clamp_pct(float(ql["usedPercent"])),
                        "window_seconds": None,
                        "default_zh": "DSH限额",
                        "default_en": "DSH Cap",
                        "reset_ts": parse_timestamp(ql.get("resetAt")),
                    }
                )
        except Exception:
            pass

    installed = bool(cli_bin or dsh_home.is_dir() or today_calls > 0)
    hit_pct = (cache_hit_tokens / input_total_tokens * 100.0) if input_total_tokens > 0 else 0.0
    return {
        "provider": "dsh",
        "installed": installed,
        "cliVersion": cli_ver,
        "webRunning": False,
        "profiles": profiles,
        "windows": windows,
        "todayCalls": today_calls,
        "todayTokens": today_tokens,
        "cacheHitPct": hit_pct,
        "todayCostCny": today_cost_cny,
        "source": "CLI" if cli_bin else ("dsh-usage" if today_calls > 0 else ""),
    }
