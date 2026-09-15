//
//  GameControllerStateManager.swift
//  DeltaCore
//
//  Created by Riley Testut on 5/29/16.
//  Copyright © 2016 Riley Testut. All rights reserved.
//

import Foundation

internal class GameControllerStateManager
{
    // Associated object on the controller; must not strongly retain it back.
    unowned let gameController: GameController
    
    private var _activatedInputs = [AnyInput: Double]()
    private var _sustainedInputs = [AnyInput: Double]()
    
    var receivers: [GameControllerReceiver] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return snapshotReceiversUnlocked()
    }

    private let _receivers = NSMapTable<AnyObject, AnyObject>.weakToStrongObjects()
    private let stateLock = NSLock()
    
    init(gameController: GameController)
    {
        self.gameController = gameController
    }
    
    func copyActivatedInputs() -> [AnyInput: Double] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _activatedInputs
    }
    
    func copySustainedInputs() -> [AnyInput: Double] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _sustainedInputs
    }
    
    private func snapshotReceiversUnlocked() -> [GameControllerReceiver] {
        return (_receivers.keyEnumerator().allObjects as? [GameControllerReceiver]) ?? []
    }
}

extension GameControllerStateManager
{
    func addReceiver(_ receiver: GameControllerReceiver, inputMapping: GameControllerInputMappingProtocol?)
    {
        stateLock.lock()
        _receivers.setObject(inputMapping as AnyObject, forKey: receiver)
        stateLock.unlock()
    }
    
    func removeReceiver(_ receiver: GameControllerReceiver)
    {
        stateLock.lock()
        _receivers.removeObject(forKey: receiver)
        stateLock.unlock()
    }
}

extension GameControllerStateManager
{
    func activate(_ input: Input, value: Double)
    {
        precondition(input.type == .controller(self.gameController.inputType), "input.type must match self.gameController.inputType")
        
        var deliveries: [(GameControllerReceiver, Input)] = []
        
        stateLock.lock()
        // An input may be "activated" multiple times, such as by pressing different buttons that map to same input, or moving an analog stick.
        _activatedInputs[AnyInput(input)] = value
        for receiver in snapshotReceiversUnlocked()
        {
            if let mappedInput = mappedInputUnlocked(for: input, receiver: receiver)
            {
                deliveries.append((receiver, mappedInput))
            }
        }
        stateLock.unlock()
        
        for (receiver, mappedInput) in deliveries
        {
            ExternalInputDispatch.deliverActivate(
                controller: gameController,
                receiver: receiver,
                input: mappedInput,
                value: value,
                physicalIsContinuous: input.isContinuous
            )
        }
    }
    
    func deactivate(_ input: Input)
    {
        precondition(input.type == .controller(self.gameController.inputType), "input.type must match self.gameController.inputType")
        
        var deliveries: [(GameControllerReceiver, Input)] = []
        var restoreSustained: Double?
        
        stateLock.lock()
        // Unlike activate(_:), we don't allow an input to be deactivated multiple times.
        guard _activatedInputs.keys.contains(AnyInput(input)) else {
            stateLock.unlock()
            return
        }
        
        if let sustainedValue = _sustainedInputs[AnyInput(input)]
        {
            if input.isContinuous
            {
                restoreSustained = sustainedValue
            }
        }
        else
        {
            _activatedInputs[AnyInput(input)] = nil
            
            for receiver in snapshotReceiversUnlocked()
            {
                if let mappedInput = mappedInputUnlocked(for: input, receiver: receiver)
                {
                    let hasActivatedMappedControllerInputs = _activatedInputs.keys.contains {
                        guard let mapped = mappedInputUnlocked(for: $0, receiver: receiver) else { return false }
                        return mapped == mappedInput
                    }
                    
                    if !hasActivatedMappedControllerInputs
                    {
                        deliveries.append((receiver, mappedInput))
                    }
                }
            }
        }
        stateLock.unlock()
        
        if let sustainedValue = restoreSustained
        {
            activate(input, value: sustainedValue)
            return
        }
        
        for (receiver, mappedInput) in deliveries
        {
            ExternalInputDispatch.deliverDeactivate(
                controller: gameController,
                receiver: receiver,
                input: mappedInput,
                physicalIsContinuous: input.isContinuous
            )
        }
    }
    
    func sustain(_ input: Input, value: Double)
    {
        precondition(input.type == .controller(self.gameController.inputType), "input.type must match self.gameController.inputType")
        
        var needsActivate = false
        stateLock.lock()
        if _activatedInputs[AnyInput(input)] != value
        {
            needsActivate = true
        }
        _sustainedInputs[AnyInput(input)] = value
        stateLock.unlock()
        
        if needsActivate
        {
            activate(input, value: value)
        }
    }
    
    // Technically not a word, but no good alternative, so ¯\_(ツ)_/¯
    func unsustain(_ input: Input)
    {
        precondition(input.type == .controller(self.gameController.inputType), "input.type must match self.gameController.inputType")
        
        stateLock.lock()
        _sustainedInputs[AnyInput(input)] = nil
        stateLock.unlock()
        
        deactivate(AnyInput(input))
    }
}

extension GameControllerStateManager
{
    func inputMapping(for receiver: GameControllerReceiver) -> GameControllerInputMappingProtocol?
    {
        stateLock.lock()
        defer { stateLock.unlock() }
        return inputMappingUnlocked(for: receiver)
    }
    
    func mappedInput(for input: Input, receiver: GameControllerReceiver) -> Input?
    {
        stateLock.lock()
        defer { stateLock.unlock() }
        return mappedInputUnlocked(for: input, receiver: receiver)
    }
    
    private func inputMappingUnlocked(for receiver: GameControllerReceiver) -> GameControllerInputMappingProtocol?
    {
        return _receivers.object(forKey: receiver) as? GameControllerInputMappingProtocol
    }
    
    private func mappedInputUnlocked(for input: Input, receiver: GameControllerReceiver) -> Input?
    {
        guard let inputMapping = inputMappingUnlocked(for: receiver) else { return input }
        return inputMapping.input(forControllerInput: input)
    }
}
