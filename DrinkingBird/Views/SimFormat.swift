import Foundation

/// Formatting helpers shared by the instrument panel and the x-ray HUD.
enum SceneText {
    static func pascalToKiloPascal(_ pa: Double) -> String {
        String(format: "%+.2f kPa", pa / 1000)
    }
    static func degrees(_ radians: Double) -> String {
        String(format: "%+.1f°", radians * 180 / .pi)
    }
    static func millimeters(_ meters: Double) -> String {
        String(format: "%.1f mm", meters * 1000)
    }
    static func torque(_ newtonMeters: Double) -> String {
        String(format: "%.2f mN·m", newtonMeters * 1000)
    }
}
