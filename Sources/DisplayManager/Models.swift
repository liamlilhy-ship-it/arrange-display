import CoreGraphics
import Foundation

struct DisplayInfo: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let uuid: String
    let name: String
    let bounds: CGRect
    let isBuiltin: Bool
    let isMain: Bool
}

struct Placement: Codable {
    let displayID: CGDirectDisplayID
    let x: Int32
    let y: Int32
}

enum Preset: String, CaseIterable, Identifiable {
    case externalAboveBuiltin = "a"
    case dualExternalBuiltinRight = "b"
    case dualExternalBuiltinBottom = "c"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .externalAboveBuiltin: return "External above, built-in below"
        case .dualExternalBuiltinRight: return "Dual external, built-in right"
        case .dualExternalBuiltinBottom: return "Dual external, built-in bottom"
        }
    }

    var requiredExternalCount: Int {
        switch self {
        case .externalAboveBuiltin: return 1
        case .dualExternalBuiltinRight, .dualExternalBuiltinBottom: return 2
        }
    }
}
