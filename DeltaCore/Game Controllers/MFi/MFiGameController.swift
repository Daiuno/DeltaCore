//
//  MFiGameController.swift
//  DeltaCore
//
//  Created by Riley Testut on 7/22/15.
//  Copyright © 2015 Riley Testut. All rights reserved.
//

import GameController

public extension GameControllerInputType
{
    static let mfi = GameControllerInputType("mfi")
}

extension MFiGameController
{
    private enum ProductCategory: String
    {
        case mfi = "MFi"
        
        case joyConL = "Nintendo Switch Joy-Con (L)"
        case joyConR = "Nintendo Switch Joy-Con (R)"
        case joyConsCombined = "Nintendo Switch Joy-Con (L/R)"
        
        case switchPro = "Switch Pro Controller"
        case switchOnlineNES = "Switch NES Controller"
        case switchOnlineSNES = "Switch SNES Controller"
    }
}

extension MFiGameController
{
    public enum Input: String, Codable
    {
        case menu
        
        case up
        case down
        case left
        case right
        
        case leftThumbstickUp
        case leftThumbstickDown
        case leftThumbstickLeft
        case leftThumbstickRight
        
        case rightThumbstickUp
        case rightThumbstickDown
        case rightThumbstickLeft
        case rightThumbstickRight
        
        case a
        case b
        case x
        case y
        
        case leftShoulder
        case leftTrigger
        
        case rightShoulder
        case rightTrigger
        
        case start
        case select
        
        case leftThumbstickButton
        case rightThumbstickButton
    }
}

extension MFiGameController.Input: Input
{
    public var type: InputType {
        return .controller(.mfi)
    }
    
    public var isContinuous: Bool {
        switch self
        {
        case .leftThumbstickUp, .leftThumbstickDown, .leftThumbstickLeft, .leftThumbstickRight: return true
        case .rightThumbstickUp, .rightThumbstickDown, .rightThumbstickLeft, .rightThumbstickRight: return true
        default: return false
        }
    }
}

public class MFiGameController: NSObject, GameController
{
    //MARK: - Properties -
    /** Properties **/
    public let controller: GCController
    
    #if os(tvOS)
    /// Where the finger is on the clickpad. Touching alone does not emit a button.
    private var siriTouchX: Float = 0
    private var siriTouchY: Float = 0
    private var siriOriginX: Float = 0
    private var siriOriginY: Float = 0
    private var siriLastX: Float = 0
    private var siriLastY: Float = 0
    private var siriGestureActive = false
    /// False while the finger is still landing. The jump from rest to the contact point is not a swipe.
    private var siriTouchSettled = false
    private var siriGestureStart: TimeInterval = 0
    /// Farthest travel from the contact point. Used when a flick ends before it can be committed.
    private var siriPeakDX: Float = 0
    private var siriPeakDY: Float = 0
    /// Direction held for the current swipe. Released when the finger lifts.
    private var siriSwipeDirection: Input?
    /// Recognized, but not emitted yet. A click in this window cancels it.
    private var siriArmedSwipe: Input?
    private var siriArmedAt: TimeInterval = 0
    /// A center or rim click owns the gesture until the finger lifts.
    private var siriSuppressSwipe = false
    /// A physical rim (cardinal d-pad) key is held. Blocks swipe outright while true.
    private var siriCardinalHeld = false
    /// The center select key is held. Blocks swipe outright while true.
    private var siriCenterHeld = false
    #endif
    
    public var name: String {
        #if os(tvOS)
        if isSiriRemote {
            return self.controller.productCategory
        }
        #endif
        return self.controller.vendorName ?? NSLocalizedString("MFi Controller", comment: "")
    }
    
    public var playerIndex: Int? {
        get {
            switch self.controller.playerIndex
            {
            case .indexUnset: return nil
            case .index1: return 0
            case .index2: return 1
            case .index3: return 2
            case .index4: return 3
            @unknown default: return nil
            }
        }
        set {
            switch newValue
            {
            case .some(0): self.controller.playerIndex = .index1
            case .some(1): self.controller.playerIndex = .index2
            case .some(2): self.controller.playerIndex = .index3
            case .some(3): self.controller.playerIndex = .index4
            default: self.controller.playerIndex = .indexUnset
            }
        }
    }
    
