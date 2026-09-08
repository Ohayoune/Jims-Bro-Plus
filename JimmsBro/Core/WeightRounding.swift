import Foundation

/// SPEC §6.11 (D35, v1.2): **the app never offers a weight you cannot load.**
///
/// The owner's note was blunt: "134 pounds next time doesn't make sense for 135." Progression
/// is arithmetic — last weight plus a step — and arithmetic will happily produce a number that
/// no combination of plates on that bar can make. So every weight the app *offers* (a
/// suggestion, a stepper tap, the chip) is snapped to a multiple of the smallest change the
/// equipment can actually make, which the owner sets per unit.
///
/// Weights the user *types* are never touched. If they lifted 61 kg on a machine the app does
/// not know about, that is what happened, and history records it.
enum WeightRounding {
    /// Which way a value may move when it is not already on the grid.
    enum Direction { case nearest, up, down }

    /// `weight` rounded to a multiple of `increment`. A non-positive or non-finite increment
    /// means "the equipment can make anything", and the weight comes back unchanged.
    static func snap(_ weight: Double, increment: Double,
                     direction: Direction = .nearest) -> Double {
        guard weight.isFinite, increment.isFinite, increment > 0 else { return weight }
        let steps = weight / increment
        let rounded: Double
        switch direction {
        case .nearest: rounded = steps.rounded()
        case .up: rounded = steps.rounded(.up)
        case .down: rounded = steps.rounded(.down)
        }
        // One decimal place, matching the input rules: 2.5 × 27 is 67.5, not 67.50000000000001.
        return max(0, (rounded * increment * 10).rounded() / 10)
    }

    /// Whether `weight` is already something the equipment can make.
    static func isLoadable(_ weight: Double, increment: Double) -> Bool {
        abs(snap(weight, increment: increment) - weight) < 0.0001
    }

    /// A suggestion that must genuinely be **heavier** than `current`: snapped to the grid, and
    /// pushed up a whole increment if rounding to nearest landed on or below where it started.
    /// Suggesting the weight you just lifted is not advice.
    static func heavier(than current: Double, target: Double, increment: Double) -> Double {
        let snapped = snap(target, increment: increment)
        guard snapped > current + 0.0001 else {
            return snap(current + max(increment, 0.1), increment: increment, direction: .up)
        }
        return snapped
    }

    /// The mirror image: genuinely **lighter** than `current`, and never below zero.
    static func lighter(than current: Double, target: Double, increment: Double) -> Double {
        let snapped = snap(target, increment: increment)
        guard snapped < current - 0.0001 else {
            return max(0, snap(max(0, current - max(increment, 0.1)), increment: increment,
                               direction: .down))
        }
        return max(0, snapped)
    }
}
