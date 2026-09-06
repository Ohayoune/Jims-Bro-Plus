#!/usr/bin/env python3
"""
Reference implementation of the Jimm's Bro+ import pipeline (docs/SPEC.md §6.1–6.3, docs/PLAN_FORMAT.md).
Purpose: (1) prove examples/manifest.json is consistent with the rules, (2) give the Swift port an oracle.
Run:  python3 tools/reference_import.py            -> checks every fixture against the manifest
      python3 tools/reference_import.py FILE       -> prints the normalized plan + issues for one file
No third-party dependencies.
"""
import json, re, sys, os, datetime

MARKER = "JIMMSBRO-PLAN-PROMPT-V1"
MAX_BYTES = 1_048_576
LIMITS = dict(days=31, exercises=50, sets=50, reps=1000, weight=10000, rest=3600, duration=86400, name=100, notes=500)
WEEKDAYS = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
DEFAULT_SETTINGS = dict(units="kg", defaultRestSeconds=90)


class Issue(dict):
    def __init__(self, severity, code, path, message):
        super().__init__(severity=severity, code=code, path=path, message=message)


def err(code, path, msg): return Issue("error", code, path, msg)
def warn(code, path, msg): return Issue("warning", code, path, msg)


# ---------------------------------------------------------------- 1. Extract
def _scan_json_value(t, start):
    """Return index just past the JSON value starting at t[start] ('{' or '['), string-aware. None if unbalanced."""
    depth, i, in_str, esc = 0, start, False, False
    while i < len(t):
        c = t[i]
        if in_str:
            if esc: esc = False
            elif c == "\\": esc = True
            elif c == '"': in_str = False
        else:
            if c == '"': in_str = True
            elif c in "{[": depth += 1
            elif c in "}]":
                depth -= 1
                if depth == 0: return i + 1
        i += 1
    return None


def extract(text):
    issues = []
    if len(text.encode("utf-8")) > MAX_BYTES:
        return None, [err("E_TOO_LARGE", "", "The pasted text is over 1 MB. Paste one plan at a time.")]
    t = re.sub("[﻿​‌‍]", "", text)
    if not t.strip():
        return None, [err("E_EMPTY", "", "Nothing to import. Paste the JSON the chatbot produced.")]
    fences = [m.group(1) for m in re.finditer(r"```[A-Za-z0-9_-]*[ \t]*\r?\n?(.*?)```", t, re.S)]
    fences = [f.strip() for f in fences if f.strip()]
    if MARKER in t and not fences:
        return None, [err("E_PROMPT_PASTED", "", "That's the prompt. Paste the chatbot's JSON reply instead.")]
    if fences:
        if len(fences) > 1:
            return None, [err("E_MULTIPLE_OBJECTS", "", "Found more than one code block. Paste just one plan.")]
        outside = re.sub(r"```[A-Za-z0-9_-]*[ \t]*\r?\n?.*?```", "", t, flags=re.S)
        if outside.strip():
            issues.append(warn("W_SURROUNDING_TEXT", "", "Text around the code block was ignored."))
        return fences[0], issues
    starts = [i for i in (t.find("{"), t.find("[")) if i >= 0]
    if not starts:
        return None, [err("E_NOT_JSON", "", "No JSON found in the pasted text.")]
    s = min(starts)
    e = _scan_json_value(t, s)
    if e is None:
        return t[s:], issues  # unbalanced: let the decoder produce the error message
    rest = t[e:].strip()
    if rest[:1] in ("{", "["):
        return None, [err("E_MULTIPLE_OBJECTS", "", "Found more than one JSON object. Paste just one plan.")]
    if t[:s].strip() or rest:
        issues.append(warn("W_SURROUNDING_TEXT", "", "Text around the JSON was ignored."))
    return t[s:e], issues


# ---------------------------------------------------------------- 2. Decode
def _strict_loads(s):
    def bad_const(c): raise ValueError(f"Invalid literal {c}")
    return json.loads(s, parse_constant=bad_const)


def decode(body):
    try:
        return _strict_loads(body), []
    except ValueError as first:
        if re.search("[“”„]", body):
            try:
                obj = _strict_loads(re.sub("[“”„]", '"', body))
                return obj, [warn("W_CURLY_QUOTES_FIXED", "", "Curly quotes were replaced with straight quotes.")]
            except ValueError:
                pass
        return None, [err("E_NOT_JSON", "", f"This isn't valid JSON: {first}. Ask the chatbot for strict JSON, or use Copy fix-it prompt.")]


# ---------------------------------------------------------------- 3+4. Normalize + validate
def _is_int_like(v):
    if isinstance(v, bool): return False
    if isinstance(v, int): return True
    if isinstance(v, float): return v.is_integer()
    if isinstance(v, str): return re.fullmatch(r"\s*\d+\s*", v) is not None
    return False


def _as_int(v): return int(float(v)) if not isinstance(v, str) else int(v.strip())


def _parse_int_field(v, path, code, lo, hi, issues, what):
    if v is None: return None
    if not _is_int_like(v):
        issues.append(err(code, path, f"{what} must be a whole number, got {json.dumps(v)}.")); return None
    n = _as_int(v)
    if n < lo or n > hi:
        issues.append(err(code, path, f"{what} must be between {lo} and {hi}, got {n}.")); return None
    return n