    public var deadZone: Float = 0.0
    
    public let inputType: GameControllerInputType = .mfi
        
    public private(set) lazy var defaultInputMapping: GameControllerInputMappingProtocol? = {
        guard let fileURL = Bundle.resources.url(forResource: "MFiGameController", withExtension: "keymapping") else {
            fatalError("MFiGameController.deltamapping does not exist.")
        }
        
        do
        {
            let inputMapping = try GameControllerInputMapping(fileURL: fileURL)
            return inputMapping
        }
        catch
        {
            print(error)
            fatalError("MFiGameController.deltamapping does not exist.")
        }
    }()
    
    //MARK: - Initializers -
    /** Initializers **/
    public init(controller: GCController)
    {
        self.controller = controller
        
        super.init()
        
        // Must be set before any handlers. Keeps HID off the main thread (Libretro / shader stay on main).
        self.controller.handlerQueue = ExternalInputDispatch.queue
        
        let inputChangedHandler: (_ input: MFiGameController.Input, _ pressed: Bool) -> Void = { [unowned self] (input, pressed) in
            if pressed
            {
                self.activate(input)
            }
            else
            {
                self.deactivate(input)
            }
        }
        
        let thumbstickChangedHandler: (_ input1: MFiGameController.Input, _ input2: MFiGameController.Input, _ value: Float) -> Void = { [unowned self] (input1, input2, value) in
            
            // In the dead zone (including cases where it doesn't precisely return to 0), deactivation must be bidirectional.
            // Otherwise, the activated direction will never be released, and the edge-triggered notification filter will keep treating it as a held state.
            if value < 0, abs(value) > deadZone
            {
                self.deactivate(input2)
                self.activate(input1, value: Double(-value))
            }
            else if value > 0, abs(value) > deadZone
            {
                self.deactivate(input1)
                self.activate(input2, value: Double(value))
            }
            else
            {
                self.deactivate(input1)
                self.deactivate(input2)
            }
        }
        
        let profile = self.controller.physicalInputProfile
        profile.buttons[GCInputButtonA]?.pressedChangedHandler = { (button, value, pressed) in inputChangedHandler(.a, pressed) }
        profile.buttons[GCInputButtonB]?.pressedChangedHandler = { (button, value, pressed) in inputChangedHandler(.b, pressed) }
        profile.buttons[GCInputButtonX]?.pressedChangedHandler = { (button, value, pressed) in inputChangedHandler(.x, pressed) }
        profile.buttons[GCInputButtonY]?.pressedChangedHandler = { (button, value, pressed) in inputChangedHandler(.y, pressed) }
        
        profile.buttons[GCInputLeftShoulder]?.pressedChangedHandler = { (button, value, pressed) in inputChangedHandler(.leftShoulder, pressed) }
        profile.buttons[GCInputLeftTrigger]?.pressedChangedHandler = { (button, value, pressed) in inputChangedHandler(.leftTrigger, pressed) }
        profile.buttons[GCInputRightShoulder]?.pressedChangedHandler = { (button, value, pressed) in inputChangedHandler(.rightShoulder, pressed) }
        profile.buttons[GCInputRightTrigger]?.pressedChangedHandler = { (button, value, pressed) in inputChangedHandler(.rightTrigger, pressed) }
        
        profile.buttons[GCInputLeftThumbstickButton]?.pressedChangedHandler = { (button, value, pressed) in inputChangedHandler(.leftThumbstickButton, pressed) }
        profile.buttons[GCInputRightThumbstickButton]?.pressedChangedHandler = { (button, value, pressed) in inputChangedHandler(.rightThumbstickButton, pressed) }
        
        // Menu = Primary menu button (Start/+/Menu)
        let menuButton = profile.buttons[GCInputButtonMenu]
        menuButton?.pressedChangedHandler = { (button, value, pressed) in inputChangedHandler(.menu, pressed) }
        
        let shareButton = profile.buttons[GCInputButtonShare]
        shareButton?.pressedChangedHandler = { (button, value, pressed) in inputChangedHandler(.menu, pressed) }
        
        let XboxPaddleOne = profile.buttons[GCInputXboxPaddleOne]
        XboxPaddleOne?.pressedChangedHandler = { (button, value, pressed) in inputChangedHandler(.menu, pressed) }
        
        let xboxPaddleTwo = profile.buttons[GCInputXboxPaddleTwo]
        xboxPaddleTwo?.pressedChangedHandler = { (button, value, pressed) in inputChangedHandler(.menu, pressed) }
        
        let xboxPaddleThree = profile.buttons[GCInputXboxPaddleThree]
        xboxPaddleThree?.pressedChangedHandler = { (button, value, pressed) in inputChangedHandler(.menu, pressed) }
        
        let xboxPaddleFour = profile.buttons[GCInputXboxPaddleFour]
        xboxPaddleFour?.pressedChangedHandler = { (button, value, pressed) in inputChangedHandler(.menu, pressed) }
        
        let dualShockTouchpadButton = profile.buttons[GCInputDualShockTouchpadButton]
        dualShockTouchpadButton?.pressedChangedHandler = { (button, value, pressed) in inputChangedHandler(.menu, pressed) }

        // Options = Secondary menu button (Select/-)
        if let optionsButton = profile.buttons[GCInputButtonOptions]
        {
            optionsButton.pressedChangedHandler = { (button, value, pressed) in inputChangedHandler(.select, pressed) }
            
            // .alwaysReceive == asking permission to record screen every time button is pressed as of iOS 16.3 (annoying).
            // optionsButton.preferredSystemGestureState = .alwaysReceive
        }
        
        if let dPad = profile.dpads[GCInputDirectionPad]
        {
            dPad.up.pressedChangedHandler = { (button, value, pressed) in inputChangedHandler(.up, pressed) }
            dPad.down.pressedChangedHandler = { (button, value, pressed) in inputChangedHandler(.down, pressed) }
            dPad.left.pressedChangedHandler = { (button, value, pressed) in inputChangedHandler(.left, pressed) }
            dPad.right.pressedChangedHandler = { (button, value, pressed) in inputChangedHandler(.right, pressed) }
        }

        if let leftThumbstick = profile.dpads[GCInputLeftThumbstick]
        {
            leftThumbstick.xAxis.valueChangedHandler = { (axis, value) in
                thumbstickChangedHandler(.leftThumbstickLeft, .leftThumbstickRight, value)
            }
            leftThumbstick.yAxis.valueChangedHandler = { (axis, value) in
                thumbstickChangedHandler(.leftThumbstickDown, .leftThumbstickUp, value)
            }
        }
        
        if let rightThumbstick = profile.dpads[GCInputRightThumbstick]
        {
            rightThumbstick.xAxis.valueChangedHandler = { (axis, value) in
                thumbstickChangedHandler(.rightThumbstickLeft, .rightThumbstickRight, value)
            }
            rightThumbstick.yAxis.valueChangedHandler = { (axis, value) in
                thumbstickChangedHandler(.rightThumbstickDown, .rightThumbstickUp, value)
            }
        }
        
        // Touchpad 1/2 are finger positions (direction pads). Same axis range as a thumbstick: -1...1, positive Y is up.
        if let touchpad = profile.dpads[GCInputDualShockTouchpadOne]
        {
            touchpad.xAxis.valueChangedHandler = { (axis, value) in
                thumbstickChangedHandler(.leftThumbstickLeft, .leftThumbstickRight, value)
            }
            touchpad.yAxis.valueChangedHandler = { (axis, value) in
                thumbstickChangedHandler(.leftThumbstickDown, .leftThumbstickUp, value)
            }
        }
        
        if let touchpad = profile.dpads[GCInputDualShockTouchpadTwo]
        {
            touchpad.xAxis.valueChangedHandler = { (axis, value) in
                thumbstickChangedHandler(.rightThumbstickLeft, .rightThumbstickRight, value)
            }
            touchpad.yAxis.valueChangedHandler = { (axis, value) in
                thumbstickChangedHandler(.rightThumbstickDown, .rightThumbstickUp, value)
            }
        }
        
        let productCategory = ProductCategory(rawValue: self.controller.productCategory)
        switch productCategory
        {
        case .mfi:
            // MFi controllers typically only have one Menu button, so no need to re-map it.
            // menuButton?.pressedChangedHandler = { (button, value, pressed) in inputChangedHandler(.menu, pressed) }
            break
            
        case .joyConL, .joyConR:
            // Rotate single Joy-Con inputs 90º
            profile.buttons[GCInputButtonA]?.pressedChangedHandler = { (button, value, pressed) in inputChangedHandler(.b, pressed) }
            profile.buttons[GCInputButtonB]?.pressedChangedHandler = { (button, value, pressed) in inputChangedHandler(.y, pressed) }
            profile.buttons[GCInputButtonX]?.pressedChangedHandler = { (button, value, pressed) in inputChangedHandler(.a, pressed) }
            profile.buttons[GCInputButtonY]?.pressedChangedHandler = { (button, value, pressed) in inputChangedHandler(.x, pressed) }
            
            // For some reason, iOS treats the analog stick as a digital dPad input (as of iOS 16.3).
            // Re-map to .leftThumbstick instead to work as expected with N64 games.
            guard let dPad = profile.dpads[GCInputDirectionPad] else { break }
            dPad.xAxis.valueChangedHandler = { (axis, value) in
                thumbstickChangedHandler(.leftThumbstickLeft, .leftThumbstickRight, value)
            }
            dPad.yAxis.valueChangedHandler = { (axis, value) in
                thumbstickChangedHandler(.leftThumbstickDown, .leftThumbstickUp, value)
            }
            
            // Remove existing dPad change handlers to avoid duplicate inputs.
            dPad.up.pressedChangedHandler = nil
            dPad.down.pressedChangedHandler = nil
            dPad.left.pressedChangedHandler = nil
            dPad.right.pressedChangedHandler = nil
            
        case .switchOnlineNES, .switchOnlineSNES:
            guard var defaultMapping = self.defaultInputMapping as? GameControllerInputMapping else { break }
            
            // Re-map ZL and ZR buttons to Menu so we can treat Start as regular input.
            if productCategory == .switchOnlineNES
            {
                defaultMapping.set(StandardGameControllerInput.menu, forControllerInput: Input.leftShoulder)
                defaultMapping.set(StandardGameControllerInput.menu, forControllerInput: Input.rightShoulder)
            }
            else
            {
                defaultMapping.set(StandardGameControllerInput.menu, forControllerInput: Input.leftTrigger)
                defaultMapping.set(StandardGameControllerInput.menu, forControllerInput: Input.rightTrigger)
            }
            
            self.defaultInputMapping = defaultMapping
            
            // Re-map Start button to...Start
            menuButton?.pressedChangedHandler = { (button, value, pressed) in inputChangedHandler(.start, pressed) }
                        
        default:
            // Home = Home/"Logo" button
            guard let homeButton = profile.buttons[GCInputButtonHome] else { break }
            
            // If controller has Home button, and isn't MFi controller, treat it as Menu button instead.
            // e.g. Switch Pro, PlayStation, and Xbox controllers
            homeButton.pressedChangedHandler = { (button, value, pressed) in inputChangedHandler(.menu, pressed) }
            
            // Disable "Show Game Center" gesture
            homeButton.preferredSystemGestureState = .disabled
            
            // Re-map Menu button to Start
            menuButton?.pressedChangedHandler = { (button, value, pressed) in inputChangedHandler(.start, pressed) }
        }
        
        #if os(tvOS)
        if self.isSiriRemote, let microGamepad = self.controller.microGamepad
        {
            self.configureSiriRemote(microGamepad, inputChangedHandler: inputChangedHandler)
        }
        #endif
    }
}

