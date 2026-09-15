//
//  KeyboardGameController.swift
//  DeltaCore
//
//  Created by Riley Testut on 6/14/18.
//  Copyright © 2018 Riley Testut. All rights reserved.
//

import UIKit
import GameController

public extension GameControllerInputType
{
    static let keyboard = GameControllerInputType("keyboard")
}

extension KeyboardGameController
{
    public struct Input: Hashable, RawRepresentable, Codable
    {
        public let rawValue: String
        
        public init(rawValue: String)
        {
            self.rawValue = rawValue
        }
        
        public init(_ rawValue: String)
        {
            self.rawValue = rawValue
        }
    }
}

extension KeyboardGameController.Input: Input
{
    public var type: InputType {
        return .controller(.keyboard)
    }
    
    public init(stringValue: String)
    {
        self.init(rawValue: stringValue)
    }
}

public extension KeyboardGameController.Input
{
    static let up = KeyboardGameController.Input("up")
    static let down = KeyboardGameController.Input("down")
    static let left = KeyboardGameController.Input("left")
    static let right = KeyboardGameController.Input("right")
    
    static let escape = KeyboardGameController.Input("escape")
    
    static let shift = KeyboardGameController.Input("shift")
    static let command = KeyboardGameController.Input("command")
    static let option = KeyboardGameController.Input("option")
    static let control = KeyboardGameController.Input("control")
    static let capsLock = KeyboardGameController.Input("capslock")
    
    static let space = KeyboardGameController.Input("space")
    static let `return` = KeyboardGameController.Input("return")
    static let tab = KeyboardGameController.Input("tab")
}

public class KeyboardGameController: UIResponder, GameController
{
    public var name: String {
        return NSLocalizedString("Keyboard", comment: "")
    }
    
    public var playerIndex: Int?
    
    public let inputType: GameControllerInputType = .keyboard
    
    public private(set) lazy var defaultInputMapping: GameControllerInputMappingProtocol? = {
        guard let fileURL = Bundle.resources.url(forResource: "KeyboardGameController", withExtension: "keymapping") else {
            fatalError("KeyboardGameController.deltamapping does not exist.")
        }
        
        do
        {
            let inputMapping = try GameControllerInputMapping(fileURL: fileURL)
            return inputMapping
        }
        catch
        {
            print(error)
            
            fatalError("KeyboardGameController.deltamapping does not exist.")
        }
    }()
    
    // When non-nil, uses modern keyboard handling.
    private let keyboard: GCKeyboard?
    
    public var keyboardPress: ((_ key: String)->Void)? = nil
    
    public init(keyboard: GCKeyboard?)
    {
        self.keyboard = keyboard
        
        super.init()
        
        self.keyboard?.keyboardInput?.keyChangedHandler = { [weak self] (profile, buttonInput, keyCode, isActive) in
            // Copy HID values on the callback thread; GCKeyboard has no handlerQueue.
            let buttonDescription = buttonInput.description
            ExternalInputDispatch.async {
                self?.handleKeyChanged(keyCode: keyCode, isActive: isActive, buttonDescription: buttonDescription)
            }
        }
    }
    
