import Foundation

/// SPEC §6.20 (D45, v1.3): history as a file another app can read, and a file from another
/// app read here. CSV, one row per logged set, in the column order Strong writes and Hevy
/// reads — plus the unit last, because this app never converts (D10).
///
/// Everything here is text in, text out. Files, sheets and dialogs are the app's.
enum HistoryCSV {
    static let header = ["Date", "Workout Name", "Duration", "Exercise Name", "Set Order", "Weight",
                         "Reps", "Distance", "Seconds", "Notes", "Workout Notes", "RPE", "Weight Unit"]

    // MARK: - Export

    static func render(_ sessions: [Session], timeZone: TimeZone = .current) -> String {
        let dates = dateFormatter("yyyy-MM-dd HH:mm:ss", timeZone: timeZone)
        var lines = [header.map(field).joined(separator: ",")]
        for session in sessions.sorted(by: { $0.startedAt < $1.startedAt }) {
            let date = dates.string(from: session.startedAt)
            let duration = durationText(SessionStats.duration(session))
            var order: [Int: Int] = [:]
            for step in session.steps where step.status == .logged {
                guard let result = step.result,
                      let exercise = session.exercises[safe: step.exerciseIndex] else { continue }
                order[step.exerciseIndex, default: 0] += 1
                let row = [date, session.dayName, duration, exercise.name,
                           String(order[step.exerciseIndex] ?? 1),
                           result.weight.map(TargetText.number) ?? "",
                           result.reps.map(String.init) ?? "",
                           "",
                           result.seconds.map(String.init) ?? "",
                           "", "", "",
                           session.units.rawValue]
                lines.append(row.map(field).joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// "48m", "1h 5m" — the shape Strong writes, which Hevy reads back.
    static func durationText(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(0, seconds).rounded(.down)) / 60
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    /// RFC 4180: quote when the value holds a comma, a quote or a line break.
    static func field(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" || $0 == ";" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - Import

    struct Parsed: Equatable {
        /// In date order, ready to be sessions — `planId` nil, the workout name as the day name.
        var sessions: [Session]
        /// What went wrong, per line, and what was assumed. Errors mean nothing was read.
        var issues: [Issue]
        /// The unit given to rows that did not say — nil when every row said.
        var assumedUnits: WeightUnit?
        var errors: [Issue] { issues.filter { $0.severity == .error } }
    }

    /// The columns a row is read through, found by header name rather than position, so the
    /// app's own export, a Strong export (either delimiter, with or without a unit column) and
    /// a Hevy export all read.
    struct Columns: Equatable {
        var date: Int?, end: Int?, workout: Int?, duration: Int?, exercise: Int?, order: Int?
        var weight: Int?, unit: Int?, reps: Int?, seconds: Int?, notes: Int?
        /// A unit named by the weight header itself: `weight_kg`, `Weight (lbs)`.
        var headerUnits: WeightUnit?

        static func find(in header: [String]) -> Columns {
            var columns = Columns()
            for (index, raw) in header.enumerated() {
                let name = raw.trimmed.lowercased()
                    .replacingOccurrences(of: "_", with: " ")
                    .replacingOccurrences(of: "  ", with: " ")
                switch name {
                case "date", "start time", "workout date", "start": columns.date = columns.date ?? index
                case "end time", "end": columns.end = columns.end ?? index
                case "workout name", "title", "workout", "routine", "workout title": columns.workout = columns.workout ?? index
                case "duration", "workout duration": columns.duration = columns.duration ?? index
                case "exercise name", "exercise title", "exercise": columns.exercise = columns.exercise ?? index
                case "set order", "set index", "set", "set number": columns.order = columns.order ?? index
                case "weight": columns.weight = columns.weight ?? index
                case "weight kg", "weight (kg)", "weight in kg": columns.weight = columns.weight ?? index; columns.headerUnits = .kg
                case "weight lbs", "weight lb", "weight (lbs)", "weight (lb)", "weight in lbs": columns.weight = columns.weight ?? index; columns.headerUnits = .lb
                case "weight unit", "unit", "units": columns.unit = columns.unit ?? index
                case "reps", "repetitions": columns.reps = columns.reps ?? index
                case "seconds", "duration seconds", "time", "time (s)": columns.seconds = columns.seconds ?? index
                case "notes", "set notes": columns.notes = columns.notes ?? index
                default: break
                }
            }
            return columns
        }

        var isUsable: Bool { date != nil && exercise != nil && (reps != nil || seconds != nil) }
    }

    /// One row of a file, as read.
    private struct Row {
        var line: Int
        var start: Date
        var end: Date?
        var workout: String
        var duration: TimeInterval?
        var exercise: String
        var weight: Double?
        var units: WeightUnit?
        var reps: Int?
        var seconds: Int?
    }

    static func parse(_ text: String, defaultUnits: WeightUnit, timeZone: TimeZone = .current,
                      calendar: Calendar = .current) -> Parsed {
        func failure(_ code: String, _ message: String) -> Parsed {
            Parsed(sessions: [], issues: [Issue(severity: .error, code: code, path: "", message: message)],
                   assumedUnits: nil)
        }
        let cleaned = text.replacingOccurrences(of: "\u{FEFF}", with: "")
        guard !cleaned.trimmed.isEmpty else {
            return failure("E_EMPTY", "The file is empty.")
        }
        let records = split(cleaned)
        guard let headerRecord = records.first(where: { !$0.fields.allSatisfy { $0.trimmed.isEmpty } }) else {
            return failure("E_EMPTY", "The file is empty.")
        }
        let columns = Columns.find(in: headerRecord.fields)
        guard columns.isUsable else {
            return failure("E_CSV_COLUMNS",
                           "Couldn't find the columns for the date, the exercise and the reps. "
                           + "The first line should name them, as an export from this app, Strong or Hevy does.")
        }

        var issues: [Issue] = []
        var rows: [Row] = []
        var assumed = false
        for record in records where record.line > headerRecord.line {
            let fields = record.fields
            guard !fields.allSatisfy({ $0.trimmed.isEmpty }) else { continue }
            func value(_ index: Int?) -> String? {
                guard let index, index < fields.count else { return nil }
                let text = fields[index].trimmed
                return text.isEmpty ? nil : text
            }
            let path = "line \(record.line)"
            guard let dateText = value(columns.date), let start = parseDate(dateText, timeZone: timeZone) else {
                issues.append(Issue(severity: .warning, code: "W_CSV_ROW_SKIPPED", path: path,
                                    message: "Couldn't read the date \"\(value(columns.date) ?? "")\"; the line was skipped."))
                continue
            }
            guard let exercise = value(columns.exercise) else {
                issues.append(Issue(severity: .warning, code: "W_CSV_ROW_SKIPPED", path: path,
                                    message: "No exercise name; the line was skipped."))
                continue
            }
            let reps = value(columns.reps).flatMap { Int(Double($0.replacingOccurrences(of: ",", with: ".")) ?? -1) }
                .flatMap { $0 >= 0 ? $0 : nil }
            let seconds = value(columns.seconds).flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
                .flatMap { $0 > 0 ? Int($0.rounded(.down)) : nil }
            guard reps != nil || seconds != nil else {
                issues.append(Issue(severity: .warning, code: "W_CSV_ROW_SKIPPED", path: path,
                                    message: "Neither reps nor seconds; the line was skipped."))
                continue
            }
            // A weight of 0 is no weight: it is what Strong writes for a bodyweight set.
            let weight = value(columns.weight).flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
                .flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            var units: WeightUnit? = columns.headerUnits
            if let text = value(columns.unit)?.lowercased() {
                units = text.hasPrefix("k") ? .kg : (text.hasPrefix("l") || text.hasPrefix("p") ? .lb : units)
            }
            if units == nil, weight != nil { assumed = true }
            rows.append(Row(line: record.line, start: start,
                            end: value(columns.end).flatMap { parseDate($0, timeZone: timeZone) },
                            workout: value(columns.workout) ?? "Workout",
                            duration: value(columns.duration).flatMap(parseDuration),
                            exercise: exercise, weight: weight, units: units, reps: reps, seconds: seconds))
        }
        guard !rows.isEmpty else {
            return Parsed(sessions: [], issues: issues + [Issue(
                severity: .error, code: "E_CSV_NO_ROWS", path: "",
                message: "No sets could be read from the file.")], assumedUnits: nil)
        }
        let sessions = group(rows, defaultUnits: defaultUnits, issues: &issues)
        return Parsed(sessions: sessions, issues: issues, assumedUnits: assumed ? defaultUnits : nil)
    }

    /// Rows become sessions: a run of rows with the same start and workout name is one
    /// workout, its exercises in order of first appearance, each row a logged set.
    private static func group(_ rows: [Row], defaultUnits: WeightUnit, issues: inout [Issue]) -> [Session] {
        var groups: [(key: String, rows: [Row])] = []
        for row in rows {
            let key = "\(row.start.timeIntervalSince1970)|\(normalized(row.workout))"
            if let last = groups.indices.last, groups[last].key == key { groups[last].rows.append(row) }
            else { groups.append((key, [row])) }
        }
        return groups.map { group -> Session in
            let rows = group.rows
            let start = rows[0].start
            // One unit per session (D10): the one most rows state, else the setting.
            let stated = rows.compactMap(\.units)
            let units = stated.isEmpty ? defaultUnits
                : (stated.filter { $0 == .kg }.count >= stated.filter { $0 == .lb }.count ? .kg : .lb)
            for row in rows where row.units != nil && row.units != units {
                issues.append(Issue(severity: .warning, code: "W_CSV_UNIT_MIXED", path: "line \(row.line)",
                                    message: "This set says \(row.units!.rawValue) in a \(units.rawValue) workout; read as \(units.rawValue)."))
            }
            // Exercises in order of first appearance, each row a set of its exercise.
            var names: [String] = [], byName: [String: [Row]] = [:]
            for row in rows {
                let key = normalized(row.exercise)
                if byName[key] == nil { names.append(key) }
                byName[key, default: []].append(row)
            }
            var exercises: [Exercise] = []
            for key in names {
                let sets = byName[key] ?? []
                let targets = sets.map { row -> SetTarget in
                    let work: WorkTarget = row.reps.map { .reps(.fixed($0)) } ?? .duration(seconds: row.seconds ?? 1)
                    return SetTarget(work: work, weight: row.weight, restSeconds: 0)
                }
                exercises.append(Exercise(name: sets[0].exercise, bodyweight: sets.allSatisfy { $0.weight == nil },
                                          sets: targets))
            }
            let day = Day(name: rows[0].workout, exercises: exercises)
            let duration = rows[0].duration
                ?? rows[0].end.map { max(0, $0.timeIntervalSince(start)) }
                ?? Double(rows.count) * 60
            let steps = flatten(day: day)
            // Sets are spread evenly over the workout: the file says when it started and how
            // long it took, not when each set was logged.
            let spacing = steps.isEmpty ? 0 : duration / Double(steps.count)
            let sessionSteps = steps.enumerated().map { index, step -> SessionStep in
                let row = byName[names[step.exerciseIndex]]?[step.setIndex]
                var step = step
                step.status = .logged
                step.result = row?.reps.map { .reps(count: $0, weight: row?.weight) }
                    ?? .duration(seconds: row?.seconds ?? 0, weight: row?.weight)
                step.loggedAt = start.addingTimeInterval(spacing * Double(index + 1))
                return step
            }
            return Session(planId: nil, planName: "Imported", dayName: day.name, units: units,
                           startedAt: start, endedAt: start.addingTimeInterval(duration),
                           exercises: exercises.map {
                               SessionExercise(name: $0.name, bodyweight: $0.bodyweight, targets: $0.sets)
                           },
                           steps: sessionSteps)
        }
    }

    // MARK: - Merging

    /// The sessions of `incoming` not already in `existing`: the same workout name at the same
    /// minute is the same workout, so a file imported twice adds nothing.
    static func new(_ incoming: [Session], against existing: [Session]) -> [Session] {
        incoming.filter { candidate in
            !existing.contains { present in
                normalized(present.dayName) == normalized(candidate.dayName)
                    && abs(present.startedAt.timeIntervalSince(candidate.startedAt)) < 60
            }
        }
    }

    /// What the file holds, said before anything is written.
    struct Summary: Equatable {
        var workouts: Int
        var sets: Int
        var from: Date?
        var to: Date?
        var alreadyHere: Int
        var skippedLines: Int
        var assumedUnits: WeightUnit?

        static func of(_ parsed: Parsed, existing: [Session]) -> Summary {
            let fresh = HistoryCSV.new(parsed.sessions, against: existing)
            return Summary(workouts: fresh.count,
                           sets: fresh.reduce(0) { $0 + $1.steps.count },
                           from: parsed.sessions.map(\.startedAt).min(),
                           to: parsed.sessions.map(\.startedAt).max(),
                           alreadyHere: parsed.sessions.count - fresh.count,
                           skippedLines: parsed.issues.filter { $0.code == "W_CSV_ROW_SKIPPED" }.count,
                           assumedUnits: parsed.assumedUnits)
        }

        /// "42 workouts (610 sets) from 12 Jan to 3 Sep · 5 already here · weights read as kg".
        func text(locale: Locale = .current, timeZone: TimeZone = .current) -> String {
            var parts: [String] = []
            var lead = "\(TargetText.counted(workouts, "workout")) (\(TargetText.counted(sets, "set")))"
            if let from, let to {
                let formatter = DateFormatter()
                formatter.locale = locale
                formatter.timeZone = timeZone
                formatter.setLocalizedDateFormatFromTemplate("d MMM")
                lead += Calendar.current.isDate(from, inSameDayAs: to)
                    ? " on \(formatter.string(from: from))"
                    : " from \(formatter.string(from: from)) to \(formatter.string(from: to))"
            }
            parts.append(lead)
            if alreadyHere > 0 { parts.append("\(alreadyHere) already here") }
            if skippedLines > 0 { parts.append("\(TargetText.counted(skippedLines, "line")) skipped") }
            if let assumedUnits { parts.append("weights read as \(assumedUnits.rawValue)") }
            return parts.joined(separator: " · ")
        }
    }

    // MARK: - Reading the text

    private struct Record { var line: Int; var fields: [String] }

    /// RFC 4180 records: quoted fields may hold the delimiter, doubled quotes and line breaks.
    /// The delimiter is whichever of `,` `;` and tab splits the first line into the most fields.
    private static func split(_ text: String) -> [Record] {
        let firstLine = text.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" }).first.map(String.init) ?? ""
        let delimiter: Character = [",", ";", "\t"].max { a, b in
            firstLine.filter { $0 == a }.count < firstLine.filter { $0 == b }.count
        } ?? ","
        var records: [Record] = []
        var fields: [String] = [], field = "", quoted = false, line = 1, recordLine = 1
        var iterator = text.makeIterator()
        var pending: Character? = iterator.next()
        func endRecord() {
            fields.append(field); field = ""
            records.append(Record(line: recordLine, fields: fields)); fields = []
            recordLine = line
        }
        while let character = pending {
            pending = iterator.next()
            if quoted {
                if character == "\"" {
                    if pending == "\"" { field.append("\""); pending = iterator.next() } else { quoted = false }
                } else {
                    if character == "\n" || character == "\r\n" { line += 1 }
                    field.append(character)
                }
            } else if character == "\"" && field.isEmpty {
                quoted = true
            } else if character == delimiter {
                fields.append(field); field = ""
            } else if character == "\n" || character == "\r\n" || character == "\r" {
                line += 1
                endRecord()
            } else {
                field.append(character)
            }
        }
        if !field.isEmpty || !fields.isEmpty { endRecord() }
        return records
    }

    /// The shapes this app, Strong and Hevy write, and a few a spreadsheet might.
    static func parseDate(_ text: String, timeZone: TimeZone = .current) -> Date? {
        let value = text.trimmed
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) { return date }
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm",
                       "d MMM yyyy, HH:mm", "d MMM yyyy HH:mm", "d MMM yyyy", "MMM d, yyyy, h:mm a", "MMM d, yyyy",
                       "yyyy-MM-dd", "dd/MM/yyyy HH:mm", "dd/MM/yyyy", "M/d/yyyy H:mm", "M/d/yyyy"] {
            if let date = dateFormatter(format, timeZone: timeZone).date(from: value) { return date }
        }
        return nil
    }

    /// "48m", "1h 5m", "1:05:00", "48:12", "2900" (seconds), "1h", "75 min".
    static func parseDuration(_ text: String) -> TimeInterval? {
        let value = text.trimmed.lowercased()
        guard !value.isEmpty else { return nil }
        if let seconds = Double(value) { return seconds >= 0 ? seconds : nil }
        let clock = value.split(separator: ":").map { Double(String($0).trimmed) }
        if clock.count >= 2, clock.allSatisfy({ $0 != nil }) {
            let parts = clock.compactMap { $0 }
            return parts.count == 3 ? parts[0] * 3600 + parts[1] * 60 + parts[2] : parts[0] * 60 + parts[1]
        }
        var total: TimeInterval = 0, matched = false
        for (pattern, scale) in [("([0-9]+(?:\\.[0-9]+)?)\\s*h", 3600.0), ("([0-9]+(?:\\.[0-9]+)?)\\s*m", 60.0),
                                 ("([0-9]+(?:\\.[0-9]+)?)\\s*s", 1.0)] {
            // `captures[0]` is the whole match ("52m"); the number is the first group.
            if let captures = value.captures(pattern), captures.count > 1, let number = Double(captures[1]) {
                total += number * scale; matched = true
            }
        }
        return matched ? total : nil
    }

    private static func dateFormatter(_ format: String, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }
}
