import AppKit

/// The octopus mark used by the app icon, menu bar, and in-app logo.
enum HopusArtwork {
    static let gold=NSColor(srgbRed:0.95,green:0.45,blue:0.08,alpha:1)
    static let ink=NSColor(srgbRed:0.36,green:0.14,blue:0.03,alpha:1)
    private static let logo:NSImage={
        guard let url=Bundle.module.url(forResource:"HopusLogo",withExtension:"png"),let image=NSImage(contentsOf:url) else { return NSImage(size:NSSize(width:64,height:64)) }
        return image
    }()
    static func draw(in rect:NSRect,happy:Bool=false,monochrome:Bool=false) {
        logo.draw(in:rect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:[.interpolation:NSImageInterpolation.high])
    }
    static func mark(size:CGFloat,happy:Bool=false)->NSImage {
        NSImage(size:NSSize(width:size,height:size),flipped:false) { rect in draw(in:rect,happy:happy);return true }
    }
    static func menuIcon(updateAvailable:Bool=false)->NSImage {
        let image=NSImage(size:NSSize(width:18,height:18),flipped:false) { rect in
            draw(in:rect)
            if updateAvailable { NSColor.white.setFill();NSBezierPath(ovalIn:NSRect(x:12,y:12,width:6,height:6)).fill() }
            return true
        }
        image.isTemplate=false
        image.accessibilityDescription=updateAvailable ? "Hopus update available":"Hopus"
        return image
    }
}