    /// Names match `LibretroKeyboardCode` labels / `RETROK_*`. Keys without a RETROK counterpart are ignored.
    private func handleKeyChanged(keyCode: GCKeyCode, isActive: Bool, buttonDescription: String)
    {
        // Scenarios where DOS or other systems handle hardware keyboards directly will turn off this switch;
        // allow the release event to pass through to prevent keys from getting stuck in the active state.
        if isActive, !ExternalGameControllerManager.shared.isKeyboardInputEnabled { return }
        
        let input: Input
        
        switch keyCode
        {
        case .upArrow: input = .up
        case .downArrow: input = .down
        case .leftArrow: input = .left
        case .rightArrow: input = .right
            
        case .escape: input = .escape
            
        case .leftShift: input = .init("lshift")
        case .rightShift: input = .init("rshift")
        case .leftGUI: input = .init("lmeta")
        case .rightGUI: input = .init("rmeta")
        case .leftAlt: input = .init("lalt")
        case .rightAlt: input = .init("ralt")
        case .leftControl: input = .init("lctrl")
        case .rightControl: input = .init("rctrl")
        case .capsLock: input = .capsLock
            
        case .spacebar: input = .space
        case .returnOrEnter: input = .return
        case .keypadEnter: input = .init("kpenter")
        case .tab: input = .tab
        case .deleteOrBackspace: input = .init("backspace")
        case .deleteForward: input = .init("delete")
            
        case .comma: input = .init("comma")
        case .period: input = .init("period")
        case .slash: input = .init("slash")
        case .semicolon: input = .init("semicolon")
        case .quote: input = .init("quote")
        case .openBracket: input = .init("leftbracket")
        case .closeBracket: input = .init("rightbracket")
        case .backslash: input = .init("backslash")
        case .nonUSBackslash: input = .init("oem102")
        case .hyphen: input = .init("minus")
        case .equalSign: input = .init("equals")
        case .graveAccentAndTilde: input = .init("backquote")
            
        case .F1: input = .init("f1")
        case .F2: input = .init("f2")
        case .F3: input = .init("f3")
        case .F4: input = .init("f4")
        case .F5: input = .init("f5")
        case .F6: input = .init("f6")
        case .F7: input = .init("f7")
        case .F8: input = .init("f8")
        case .F9: input = .init("f9")
        case .F10: input = .init("f10")
        case .F11: input = .init("f11")
        case .F12: input = .init("f12")
        case .F13: input = .init("f13")
        case .F14: input = .init("f14")
        case .F15: input = .init("f15")
            
        case .insert: input = .init("insert")
        case .home: input = .init("home")
        case .end: input = .init("end")
        case .pageUp: input = .init("pageup")
        case .pageDown: input = .init("pagedown")
        case .printScreen: input = .init("print")
        case .scrollLock: input = .init("scrolllock")
        case .pause: input = .init("pause")
        case .keypadNumLock: input = .init("numlock")
            
        case .keypadPlus: input = .init("kpplus")
        case .keypadAsterisk: input = .init("kpmultiply")
        case .keypadHyphen: input = .init("kpminus")
        case .keypadSlash: input = .init("kpdivide")
        case .keypadPeriod: input = .init("kpperiod")
        case .keypadEqualSign: input = .init("kpequals")
        case .keypad1: input = .init("kp1")
        case .keypad2: input = .init("kp2")
        case .keypad3: input = .init("kp3")
        case .keypad4: input = .init("kp4")
        case .keypad5: input = .init("kp5")
        case .keypad6: input = .init("kp6")
        case .keypad7: input = .init("kp7")
        case .keypad8: input = .init("kp8")
        case .keypad9: input = .init("kp9")
        case .keypad0: input = .init("kp0")
            
        case .one: input = .init("1")
        case .two: input = .init("2")
        case .three: input = .init("3")
        case .four: input = .init("4")
        case .five: input = .init("5")
        case .six: input = .init("6")
        case .seven: input = .init("7")
        case .eight: input = .init("8")
        case .nine: input = .init("9")
        case .zero: input = .init("0")
            
        case .keyA: input = .init("a")
        case .keyB: input = .init("b")
        case .keyC: input = .init("c")
        case .keyD: input = .init("d")
        case .keyE: input = .init("e")
        case .keyF: input = .init("f")
        case .keyG: input = .init("g")
        case .keyH: input = .init("h")
        case .keyI: input = .init("i")
        case .keyJ: input = .init("j")
        case .keyK: input = .init("k")
        case .keyL: input = .init("l")
        case .keyM: input = .init("m")
        case .keyN: input = .init("n")
        case .keyO: input = .init("o")
        case .keyP: input = .init("p")
        case .keyQ: input = .init("q")
        case .keyR: input = .init("r")
        case .keyS: input = .init("s")
        case .keyT: input = .init("t")
        case .keyU: input = .init("u")
        case .keyV: input = .init("v")
        case .keyW: input = .init("w")
        case .keyX: input = .init("x")
        case .keyY: input = .init("y")
        case .keyZ: input = .init("z")
            
        default:
            // Catch-all for single-character keys.
            guard let key = buttonDescription.components(separatedBy: .whitespacesAndNewlines).first(where: { $0.count == 1 }) else { return }
            input = Input(stringValue: key.lowercased())
        }
        
        if isActive
        {
            // ControllerMappingView records keys from this callback.
            let keyName = input.stringValue
            ExternalInputDispatch.performOnMain { [weak self] in
                self?.keyboardPress?(keyName)
            }
            self.activate(input)
        }
        else
        {
            self.deactivate(input)
        }
    }
}

public extension KeyboardGameController
{
    override func keyPressesBegan(_ presses: Set<KeyPress>, with event: UIEvent)
    {
        // Ignore unless using legacy keyboard handling.
        guard self.keyboard == nil else { return }
        
        for press in presses
        {
            keyboardPress?(press.key)
            let input = Input(press.key)
            self.activate(input)
        }
    }
    
    override func keyPressesEnded(_ presses: Set<KeyPress>, with event: UIEvent)
    {
        // Ignore unless using legacy keyboard handling.
        guard self.keyboard == nil else { return }
        
        for press in presses
        {
            let input = Input(press.key)
            self.deactivate(input)
        }
    }
}