REP_WORDS = {"amrap", "max", "failure", "to failure", "as many as possible"}


def parse_reps(v, path, issues):
    """Returns ('fixed', n) | ('range', lo, hi) | ('amrap', min_or_None) or None (error appended)."""
    bad = lambda: issues.append(err("E_REPS_INVALID", path, f'{json.dumps(v, ensure_ascii=False)} is not a valid reps value. Use a whole number, a range like "8-12", "AMRAP", or "10+".'))
    if isinstance(v, bool) or v is None or isinstance(v, (dict, list)): bad(); return None
    if isinstance(v, (int, float)):
        if isinstance(v, float) and not v.is_integer(): bad(); return None
        n = int(v)
        if 1 <= n <= LIMITS["reps"]: return ("fixed", n)
        bad(); return None
    s = str(v).strip().lower()
    s = re.sub(r"\s*reps?$", "", s)
    if s in REP_WORDS: return ("amrap", None)
    m = re.fullmatch(r"(\d+)\s*\+", s)
    if m:
        n = int(m.group(1))
        if 1 <= n <= LIMITS["reps"]: return ("amrap", n)
        bad(); return None
    m = re.fullmatch(r"(\d+)\s*(?:-|–|—|/|to)\s*(\d+)", s)
    if m:
        a, b = int(m.group(1)), int(m.group(2))
        if not (1 <= a <= LIMITS["reps"] and 1 <= b <= LIMITS["reps"]): bad(); return None
        if a == b: return ("fixed", a)
        if a > b:
            issues.append(warn("W_RANGE_SWAPPED", path, f'"{v}" was read as {b}-{a}.'))
            a, b = b, a
        return ("range", a, b)
    if re.fullmatch(r"\d+", s):
        n = int(s)
        if 1 <= n <= LIMITS["reps"]: return ("fixed", n)
    bad(); return None


def parse_duration(v, path, issues):
    """PLAN_FORMAT §3.12. Returns ("duration", n) | ("open", min_or_None) | None."""
    bad = lambda: issues.append(err("E_DURATION_INVALID", path, f'{json.dumps(v, ensure_ascii=False)} is not a valid duration. Use whole seconds (1-86400), "max", or "30+".'))
    if isinstance(v, str) and not re.fullmatch(r"\s*\d+\s*", v):
        s = v.strip().lower()
        if s in OPEN_WORDS: return ("open", None)
        m = re.fullmatch(r"(\d+)\s*\+", s)
        if m and 1 <= int(m.group(1)) <= LIMITS["duration"]: return ("open", int(m.group(1)))
        bad(); return None
    tmp = []
    n = _parse_int_field(v, path, "E_DURATION_INVALID", 1, LIMITS["duration"], tmp, "durationSeconds")
    issues.extend(tmp)
    return ("duration", n) if n is not None else None


def parse_warning(v, path, issues):
    """PLAN_FORMAT §3.12. Returns "off" | "pct" | ("sec", n) | None (error appended). v is not None."""
    if isinstance(v, bool): return "pct" if v else "off"
    if not isinstance(v, str) and _is_int_like(v) and 1 <= _as_int(v) <= 86399: return ("sec", _as_int(v))
    issues.append(err("E_WARNING_BEEP_INVALID", path, f"warningBeep must be true, false, or a whole number of seconds before the end, got {json.dumps(v)}."))
    return None


def resolve_warning(spec, work, path, issues):
    """spec: None (absent) | "off" | "pct" | ("sec", n). Returns seconds or None."""
    if work is None: return None
    if work[0] != "duration":
        if spec is not None: issues.append(warn("W_WARNING_BEEP_IGNORED", path, "warningBeep only applies to sets with a fixed durationSeconds."))
        return None
    d = work[1]
    if spec is None or spec == "pct":
        return None if d < 10 else max(1, int(d / 10 + 0.5))
    if spec == "off": return None
    n = spec[1]
    if n >= d:
        issues.append(warn("W_WARNING_BEEP_IGNORED", path, f"warningBeep {n} is not before the end of a {d} s set.")); return None
    return n


BW_FLAG_WORDS = {"bw", "bodyweight", "body weight"}
BW_WORDS = {"bw", "bodyweight", "body weight", "none", ""}


def parse_weight(v, path, units, issues):
    """Returns (present: bool, value or None)."""
    bad = lambda: issues.append(err("E_WEIGHT_INVALID", path, f"{json.dumps(v, ensure_ascii=False)} is not a valid weight. Use a number in {units}, or leave it out for bodyweight."))
    if v is None: return (False, None)
    if isinstance(v, bool) or isinstance(v, (dict, list)): bad(); return (True, None)
    if isinstance(v, str):
        s = v.strip().lower()
        if s in BW_FLAG_WORDS: return (False, "bw")
        if s in BW_WORDS: return (False, None)
        m = re.fullmatch(r"\+?\s*(\d+(?:[.,]\d+)?)\s*([a-z]*)\.?", s)
        if not m: bad(); return (True, None)
        num = float(m.group(1).replace(",", "."))
        unit = m.group(2)
        unit_norm = {"kg": "kg", "kgs": "kg", "kilograms": "kg", "kilogram": "kg", "lb": "lb", "lbs": "lb", "pounds": "lb", "pound": "lb"}.get(unit)
        if unit and unit_norm is None: bad(); return (True, None)
        if unit_norm and unit_norm != units:
            issues.append(warn("W_WEIGHT_UNIT_IGNORED", path, f'The unit in "{v}" was ignored; this plan uses {units}.'))
    else:
        num = float(v)
    if num < 0 or num > LIMITS["weight"]: bad(); return (True, None)
    rounded = round(num + 1e-9, 1)
    if abs(rounded - num) > 1e-9:
        issues.append(warn("W_WEIGHT_ROUNDED", path, f"{num} was rounded to {rounded}."))
    return (True, rounded)


