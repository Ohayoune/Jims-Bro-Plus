#!/usr/bin/env python3
"""Regenerates examples/valid, examples/invalid, and examples/manifest.json from scratch.
Run from anywhere:  python3 tools/generate_fixtures.py
Then verify:        python3 tools/reference_import.py
"""
import json, os, re
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
os.makedirs("examples/valid", exist_ok=True); os.makedirs("examples/invalid", exist_ok=True)
root = ROOT
V = os.path.join(root, "examples/valid"); I = os.path.join(root, "examples/invalid")

def wj(d, name, obj): open(os.path.join(d, name), "w").write(json.dumps(obj, indent=2, ensure_ascii=False) + "\n")
def wt(d, name, text): open(os.path.join(d, name), "w").write(text)

push = {"name": "Push", "defaultRestSeconds": 120, "exercises": [
    {"name": "Barbell Bench Press", "sets": 4, "reps": "6-8", "weight": 80, "restSeconds": 150, "notes": "Pause on chest"},
    {"name": "Incline Dumbbell Press", "sets": [{"reps": 12, "weight": 24}, {"reps": 10, "weight": 26}, {"reps": 8, "weight": 28}], "repRange": "8-12", "restSeconds": 90},
    {"name": "Lateral Raise", "group": "A", "sets": 3, "reps": 15, "repRange": "12-15", "weight": 10, "restSeconds": 60},
    {"name": "Tricep Pushdown", "group": "A", "sets": 3, "reps": 12, "repRange": "10-12", "weight": 25, "restSeconds": 60, "drops": [{"weight": 20}, {"weight": 15}]},
    {"name": "Plank", "sets": 3, "durationSeconds": 45, "warningBeep": True, "bodyweight": True, "restSeconds": 45}]}
pull = {"name": "Pull", "exercises": [
    {"name": "Deadlift", "sets": 3, "reps": 5, "weight": 120, "restSeconds": 180},
    {"name": "Pull-Up", "sets": 4, "reps": "AMRAP", "restSeconds": 120},
    {"name": "Barbell Row", "sets": 3, "reps": "8-10", "weight": 70, "restSeconds": 90},
    {"name": "Face Pull", "group": "B", "sets": 3, "reps": 15, "weight": 15},
    {"name": "Dumbbell Curl", "group": "B", "sets": 3, "reps": 12, "weight": 12, "restSeconds": 60}]}
legs = {"name": "Legs", "exercises": [
    {"name": "Barbell Back Squat", "sets": 4, "reps": "5", "repRange": "4-6", "weight": 100, "restSeconds": 180},
    {"name": "Romanian Deadlift", "sets": 3, "reps": "8-10", "weight": 80, "restSeconds": 120},
    {"name": "Leg Press", "sets": 3, "reps": "10-12", "weight": 160, "restSeconds": 90},
    {"name": "Walking Lunge", "sets": 2, "reps": 20, "weight": 16, "restSeconds": 60, "notes": "10 each side"},
    {"name": "Standing Calf Raise", "sets": 4, "reps": "12-15", "weight": 60, "restSeconds": 45}]}

# ---------- valid ----------
wj(V, "weekly-rotation.json", {"schemaVersion": 1, "name": "Push Pull Legs", "units": "kg", "defaultRestSeconds": 90, "schedule": "rotation", "cycle": ["Push", "Pull", "Legs", "Push", "Pull", "Legs", "rest"], "days": [push, pull, legs]})
wj(V, "weekly-weekday.json", {"schemaVersion": 1, "name": "Mon Wed Fri Full Body", "units": "kg", "schedule": "weekday", "days": [
    {"name": "Full Body A", "weekday": "monday", "exercises": [{"name": "Barbell Back Squat", "sets": 3, "reps": 5, "weight": 100, "restSeconds": 180}, {"name": "Barbell Bench Press", "sets": 3, "reps": 5, "weight": 80, "restSeconds": 150}, {"name": "Barbell Row", "sets": 3, "reps": 5, "weight": 70, "restSeconds": 120}]},
    {"name": "Full Body B", "weekday": "Wed", "exercises": [{"name": "Deadlift", "sets": 1, "reps": 5, "weight": 140, "restSeconds": 180}, {"name": "Overhead Press", "sets": 3, "reps": 5, "weight": 50, "restSeconds": 150}, {"name": "Pull-Up", "sets": 3, "reps": "AMRAP", "restSeconds": 120}]},
    {"name": "Full Body C", "weekday": "FRIDAY", "exercises": [{"name": "Barbell Back Squat", "sets": 3, "reps": 5, "weight": 102.5, "restSeconds": 180}, {"name": "Barbell Bench Press", "sets": 3, "reps": 5, "weight": 82.5, "restSeconds": 150}, {"name": "Barbell Row", "sets": 3, "reps": 5, "weight": 72.5, "restSeconds": 120}]}]})
wj(V, "no-schedule-weekdays.json", {"name": "Inferred weekday", "days": [
    {"name": "Upper", "weekday": "tuesday", "exercises": [{"name": "Barbell Bench Press", "sets": 3, "reps": 8, "weight": 70}]},
    {"name": "Lower", "weekday": "thursday", "exercises": [{"name": "Barbell Back Squat", "sets": 3, "reps": 8, "weight": 90}]}]})
wj(V, "single-day.json", {"schemaVersion": 1, "name": "Quick Upper", "units": "kg", "days": [{"name": "Quick Upper", "exercises": [
    {"name": "Push-Up", "sets": 3, "reps": "15+", "restSeconds": 60},
    {"name": "Dumbbell Row", "sets": 3, "reps": 12, "weight": 20, "restSeconds": 60}]}]})
wj(V, "single-day-bare.json", {"name": "Hotel Workout", "exercises": [
    {"name": "Push-Up", "sets": 4, "reps": 20, "restSeconds": 45},
    {"name": "Bodyweight Squat", "sets": 4, "reps": 25, "restSeconds": 45},
    {"name": "Plank", "sets": 2, "durationSeconds": 60, "restSeconds": 60}]})
wj(V, "array-of-days.json", [
    {"name": "Day 1", "exercises": [{"name": "Barbell Bench Press", "sets": 3, "reps": 8, "weight": 60}]},
    {"name": "Day 2", "exercises": [{"name": "Barbell Back Squat", "sets": 3, "reps": 8, "weight": 80}]}])
