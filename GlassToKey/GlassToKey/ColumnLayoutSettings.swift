import Foundation

struct ColumnLayoutSettings: Codable, Hashable {
    var scale: Double
    var offsetXPercent: Double
    var offsetYPercent: Double
}

enum ColumnLayoutStore {
    static func decode(_ data: Data) -> [ColumnLayoutSettings]? {
        guard !data.isEmpty else { return nil }
        do {
            return try JSONDecoder().decode([ColumnLayoutSettings].self, from: data)
        } catch {
            return nil
        }
    }

    static func encode(_ settings: [ColumnLayoutSettings]) -> Data? {
        do {
            return try JSONEncoder().encode(settings)
        } catch {
            return nil
        }
    }
}

enum ColumnLayoutDefaults {
    static let scaleRange: ClosedRange<Double> = 0.5...2.0
    static let offsetPercentRange: ClosedRange<Double> = -30.0...30.0

    static func defaultSettings(columns: Int) -> [ColumnLayoutSettings] {
        Array(
            repeating: ColumnLayoutSettings(scale: 1.0, offsetXPercent: 0.0, offsetYPercent: 0.0),
            count: columns
        )
    }

    static func normalizedSettings(
        _ settings: [ColumnLayoutSettings],
        columns: Int
    ) -> [ColumnLayoutSettings] {
        var resolved = settings
        if resolved.count != columns {
            resolved = defaultSettings(columns: columns)
        }
        return resolved.map { setting in
            ColumnLayoutSettings(
                scale: min(max(setting.scale, scaleRange.lowerBound), scaleRange.upperBound),
                offsetXPercent: min(
                    max(setting.offsetXPercent, offsetPercentRange.lowerBound),
                    offsetPercentRange.upperBound
                ),
                offsetYPercent: min(
                    max(setting.offsetYPercent, offsetPercentRange.lowerBound),
                    offsetPercentRange.upperBound
                )
            )
        }
    }
}
