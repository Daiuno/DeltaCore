//
//  ExternalInputDispatch.swift
//  DeltaCore
//
//  HID callbacks run on `queue`. UIKit / emulator cores are hopped to the main thread.
//

import Foundation

/// Destination for external (MFi / keyboard) controller events.
public enum ExternalInputSink: Int {
    /// System UI navigation (FocusKit). Digital edges only.
    case focusKit
    /// Live emulation: mapped game inputs + function-key mappings.
    case gameplay
    /// Controller mapping UI is capturing physical keys.
    case mapping
    /// Drop events (still track pressed state to avoid stuck keys).
    case none
}

public enum ExternalInputDispatch {
    private static let specificKey = DispatchSpecificKey<UInt8>()
    private static let sinkLock = NSLock()
    private static var _sink: ExternalInputSink = .focusKit

    public static let queue: DispatchQueue = {
        let queue = DispatchQueue(label: "com.manicemu.external-input", qos: .userInteractive)
        queue.setSpecific(key: specificKey, value: 1)
        return queue
    }()

    public static var isOnQueue: Bool {
        DispatchQueue.getSpecific(key: specificKey) != nil
    }

    public static var sink: ExternalInputSink {
        get {
            sinkLock.lock()
            defer { sinkLock.unlock() }
            return _sink
        }
        set {
            sinkLock.lock()
            let old = _sink
            _sink = newValue
            sinkLock.unlock()
            if old != newValue {
                AnalogInputCoalescer.shared.cancelPending()
            }
        }
    }

    /// Receivers on the HID queue (PlayVC / cores / mapping UI). Skin stays on main and is always delivered.
    public static var shouldDeliverReceivers: Bool {
        if !isOnQueue { return true }
        switch sink {
        case .gameplay, .mapping: return true
        case .focusKit, .none: return false
        }
    }

    public static func async(_ work: @escaping () -> Void) {
        if isOnQueue {
            work()
        } else {
            queue.async(execute: work)
        }
    }

    public static func performOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    static func deliverActivate(controller: GameController, receiver: GameControllerReceiver, input: Input, value: Double, physicalIsContinuous: Bool) {
        guard shouldDeliverReceivers else { return }
        if isOnQueue {
            if physicalIsContinuous {
                AnalogInputCoalescer.shared.enqueue(controller: controller, receiver: receiver, input: input, value: value, isActivate: true)
            } else {
                DispatchQueue.main.async {
                    receiver.gameController(controller, didActivate: input, value: value)
                }
            }
        } else {
            receiver.gameController(controller, didActivate: input, value: value)
        }
    }

    static func deliverDeactivate(controller: GameController, receiver: GameControllerReceiver, input: Input, physicalIsContinuous: Bool) {
        guard shouldDeliverReceivers else { return }
        if isOnQueue {
            if physicalIsContinuous {
                AnalogInputCoalescer.shared.enqueue(controller: controller, receiver: receiver, input: input, value: 0, isActivate: false)
            } else {
                DispatchQueue.main.async {
                    receiver.gameController(controller, didDeactivate: input)
                }
            }
        } else {
            receiver.gameController(controller, didDeactivate: input)
        }
    }
}

/// Last analog sample per (controller, receiver, input) is flushed once per main runloop.
final class AnalogInputCoalescer {
    static let shared = AnalogInputCoalescer()

    private struct Key: Hashable {
        let controller: ObjectIdentifier
        let receiver: ObjectIdentifier
        let inputType: String
        let inputName: String
    }

    private struct Event {
        let controller: GameController
        let receiver: GameControllerReceiver
        let input: AnyInput
        var value: Double
        var isActivate: Bool
    }

    private let lock = NSLock()
    private var pending: [Key: Event] = [:]
    private var scheduled = false

    private init() {}

    func enqueue(controller: GameController, receiver: GameControllerReceiver, input: Input, value: Double, isActivate: Bool) {
        let key = Key(
            controller: ObjectIdentifier(controller),
            receiver: ObjectIdentifier(receiver as AnyObject),
            inputType: input.type.rawValue,
            inputName: input.stringValue
        )
        lock.lock()
        pending[key] = Event(controller: controller, receiver: receiver, input: AnyInput(input), value: value, isActivate: isActivate)
        let needsSchedule = !scheduled
        scheduled = true
        lock.unlock()
        if needsSchedule {
            DispatchQueue.main.async { [weak self] in
                self?.flush()
            }
        }
    }

    func cancelPending() {
        lock.lock()
        pending.removeAll(keepingCapacity: true)
        scheduled = false
        lock.unlock()
    }

    private func flush() {
        lock.lock()
        let events = Array(pending.values)
        pending.removeAll(keepingCapacity: true)
        scheduled = false
        lock.unlock()
        for event in events {
            if event.isActivate {
                event.receiver.gameController(event.controller, didActivate: event.input, value: event.value)
            } else {
                event.receiver.gameController(event.controller, didDeactivate: event.input)
            }
        }
    }
}