#if os(tvOS)
extension MFiGameController
{
    /// The Siri Remote only has a micro gamepad profile (no extended gamepad).
    public var isSiriRemote: Bool {
        return self.controller.extendedGamepad == nil && self.controller.microGamepad != nil && self.controller.productCategory.contains("Remote")
    }
    
    /// Click uses the finger's position: rim is a direction, center is A. A swipe is a separate direction.
    /// Play/Pause is B. The TV button is Menu. Another gamepad does not disable the remote.
    private func configureSiriRemote(_ microGamepad: GCMicroGamepad, inputChangedHandler: @escaping (MFiGameController.Input, Bool) -> Void)
    {
        
        // Absolute position is where the finger is resting. The digital d-pad buttons are not used.
        microGamepad.reportsAbsoluteDpadValues = true
        microGamepad.allowsRotation = true
        
        let profile = self.controller.physicalInputProfile
        [GCInputButtonA, GCInputButtonB, GCInputButtonX, GCInputButtonY, GCInputButtonMenu].forEach { profile.buttons[$0]?.pressedChangedHandler = nil }
        if let dPad = profile.dpads[GCInputDirectionPad]
        {
            [dPad.up, dPad.down, dPad.left, dPad.right].forEach { $0.pressedChangedHandler = nil }
            dPad.xAxis.valueChangedHandler = nil
            dPad.yAxis.valueChangedHandler = nil
        }
        
        profile.buttons[GCInputDirectionalCenterButton]?.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.siriCenterHeld = pressed
            if pressed { self?.cancelSiriSwipe(inputChangedHandler) }
            inputChangedHandler(.a, pressed)
        }
        
