import Foundation

/// What a file on disk is allowed to leave out (SPEC §8.3, v1.2).
///
/// Synthesized `Codable` treats a property with a default value as a *required* key: a
/// `settings.json` written before a field existed fails to decode, and the store's corruption
/// path renames it aside. Every release that adds one field to `Settings`, `Plan` or `Session`
/// would therefore silently reset the user's settings and lose their plans.
///
/// So the rule is written out here instead, once, and it is this:
///
/// - **Identity is required.** A plan with no `name`, a set with no work target, a session with
///   no `id` — those are corrupt, and corrupt files are set aside, which is the behavior SPEC
///   §8.3 promises.
/// - **Everything with a sensible default is optional.** A missing key that has a default is a
///   file written by an older version, not a damaged one.
///
/// Each `init(from:)` lives in an extension so the memberwise initializer survives.
/// `JimmsBroTests/StoreMigrationTests.swift` decodes a frozen v1 file of every type, so a
/// field added later cannot break an old file without turning a test red.

extension KeyedDecodingContainer {
    /// The decoded value, or `fallback` when the key is absent, null, or of the wrong type.
    func value<T: Decodable>(_ key: Key, or fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }

    /// The decoded value, or nil when the key is absent, null, or of the wrong type.
    func optional<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }
}

extension Settings {
    /// Nothing here is required: every setting has a default, and a file that predates a
    /// setting simply does not mention it.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Settings()
        self.init(
            units: container.value(.units, or: defaults.units),
            defaultRestSeconds: container.value(.defaultRestSeconds, or: defaults.defaultRestSeconds),
            warmUpSeconds: container.value(.warmUpSeconds, or: defaults.warmUpSeconds),
            transitionRestSeconds: container.value(.transitionRestSeconds, or: defaults.transitionRestSeconds),
            sound: container.value(.sound, or: defaults.sound),
            vibration: container.value(.vibration, or: defaults.vibration),
            keepAwake: container.value(.keepAwake, or: defaults.keepAwake),
            weightStepKg: container.value(.weightStepKg, or: defaults.weightStepKg),
            weightStepLb: container.value(.weightStepLb, or: defaults.weightStepLb),
            weightIncrementKg: container.value(.weightIncrementKg, or: defaults.weightIncrementKg),
            weightIncrementLb: container.value(.weightIncrementLb, or: defaults.weightIncrementLb),
            introSeen: container.value(.introSeen, or: defaults.introSeen))
    }
}

extension Plan {
    /// Required: what makes it this plan — its id, name, units, schedule and days. Everything
    /// else is either derivable or decoration.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let days = try container.decode([Day].self, forKey: .days)
        self.init(
            id: container.value(.id, or: UUID()),
            name: try container.decode(String.self, forKey: .name),
            units: try container.decode(WeightUnit.self, forKey: .units),
            schedule: try container.decode(Schedule.self, forKey: .schedule),
            days: days,
            importedAt: container.value(.importedAt, or: Date(timeIntervalSince1970: 0)),
            sourceText: container.value(.sourceText, or: ""),
            warnings: container.value(.warnings, or: []),
            // A plan written before cycles existed repeats its days in order, which is what
            // the importer would have given it.
            cycle: container.value(.cycle, or: days.indices.map(CycleEntry.day)),
            cyclePosition: container.optional(.cyclePosition),
            cycleAnchor: container.optional(.cycleAnchor),
            progression: container.optional(.progression))
    }
}

extension Day {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: container.value(.id, or: UUID()),
                  name: try container.decode(String.self, forKey: .name),
                  weekday: container.optional(.weekday),
                  exercises: try container.decode([Exercise].self, forKey: .exercises))
    }
}

extension Exercise {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: container.value(.id, or: UUID()),
                  name: try container.decode(String.self, forKey: .name),
                  group: container.optional(.group),
                  notes: container.optional(.notes),
                  repRange: container.optional(.repRange),
                  bodyweight: container.value(.bodyweight, or: false),
                  sets: try container.decode([SetTarget].self, forKey: .sets))
    }
}

extension SetTarget {
    /// `work` says what the set is, so it is required; `restSeconds` is required because a set
    /// with no rest and a set that forgot to say are different things.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(work: try container.decode(WorkTarget.self, forKey: .work),
                  weight: container.optional(.weight),
                  restSeconds: try container.decode(Int.self, forKey: .restSeconds),
                  warningBeepSeconds: container.optional(.warningBeepSeconds),
                  drops: container.value(.drops, or: []),
                  groupRestSeconds: container.optional(.groupRestSeconds),
                  inReserve: container.optional(.inReserve))
    }
}

extension Session {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try container.decode(UUID.self, forKey: .id),
                  planId: container.optional(.planId),
                  planName: container.value(.planName, or: ""),
                  dayName: container.value(.dayName, or: ""),
                  units: try container.decode(WeightUnit.self, forKey: .units),
                  startedAt: try container.decode(Date.self, forKey: .startedAt),
                  endedAt: container.optional(.endedAt),
                  exercises: try container.decode([SessionExercise].self, forKey: .exercises),
                  steps: try container.decode([SessionStep].self, forKey: .steps),
                  progressionWeek: container.optional(.progressionWeek),
                  progressionWeeks: container.optional(.progressionWeeks),
                  progressionMode: container.optional(.progressionMode))
    }
}

extension Progression {
    /// D53 (v1.5): `mode` is new; a progression written by v1.3 is a calendar one.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(startDate: try container.decode(Date.self, forKey: .startDate),
                  weeks: try container.decode(Int.self, forKey: .weeks),
                  entries: container.value(.entries, or: []),
                  mode: container.value(.mode, or: .calendar))
    }
}

extension ProgressionEntry {
    /// D53 (v1.5): `step` and `tries` are new; an entry written by v1.3 starts at the first.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(dayName: try container.decode(String.self, forKey: .dayName),
                  exerciseName: try container.decode(String.self, forKey: .exerciseName),
                  weeks: container.value(.weeks, or: []),
                  step: container.value(.step, or: 0),
                  tries: container.value(.tries, or: 0))
    }
}

extension SessionExercise {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: container.value(.id, or: UUID()),
                  name: try container.decode(String.self, forKey: .name),
                  group: container.optional(.group),
                  notes: container.optional(.notes),
                  repRange: container.optional(.repRange),
                  bodyweight: container.value(.bodyweight, or: false),
                  targets: try container.decode([SetTarget].self, forKey: .targets),
                  advice: container.optional(.advice),
                  substitutedFor: container.optional(.substitutedFor),
                  replaces: container.optional(.replaces),
                  progressionWeek: container.optional(.progressionWeek))
    }
}

extension SessionStep {
    /// The six index fields are what makes the step addressable, so they are required. What
    /// happened to it — status, result, timestamps — may be absent on a step never reached.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(exerciseIndex: try container.decode(Int.self, forKey: .exerciseIndex),
                  setIndex: try container.decode(Int.self, forKey: .setIndex),
                  dropIndex: try container.decode(Int.self, forKey: .dropIndex),
                  blockIndex: try container.decode(Int.self, forKey: .blockIndex),
                  isLastInRound: container.value(.isLastInRound, or: false),
                  isLastInBlock: container.value(.isLastInBlock, or: false),
                  status: container.value(.status, or: .pending),
                  result: container.optional(.result),
                  startedAt: container.optional(.startedAt),
                  loggedAt: container.optional(.loggedAt))
    }
}