def _clip_name(v, path, default, issues, default_code=True):
    if v is None or not isinstance(v, str) or not v.strip():
        if default_code: issues.append(warn("W_DEFAULT_NAME", path, f'No name given; using "{default}".'))
        return default
    s = v.strip()
    if len(s) > LIMITS["name"]:
        issues.append(warn("W_NAME_TRUNCATED", path, "Name was cut to 100 characters."))
        s = s[:LIMITS["name"]]
    return s


def normalize_name(s): return re.sub(r"\s+", " ", s.strip()).lower()


KNOWN_PLAN = {"schemaVersion", "name", "units", "defaultRestSeconds", "schedule", "cycle", "days"}
KNOWN_DAY = {"name", "weekday", "defaultRestSeconds", "exercises"}
KNOWN_EX = {"name", "group", "notes", "sets", "reps", "repRange", "durationSeconds", "warningBeep", "bodyweight", "weight", "restSeconds", "drops"}
KNOWN_SET = {"reps", "durationSeconds", "warningBeep", "weight", "restSeconds", "drops"}
OPEN_WORDS = {"max", "open", "amsap", "as long as possible", "to failure"}
KNOWN_DROP = {"reps", "weight"}


def parse_drops(v, path, units, issues):
    """PLAN_FORMAT §3.11. Returns list of {"work","weight"} or None (error appended)."""
    if not isinstance(v, list) or not v or len(v) > 5 or not all(isinstance(d, dict) for d in v):
        issues.append(err("E_DROPS_INVALID", path, "drops must be a list of 1 to 5 objects like { \"weight\": 20 }.")); return None
    out = []
    for j, d in enumerate(v):
        dp = f"{path}[{j}]"
        _unknown(d, KNOWN_DROP, dp, issues)
        work = ("reps", ("amrap", None))
        if d.get("reps") is not None:
            pr = parse_reps(d["reps"], f"{dp}.reps", issues)
            work = ("reps", pr) if pr else None
        w = None
        if d.get("weight") is not None:
            _, w = parse_weight(d["weight"], f"{dp}.weight", units, issues)
            if w == "bw": w = None
        out.append({"work": work, "weight": w})
    return out


def _unknown(obj, known, path, issues):
    for k in obj:
        if k not in known:
            issues.append(warn("W_UNKNOWN_FIELD", f"{path}.{k}" if path else k, f'Field "{k}" was ignored.'))


def _parse_units(v, path, settings, issues):
    if v is None: return settings["units"]
    m = {"kg": "kg", "kgs": "kg", "kilogram": "kg", "kilograms": "kg", "lb": "lb", "lbs": "lb", "pound": "lb", "pounds": "lb"}
    u = m.get(str(v).strip().lower()) if isinstance(v, str) else None
    if u is None: issues.append(err("E_UNITS_INVALID", path, f'units must be "kg" or "lb", got {json.dumps(v)}.'))
    return u or settings["units"]


def _parse_weekday(v, path, issues):
    if not isinstance(v, str): issues.append(err("E_WEEKDAY_INVALID", path, f"{json.dumps(v)} is not a weekday.")); return None
    s = v.strip().lower()
    for w in WEEKDAYS:
        if s == w or s == w[:3]: return w
    issues.append(err("E_WEEKDAY_INVALID", path, f'"{v}" is not a weekday. Use "monday" … "sunday".')); return None


