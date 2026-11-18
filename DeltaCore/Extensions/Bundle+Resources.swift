//
//  Bundle+Resources.swift
//  DeltaCore
//
//  Created by Riley Testut on 2/3/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

extension Bundle
{
    class var resources: Bundle {
        #if FRAMEWORK
        let bundle = Bundle(for: RingBuffer.self)
        #elseif SWIFT_PACKAGE
        let bundle: Bundle
        #if os(tvOS)
        // Shipped resources live in the app bundle, not in an unpacked System.bundle.
        let systemTV = Bundle.main.bundleURL.appendingPathComponent("SystemTV", isDirectory: true)
        bundle = Bundle(url: systemTV) ?? .main
        #else
        if let library = NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true).first {
            bundle = Bundle(url: URL(fileURLWithPath: library + "/System.bundle"))!
        }
        else
        {
            bundle = .main
        }
        #endif
        #elseif STATIC_LIBRARY
        let bundle: Bundle
        if let bundleURL = Bundle.main.url(forResource: "DeltaCore", withExtension: "bundle")
        {
            bundle = Bundle(url: bundleURL)!
        }
        else
        {
            bundle = .main
        }
        #else
        let bundle = Bundle.main
        #endif
        
        return bundle
    }
}
