import Foundation
import Carbon.HIToolbox

struct HotKeyChoice: Identifiable, Hashable {
    let keyCode: UInt32
    let label: String

    var id: UInt32 { keyCode }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    static let quickTrayLauncherDidShow = Notification.Name("QuickTrayLauncherDidShow")

    static let defaultToggleKeyCode = UInt32(kVK_ANSI_V)
    static let defaultToggleModifiers = UInt32(optionKey | cmdKey)
    static let defaultWindowOpacity = 0.92
    static let defaultCommandVStripItemCount = 5
    static let minCommandVStripItemCount = 2
    static let maxCommandVStripItemCount = 10
    static let defaultLauncherHoldDuration = 1.0
    static let minLauncherHoldDuration = 0.2
    static let maxLauncherHoldDuration = 1.8

    static let availableToggleKeys: [HotKeyChoice] = [
        HotKeyChoice(keyCode: UInt32(kVK_Space), label: "Space"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_A), label: "A"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_B), label: "B"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_C), label: "C"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_D), label: "D"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_E), label: "E"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_F), label: "F"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_G), label: "G"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_H), label: "H"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_I), label: "I"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_J), label: "J"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_K), label: "K"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_L), label: "L"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_M), label: "M"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_N), label: "N"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_O), label: "O"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_P), label: "P"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_Q), label: "Q"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_R), label: "R"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_S), label: "S"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_T), label: "T"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_U), label: "U"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_V), label: "V"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_W), label: "W"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_X), label: "X"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_Y), label: "Y"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_Z), label: "Z"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_0), label: "0"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_1), label: "1"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_2), label: "2"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_3), label: "3"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_4), label: "4"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_5), label: "5"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_6), label: "6"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_7), label: "7"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_8), label: "8"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_9), label: "9"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_Minus), label: "-"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_Equal), label: "="),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_LeftBracket), label: "["),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_RightBracket), label: "]"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_Backslash), label: "\\"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_Semicolon), label: ";"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_Quote), label: "'"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_Comma), label: ","),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_Period), label: "."),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_Slash), label: "/"),
        HotKeyChoice(keyCode: UInt32(kVK_ANSI_Grave), label: "`")
    ]

    private enum Keys {
        static let toggleKeyCode = "settings.toggleKeyCode"
        static let toggleModifiers = "settings.toggleModifiers"
        static let windowOpacity = "settings.windowOpacity"
        static let launcherWindowOriginX = "settings.launcherWindowOriginX"
        static let launcherWindowOriginY = "settings.launcherWindowOriginY"
        static let focusSearchOnOpen = "settings.focusSearchOnOpen"
        static let hasCompletedOnboarding = "settings.hasCompletedOnboarding"
        static let showLauncherOnStartup = "settings.showLauncherOnStartup"
        static let commandVStripItemCount = "settings.commandVStripItemCount"
        static let launcherHoldDuration = "settings.launcherHoldDuration"
    }

    @Published var toggleKeyCode: UInt32 {
        didSet { persistHotKey() }
    }

    @Published var toggleModifiers: UInt32 {
        didSet { persistHotKey() }
    }

    @Published var windowOpacity: Double {
        didSet {
            UserDefaults.standard.set(windowOpacity, forKey: Keys.windowOpacity)
        }
    }

    @Published var focusSearchOnOpen: Bool {
        didSet {
            UserDefaults.standard.set(focusSearchOnOpen, forKey: Keys.focusSearchOnOpen)
        }
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding)
        }
    }

    @Published var showLauncherOnStartup: Bool {
        didSet {
            UserDefaults.standard.set(showLauncherOnStartup, forKey: Keys.showLauncherOnStartup)
        }
    }

    @Published var commandVStripItemCount: Int {
        didSet {
            let clamped = Self.clampedCommandVStripItemCount(commandVStripItemCount)
            if clamped != commandVStripItemCount {
                commandVStripItemCount = clamped
                return
            }
            UserDefaults.standard.set(commandVStripItemCount, forKey: Keys.commandVStripItemCount)
        }
    }

    @Published var launcherHoldDuration: Double {
        didSet {
            let clamped = Self.clampedLauncherHoldDuration(launcherHoldDuration)
            if clamped != launcherHoldDuration {
                launcherHoldDuration = clamped
                return
            }
            UserDefaults.standard.set(launcherHoldDuration, forKey: Keys.launcherHoldDuration)
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        let savedKeyCode = defaults.object(forKey: Keys.toggleKeyCode) != nil ? UInt32(defaults.integer(forKey: Keys.toggleKeyCode)) : nil
        let savedModifiers = defaults.object(forKey: Keys.toggleModifiers) != nil ? UInt32(defaults.integer(forKey: Keys.toggleModifiers)) : nil
        let savedOpacity = defaults.object(forKey: Keys.windowOpacity) as? Double

        toggleKeyCode = savedKeyCode ?? Self.defaultToggleKeyCode
        toggleModifiers = Self.sanitizedModifiers(savedModifiers ?? Self.defaultToggleModifiers)
        windowOpacity = min(max(savedOpacity ?? Self.defaultWindowOpacity, 0.45), 1.0)
        focusSearchOnOpen = defaults.object(forKey: Keys.focusSearchOnOpen) as? Bool ?? true
        hasCompletedOnboarding = defaults.object(forKey: Keys.hasCompletedOnboarding) as? Bool ?? false
        showLauncherOnStartup = defaults.object(forKey: Keys.showLauncherOnStartup) as? Bool ?? true
        let savedCommandVCount = defaults.integer(forKey: Keys.commandVStripItemCount)
        let initialCommandVCount = savedCommandVCount > 0 ? savedCommandVCount : Self.defaultCommandVStripItemCount
        commandVStripItemCount = Self.clampedCommandVStripItemCount(initialCommandVCount)
        let savedHoldDuration = defaults.object(forKey: Keys.launcherHoldDuration) as? Double
        launcherHoldDuration = Self.clampedLauncherHoldDuration(savedHoldDuration ?? Self.defaultLauncherHoldDuration)
    }

    var toggleShortcutLabel: String {
        label(for: toggleKeyCode, modifiers: toggleModifiers)
    }

    func setModifier(_ flag: UInt32, enabled: Bool) {
        var next = toggleModifiers
        if enabled {
            next |= flag
        } else {
            next &= ~flag
        }
        toggleModifiers = Self.sanitizedModifiers(next)
    }

    func setToggleKeyCode(_ keyCode: UInt32) {
        toggleKeyCode = keyCode
    }

    func setWindowOpacity(_ opacity: Double) {
        windowOpacity = min(max(opacity, 0.45), 1.0)
    }

    func setLauncherWindowOrigin(_ origin: CGPoint) {
        UserDefaults.standard.set(origin.x, forKey: Keys.launcherWindowOriginX)
        UserDefaults.standard.set(origin.y, forKey: Keys.launcherWindowOriginY)
    }

    func launcherWindowOrigin() -> CGPoint? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Keys.launcherWindowOriginX) != nil,
              defaults.object(forKey: Keys.launcherWindowOriginY) != nil else {
            return nil
        }

        return CGPoint(
            x: defaults.double(forKey: Keys.launcherWindowOriginX),
            y: defaults.double(forKey: Keys.launcherWindowOriginY)
        )
    }

    func includesModifier(_ flag: UInt32) -> Bool {
        (toggleModifiers & flag) != 0
    }

    func resetDefaults() {
        toggleKeyCode = Self.defaultToggleKeyCode
        toggleModifiers = Self.defaultToggleModifiers
        windowOpacity = Self.defaultWindowOpacity
        focusSearchOnOpen = true
        showLauncherOnStartup = true
        commandVStripItemCount = Self.defaultCommandVStripItemCount
        launcherHoldDuration = Self.defaultLauncherHoldDuration
        UserDefaults.standard.removeObject(forKey: Keys.launcherWindowOriginX)
        UserDefaults.standard.removeObject(forKey: Keys.launcherWindowOriginY)
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    func label(for keyCode: UInt32, modifiers: UInt32) -> String {
        var prefix = ""
        if (modifiers & UInt32(controlKey)) != 0 { prefix += "⌃" }
        if (modifiers & UInt32(optionKey)) != 0 { prefix += "⌥" }
        if (modifiers & UInt32(shiftKey)) != 0 { prefix += "⇧" }
        if (modifiers & UInt32(cmdKey)) != 0 { prefix += "⌘" }

        let keyLabel = Self.availableToggleKeys.first(where: { $0.keyCode == keyCode })?.label ?? "?"
        return prefix + keyLabel.uppercased()
    }

    private func persistHotKey() {
        let sanitized = Self.sanitizedModifiers(toggleModifiers)
        if sanitized != toggleModifiers {
            toggleModifiers = sanitized
            return
        }

        UserDefaults.standard.set(Int(toggleKeyCode), forKey: Keys.toggleKeyCode)
        UserDefaults.standard.set(Int(toggleModifiers), forKey: Keys.toggleModifiers)
    }

    private static func sanitizedModifiers(_ modifiers: UInt32) -> UInt32 {
        modifiers == 0 ? defaultToggleModifiers : modifiers
    }

    private static func clampedCommandVStripItemCount(_ value: Int) -> Int {
        min(max(value, minCommandVStripItemCount), maxCommandVStripItemCount)
    }

    private static func clampedLauncherHoldDuration(_ value: Double) -> Double {
        min(max(value, minLauncherHoldDuration), maxLauncherHoldDuration)
    }
}