def normalize(obj, settings=DEFAULT_SETTINGS, today=None):
    issues = []
    today = today or datetime.date.today().isoformat()
    # ---- shape
    wrapped = False
    if isinstance(obj, dict) and "days" in obj:
        raw = obj
    elif isinstance(obj, dict) and "exercises" in obj:
        raw = {"name": obj.get("name"), "days": [obj]}; wrapped = True
    elif isinstance(obj, list) and obj and all(isinstance(d, dict) and "exercises" in d for d in obj):
        raw = {"days": obj}; wrapped = True
    elif isinstance(obj, list) and obj and all(isinstance(d, dict) and "name" in d and "exercises" not in d for d in obj):
        raw = {"days": [{"exercises": obj}]}; wrapped = True
    else:
        kind = type(obj).__name__ if not isinstance(obj, dict) else "an object without days or exercises"
        return None, [err("E_NOT_A_PLAN", "", f"This JSON isn't a workout plan (found {kind}).")]
    if wrapped: issues.append(warn("W_WRAPPED_SINGLE_DAY", "", "Wrapped the pasted content into a plan."))
    _unknown(raw, KNOWN_PLAN, "", issues) if not wrapped else None
    if wrapped and isinstance(obj, dict): _unknown(obj, KNOWN_DAY | {"name"}, "days[0]", issues)

    # ---- plan fields
    sv = raw.get("schemaVersion")
    if sv is not None:
        if not _is_int_like(sv) or _as_int(sv) > 1:
            issues.append(err("E_SCHEMA_VERSION", "schemaVersion", f"This plan needs schemaVersion {sv}; the app supports 1. Update the app."))
    name = _clip_name(raw.get("name"), "name", f"Imported plan {today}", issues)
    units = _parse_units(raw.get("units"), "units", settings, issues)
    plan_rest = _parse_int_field(raw.get("defaultRestSeconds"), "defaultRestSeconds", "E_REST_INVALID", 0, LIMITS["rest"], issues, "defaultRestSeconds")
    days_raw = raw.get("days")
    if not isinstance(days_raw, list) or not days_raw:
        issues.append(err("E_NO_DAYS", "days", "The plan has no days. Add at least one day with exercises."))
        return None, issues
    if len(days_raw) > LIMITS["days"]:
        issues.append(err("E_LIMIT_EXCEEDED", "days", f"Too many days ({len(days_raw)}); the limit is {LIMITS['days']}."))
        return None, issues

    days = []
    for di, d in enumerate(days_raw):
        dp = f"days[{di}]"
        if not isinstance(d, dict):
            issues.append(err("E_NO_EXERCISES", f"{dp}.exercises", "Each day must be an object with exercises.")); continue
        _unknown(d, KNOWN_DAY, dp, issues)
        dname = _clip_name(d.get("name"), f"{dp}.name", (name if (wrapped and isinstance(obj, dict)) else f"Day {di + 1}"), issues, default_code=not (wrapped and isinstance(obj, dict) and d.get("name")))
        weekday_raw = d.get("weekday")
        day_rest = _parse_int_field(d.get("defaultRestSeconds"), f"{dp}.defaultRestSeconds", "E_REST_INVALID", 0, LIMITS["rest"], issues, "defaultRestSeconds")
        exs_raw = d.get("exercises")
        if not isinstance(exs_raw, list) or not exs_raw:
            issues.append(err("E_NO_EXERCISES", f"{dp}.exercises", f'Day "{dname}" has no exercises.'))
            days.append({"name": dname, "weekday_raw": weekday_raw, "exercises": []}); continue
        if len(exs_raw) > LIMITS["exercises"]:
            issues.append(err("E_LIMIT_EXCEEDED", f"{dp}.exercises", f"Too many exercises ({len(exs_raw)}); the limit is {LIMITS['exercises']}."))
            days.append({"name": dname, "weekday_raw": weekday_raw, "exercises": []}); continue
        exercises = []
        for ei, e in enumerate(exs_raw):
            ep = f"{dp}.exercises[{ei}]"
            if not isinstance(e, dict):
                issues.append(err("E_MISSING_NAME", f"{ep}.name", "Each exercise must be an object with a name.")); continue
            _unknown(e, KNOWN_EX, ep, issues)
            ename = e.get("name")
            if not isinstance(ename, str) or not ename.strip():
                issues.append(err("E_MISSING_NAME", f"{ep}.name", "Every exercise needs a name."))
                ename = "?"
            else:
                ename = _clip_name(ename, f"{ep}.name", "?", issues)
            group = e.get("group")
            group = str(group).strip().upper() if group is not None and str(group).strip() else None
            notes = e.get("notes")
            if notes is not None and isinstance(notes, str) and len(notes) > LIMITS["notes"]:
                issues.append(warn("W_NOTES_TRUNCATED", f"{ep}.notes", "Notes were cut to 500 characters.")); notes = notes[:LIMITS["notes"]]
            if notes is not None and not isinstance(notes, str): notes = str(notes)
            ex_rest = _parse_int_field(e.get("restSeconds"), f"{ep}.restSeconds", "E_REST_INVALID", 0, LIMITS["rest"], issues, "restSeconds")
            # exercise-level defaults
            ex_reps = parse_reps(e["reps"], f"{ep}.reps", issues) if "reps" in e and e["reps"] is not None else None
            ex_dur = parse_duration(e["durationSeconds"], f"{ep}.durationSeconds", issues) if e.get("durationSeconds") is not None else None
            ex_w_present, ex_w = parse_weight(e.get("weight"), f"{ep}.weight", units, issues)
            bodyweight = False
            if ex_w == "bw": bodyweight = True; ex_w = None
            if e.get("bodyweight") is not None:
                if isinstance(e["bodyweight"], bool): bodyweight = bodyweight or e["bodyweight"]
                else: issues.append(err("E_BODYWEIGHT_INVALID", f"{ep}.bodyweight", "bodyweight must be true or false."))
            ex_warn = parse_warning(e["warningBeep"], f"{ep}.warningBeep", issues) if e.get("warningBeep") is not None else None
            if bodyweight and ex_w is not None:
                issues.append(warn("W_BODYWEIGHT_WEIGHT_IGNORED", f"{ep}.weight", "Weight ignored on a bodyweight exercise.")); ex_w = None
            has_ex_reps = "reps" in e and e["reps"] is not None
            has_ex_dur = "durationSeconds" in e and e["durationSeconds"] is not None
            ex_drops = parse_drops(e["drops"], f"{ep}.drops", units, issues) if e.get("drops") is not None else None
            # repRange (PLAN_FORMAT §3.9)
            rep_range = None
            rr = e.get("repRange")
            if rr is not None:
                if has_ex_dur and not has_ex_reps:
                    issues.append(warn("W_REPRANGE_IGNORED", f"{ep}.repRange", "repRange is ignored on a timed exercise."))
                else:
                    tmp = []
                    parsed = parse_reps(rr, f"{ep}.repRange", tmp)
                    for t in tmp:
                        if t["code"] == "E_REPS_INVALID":
                            issues.append(err("E_REPRANGE_INVALID", f"{ep}.repRange", f'{json.dumps(rr, ensure_ascii=False)} is not a valid rep range. Use a range like "8-12".'))
                        else:
                            issues.append(t)
                    if parsed and parsed[0] == "fixed": rep_range = (parsed[1], parsed[1])
                    elif parsed and parsed[0] == "range": rep_range = (parsed[1], parsed[2])
                    elif parsed and parsed[0] == "amrap":
                        issues.append(err("E_REPRANGE_INVALID", f"{ep}.repRange", f'{json.dumps(rr, ensure_ascii=False)} is not a valid rep range. Use a range like "8-12".'))
                    if rep_range and ex_reps and ex_reps[0] == "fixed" and not (rep_range[0] <= ex_reps[1] <= rep_range[1]):
                        issues.append(warn("W_REPRANGE_OUTSIDE", f"{ep}.repRange", f"The reps target {ex_reps[1]} is outside repRange {rep_range[0]}-{rep_range[1]}."))
            elif ex_reps and ex_reps[0] == "range":
                rep_range = (ex_reps[1], ex_reps[2])
            sets_raw = e.get("sets", 1)
            set_specs = None
            if sets_raw is None: sets_raw = 1
            if isinstance(sets_raw, list):
                if not sets_raw:
                    issues.append(err("E_SETS_INVALID", f"{ep}.sets", "sets must be a number of sets or a non-empty list of sets."))
                elif len(sets_raw) > LIMITS["sets"]:
                    issues.append(err("E_LIMIT_EXCEEDED", f"{ep}.sets", f"Too many sets ({len(sets_raw)}); the limit is {LIMITS['sets']}."))
                else:
                    set_specs = []
                    for si, s in enumerate(sets_raw):
                        sp = f"{ep}.sets[{si}]"
                        if not isinstance(s, dict): s = {}
                        _unknown(s, KNOWN_SET, sp, issues)
                        has_reps = "reps" in s and s["reps"] is not None
                        has_dur = "durationSeconds" in s and s["durationSeconds"] is not None
                        if has_reps and has_dur:
                            issues.append(err("E_TARGET_CONFLICT", sp, "A set can't have both reps and durationSeconds.")); continue
                        if has_reps: work = ("reps", parse_reps(s["reps"], f"{sp}.reps", issues))
                        elif has_dur:
                            pd = parse_duration(s["durationSeconds"], f"{sp}.durationSeconds", issues)
                            if pd is None: continue
                            work = pd
                        elif has_ex_reps and has_ex_dur:
                            issues.append(err("E_TARGET_CONFLICT", ep, "An exercise can't have both reps and durationSeconds.")); continue
                        elif has_ex_reps: work = ("reps", ex_reps)
                        elif has_ex_dur:
                            if ex_dur is None: continue
                            work = ex_dur
                        else:
                            issues.append(err("E_TARGET_MISSING", sp, "Each set needs reps or durationSeconds.")); continue
                        if "weight" in s and s["weight"] is not None:
                            _, w = parse_weight(s["weight"], f"{sp}.weight", units, issues)
                            if w == "bw": w = None; bodyweight = True
                            elif w is not None and bodyweight:
                                issues.append(warn("W_BODYWEIGHT_WEIGHT_IGNORED", f"{sp}.weight", "Weight ignored on a bodyweight exercise.")); w = None
                        else:
                            w = ex_w
                        if s.get("warningBeep") is not None:
                            wspec = parse_warning(s["warningBeep"], f"{sp}.warningBeep", issues); wpath = f"{sp}.warningBeep"
                        else:
                            wspec = ex_warn; wpath = f"{ep}.warningBeep"
                        if wspec is None and s.get("warningBeep") is not None: beep = None
                        else: beep = resolve_warning(wspec, work, wpath, issues)
                        r = _parse_int_field(s.get("restSeconds"), f"{sp}.restSeconds", "E_REST_INVALID", 0, LIMITS["rest"], issues, "restSeconds")
                        drops = parse_drops(s["drops"], f"{sp}.drops", units, issues) if s.get("drops") is not None else ex_drops
                        if drops and work[0] != "reps":
                            issues.append(warn("W_DROPS_IGNORED", f"{sp}.drops", "Drops are ignored on a timed set.")); drops = None
                        set_specs.append({"work": work, "weight": w, "rest": r, "beep": beep, "drops": drops or []})
            elif _is_int_like(sets_raw) and 1 <= _as_int(sets_raw) <= LIMITS["sets"]:
                n = _as_int(sets_raw)
                if has_ex_reps and has_ex_dur:
                    issues.append(err("E_TARGET_CONFLICT", ep, "An exercise can't have both reps and durationSeconds."))
                elif not has_ex_reps and not has_ex_dur:
                    issues.append(err("E_TARGET_MISSING", ep, "Each exercise needs reps or durationSeconds."))
                else:
                    work = ("reps", ex_reps) if has_ex_reps else ex_dur
                    drops = ex_drops or []
                    beep = None
                    if work is not None:
                        if drops and work[0] != "reps":
                            issues.append(warn("W_DROPS_IGNORED", f"{ep}.drops", "Drops are ignored on a timed exercise.")); drops = []
                        beep = resolve_warning(ex_warn, work, f"{ep}.warningBeep", issues)
                        set_specs = [{"work": work, "weight": ex_w, "rest": None, "beep": beep, "drops": list(drops)} for _ in range(n)]
            elif _is_int_like(sets_raw) and _as_int(sets_raw) > LIMITS["sets"]:
                issues.append(err("E_LIMIT_EXCEEDED", f"{ep}.sets", f"Too many sets ({_as_int(sets_raw)}); the limit is {LIMITS['sets']}."))
                if has_ex_reps and has_ex_dur: issues.append(err("E_TARGET_CONFLICT", ep, "An exercise can't have both reps and durationSeconds."))
            else:
                issues.append(err("E_SETS_INVALID", f"{ep}.sets", f"sets must be a whole number from 1 to 50 or a list of sets, got {json.dumps(sets_raw)}."))
                if not has_ex_reps and not has_ex_dur: issues.append(err("E_TARGET_MISSING", ep, "Each exercise needs reps or durationSeconds."))
            exercises.append({"name": ename, "group": group, "notes": notes, "repRange": list(rep_range) if rep_range else None, "bodyweight": bodyweight, "rest": ex_rest, "set_specs": set_specs or []})
        days.append({"name": dname, "weekday_raw": weekday_raw, "rest": day_rest, "exercises": exercises})

    # ---- schedule + weekdays
    sched_raw = raw.get("schedule")
    sched = sched_raw.strip().lower() if isinstance(sched_raw, str) else None
    has_wd = [d["weekday_raw"] is not None for d in days]
    inferred = "weekday" if all(has_wd) else ("rotation" if not any(has_wd) else None)
    if sched in ("rotation", "weekday"):
        schedule = sched
    else:
        if sched_raw is not None:
            issues.append(warn("W_SCHEDULE_INFERRED", "schedule", f'schedule {json.dumps(sched_raw)} is not "rotation" or "weekday"; inferred from the days.'))
        if inferred is None:
            issues.append(err("E_SCHEDULE_MIXED", "schedule", 'Some days have a weekday and some don\'t. Give every day a weekday, or none, or set "schedule".'))
        schedule = inferred or "rotation"
    seen = {}
    for di, d in enumerate(days):
        dp = f"days[{di}].weekday"
        if schedule == "rotation":
            if d["weekday_raw"] is not None: issues.append(warn("W_WEEKDAY_IGNORED", dp, "weekday is ignored in a rotation plan."))
            d["weekday"] = None
        else:
            if d["weekday_raw"] is None:
                issues.append(err("E_WEEKDAY_MISSING", dp, f'Day "{d["name"]}" needs a weekday in a weekday plan.')); d["weekday"] = None; continue
            w = _parse_weekday(d["weekday_raw"], dp, issues)
            if w and w in seen: issues.append(err("E_WEEKDAY_DUPLICATE", dp, f'Two days are on {w}: "{seen[w]}" and "{d["name"]}".'))
            elif w: seen[w] = d["name"]
            d["weekday"] = w
        del d["weekday_raw"]

    # ---- duplicate day names
    counts = {}
    for di, d in enumerate(days):
        k = normalize_name(d["name"])
        counts[k] = counts.get(k, 0) + 1
        if counts[k] > 1:
            issues.append(warn("W_DAY_RENAMED", f"days[{di}].name", f'Renamed duplicate day to "{d["name"]} ({counts[k]})".'))
            d["name"] = f"{d['name']} ({counts[k]})"

    # ---- cycle (PLAN_FORMAT §3.10)
    cycle_raw = raw.get("cycle")
    if schedule == "weekday":
        if cycle_raw is not None: issues.append(warn("W_CYCLE_IGNORED", "cycle", "cycle is ignored in a weekday plan; it is derived from the weekdays."))
        by_wd = {d["weekday"]: d["name"] for d in days if d.get("weekday")}
        cycle = [by_wd.get(w, "rest") for w in WEEKDAYS]
    elif cycle_raw is None:
        cycle = [d["name"] for d in days]
    elif not isinstance(cycle_raw, list) or not cycle_raw or len(cycle_raw) > 31 or not all(isinstance(c, str) for c in cycle_raw):
        issues.append(err("E_CYCLE_INVALID", "cycle", 'cycle must be a list of 1 to 31 day names or "rest".')); cycle = [d["name"] for d in days]
    else:
        names = {normalize_name(d["name"]): d["name"] for d in days}
        cycle = []
        for ci, c in enumerate(cycle_raw):
            k = normalize_name(c)
            if k in ("rest", "off"): cycle.append("rest")
            elif k in names: cycle.append(names[k])
            else: issues.append(err("E_CYCLE_UNKNOWN_DAY", f"cycle[{ci}]", f'"{c}" is not one of this plan\'s days.'))
        missing = [d["name"] for d in days if d["name"] not in cycle]
        if missing and not any(i["code"] == "E_CYCLE_UNKNOWN_DAY" for i in issues):
            issues.append(warn("W_CYCLE_MISSING_DAY", "cycle", f"These days never appear in the cycle: {', '.join(missing)}."))

    # ---- groups
    for di, d in enumerate(days):
        exs = d["exercises"]
        runs = []  # (group, start, end)
        i = 0
        while i < len(exs):
            g = exs[i]["group"]; j = i
            while j + 1 < len(exs) and exs[j + 1]["group"] == g and g is not None: j += 1
            runs.append((g, i, j)); i = j + 1
        seen_g = {}
        for g, a, b in runs:
            if g is None: continue
            if g in seen_g:
                new = f"{g}{seen_g[g] + 1}"; seen_g[g] += 1
                issues.append(warn("W_GROUP_SPLIT", f"days[{di}].exercises[{a}].group", f'Group "{g}" appeared again after other exercises; treating it as a separate group "{new}".'))
                for k in range(a, b + 1): exs[k]["group"] = new
                g = new
            else:
                seen_g[g] = 1
            if a == b:
                issues.append(warn("W_GROUP_SINGLE", f"days[{di}].exercises[{a}].group", f'Group "{g}" has only one exercise; treating it as a normal exercise.'))
                exs[a]["group"] = None
            else:
                ns = {len(exs[k]["set_specs"]) for k in range(a, b + 1)}
                if len(ns) > 1:
                    issues.append(warn("W_GROUP_SET_MISMATCH", f"days[{di}].exercises[{a}].group", f'Exercises in group "{g}" have different set counts; shorter ones drop out of later rounds.'))

    # ---- rest resolution + final shape
    for d in days:
        for e in d["exercises"]:
            sets = []
            warned_drop_weights = False
            for s in e["set_specs"]:
                rest = next((r for r in (s["rest"], e["rest"], d.get("rest"), plan_rest, settings["defaultRestSeconds"]) if r is not None), 90)
                drops = s.get("drops", [])
                if e.get("bodyweight") and any(dr["weight"] is not None for dr in drops):
                    if not warned_drop_weights:
                        issues.append(warn("W_BODYWEIGHT_WEIGHT_IGNORED", "", f'Drop weights ignored on bodyweight exercise "{e["name"]}".'))
                        warned_drop_weights = True
                    drops = [{"work": dr["work"], "weight": None} for dr in drops]
                sets.append({"work": s["work"], "weight": s["weight"], "restSeconds": rest, "warningBeepSeconds": s.get("beep"), "drops": drops})
            e["sets"] = sets; e["explicitRest"] = e.pop("rest"); e.pop("set_specs")
        d.pop("rest", None)

    plan = {"name": name, "units": units, "schedule": schedule, "cycle": cycle, "days": days}
    if any(i["severity"] == "error" for i in issues): return None, issues
    return plan, issues