wj(V, "array-of-exercises.json", [
    {"name": "Kettlebell Swing", "sets": 5, "reps": 20, "weight": 24, "restSeconds": 60},
    {"name": "Goblet Squat", "sets": 3, "reps": 12, "weight": 24, "restSeconds": 60}])
wj(V, "minimal.json", {"days": [{"exercises": [{"name": "Burpee", "reps": 10}]}]})
wj(V, "explicit-sets-pyramid.json", {"name": "Pyramid", "units": "kg", "days": [{"name": "Chest", "exercises": [
    {"name": "Barbell Bench Press", "restSeconds": 120, "sets": [{"reps": 12, "weight": 50}, {"reps": 10, "weight": 60}, {"reps": 8, "weight": 70}, {"reps": 6, "weight": 80}, {"reps": "AMRAP", "weight": 60, "restSeconds": 180}]},
    {"name": "Cable Fly", "weight": 15, "reps": 15, "sets": [{}, {}, {"reps": "12-15"}]}]}]})
wj(V, "superset-circuit.json", {"name": "Circuit Day", "units": "kg", "defaultRestSeconds": 60, "days": [{"name": "Circuit", "exercises": [
    {"name": "Goblet Squat", "group": "a", "sets": 3, "reps": 12, "weight": 20},
    {"name": "Push-Up", "group": "A", "sets": 3, "reps": 15},
    {"name": "Kettlebell Swing", "group": "A", "sets": 2, "reps": 20, "weight": 24, "restSeconds": 90},
    {"name": "Dead Hang", "sets": 2, "durationSeconds": 30, "restSeconds": 45}]}]})
wj(V, "timed-sets.json", {"name": "Core and Cardio", "days": [{"name": "Core", "exercises": [
    {"name": "Plank", "sets": 3, "durationSeconds": 45, "restSeconds": 30},
    {"name": "Side Plank", "sets": 2, "durationSeconds": 30, "restSeconds": 30, "notes": "each side"},
    {"name": "Stationary Bike", "sets": 1, "durationSeconds": 600, "restSeconds": 0},
    {"name": "Farmer Carry", "sets": 3, "durationSeconds": 40, "weight": 32, "restSeconds": 60},
    {"name": "Dead Hang", "sets": 2, "durationSeconds": "max", "bodyweight": True, "restSeconds": 60},
    {"name": "Max Plank", "sets": 1, "durationSeconds": "30+", "restSeconds": 0},
    {"name": "Wall Sit", "durationSeconds": 60, "warningBeep": 15, "sets": [{}, {"durationSeconds": "AMSAP", "warningBeep": 5}]},
    {"name": "Hollow Hold", "sets": 2, "durationSeconds": 20, "warningBeep": False},
    {"name": "Short Hold", "sets": 1, "durationSeconds": 8},
    {"name": "Late Warning", "sets": 1, "durationSeconds": 30, "warningBeep": 45},
    {"name": "Rounding", "sets": 1, "durationSeconds": 25}]}]})
wj(V, "bodyweight.json", {"name": "Calisthenics", "days": [{"name": "A", "exercises": [
    {"name": "Push-Up", "sets": 3, "reps": "15+", "bodyweight": True, "restSeconds": 60},
    {"name": "Pull-Up", "sets": 3, "reps": "AMRAP", "weight": "bodyweight", "restSeconds": 90},
    {"name": "Dip", "sets": 3, "reps": 10, "weight": 10, "restSeconds": 90},
    {"name": "Pistol Squat", "sets": 2, "reps": 6, "bodyweight": True, "weight": 5, "restSeconds": 60},
    {"name": "Bodyweight Row", "sets": 2, "reps": 12, "bodyweight": False, "warningBeep": True, "restSeconds": 60},
    {"name": "Nordic Curl", "sets": 2, "reps": 5, "bodyweight": True, "drops": [{"weight": 5}]}]}]})
# v1.5 (D51): the effort target — inReserve at exercise and set level, its alias, on a hold.
wj(V, "in-reserve.json", {"name": "Effort", "days": [{"name": "A", "exercises": [
    {"name": "Barbell Bench Press", "reps": "6-8", "weight": 80, "restSeconds": 150, "inReserve": 2, "sets": [{}, {}, {"inReserve": 1}]},
    {"name": "Barbell Row", "sets": 2, "reps": "8-10", "weight": 70, "restSeconds": 90, "rir": 3},
    {"name": "Plank", "sets": 2, "durationSeconds": 45, "bodyweight": True, "restSeconds": 45, "inReserve": 5},
    {"name": "Dumbbell Curl", "sets": 1, "reps": 12, "weight": 12, "restSeconds": 60}]}]})
wj(V, "in-reserve-alias.json", {"name": "Effort alias", "days": [{"name": "A", "exercises": [
    {"name": "Lat Pulldown", "reps": "10-12", "weight": 50, "restSeconds": 90, "sets": [{"rir": "2"}, {"inReserve": 0}]}]}]})
wj(V, "rest-precedence.json", {"name": "Rest chain", "defaultRestSeconds": 100, "days": [
    {"name": "Day A", "defaultRestSeconds": 80, "exercises": [
        {"name": "Ex 1", "sets": 2, "reps": 10},
        {"name": "Ex 2", "sets": 2, "reps": 10, "restSeconds": 70},
        {"name": "Ex 3", "reps": 10, "restSeconds": 70, "sets": [{}, {"restSeconds": 60}]},
        {"name": "Ex 4", "sets": 1, "reps": 10, "restSeconds": 0}]},
    {"name": "Day B", "exercises": [{"name": "Ex 5", "sets": 1, "reps": 10}]}]})
wj(V, "lenient-values.json", {"schemaVersion": "1", "name": "Lenient", "units": "KGS", "days": [{"name": "Mixed", "exercises": [
    {"name": "  Barbell Bench Press ", "sets": "4", "reps": "8 to 12", "weight": "60kg", "restSeconds": "90"},
    {"name": "Incline Press", "sets": 3.0, "reps": "12-8", "weight": "22,5"},
    {"name": "Pull-Up", "sets": 3, "reps": "to failure", "weight": "bodyweight"},
    {"name": "Dip", "sets": 3, "reps": "10 +", "weight": "+10kg"},
    {"name": "Curl", "sets": 2, "reps": "12 reps", "weight": "135 lbs"},
    {"name": "Hammer Curl", "sets": 2, "reps": 10.0, "weight": 12.55}]}]})
