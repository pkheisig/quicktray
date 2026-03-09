import AppKit
import Carbon.HIToolbox

final class HotKeyManager {
    static let shared = HotKeyManager()

    private let signature = OSType(0x51545259)
    private struct HandlerPair {
        let onPress: () -> Void
        let onRelease: (() -> Void)?
    }

    private var handlers: [UInt32: HandlerPair] = [:]
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]

    private init() {
        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            )
        ]

        _ = eventTypes.withUnsafeMutableBufferPointer { buffer in
            InstallEventHandler(
                GetEventDispatcherTarget(),
                { _, event, userData in
                    guard
                        let userData,
                        let event
                    else {
                        return noErr
                    }

                    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                    var hotKeyID = EventHotKeyID()
                    let status = GetEventParameter(
                        event,
                        EventParamName(kEventParamDirectObject),
                        EventParamType(typeEventHotKeyID),
                        nil,
                        MemoryLayout<EventHotKeyID>.size,
                        nil,
                        &hotKeyID
                    )

                    guard status == noErr else { return status }
                    guard let handlers = manager.handlers[hotKeyID.id] else { return noErr }

                    switch GetEventKind(event) {
                    case UInt32(kEventHotKeyPressed):
                        handlers.onPress()
                    case UInt32(kEventHotKeyReleased):
                        handlers.onRelease?()
                    default:
                        break
                    }

                    return noErr
                },
                buffer.count,
                buffer.baseAddress,
                UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                nil
            )
        }
    }

    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        register(id: id, keyCode: keyCode, modifiers: modifiers, onPress: handler, onRelease: nil)
    }

    func register(
        id: UInt32,
        keyCode: UInt32,
        modifiers: UInt32,
        onPress: @escaping () -> Void,
        onRelease: (() -> Void)? = nil
    ) {
        unregister(id: id)

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        if let hotKeyRef {
            hotKeyRefs[id] = hotKeyRef
            handlers[id] = HandlerPair(onPress: onPress, onRelease: onRelease)
        }
    }

    func unregister(id: UInt32) {
        if let hotKeyRef = hotKeyRefs[id] {
            UnregisterEventHotKey(hotKeyRef)
        }

        hotKeyRefs[id] = nil
        handlers[id] = nil
    }
}