# ---------------------------------------------------------------- Steps + execution rest (SPEC §6.2, §6.3)
def flatten(day):
    exs = day["exercises"]; steps = []; i = 0; block = 0
    while i < len(exs):
        g = exs[i]["group"]; j = i
        if g is not None:
            while j + 1 < len(exs) and exs[j + 1]["group"] == g: j += 1
        members = list(range(i, j + 1))
        rounds = max(len(exs[m]["sets"]) for m in members)
        first = len(steps)
        for r in range(rounds):
            active = [m for m in members if r < len(exs[m]["sets"])]
            for k, m in enumerate(active):
                drops = exs[m]["sets"][r].get("drops", [])
                for dI in range(len(drops) + 1):
                    steps.append({"exerciseIndex": m, "setIndex": r, "dropIndex": dI, "blockIndex": block,
                                  "isLastInRound": k == len(active) - 1 and dI == len(drops), "isLastInBlock": False})
        if len(steps) > first: steps[-1]["isLastInBlock"] = True
        i = j + 1; block += 1
    return steps


def rest_after(day, steps, i, settings=DEFAULT_SETTINGS):
    """Rest started after logging step i, assuming all later steps are pending (SPEC §6.3)."""
    if i == len(steps) - 1: return 0
    st = steps[i]
    if st["isLastInBlock"] and steps[i + 1]["blockIndex"] != st["blockIndex"]: return "transition"
    if not st["isLastInRound"]: return 0
    ex = day["exercises"][st["exerciseIndex"]]
    if ex["group"] is None: return ex["sets"][st["setIndex"]]["restSeconds"]
    members = [e for e in day["exercises"] if e["group"] == ex["group"]]
    for m in members:
        if m["explicitRest"] is not None: return m["explicitRest"]
    return ex["sets"][st["setIndex"]]["restSeconds"]


