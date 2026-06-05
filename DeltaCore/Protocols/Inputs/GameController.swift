//
//  GameController.swift
//  DeltaCore
//
//  Created by Riley Testut on 5/3/15.
//  Copyright (c) 2015 Riley Testut. All rights reserved.
//

import ObjectiveC

private var gameControllerStateManagerKey = 0

class NotificationDebouncer {
    static let shared = NotificationDebouncer()

    private struct PendingNotification {
        let name: Notification.Name
        let object: Any?
        let userInfo: [AnyHashable: Any]?
        let value: Double
    }

    private var pendingNotifications: [PendingNotification] = []
    private var workItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 0.1
    private let queue = DispatchQueue(label: "notification.debouncer")

    private init() {}

    func post(name: Notification.Name, value: Double, object: Any? = nil, userInfo: [AnyHashable: Any]? = nil) {
        queue.async {
            // 记录本次通知
            let notification = PendingNotification(name: name, object: object, userInfo: userInfo, value: value)
            self.pendingNotifications.append(notification)

            // 取消之前的防抖任务
            self.workItem?.cancel()

            // 创建新的任务
            let task = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                // 找到最大值的通知
                if let maxNotification = self.pendingNotifications.max(by: { $0.value < $1.value }) {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: maxNotification.name, object: maxNotification.object, userInfo: maxNotification.userInfo)
                    }
                }
                self.queue.async {
                    self.pendingNotifications.removeAll()
                    self.workItem = nil
                }
            }

            // 保存并调度任务
            self.workItem = task
            self.queue.asyncAfter(deadline: .now() + self.debounceInterval, execute: task)
        }
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
        return self.stateManager.activatedInputs
    }
    
    var sustainedInputs: [AnyInput: Double] {
        return self.stateManager.sustainedInputs
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
        NotificationDebouncer.shared.post(name: .externalGameControllerDidPress, value: value, userInfo: ["input": input, "value": value])
    }
    
    func deactivate(_ input: Input)
    {
        self.stateManager.deactivate(input)
        NotificationCenter.default.post(name: .externalGameControllerDidRelease, object: nil, userInfo: ["input": input])
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
