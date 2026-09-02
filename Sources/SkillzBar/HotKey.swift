import Carbon
import SkillzBarCore

/// Carbon global hotkey: no Accessibility permission required. Registration failure is logged (conflicts fail here).
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private static var current: HotKey?

    init(spec: HotKeySpec, action: @escaping () -> Void) {
        self.action = action
        HotKey.current = self
        var mods: UInt32 = 0
        if spec.command { mods |= UInt32(cmdKey) }
        if spec.option { mods |= UInt32(optionKey) }
        if spec.control { mods |= UInt32(controlKey) }
        if spec.shift { mods |= UInt32(shiftKey) }
        guard let code = HotKey.keyCode(for: spec.key) else {
            Log.shared.error("hotkey.register", "unknown key '\(spec.key)' in hotkey spec"); return
        }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            HotKey.current?.action(); return noErr
        }, 1, &eventType, nil, &handler)
        let id = EventHotKeyID(signature: 0x534B_5A42 /* SKZB */, id: 1)
        let status = RegisterEventHotKey(code, mods, id, GetApplicationEventTarget(), 0, &ref)
        if status != noErr {
            Log.shared.error("hotkey.register", "RegisterEventHotKey failed for \(spec.display): OSStatus \(status) (likely claimed by another app)")
        } else {
            Log.shared.info("hotkey.register", "registered \(spec.display)")
        }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }

    static func keyCode(for key: String) -> UInt32? {
        let table: [String: Int] = [
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G,
            "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N,
            "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U,
            "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4, "5": kVK_ANSI_5,
            "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9, " ": kVK_Space, "space": kVK_Space,
            "/": kVK_ANSI_Slash, ";": kVK_ANSI_Semicolon, "`": kVK_ANSI_Grave, ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period,
        ]
        return table[key.lowercased()].map(UInt32.init)
    }
}