        if let dPad = profile.dpads[GCInputDirectionalCardinalDpad] {
            let bind: (Input, GCControllerButtonInput) -> Void = { [weak self] input, button in
                button.pressedChangedHandler = {[weak self] _, _, pressed in
                    if pressed {
                        self?.siriCardinalHeld = true
                        self?.cancelSiriSwipe(inputChangedHandler)
                    } else {
                        self?.siriCardinalHeld = false
                    }
                    inputChangedHandler(input, pressed)
                }
            }
            bind(.up, dPad.up)
            bind(.down, dPad.down)
            bind(.left, dPad.left)
            bind(.right, dPad.right)
        }
        
        let track: (Float, Bool) -> Void = { [weak self] value, isX in
            if isX { self?.siriTouchX = value } else { self?.siriTouchY = value }
            self?.trackSiriTouch(inputChangedHandler)
        }
        
        if let dPad = profile.dpads[GCInputDirectionalDpad] {
            dPad.up.pressedChangedHandler = nil
            dPad.down.pressedChangedHandler = nil
            dPad.left.pressedChangedHandler = nil
            dPad.right.pressedChangedHandler = nil
            dPad.xAxis.valueChangedHandler = { _, value in track(value, true) }
            dPad.yAxis.valueChangedHandler = { _, value in track(value, false) }
        }
        
