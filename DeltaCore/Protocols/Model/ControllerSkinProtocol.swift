//
//  ControllerSkinProtocol.swift
//  DeltaCore
//
//  Created by Riley Testut on 10/13/16.
//  Copyright © 2016 Riley Testut. All rights reserved.
//

import UIKit

public protocol ControllerSkinProtocol
{
    var name: String { get }
    var identifier: String { get }
    var gameType: GameType { get }
    var isDebugModeEnabled: Bool { get }
    
    func supports(_ traits: ControllerSkin.Traits) -> Bool
    
    func image(for traits: ControllerSkin.Traits, preferredSize: ControllerSkin.Size) -> UIImage?
    func thumbstick(for item: ControllerSkin.Item, traits: ControllerSkin.Traits, preferredSize: ControllerSkin.Size) -> (UIImage, CGSize)?
    
    func items(for traits: ControllerSkin.Traits) -> [ControllerSkin.Item]?
    
    func isTranslucent(for traits: ControllerSkin.Traits) -> Bool?
    
    func gameScreenFrame(for traits: ControllerSkin.Traits) -> CGRect?
    func screens(for traits: ControllerSkin.Traits) -> [ControllerSkin.Screen]?
    
    func aspectRatio(for traits: ControllerSkin.Traits) -> CGSize?
    func contentSize(for traits: ControllerSkin.Traits) -> CGSize?
    
    func menuInsets(for traits: ControllerSkin.Traits) -> UIEdgeInsets?
    
    func supportedTraits(for traits: ControllerSkin.Traits) -> ControllerSkin.Traits?
    
    func switchView(for item: ControllerSkin.Item, traits: ControllerSkin.Traits, onImageSize: CGSize, offImageSize: CGSize) -> (UIImage?, UIImage?)?
}

public extension ControllerSkinProtocol
{
    func supportedTraits(for traits: ControllerSkin.Traits) -> ControllerSkin.Traits?
    {
        let maximumFallbackAttempts = 10
        var numberOfAttempts = 0
        
        var traits = traits
        
        while !self.supports(traits)
        {
            numberOfAttempts += 1
            
            // Sanity check to ensure this never results in (1) Infinite Loop.
            guard numberOfAttempts <= maximumFallbackAttempts else {
                assertionFailure("ControllerSkinProtocol.supportedTraits(for:) reached max number of fallback attempts. This is most likely due to programmer error.")
                return nil
            }
            
            if traits.device == .iphone
            {
                switch traits.displayType
                {
                case .edgeToEdge:
                    // Fall back to standard representations from edgeToEdge.
                    traits.displayType = .standard
                    
                case .inner, .outer:
                    return self.duoFallbackTraits(for: traits)
                    
                case .splitView:
                    // Fall back to iPad split view
                    traits.device = .ipad
                    
                case .standard, .cover: return nil
                }
            }
            else if traits.device == .ipad
            {
                switch traits.displayType
                {
                case .standard, .edgeToEdge:
                    // Fall back to iPhone edgeToEdge skins (followed by standard skins, as handled above)
                    traits.device = .iphone
                    traits.displayType = .edgeToEdge
                    
                case .outer, .inner, .splitView, .cover: return nil
                }
            }
            else
            {
                return nil
            }
        }
        
        return traits
    }
    
    func gameScreenFrame(for traits: DeltaCore.ControllerSkin.Traits) -> CGRect?
    {
        return self.screens(for: traits)?.first?.outputFrame
    }
}

private extension ControllerSkinProtocol
{
    /// Fallback for iPhone Duo displays when the skin has no representation for them.
    /// Picks the supported iPad/iPhone representation
    /// that shows the largest game picture on the display, since skins differ a lot
    /// (e.g. small realistic consoles on iPad vs large screens on iPhone). Ties keep the earlier candidate.
    func duoFallbackTraits(for traits: ControllerSkin.Traits) -> ControllerSkin.Traits?
    {
        func candidate(_ device: ControllerSkin.Device, _ displayType: ControllerSkin.DisplayType) -> ControllerSkin.Traits
        {
            var candidate = traits
            candidate.device = device
            candidate.displayType = displayType
            return candidate
        }
        
        let candidates: [ControllerSkin.Traits]
        switch traits.displayType
        {
        case .inner:
            // Outer display representations have the same aspect ratio, so prefer them over everything else.
            let outer = candidate(.iphone, .outer)
            if self.supports(outer)
            {
                return outer
            }
            
            // Display is iPad-like, so try iPad first, then iPhone edgeToEdge and standard.
            candidates = [candidate(.ipad, .standard), candidate(.iphone, .edgeToEdge), candidate(.iphone, .standard)]
            
        case .outer:
            // iPhone-like, but very short so skip edgeToEdge.
            candidates = [candidate(.iphone, .standard), candidate(.ipad, .standard)]
            
        default: return nil
        }

        // Display sizes in points (portrait): inner 669x951, outer 466x678.
        let portraitSize = (traits.displayType == .inner) ? CGSize(width: 669, height: 951) : CGSize(width: 466, height: 678)
        let displaySize = (traits.orientation == .portrait) ? portraitSize : CGSize(width: portraitSize.height, height: portraitSize.width)
        
        var bestTraits: ControllerSkin.Traits?
        var bestArea: CGFloat = -1
        
        for candidate in candidates where self.supports(candidate)
        {
            let area = self.gameScreenArea(for: candidate, in: displaySize)
            if area > bestArea + 1
            {
                bestTraits = candidate
                bestArea = area
            }
        }
        
        return bestTraits
    }
    
    /// Total area of the skin's game screens after fitting the skin inside `displaySize`.
    func gameScreenArea(for traits: ControllerSkin.Traits, in displaySize: CGSize) -> CGFloat
    {
        guard let aspectRatio = self.aspectRatio(for: traits), aspectRatio.width > 0, aspectRatio.height > 0 else { return 0 }
        
        let scale = min(displaySize.width / aspectRatio.width, displaySize.height / aspectRatio.height)
        let skinSize = CGSize(width: aspectRatio.width * scale, height: aspectRatio.height * scale)
        
        let screens = self.screens(for: traits) ?? []
        return screens.reduce(0) { area, screen in
            // `app` placement screens are positioned by the app, not inside the skin.
            guard screen.placement == .controller, let frame = screen.outputFrame else { return area }
            return area + (frame.width * skinSize.width) * (frame.height * skinSize.height)
        }
    }
}

public func ==(lhs: ControllerSkinProtocol?, rhs: ControllerSkinProtocol?) -> Bool
{
    return lhs?.identifier == rhs?.identifier
}

public func !=(lhs: ControllerSkinProtocol?, rhs: ControllerSkinProtocol?) -> Bool
{
    return !(lhs == rhs)
}

public func ~=(pattern: ControllerSkinProtocol?, value: ControllerSkinProtocol?) -> Bool
{
    return pattern == value
}