wj(V, "unknown-fields.json", {"name": "Extras", "author": "coach", "days": [{"name": "A", "exercises": [
    {"name": "Barbell Back Squat", "sets": 3, "reps": 5, "weight": 100, "restSeconds": 180, "tempo": "3010", "rpe": 8, "equipment": "barbell"}]}]})
wj(V, "lb-plan.json", {"name": "US plan", "units": "lbs", "days": [{"name": "A", "exercises": [{"name": "Barbell Bench Press", "sets": 3, "reps": 5, "weight": 185, "restSeconds": 180}]}]})
wj(V, "duplicate-day-names.json", {"name": "Dupes", "days": [
    {"name": "Push", "exercises": [{"name": "Barbell Bench Press", "sets": 3, "reps": 8}]},
    {"name": "push ", "exercises": [{"name": "Overhead Press", "sets": 3, "reps": 8}]},
    {"name": "Push", "exercises": [{"name": "Dip", "sets": 3, "reps": 8}]}]})
wj(V, "group-edge-cases.json", {"name": "Groups", "days": [{"name": "A", "exercises": [
    {"name": "Curl", "group": "A", "sets": 3, "reps": 12},
    {"name": "Pushdown", "group": "A", "sets": 3, "reps": 12},
    {"name": "Barbell Back Squat", "group": "B", "sets": 3, "reps": 5},
    {"name": "Lateral Raise", "group": "A", "sets": 3, "reps": 15},
    {"name": "Plank", "group": " ", "sets": 2, "durationSeconds": 30}]}]})
wj(V, "nulls-and-defaults.json", {"name": None, "days": [{"name": None, "exercises": [
    {"name": "Row", "sets": 2, "reps": 10, "weight": None, "notes": None, "group": None}]}]})
wj(V, "long-names.json", {"name": "N" * 150, "days": [{"name": "D" * 120, "exercises": [{"name": "E" * 101, "sets": 1, "reps": 10, "notes": "x" * 600}]}]})
wj(V, "unicode-names.json", {"name": "🏋️ Программа", "days": [{"name": "胸 Chest", "exercises": [{"name": "Développé couché", "sets": 3, "reps": 8, "weight": 60}]}]})
wj(V, "rotation-with-weekdays.json", {"name": "Rotation ignores weekdays", "schedule": "rotation", "days": [
    {"name": "A", "weekday": "monday", "exercises": [{"name": "Row", "sets": 1, "reps": 10}]},
    {"name": "B", "weekday": "wednesday", "exercises": [{"name": "Row", "sets": 1, "reps": 10}]}]})
wj(V, "schedule-unknown-value.json", {"name": "Schedule typo", "schedule": "Weekly", "days": [
    {"name": "A", "exercises": [{"name": "Row", "sets": 1, "reps": 10}]}]})
wj(V, "boundaries.json", {"name": "Boundaries", "days": [{"name": "A", "exercises": [
    {"name": "Max reps", "sets": 50, "reps": 1000, "weight": 10000, "restSeconds": 3600},
    {"name": "Max duration", "sets": 1, "durationSeconds": 86400, "restSeconds": 0},
    {"name": "Zero weight", "sets": 1, "reps": 1, "weight": 0}]}]})
wj(V, "reprange-cases.json", {"name": "Rep ranges", "days": [{"name": "A", "exercises": [
    {"name": "Explicit", "sets": 3, "reps": 10, "repRange": "8-12"},
    {"name": "From reps range", "sets": 3, "reps": "8-12"},
    {"name": "None", "sets": 3, "reps": 10},
    {"name": "Outside", "sets": 3, "reps": 15, "repRange": "8-12"},
    {"name": "Timed", "sets": 2, "durationSeconds": 30, "repRange": "8-12"},
    {"name": "Single number", "sets": 3, "reps": 10, "repRange": 10},
    {"name": "Swapped", "sets": 3, "reps": 10, "repRange": "12-8"},
    {"name": "Per-set reps only", "sets": [{"reps": 12}, {"reps": 10}], "repRange": "8-12"},
    {"name": "Per-set no range", "sets": [{"reps": "8-12"}, {"reps": "8-12"}]}]}]})
wj(V, "drop-sets.json", {"name": "Drops", "units": "kg", "days": [{"name": "A", "exercises": [
    {"name": "Cable Fly", "sets": 3, "reps": 12, "weight": 20, "restSeconds": 60, "drops": [{"weight": 15}, {"weight": 10, "reps": "8-10"}]},
    {"name": "Leg Extension", "reps": 12, "weight": 50, "restSeconds": 60, "sets": [{}, {}, {"drops": [{"weight": 40}]}]},
    {"name": "Lat Pulldown", "sets": 2, "reps": 10, "weight": 60, "drops": [{"weight": 45}], "restSeconds": 90},
    {"name": "Plank", "sets": 2, "durationSeconds": 30, "drops": [{"weight": 5}]}]}]})
wj(V, "cycle-cases.json", {"name": "Cycle", "cycle": ["upper", "REST", "Lower", "off"], "days": [
    {"name": "Upper", "exercises": [{"name": "Row", "sets": 1, "reps": 10}]},
    {"name": "Lower", "exercises": [{"name": "Squat", "sets": 1, "reps": 10}]},
    {"name": "Arms", "exercises": [{"name": "Curl", "sets": 1, "reps": 10}]}]})
wj(V, "cycle-weekday-ignored.json", {"name": "Cycle ignored", "cycle": ["A", "rest"], "days": [
    {"name": "A", "weekday": "tuesday", "exercises": [{"name": "Row", "sets": 1, "reps": 10}]},
    {"name": "B", "weekday": "saturday", "exercises": [{"name": "Row", "sets": 1, "reps": 10}]}]})
wj(V, "braces-in-strings.json", {"name": "Braces {in} strings", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 1, "reps": 10, "notes": "hold {tight} and [breathe]"}]}]})

