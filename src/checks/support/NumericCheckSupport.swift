import Foundation

/// Approximate equality shared by suites in every lane.
public func near(_ lhs: Double, _ rhs: Double, tolerance: Double = 1e-9) -> Bool {
    abs(lhs - rhs) <= tolerance
}
