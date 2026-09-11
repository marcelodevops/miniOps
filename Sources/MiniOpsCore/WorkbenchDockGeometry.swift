import Foundation

public enum WorkbenchDockGeometry {
    public static func resolve(width: Double, left: Double, right: Double) -> (left: Double, right: Double) {
        let left = max(0, min(left, 450))
        let right = max(0, min(right, 500))
        let dividers = (left > 0 ? 4.0 : 0) + (right > 0 ? 4.0 : 0)
        let available = max(0, width - 360 - dividers)
        let scale = left + right > 0 ? min(1, available / (left + right)) : 1
        return (left * scale, right * scale)
    }

    /// Translation is measured from gesture start, not the preceding event.
    public static func dragged(start: Double, translation: Double, minimum: Double, maximum: Double) -> Double {
        min(max(start + translation, minimum), max(minimum, maximum))
    }
}