# ---------------------------------------------------------------- Pipeline
def import_plan(text, settings=DEFAULT_SETTINGS, today=None):
    body, issues = extract(text)
    if body is None: return None, issues
    obj, dec = decode(body); issues += dec
    if dec and dec[-1]["severity"] == "error": return None, issues
    plan, norm = normalize(obj, settings, today); issues += norm
    return plan, issues


# ---------------------------------------------------------------- Manifest check
def _work_str(w):
    kind, v = w
    if kind == "duration": return f"duration:{v}"
    if kind == "open": return "open" if v is None else f"open:{v}"
    if v[0] == "fixed": return f"fixed:{v[1]}"
    if v[0] == "range": return f"range:{v[1]}-{v[2]}"
    return "amrap" if v[1] is None else f"amrap:{v[1]}"


def check_manifest(root):
    man = json.load(open(os.path.join(root, "examples", "manifest.json")))
    fails = 0
    for fx in man["fixtures"]:
        path = os.path.join(root, "examples", fx["file"])
        text = open(path, encoding="utf-8").read()
        plan, issues = import_plan(text, today="2026-09-04")
        errors = [(i["code"], i["path"]) for i in issues if i["severity"] == "error"]
        warnings = sorted(i["code"] for i in issues if i["severity"] == "warning")
        problems = []
        if fx["outcome"] == "valid":
            if plan is None or errors: problems.append(f"expected valid, got errors {errors}")
            if warnings != sorted(fx.get("warnings", [])): problems.append(f"warnings {warnings} != expected {sorted(fx.get('warnings', []))}")
            for key, exp in fx.get("checks", {}).items():
                got = None
                try:
                    if key == "planName": got = plan["name"]
                    elif key == "units": got = plan["units"]
                    elif key == "schedule": got = plan["schedule"]
                    elif key == "dayNames": got = [d["name"] for d in plan["days"]]
                    elif key == "weekdays": got = [d["weekday"] for d in plan["days"]]
                    elif key == "stepsPerDay": got = [len(flatten(d)) for d in plan["days"]]
                    elif key == "exerciseNames": got = {k: [e["name"] for e in plan["days"][int(k)]["exercises"]] for k in exp}
                    elif key == "groups": got = {k: [e["group"] for e in plan["days"][int(k)]["exercises"]] for k in exp}
                    elif key == "repRange": got = {k: plan["days"][int(k.split(".")[0])]["exercises"][int(k.split(".")[1])]["repRange"] for k in exp}
                    elif key == "notes": got = {k: plan["days"][int(k.split(".")[0])]["exercises"][int(k.split(".")[1])]["notes"] for k in exp}
                    elif key == "restPerSet": got = {k: [s["restSeconds"] for s in plan["days"][int(k.split(".")[0])]["exercises"][int(k.split(".")[1])]["sets"]] for k in exp}
                    elif key == "weightPerSet": got = {k: [s["weight"] for s in plan["days"][int(k.split(".")[0])]["exercises"][int(k.split(".")[1])]["sets"]] for k in exp}
                    elif key == "workPerSet": got = {k: [_work_str(s["work"]) for s in plan["days"][int(k.split(".")[0])]["exercises"][int(k.split(".")[1])]["sets"]] for k in exp}
                    elif key == "stepOrder": got = {k: [f'{s["exerciseIndex"]}.{s["setIndex"]}' + (f'.{s["dropIndex"]}' if s["dropIndex"] else "") for s in flatten(plan["days"][int(k)])] for k in exp}
                    elif key == "cycle": got = plan["cycle"]
                    elif key == "bodyweight": got = {k: plan["days"][int(k.split(".")[0])]["exercises"][int(k.split(".")[1])]["bodyweight"] for k in exp}
                    elif key == "warningPerSet": got = {k: [s["warningBeepSeconds"] for s in plan["days"][int(k.split(".")[0])]["exercises"][int(k.split(".")[1])]["sets"]] for k in exp}
                    elif key == "dropsPerSet": got = {k: [len(s["drops"]) for s in plan["days"][int(k.split(".")[0])]["exercises"][int(k.split(".")[1])]["sets"]] for k in exp}
                    elif key == "dropTargets":
                        got = {}
                        for k in exp:
                            d, e, si = (int(x) for x in k.split("."))
                            got[k] = [[_work_str(dr["work"]), dr["weight"]] for dr in plan["days"][d]["exercises"][e]["sets"][si]["drops"]]
                    elif key == "restAfterStep":
                        got = {}
                        for k in exp:
                            di, si = k.split(":"); d = plan["days"][int(di)]
                            got[k] = rest_after(d, flatten(d), int(si))
                    else: problems.append(f"unknown check {key}"); continue
                except Exception as ex:  # noqa
                    problems.append(f"check {key} crashed: {ex!r}"); continue
                if got != exp: problems.append(f"check {key}: got {got!r}, expected {exp!r}")
        else:
            if plan is not None: problems.append("expected invalid, but import succeeded")
            exp_errors = [(e["code"], e.get("path")) for e in fx["errors"]]
            got_set = set(errors)
            for code, p in exp_errors:
                if p is None:
                    if not any(c == code for c, _ in errors): problems.append(f"missing error {code}")
                elif (code, p) not in got_set: problems.append(f"missing error {code} at {p}; got {errors}")
            if fx.get("exact", True) and len(errors) != len(exp_errors): problems.append(f"error count {len(errors)} != {len(exp_errors)}: {errors}")
            if "warnings" in fx and warnings != sorted(fx["warnings"]): problems.append(f"warnings {warnings} != {sorted(fx['warnings'])}")
        if problems:
            fails += 1; print(f"FAIL {fx['file']}"); [print("   ", p) for p in problems]
    print(f"{len(man['fixtures']) - fails}/{len(man['fixtures'])} fixtures match the manifest")
    return fails == 0


if __name__ == "__main__":
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if len(sys.argv) > 1:
        plan, issues = import_plan(open(sys.argv[1], encoding="utf-8").read())
        print(json.dumps({"plan": plan, "issues": issues}, indent=2, ensure_ascii=False, default=str))
    else:
        sys.exit(0 if check_manifest(root) else 1)
