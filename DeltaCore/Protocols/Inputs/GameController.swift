//
//  GameController.swift
//  DeltaCore
//
//  Created by Riley Testut on 5/3/15.
//  Copyright (c) 2015 Riley Testut. All rights reserved.
//

import ObjectiveC

private var gameControllerStateManagerKey = 0

// Edge-triggered filter for controller input notifications.
// 
// The stick is an analog signal—while held, it keeps firing value-change callbacks at a very high frequency, so "trailing debounce" won't work (new events keep canceling the timer, and the notification might never fire while the stick is held).
// The semantics here are: when an input first crosses the activation threshold, a press notification is sent **immediately** (zero delay), and holding it down afterward won't resend it; when the input deactivates, it resets and sends a release notification.
// This matches the hold-dedup logic on the receiving end (FocusKeyObserver / UIControllerKit).
class NotificationDebouncer {
    static let shared = NotificationDebouncer()

    private let lock = NSLock()
    /// Inputs that have been sent as press but not yet released (distinguished by controller + input dimension)
    private var pressedKeys = Set<String>()

    private init() {}

    /// Input activated (value has crossed the threshold). First activation triggers a notification immediately; repeated activations while holding are filtered out.
    func postPress(key: String, userInfo: [AnyHashable: Any]?) {
        lock.lock()
        let isFirstPress = pressedKeys.insert(key).inserted
        lock.unlock()
        guard isFirstPress else { return }
        // Always track edges; only FocusKit consumes these notifications.
        guard ExternalInputDispatch.sink == .focusKit else { return }
        NotificationCenter.default.post(name: .externalGameControllerDidPress, object: nil, userInfo: userInfo)
    }

    /// Input release. Only send release if press was previously sent, to avoid a release storm caused by repeated simulated signals.
    func postRelease(key: String, userInfo: [AnyHashable: Any]?) {
        lock.lock()
        let wasPressed = pressedKeys.remove(key) != nil
        lock.unlock()
        guard wasPressed else { return }
        guard ExternalInputDispatch.sink == .focusKit else { return }
        NotificationCenter.default.post(name: .externalGameControllerDidRelease, object: nil, userInfo: userInfo)
    }

    func clearKeys(for controller: GameController) {
        let prefix = "\(ObjectIdentifier(controller))-"
        lock.lock()
        pressedKeys = pressedKeys.filter { !$0.hasPrefix(prefix) }
        lock.unlock()
    }
}

//MARK: - GameControllerReceiver -
public protocol GameControllerReceiver: class
{
    /// Equivalent to pressing a button, or moving an analog stick
    func gameController(_ gameController: GameController, didActivate input: Input, value: Double)
    
    /// Equivalent to releasing a button or an analog stick
    func gameController(_ gameController: GameController, didDeactivate input: Input)
}

//MARK: - GameController -
public protocol GameController: NSObjectProtocol
{
    var name: String { get }
        
    var playerIndex: Int? { get set }
    
    var inputType: GameControllerInputType { get }
    
    var defaultInputMapping: GameControllerInputMappingProtocol? { get }
}

public extension GameController
{
    private var stateManager: GameControllerStateManager {
        var stateManager = objc_getAssociatedObject(self, &gameControllerStateManagerKey) as? GameControllerStateManager
        
        if stateManager == nil
        {
            stateManager = GameControllerStateManager(gameController: self)
            objc_setAssociatedObject(self, &gameControllerStateManagerKey, stateManager, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        
        return stateManager!
    }
    
    var receivers: [GameControllerReceiver] {
        return self.stateManager.receivers
    }
    
    var activatedInputs: [AnyInput: Double] {
        return self.stateManager.copyActivatedInputs()
    }
    
    var sustainedInputs: [AnyInput: Double] {
        return self.stateManager.copySustainedInputs()
    }
}

public extension GameController
{
    func addReceiver(_ receiver: GameControllerReceiver)
    {
        self.addReceiver(receiver, inputMapping: self.defaultInputMapping)
    }
    
    func addReceiver(_ receiver: GameControllerReceiver, inputMapping: GameControllerInputMappingProtocol?)
    {
        self.stateManager.addReceiver(receiver, inputMapping: inputMapping)
    }
    
    func removeReceiver(_ receiver: GameControllerReceiver)
    {
        self.stateManager.removeReceiver(receiver)
    }
    
    func activate(_ input: Input, value: Double = 1.0)
    {
        self.stateManager.activate(input, value: value)
        guard value > 0.5 else { return }
        NotificationDebouncer.shared.postPress(key: self.notificationKey(for: input), userInfo: ["input": input, "value": value])
    }
    
    func deactivate(_ input: Input)
    {
        self.stateManager.deactivate(input)
        NotificationDebouncer.shared.postRelease(key: self.notificationKey(for: input), userInfo: ["input": input])
    }
    
    private func notificationKey(for input: Input) -> String
    {
        "\(ObjectIdentifier(self))-\(input.stringValue)"
    }
    
    func sustain(_ input: Input, value: Double = 1.0)
    {
        self.stateManager.sustain(input, value: value)
    }
    
    func unsustain(_ input: Input)
    {
        self.stateManager.unsustain(input)
    }
}

public extension GameController
{
    func inputMapping(for receiver: GameControllerReceiver) -> GameControllerInputMappingProtocol?
    {
        return self.stateManager.inputMapping(for: receiver)
    }
    
    func mappedInput(for input: Input, receiver: GameControllerReceiver) -> Input?
    {
        return self.stateManager.mappedInput(for: input, receiver: receiver)
    }
}

public func ==(lhs: GameController?, rhs: GameController?) -> Bool
{
    switch (lhs, rhs)
    {
    case (nil, nil): return true
    case (_?, nil): return false
    case (nil, _?): return false
    case (let lhs?, let rhs?): return lhs.isEqual(rhs)
    }
}

public func !=(lhs: GameController?, rhs: GameController?) -> Bool
{
    return !(lhs == rhs)
}

public func ~=(pattern: GameController?, value: GameController?) -> Bool
{
    return pattern == value
}
