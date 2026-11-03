import AppKit

/// Shared vector artwork: the app, menu bar, installer icon and brand exports
/// all draw the same orange, stem and leaf.
enum NashiArtwork {
    static let gold=NSColor(srgbRed:0.95,green:0.45,blue:0.08,alpha:1)
    static let ink=NSColor(srgbRed:0.36,green:0.14,blue:0.03,alpha:1)
    static func bodyPath()->CGPath {
        let p=CGMutablePath()
        p.addEllipse(in:CGRect(x:0.14,y:0.22,width:0.72,height:0.70))
        return p
    }
    static func leafPath()->CGPath {
        let p=CGMutablePath();p.move(to:CGPoint(x:0.52,y:0.24))
        p.addCurve(to:CGPoint(x:0.84,y:0.07),control1:CGPoint(x:0.64,y:0.08),control2:CGPoint(x:0.78,y:0.01))
        p.addCurve(to:CGPoint(x:0.52,y:0.24),control1:CGPoint(x:0.72,y:0.18),control2:CGPoint(x:0.60,y:0.26));p.closeSubpath();return p
    }
    static func draw(in rect:NSRect,happy:Bool=false,monochrome:Bool=false) {
        guard let c=NSGraphicsContext.current?.cgContext else { return }
        c.saveGState();defer{c.restoreGState()}
        c.translateBy(x:rect.minX,y:rect.maxY);c.scaleBy(x:rect.width,y:-rect.height)
        let stem=NSColor(srgbRed:0.45,green:0.28,blue:0.12,alpha:1)
        if monochrome {
            c.setFillColor(NSColor.black.cgColor);c.addPath(bodyPath());c.fillPath();c.addPath(leafPath());c.fillPath()
            c.setStrokeColor(NSColor.black.cgColor);c.setLineWidth(0.035);c.setLineCap(.round)
            c.move(to:CGPoint(x:0.50,y:0.24));c.addQuadCurve(to:CGPoint(x:0.46,y:0.08),control:CGPoint(x:0.44,y:0.15));c.strokePath()
            c.setLineWidth(0.012);c.strokeEllipse(in:CGRect(x:0.45,y:0.78,width:0.10,height:0.07))
        } else {
            c.saveGState();c.addPath(bodyPath());c.clip()
            let colors=[NSColor(srgbRed:1.0,green:0.72,blue:0.28,alpha:1).cgColor,NSColor(srgbRed:0.93,green:0.38,blue:0.05,alpha:1).cgColor,NSColor(srgbRed:0.78,green:0.24,blue:0.02,alpha:1).cgColor] as CFArray
            let gradient=CGGradient(colorsSpace:CGColorSpace(name:CGColorSpace.sRGB),colors:colors,locations:[0,0.55,1])!
            c.drawLinearGradient(gradient,start:CGPoint(x:0.22,y:0.28),end:CGPoint(x:0.82,y:0.92),options:[.drawsBeforeStartLocation,.drawsAfterEndLocation]);c.restoreGState()
            c.setFillColor(NSColor(srgbRed:0.24,green:0.58,blue:0.22,alpha:1).cgColor);c.addPath(leafPath());c.fillPath()
            c.setStrokeColor(stem.cgColor);c.setLineWidth(0.04);c.setLineCap(.round)
            c.move(to:CGPoint(x:0.50,y:0.24));c.addQuadCurve(to:CGPoint(x:0.46,y:0.07),control:CGPoint(x:0.43,y:0.14));c.strokePath()
            c.setFillColor(NSColor.white.withAlphaComponent(0.38).cgColor);c.fillEllipse(in:CGRect(x:0.26,y:0.34,width:0.16,height:0.22))
            c.setFillColor(ink.withAlphaComponent(0.22).cgColor)
            for point in [CGPoint(x:0.30,y:0.48),CGPoint(x:0.62,y:0.40),CGPoint(x:0.40,y:0.70),CGPoint(x:0.70,y:0.62),CGPoint(x:0.24,y:0.62),CGPoint(x:0.74,y:0.48),CGPoint(x:0.52,y:0.78),CGPoint(x:0.34,y:0.36),CGPoint(x:0.58,y:0.58)] { c.fillEllipse(in:CGRect(x:point.x,y:point.y,width:0.018,height:0.018)) }
            c.setStrokeColor(NSColor(srgbRed:0.55,green:0.20,blue:0.04,alpha:1).cgColor);c.setLineWidth(0.012);c.strokeEllipse(in:CGRect(x:0.45,y:0.78,width:0.10,height:0.07))
            if happy {
                c.setFillColor(ink.cgColor)
                for x:CGFloat in [0.38,0.56] { c.fillEllipse(in:CGRect(x:x,y:0.50,width:0.055,height:0.055)) }
                c.setStrokeColor(ink.cgColor);c.setLineWidth(0.028);c.setLineCap(.round)
                c.move(to:CGPoint(x:0.40,y:0.64));c.addQuadCurve(to:CGPoint(x:0.60,y:0.64),control:CGPoint(x:0.50,y:0.74));c.strokePath()
            }
        }
    }
    static func mark(size:CGFloat,happy:Bool=false)->NSImage {
        NSImage(size:NSSize(width:size,height:size),flipped:false) { rect in draw(in:rect,happy:happy);return true }
    }
    static func menuIcon(updateAvailable:Bool=false)->NSImage {
        let image=NSImage(size:NSSize(width:20,height:20),flipped:false) { rect in
            draw(in:rect.insetBy(dx:0.5,dy:0.5),monochrome:true)
            if updateAvailable { NSColor.black.setFill();NSBezierPath(ovalIn:NSRect(x:15,y:15,width:4,height:4)).fill() }
            return true
        }
        image.isTemplate=true;image.accessibilityDescription=updateAvailable ? "Hopus update available":"Hopus";return image
    }
}