inner = json.dumps({"name": "From chat", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10, "restSeconds": 60}]}]}, indent=2)
wt(V, "fenced-plain.txt", "```json\n" + inner + "\n```\n")
wt(V, "fenced-with-prose.txt", "Here is your plan in the requested format:\n\n```json\n" + inner + "\n```\n\nLet me know if you want any changes!\n")
wt(V, "fenced-other-language.txt", "```javascript\n" + inner + "\n```\n")
wt(V, "prose-no-fence.txt", "Sure! Here's the JSON:\n" + inner + "\nEnjoy your workout.\n")
wt(V, "marker-and-json.txt", "JIMMSBRO-PLAN-PROMPT-V1\n(I pasted the prompt above by mistake but here is the plan too)\n```json\n" + inner + "\n```\n")
wt(V, "curly-quotes.txt", inner.replace('"', "\u201c", 1).replace('"', "\u201d", 1).replace('"name"', "\u201cname\u201d").replace('"days"', "\u201cdays\u201d"))
wt(V, "curly-in-string-value.txt", json.dumps({"name": "Quotes", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 1, "reps": 10, "notes": "\u201cslow\u201d eccentric"}]}]}, ensure_ascii=False))
wt(V, "bom-and-zero-width.txt", "\ufeff\u200b" + inner + "\u200b\n")
wt(V, "top-level-array-fenced.txt", "```json\n" + json.dumps([{"name": "Only day", "exercises": [{"name": "Row", "sets": 1, "reps": 10}]}]) + "\n```")

# ---------- invalid ----------
wt(I, "empty.txt", "")
wt(I, "whitespace.txt", "  \n\n\t \n")
wt(I, "prompt-pasted.txt", "JIMMSBRO-PLAN-PROMPT-V1\nYou are converting a workout plan into JSON for a workout-tracking app.\nReply with ONLY one JSON object.\nMy plan:\nMon: bench 3x8\n")
wt(I, "multiple-objects-fenced.txt", "Option A:\n```json\n" + inner + "\n```\nOption B:\n```json\n" + inner + "\n```\n")
wt(I, "multiple-objects-bare.txt", inner + "\n" + inner + "\n")
wt(I, "trailing-comma.txt", '{"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10},]}],}\n')
wt(I, "truncated.txt", "```json\n" + inner[: len(inner) // 2] + "\n")
wt(I, "comments.txt", '{\n  // my plan\n  "name": "X",\n  "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10}]}]\n}\n')
wt(I, "single-quotes.txt", "{'name': 'X', 'days': [{'name': 'A', 'exercises': [{'name': 'Row', 'sets': 3, 'reps': 10}]}]}\n")
wt(I, "not-json-at-all.txt", "Monday: bench press 3x8, rows 3x10\nWednesday: squats 5x5\n")
wt(I, "too-large.txt", "{" + " " * 1048577 + "}")
wj(I, "not-a-plan.json", {"foo": 1, "bar": [1, 2, 3]})
wj(I, "null-top-level.json", None)
wj(I, "days-not-array.json", {"name": "X", "days": {"name": "A"}})
wj(I, "no-days.json", {"name": "X", "days": []})
wj(I, "days-null.json", {"name": "X", "days": None})
wj(I, "no-exercises.json", {"name": "X", "days": [{"name": "A", "exercises": []}]})
wj(I, "missing-exercise-name.json", {"name": "X", "days": [{"name": "A", "exercises": [{"sets": 3, "reps": 10}]}]})
wj(I, "blank-exercise-name.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "   ", "sets": 3, "reps": 10}]}]})
wj(I, "sets-zero.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 0, "reps": 10}]}]})
wj(I, "sets-fraction.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 2.5, "reps": 10}]}]})
wj(I, "sets-word.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": "three", "reps": 10}]}]})
wj(I, "sets-empty-array.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": [], "reps": 10}]}]})
wj(I, "sets-too-many.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 51, "reps": 10}]}]})
wj(I, "reps-word.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": "ten"}]}]})
wj(I, "reps-zero.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 0}]}]})
wj(I, "reps-fraction.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10.5}]}]})
wj(I, "reps-triple-range.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": "8-12-15"}]}]})
wj(I, "reps-open-range.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": "8-"}]}]})
wj(I, "reps-too-big.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 1001}]}]})
wj(I, "reps-bool.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": True}]}]})
wj(I, "reprange-word.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10, "repRange": "lots"}]}]})
wj(I, "reprange-amrap.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10, "repRange": "AMRAP"}]}]})
wj(I, "reprange-zero.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10, "repRange": "0-5"}]}]})
wj(I, "drops-empty.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10, "drops": []}]}]})
wj(I, "drops-too-many.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10, "drops": [{"weight": 1}] * 6}]}]})
wj(I, "drops-not-list.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10, "drops": {"weight": 5}}]}]})
wj(I, "drops-bad-weight.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10, "drops": [{"weight": "heavy"}]}]}]})
wj(I, "cycle-unknown-day.json", {"name": "X", "cycle": ["A", "Legs"], "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10}]}]})
wj(I, "cycle-empty.json", {"name": "X", "cycle": [], "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10}]}]})
wj(I, "cycle-not-list.json", {"name": "X", "cycle": "A, rest", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10}]}]})
wj(I, "in-reserve-word.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Curl", "sets": 2, "reps": 10, "inReserve": "two"}]}]})
wj(I, "in-reserve-too-many.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Curl", "reps": 10, "sets": [{}, {"inReserve": 25}]}]}]})
wj(I, "warning-beep-zero.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Plank", "sets": 3, "durationSeconds": 30, "warningBeep": 0}]}]})
wj(I, "warning-beep-too-long.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Plank", "sets": 3, "durationSeconds": 30, "warningBeep": 86400}]}]})
wj(I, "warning-beep-word.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Plank", "sets": 3, "durationSeconds": 30, "warningBeep": "soon"}]}]})
wj(I, "warning-beep-fraction.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Plank", "sets": [{"durationSeconds": 30, "warningBeep": 2.5}]}]}]})
wj(I, "duration-word.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Plank", "sets": 3, "durationSeconds": "forever"}]}]})
wj(I, "bodyweight-string.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Push-Up", "sets": 3, "reps": 10, "bodyweight": "yes"}]}]})
wj(I, "target-conflict-exercise.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10, "durationSeconds": 30}]}]})
wj(I, "target-conflict-set.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": [{"reps": 10, "durationSeconds": 30}]}]}]})
wj(I, "target-missing-exercise.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3}]}]})
wj(I, "target-missing-set.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": [{"weight": 20}]}]}]})
wj(I, "duration-zero.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Plank", "sets": 3, "durationSeconds": 0}]}]})
wj(I, "duration-string-unit.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Plank", "sets": 3, "durationSeconds": "30s"}]}]})
wj(I, "duration-too-long.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Bike", "sets": 1, "durationSeconds": 86401}]}]})
wj(I, "weight-negative.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10, "weight": -5}]}]})
wj(I, "weight-word.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10, "weight": "heavy"}]}]})
wj(I, "weight-too-big.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10, "weight": 10001}]}]})
wj(I, "rest-negative.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10, "restSeconds": -1}]}]})
wj(I, "rest-too-long.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10, "restSeconds": 3601}]}]})
wj(I, "rest-fraction.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10, "restSeconds": 90.5}]}]})
wj(I, "rest-string-unit.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10, "restSeconds": "1m30"}]}]})
wj(I, "rest-day-level-invalid.json", {"name": "X", "days": [{"name": "A", "defaultRestSeconds": -10, "exercises": [{"name": "Row", "sets": 3, "reps": 10}]}]})
wj(I, "weekday-invalid.json", {"name": "X", "schedule": "weekday", "days": [{"name": "A", "weekday": "Funday", "exercises": [{"name": "Row", "sets": 3, "reps": 10}]}]})
wj(I, "weekday-duplicate.json", {"name": "X", "days": [
    {"name": "A", "weekday": "friday", "exercises": [{"name": "Row", "sets": 3, "reps": 10}]},
    {"name": "B", "weekday": "Fri", "exercises": [{"name": "Row", "sets": 3, "reps": 10}]}]})
wj(I, "weekday-missing.json", {"name": "X", "schedule": "weekday", "days": [
    {"name": "A", "weekday": "monday", "exercises": [{"name": "Row", "sets": 3, "reps": 10}]},
    {"name": "B", "exercises": [{"name": "Row", "sets": 3, "reps": 10}]}]})
wj(I, "schedule-mixed.json", {"name": "X", "days": [
    {"name": "A", "weekday": "monday", "exercises": [{"name": "Row", "sets": 3, "reps": 10}]},
    {"name": "B", "exercises": [{"name": "Row", "sets": 3, "reps": 10}]}]})
wj(I, "schema-version-2.json", {"schemaVersion": 2, "name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10}]}]})
wj(I, "units-invalid.json", {"name": "X", "units": "stone", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10}]}]})
wj(I, "too-many-days.json", {"name": "X", "days": [{"name": f"Day {i+1}", "exercises": [{"name": "Row", "sets": 1, "reps": 10}]} for i in range(32)]})
wj(I, "too-many-exercises.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": f"Ex {i+1}", "sets": 1, "reps": 10} for i in range(51)]}]})
wj(I, "multi-error.json", {"name": "X", "units": "stone", "days": [
    {"name": "A", "exercises": [{"name": "", "sets": 0, "reps": "ten"}, {"name": "Row", "sets": 3, "reps": 10, "weight": -1, "restSeconds": 5000}]},
    {"name": "B", "exercises": []}]})