        microGamepad.buttonX.pressedChangedHandler = { _, _, pressed in
            inputChangedHandler(.start, pressed)
        }
        // Siri Remote Menu is UIPress-only (see ManicApplication.sendEvent). Do not bind
        // buttonMenu — it rarely fires and would duplicate Menu if it ever did.
    }
    
    /// Remember the finger. A swipe is movement after the finger has landed; the initial contact is not one.
    private func trackSiriTouch(_ inputChangedHandler: (Input, Bool) -> Void)
    {
        let idle: Float = 0.08
        if abs(siriTouchX) < idle, abs(siriTouchY) < idle
        {
            if let swipe = siriSwipeDirection
            {
                siriSwipeDirection = nil
                inputChangedHandler(swipe, false)
            }
            siriGestureActive = false
            siriTouchSettled = false
            if let armed = siriArmedSwipe {
                siriArmedSwipe = nil
                // Not committed yet, and the finger is gone, so the click-cancel window has passed.
                // One press and release: FocusKit moves on press only.
                if !siriSuppressSwipe {
                    inputChangedHandler(armed, true)
                    inputChangedHandler(armed, false)
                }
            }
            siriPeakDX = 0
            siriPeakDY = 0
            siriSuppressSwipe = false
            return
        }
        if !siriGestureActive
        {
            siriGestureActive = true
            siriTouchSettled = false
            siriGestureStart = Date().timeIntervalSinceReferenceDate
            siriOriginX = siriTouchX
            siriOriginY = siriTouchY
            siriLastX = siriTouchX
            siriLastY = siriTouchY
            siriPeakDX = 0
            siriPeakDY = 0
            return
        }
        let stepX = siriTouchX - siriLastX
        let stepY = siriTouchY - siriLastY
        siriLastX = siriTouchX
        siriLastY = siriTouchY
        let travelX = siriTouchX - siriOriginX
        let travelY = siriTouchY - siriOriginY
        if abs(travelX) + abs(travelY) > abs(siriPeakDX) + abs(siriPeakDY) {
            siriPeakDX = travelX
            siriPeakDY = travelY
        }
        if !siriTouchSettled
        {
            let step = max(abs(stepX), abs(stepY))
            let elapsed = Date().timeIntervalSinceReferenceDate - siriGestureStart
            if step < 0.12
            {
                // Finger stopped. Later travel is measured from here, so a resting touch is not a swipe.
                siriTouchSettled = true
                siriOriginX = siriTouchX
                siriOriginY = siriTouchY
                // Landing travel is not a swipe. Measure only what happens after the finger rests.
                siriPeakDX = 0
                siriPeakDY = 0
            }
            else if elapsed > 0.1
            {
                // Still moving well after contact: this is a swipe, measured from where it began.
                siriTouchSettled = true
            }
            else
            {
                return
            }
        }
        guard !siriSuppressSwipe, !siriCardinalHeld, !siriCenterHeld, siriSwipeDirection == nil else { return }
        let dx = siriTouchX - siriOriginX
        let dy = siriTouchY - siriOriginY
        if siriArmedSwipe == nil
        {
            guard let direction = siriSwipeDirection(dx: dx, dy: dy) else { return }
            // A rim click often lands with a small travel. Hold the swipe for a beat so that a
            // follow-up physical press (which reports on a separate channel) can cancel it first.
            siriArmedSwipe = direction
            siriArmedAt = Date().timeIntervalSinceReferenceDate
            return
        }
        guard Date().timeIntervalSinceReferenceDate - siriArmedAt >= 0.24 else { return }
        siriSwipeDirection = siriArmedSwipe
        siriArmedSwipe = nil
        if let direction = siriSwipeDirection
        {
            inputChangedHandler(direction, true)
        }
    }
    
    /// A center or rim click wins over a swipe from the same gesture. Hard-resets the gesture state
    /// so the ongoing touch can't be re-interpreted as a swipe while the button is held.
    private func cancelSiriSwipe(_ inputChangedHandler: (Input, Bool) -> Void)
    {
        siriSuppressSwipe = true
        siriArmedSwipe = nil
        // Reset the gesture state machine so a rim press is never followed by a spurious swipe.
        siriGestureActive = false
        siriTouchSettled = false
        siriPeakDX = 0
        siriPeakDY = 0
        guard let swipe = siriSwipeDirection else { return }
        siriSwipeDirection = nil
        inputChangedHandler(swipe, false)
    }

    /// A short fast flick or a longer slow drag. Distance is from the settled contact point, not from the pad center.
    private func siriSwipeDirection(dx: Float, dy: Float) -> Input?
    {
        let ax = abs(dx)
        let ay = abs(dy)
        let distance = max(ax, ay)
        let elapsed = max(Date().timeIntervalSinceReferenceDate - siriGestureStart, 0.016)
        let velocity = Double(distance) / elapsed
        // Inner flick: a small travel at high speed. Slow drag: a little more travel, any speed.
        guard distance >= 0.28 || (distance >= 0.12 && velocity >= 1.1) else { return nil }
        if ax >= ay
        {
            return dx >= 0 ? .right : .left
        }
        return dy >= 0 ? .up : .down
    }
}
#endif
