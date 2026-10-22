//
//  ControllerSkinTraits.swift
//  DeltaCore
//
//  Created by Riley Testut on 7/4/16.
//  Copyright © 2016 Riley Testut. All rights reserved.
//

import UIKit

var isPhoneDuo: Bool {
    var isPhoneDuo = false
#if targetEnvironment(simulator)
    isPhoneDuo = ProcessInfo().environment["SIMULATOR_MODEL_IDENTIFIER"]! == "iPhone19,4"
#else
    var systemInfo = utsname()
    uname(&systemInfo)
    
    let versionCode: String = String(validatingUTF8: NSString(bytes: &systemInfo.machine, length: Int(_SYS_NAMELEN), encoding: String.Encoding.ascii.rawValue)!.utf8String!)!
    isPhoneDuo = versionCode == "iPhone19,4"
#endif
    return isPhoneDuo
}

var isPhoneDuoOuter: Bool {
    guard isPhoneDuo else { return false }
    let screenBounds = UIScreen.main.bounds
    let screenHeight: Double = max(screenBounds.width, screenBounds.height)
    return screenHeight == 678
}

var isPhoneDuoInner: Bool {
    guard isPhoneDuo else { return false }
    let screenBounds = UIScreen.main.bounds
    let screenHeight: Double = max(screenBounds.width, screenBounds.height)
    return screenHeight == 951
}

var isPhoneDuoSplitView: Bool {
    guard isPhoneDuoInner else { return false }
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first { $0.activationState == .foregroundActive && $0.session.role == .windowApplication } ?? scenes.first
    if let window = scene?.keyWindow {
        return !window.screen.bounds.equalTo(UIScreen.main.bounds)
    }
    return false
}

extension ControllerSkin
{
    public enum Device: String, CaseIterable
    {
        // Naming conventions? I treat the "P" as the capital letter, so since it's a value (not a type) I've opted to lowercase it
        case iphone
        case ipad
        case tv
    }

    public enum DisplayType: String, CaseIterable
    {
        case standard
        case edgeToEdge
        case splitView
        case duo
    }

    public enum Orientation: String, CaseIterable
    {
        case portrait
        case landscape
    }
    
    public enum Size: String
    {
        case small
        case medium
        case large
    }
    
    public struct Traits: Hashable, CustomStringConvertible
    {
        public var device: Device
        public var displayType: DisplayType
        public var orientation: Orientation
        
        /// CustomStringConvertible
        public var description: String {
            return self.device.rawValue + "-" + self.displayType.rawValue + "-" + self.orientation.rawValue
        }
        
        public init(device: Device, displayType: DisplayType, orientation: Orientation)
        {
            self.device = device
            self.displayType = displayType
            self.orientation = orientation
        }
        
        public static func defaults(for window: UIWindow) -> ControllerSkin.Traits
        {
            let device: Device
            let displayType: DisplayType
            let orientation: Orientation
            
            if let scene = window.windowScene, scene.session.role == .windowExternalDisplay
            {
                //TODO: Support .portrait TV skins
                device = .tv
                displayType = .standard
                orientation = .landscape
            }
            else
            {
                // Use trait collection to determine device because our container app may be containing us in an "iPhone" trait collection despite being on iPad
                // 99% of the time, won't make a difference ¯\_(ツ)_/¯
                if window.traitCollection.userInterfaceIdiom == .pad
                {
                    device = .ipad
                    displayType = .standard
                    orientation = window.bounds.width/window.bounds.height > 1.333 ? .landscape : .portrait
                    //manic doesn't support iPad's Split View
                    
//                    if window.isKeyboardWindow
//                    {
//                        displayType = .splitView
//                        
//                        // Screen bounds may be incorrect when entering background, but keyboard window bounds is full screen and always accurate, so use window bounds instead.
//                        orientation = (window.bounds.width > window.bounds.height) ? .landscape : .portrait
//                    }
//                    else if !window.bounds.equalTo(window.screen.bounds)
//                    {
//                        displayType = .splitView
//                        
//                        // Use screen bounds because in split view window bounds might be portrait, but device is actually landscape (and we want landscape skin).
//                        orientation = (window.screen.bounds.width > window.screen.bounds.height) ? .landscape : .portrait
//                    }
//                    else
//                    {
//                        displayType = .standard
//                        orientation = (window.bounds.width > window.bounds.height) ? .landscape : .portrait
//                    }
                }
                else
                {
                    device = .iphone
                    displayType = isPhoneDuo ? .duo : (window.safeAreaInsets.bottom != 0) ? .edgeToEdge : .standard
                    orientation = (window.bounds.width > window.bounds.height) ? .landscape : .portrait
                }
            }            
            
            let traits = ControllerSkin.Traits(device: device, displayType: displayType, orientation: orientation)
            return traits
        }
    }
}