# ---------------- prompt-derived fixtures
p = open("docs/PROMPT.md", encoding="utf-8").read()
block = re.search(r"## 1\. Plan prompt.*?\n```\n(.*?)\n```", p, re.S).group(1)
assert "```" not in block, "the plan prompt must not contain three backticks (see PROMPT.md marker rule)"
block = block.replace("{{units}}", "kg").replace("{{defaultRest}}", "90")
wt(I, "prompt-pasted-full.txt", block + "\nMon: bench 3x8, rows 3x10\n")
def _balanced(t, s):
    depth = 0; in_str = False; esc = False
    for i in range(s, len(t)):
        c = t[i]
        if in_str:
            if esc: esc = False
            elif c == "\\": esc = True
            elif c == '"': in_str = False
        elif c == '"': in_str = True
        elif c in "{[": depth += 1
        elif c in "}]":
            depth -= 1
            if depth == 0: return i + 1
    raise ValueError("unbalanced example JSON in prompt")
start = block.index("{"); ex = block[start:_balanced(block, start)]
wt(V, "prompt-example.txt", ex + "\n")

# ---------------- manifest
V = lambda f, warnings=(), **checks: {"file": f"valid/{f}", "outcome": "valid", "warnings": list(warnings), **({"checks": checks} if checks else {})}
def I(f, *errors, warnings=None, exact=True):
    d = {"file": f"invalid/{f}", "outcome": "invalid", "errors": [{"code": c, **({"path": p} if p is not None else {})} for c, p in errors]}
    if warnings is not None: d["warnings"] = warnings
    if not exact: d["exact"] = False
    return d
