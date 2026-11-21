import Foundation

public enum AppTheme: String, CaseIterable, Codable, Sendable {
    case system
    case slateCyan
    case tokyoNight
    case nord
    case catppuccin

    public var title: String {
        switch self {
        case .system: L10n.text("System Default")
        case .slateCyan: "Slate Cyan"
        case .tokyoNight: "Tokyo Night"
        case .nord: "Nord"
        case .catppuccin: "Catppuccin Mocha"
        }
    }

    public var forcesDarkAppearance: Bool { self != .system }
}