E0 = "days[0].exercises[0]"
fixtures = [
  V("weekly-rotation.json", planName="Push Pull Legs", units="kg", schedule="rotation", dayNames=["Push","Pull","Legs"], stepsPerDay=[22,16,16],
    cycle=["Push","Pull","Legs","Push","Pull","Legs","rest"], dropsPerSet={"0.3":[2,2,2], "0.2":[0,0,0]}, dropTargets={"0.3.0":[["amrap",20],["amrap",15]]},
    restPerSet={"0.0":[150,150,150,150], "0.1":[90,90,90], "0.4":[45,45,45], "1.3":[90,90,90]},
    workPerSet={"0.0":["range:6-8"]*4, "1.1":["amrap"]*4, "0.4":["duration:45"]*3, "2.0":["fixed:5"]*4},
    stepOrder={"0":["0.0","0.1","0.2","0.3","1.0","1.1","1.2","2.0","3.0","3.0.1","3.0.2","2.1","3.1","3.1.1","3.1.2","2.2","3.2","3.2.1","3.2.2","4.0","4.1","4.2"]},
    restAfterStep={"0:0":150, "0:3":"transition", "0:6":"transition", "0:7":0, "0:8":0, "0:9":0, "0:10":60, "0:14":60, "0:18":"transition", "0:19":45, "0:21":0, "1:9":"transition", "1:10":0, "1:11":60, "1:15":0},
    repRange={"0.0":[6,8], "0.1":[8,12], "0.2":[12,15], "0.3":[10,12], "0.4":None, "1.0":None, "1.1":None, "1.2":[8,10], "2.0":[4,6]}),
  V("drop-sets.json", ["W_DROPS_IGNORED"], stepsPerDay=[9+4+4+2], dropsPerSet={"0.0":[2,2,2], "0.1":[0,0,1], "0.2":[1,1], "0.3":[0,0]},
    dropTargets={"0.0.0":[["amrap",15],["range:8-10",10]], "0.1.2":[["amrap",40]]},
    stepOrder={"0":["0.0","0.0.1","0.0.2","0.1","0.1.1","0.1.2","0.2","0.2.1","0.2.2","1.0","1.1","1.2","1.2.1","2.0","2.0.1","2.1","2.1.1","3.0","3.1"]},
    restAfterStep={"0:0":0, "0:1":0, "0:2":60, "0:8":"transition", "0:9":60, "0:11":0, "0:12":"transition", "0:13":0, "0:14":90, "0:16":"transition"}),
  V("cycle-cases.json", ["W_CYCLE_MISSING_DAY"], cycle=["Upper","rest","Lower","rest"]),
  V("cycle-weekday-ignored.json", ["W_CYCLE_IGNORED"], schedule="weekday", cycle=["rest","A","rest","rest","rest","B","rest"]),
  V("reprange-cases.json", ["W_RANGE_SWAPPED","W_REPRANGE_IGNORED","W_REPRANGE_OUTSIDE"],
    repRange={"0.0":[8,12], "0.1":[8,12], "0.2":None, "0.3":[8,12], "0.4":None, "0.5":[10,10], "0.6":[8,12], "0.7":[8,12], "0.8":None}),
  V("weekly-weekday.json", schedule="weekday", weekdays=["monday","wednesday","friday"], stepsPerDay=[9,7,9], cycle=["Full Body A","rest","Full Body B","rest","Full Body C","rest","rest"]),
  V("no-schedule-weekdays.json", schedule="weekday", weekdays=["tuesday","thursday"]),
  V("single-day.json", dayNames=["Quick Upper"], cycle=["Quick Upper"], workPerSet={"0.0":["amrap:15"]*3}, weightPerSet={"0.0":[None]*3, "0.1":[20]*3}),
  V("single-day-bare.json", ["W_WRAPPED_SINGLE_DAY"], planName="Hotel Workout", dayNames=["Hotel Workout"], stepsPerDay=[10]),
  V("array-of-days.json", ["W_WRAPPED_SINGLE_DAY","W_DEFAULT_NAME"], planName="Imported plan 2026-09-04", dayNames=["Day 1","Day 2"]),
  V("array-of-exercises.json", ["W_WRAPPED_SINGLE_DAY","W_DEFAULT_NAME","W_DEFAULT_NAME"], dayNames=["Day 1"], stepsPerDay=[8]),
  V("minimal.json", ["W_DEFAULT_NAME","W_DEFAULT_NAME"], planName="Imported plan 2026-09-04", dayNames=["Day 1"], stepsPerDay=[1], restPerSet={"0.0":[90]}, workPerSet={"0.0":["fixed:10"]}),
  V("explicit-sets-pyramid.json", restPerSet={"0.0":[120,120,120,120,180], "0.1":[90,90,90]}, weightPerSet={"0.0":[50,60,70,80,60], "0.1":[15,15,15]},
    workPerSet={"0.0":["fixed:12","fixed:10","fixed:8","fixed:6","amrap"], "0.1":["fixed:15","fixed:15","range:12-15"]}),
  V("superset-circuit.json", ["W_GROUP_SET_MISMATCH"], groups={"0":["A","A","A",None]}, stepsPerDay=[10],
    stepOrder={"0":["0.0","1.0","2.0","0.1","1.1","2.1","0.2","1.2","3.0","3.1"]},
    restPerSet={"0.0":[60,60,60], "0.2":[90,90], "0.3":[45,45]},
    restAfterStep={"0:0":0, "0:1":0, "0:2":90, "0:5":90, "0:6":0, "0:7":"transition", "0:8":45, "0:9":0}),
  V("timed-sets.json", ["W_WARNING_BEEP_IGNORED","W_WARNING_BEEP_IGNORED"], workPerSet={"0.0":["duration:45"]*3, "0.2":["duration:600"], "0.3":["duration:40"]*3, "0.4":["open","open"], "0.5":["open:30"], "0.6":["duration:60","open"]},
    weightPerSet={"0.3":[32,32,32], "0.4":[None,None]}, restPerSet={"0.2":[0]}, restAfterStep={"0:5":"transition", "0:4":"transition", "0:0":30, "0:2":"transition", "0:8":"transition", "0:9":60, "0:10":"transition"},
    warningPerSet={"0.0":[5,5,5], "0.1":[3,3], "0.2":[60], "0.3":[4,4,4], "0.4":[None,None], "0.5":[None], "0.6":[15,None], "0.7":[None,None], "0.8":[None], "0.9":[None], "0.10":[3]},
    bodyweight={"0.3":False, "0.4":True, "0.5":False}, stepsPerDay=[19]),
  V("bodyweight.json", ["W_WARNING_BEEP_IGNORED","W_BODYWEIGHT_WEIGHT_IGNORED","W_BODYWEIGHT_WEIGHT_IGNORED"],
    bodyweight={"0.0":True, "0.1":True, "0.2":False, "0.3":True, "0.4":False, "0.5":True}, weightPerSet={"0.2":[10]*3, "0.3":[None,None], "0.1":[None]*3},
    warningPerSet={"0.4":[None,None]}, dropTargets={"0.5.0":[["amrap",None]]}),
  V("rest-precedence.json", restPerSet={"0.0":[80,80], "0.1":[70,70], "0.2":[70,60], "0.3":[0], "1.0":[100]}),
  V("lenient-values.json", ["W_RANGE_SWAPPED","W_WEIGHT_UNIT_IGNORED","W_WEIGHT_ROUNDED"], units="kg", bodyweight={"0.2":True, "0.3":False}, repRange={"0.0":[8,12], "0.1":[8,12], "0.2":None, "0.3":None, "0.4":None},
    exerciseNames={"0":["Barbell Bench Press","Incline Press","Pull-Up","Dip","Curl","Hammer Curl"]},
    stepsPerDay=[17],
    workPerSet={"0.0":["range:8-12"]*4, "0.1":["range:8-12"]*3, "0.2":["amrap"]*3, "0.3":["amrap:10"]*3, "0.4":["fixed:12"]*2, "0.5":["fixed:10"]*2},
    weightPerSet={"0.0":[60]*4, "0.1":[22.5]*3, "0.2":[None]*3, "0.3":[10]*3, "0.4":[135]*2, "0.5":[12.6]*2},
    restPerSet={"0.0":[90]*4}),
  V("unknown-fields.json", ["W_UNKNOWN_FIELD"]*4),
  V("lb-plan.json", units="lb"),
  V("in-reserve.json", inReservePerSet={"0.0":[2,2,1], "0.1":[3,3], "0.2":[5,5], "0.3":[None]}),
  V("in-reserve-alias.json", inReservePerSet={"0.0":[2,0]}),
  V("duplicate-day-names.json", ["W_DAY_RENAMED","W_DAY_RENAMED"], dayNames=["Push","push (2)","Push (3)"]),
  V("group-edge-cases.json", ["W_GROUP_SINGLE","W_GROUP_SINGLE","W_GROUP_SPLIT"], groups={"0":["A","A",None,None,None]},
    stepOrder={"0":["0.0","1.0","0.1","1.1","0.2","1.2","2.0","2.1","2.2","3.0","3.1","3.2","4.0","4.1"]}),
  V("nulls-and-defaults.json", ["W_DEFAULT_NAME","W_DEFAULT_NAME"], weightPerSet={"0.0":[None,None]}, groups={"0":[None]}, notes={"0.0":None}),
  V("long-names.json", ["W_NAME_TRUNCATED","W_NAME_TRUNCATED","W_NAME_TRUNCATED","W_NOTES_TRUNCATED"], planName="N"*100, dayNames=["D"*100], exerciseNames={"0":["E"*100]}),
  V("unicode-names.json", planName="🏋️ Программа", dayNames=["胸 Chest"], exerciseNames={"0":["Développé couché"]}),
  V("rotation-with-weekdays.json", ["W_WEEKDAY_IGNORED","W_WEEKDAY_IGNORED"], schedule="rotation", weekdays=[None,None]),
  V("schedule-unknown-value.json", ["W_SCHEDULE_INFERRED"], schedule="rotation"),
  V("boundaries.json", stepsPerDay=[52], workPerSet={"0.1":["duration:86400"], "0.2":["fixed:1"]}, weightPerSet={"0.2":[0]}, restPerSet={"0.1":[0]}),
  V("braces-in-strings.json", planName="Braces {in} strings", notes={"0.0":"hold {tight} and [breathe]"}),
  V("fenced-plain.txt", planName="From chat"),
  V("fenced-with-prose.txt", ["W_SURROUNDING_TEXT"], planName="From chat"),
  V("fenced-other-language.txt", planName="From chat"),
  V("prose-no-fence.txt", ["W_SURROUNDING_TEXT"], planName="From chat"),
  V("marker-and-json.txt", ["W_SURROUNDING_TEXT"], planName="From chat"),
  V("curly-quotes.txt", ["W_CURLY_QUOTES_FIXED"], planName="From chat"),
  V("curly-in-string-value.txt", notes={"0.0":"“slow” eccentric"}),
  V("bom-and-zero-width.txt", planName="From chat"),
  V("top-level-array-fenced.txt", ["W_WRAPPED_SINGLE_DAY","W_DEFAULT_NAME"], dayNames=["Only day"]),
  V("prompt-example.txt", planName="Push Pull Legs", stepsPerDay=[24], cycle=["Push","rest"], workPerSet={"0.5":["open","open"]}, warningPerSet={"0.4":[5,5,5], "0.5":[None,None]}, bodyweight={"0.4":True, "0.5":True}),

  I("empty.txt", ("E_EMPTY", "")),
  I("whitespace.txt", ("E_EMPTY", "")),
  I("prompt-pasted.txt", ("E_PROMPT_PASTED", "")),
  I("prompt-pasted-full.txt", ("E_PROMPT_PASTED", "")),
  I("multiple-objects-fenced.txt", ("E_MULTIPLE_OBJECTS", "")),
  I("multiple-objects-bare.txt", ("E_MULTIPLE_OBJECTS", "")),
  I("trailing-comma.txt", ("E_NOT_JSON", "")),
  I("truncated.txt", ("E_NOT_JSON", "")),
  I("comments.txt", ("E_NOT_JSON", "")),
  I("single-quotes.txt", ("E_NOT_JSON", "")),
  I("not-json-at-all.txt", ("E_NOT_JSON", "")),
  I("too-large.txt", ("E_TOO_LARGE", "")),
  I("not-a-plan.json", ("E_NOT_A_PLAN", "")),
  I("null-top-level.json", ("E_NOT_JSON", "")),
  I("days-not-array.json", ("E_NO_DAYS", "days")),
  I("no-days.json", ("E_NO_DAYS", "days")),
  I("days-null.json", ("E_NO_DAYS", "days")),
  I("no-exercises.json", ("E_NO_EXERCISES", "days[0].exercises")),
  I("missing-exercise-name.json", ("E_MISSING_NAME", f"{E0}.name")),
  I("blank-exercise-name.json", ("E_MISSING_NAME", f"{E0}.name")),
  I("sets-zero.json", ("E_SETS_INVALID", f"{E0}.sets")),
  I("sets-fraction.json", ("E_SETS_INVALID", f"{E0}.sets")),
  I("sets-word.json", ("E_SETS_INVALID", f"{E0}.sets")),
  I("sets-empty-array.json", ("E_SETS_INVALID", f"{E0}.sets")),
  I("sets-too-many.json", ("E_LIMIT_EXCEEDED", f"{E0}.sets")),
  I("reps-word.json", ("E_REPS_INVALID", f"{E0}.reps")),
  I("reps-zero.json", ("E_REPS_INVALID", f"{E0}.reps")),
  I("reps-fraction.json", ("E_REPS_INVALID", f"{E0}.reps")),
  I("reps-triple-range.json", ("E_REPS_INVALID", f"{E0}.reps")),
  I("reps-open-range.json", ("E_REPS_INVALID", f"{E0}.reps")),
  I("reps-too-big.json", ("E_REPS_INVALID", f"{E0}.reps")),
  I("reps-bool.json", ("E_REPS_INVALID", f"{E0}.reps")),
  I("reprange-word.json", ("E_REPRANGE_INVALID", f"{E0}.repRange")),
  I("reprange-amrap.json", ("E_REPRANGE_INVALID", f"{E0}.repRange")),
  I("reprange-zero.json", ("E_REPRANGE_INVALID", f"{E0}.repRange")),
  I("drops-empty.json", ("E_DROPS_INVALID", f"{E0}.drops")),
  I("drops-too-many.json", ("E_DROPS_INVALID", f"{E0}.drops")),
  I("drops-not-list.json", ("E_DROPS_INVALID", f"{E0}.drops")),
  I("drops-bad-weight.json", ("E_WEIGHT_INVALID", f"{E0}.drops[0].weight")),
  I("cycle-unknown-day.json", ("E_CYCLE_UNKNOWN_DAY", "cycle[1]")),
  I("cycle-empty.json", ("E_CYCLE_INVALID", "cycle")),
  I("cycle-not-list.json", ("E_CYCLE_INVALID", "cycle")),
  I("in-reserve-word.json", ("E_IN_RESERVE_INVALID", f"{E0}.inReserve")),
  I("in-reserve-too-many.json", ("E_IN_RESERVE_INVALID", f"{E0}.sets[1].inReserve")),
  I("warning-beep-zero.json", ("E_WARNING_BEEP_INVALID", f"{E0}.warningBeep")),
  I("warning-beep-too-long.json", ("E_WARNING_BEEP_INVALID", f"{E0}.warningBeep")),
  I("warning-beep-word.json", ("E_WARNING_BEEP_INVALID", f"{E0}.warningBeep")),
  I("warning-beep-fraction.json", ("E_WARNING_BEEP_INVALID", f"{E0}.sets[0].warningBeep")),
  I("duration-word.json", ("E_DURATION_INVALID", f"{E0}.durationSeconds")),
  I("bodyweight-string.json", ("E_BODYWEIGHT_INVALID", f"{E0}.bodyweight")),
  I("target-conflict-exercise.json", ("E_TARGET_CONFLICT", E0)),
  I("target-conflict-set.json", ("E_TARGET_CONFLICT", f"{E0}.sets[0]")),
  I("target-missing-exercise.json", ("E_TARGET_MISSING", E0)),
  I("target-missing-set.json", ("E_TARGET_MISSING", f"{E0}.sets[0]")),
  I("duration-zero.json", ("E_DURATION_INVALID", f"{E0}.durationSeconds")),
  I("duration-string-unit.json", ("E_DURATION_INVALID", f"{E0}.durationSeconds")),
  I("duration-too-long.json", ("E_DURATION_INVALID", f"{E0}.durationSeconds")),
  I("weight-negative.json", ("E_WEIGHT_INVALID", f"{E0}.weight")),
  I("weight-word.json", ("E_WEIGHT_INVALID", f"{E0}.weight")),
  I("weight-too-big.json", ("E_WEIGHT_INVALID", f"{E0}.weight")),
  I("rest-negative.json", ("E_REST_INVALID", f"{E0}.restSeconds")),
  I("rest-too-long.json", ("E_REST_INVALID", f"{E0}.restSeconds")),
  I("rest-fraction.json", ("E_REST_INVALID", f"{E0}.restSeconds")),
  I("rest-string-unit.json", ("E_REST_INVALID", f"{E0}.restSeconds")),
  I("rest-day-level-invalid.json", ("E_REST_INVALID", "days[0].defaultRestSeconds")),
  I("weekday-invalid.json", ("E_WEEKDAY_INVALID", "days[0].weekday")),
  I("weekday-duplicate.json", ("E_WEEKDAY_DUPLICATE", "days[1].weekday")),
  I("weekday-missing.json", ("E_WEEKDAY_MISSING", "days[1].weekday")),
  I("schedule-mixed.json", ("E_SCHEDULE_MIXED", "schedule")),
  I("schema-version-2.json", ("E_SCHEMA_VERSION", "schemaVersion")),
  I("units-invalid.json", ("E_UNITS_INVALID", "units")),
  I("too-many-days.json", ("E_LIMIT_EXCEEDED", "days")),
  I("too-many-exercises.json", ("E_LIMIT_EXCEEDED", "days[0].exercises")),
  I("multi-error.json", ("E_UNITS_INVALID", "units"), ("E_MISSING_NAME", f"{E0}.name"), ("E_SETS_INVALID", f"{E0}.sets"), ("E_REPS_INVALID", f"{E0}.reps"),
    ("E_WEIGHT_INVALID", "days[0].exercises[1].weight"), ("E_REST_INVALID", "days[0].exercises[1].restSeconds"), ("E_NO_EXERCISES", "days[1].exercises")),
]
man = {
  "_readme": "Expected import outcomes for every file in examples/. Run with settings units=kg, defaultRestSeconds=90, today=2026-09-04 (for default plan names). "
             "valid: 'warnings' is the exact multiset of warning codes; 'checks' keys: planName, units, schedule, dayNames, weekdays, stepsPerDay, exerciseNames{'d':[..]}, groups{'d':[..]}, notes{'d.e':..}, "
             "restPerSet{'d.e':[..]}, weightPerSet{'d.e':[..]}, workPerSet{'d.e':['fixed:10'|'range:8-12'|'amrap'|'amrap:10'|'duration:45']}, stepOrder{'d':['e.s',..]}, restAfterStep{'d:stepIndex':seconds} (rest started after logging that step, all later steps pending), repRange{'d.e':[min,max]|null}, cycle[...names or 'rest'], dropsPerSet{'d.e':[n per set]}, dropTargets{'d.e.s':[[work,weight],..]}. stepOrder entries are 'e.s' or 'e.s.d' for drops; restAfterStep values are seconds or 'transition'; workPerSet also 'open' | 'open:30'; warningPerSet{'d.e':[seconds|null]} (resolved warning-beep offset); bodyweight{'d.e':bool}. "
             "invalid: every listed error (code + path) must be reported; 'exact' (default true) also requires no other errors.",
  "settings": {"units": "kg", "defaultRestSeconds": 90, "today": "2026-09-04"},
  "fixtures": fixtures,
}
json.dump(man, open("examples/manifest.json", "w"), indent=2, ensure_ascii=False)
print("wrote", len(os.listdir("examples/valid")), "valid,", len(os.listdir("examples/invalid")), "invalid fixtures and examples/manifest.json with", len(fixtures), "entries")
