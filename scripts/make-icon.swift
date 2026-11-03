import AppKit

@main struct MakeHopusIcon {
    static func main() throws {
        let output=URL(fileURLWithPath:CommandLine.arguments[1]);try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        func bitmap(_ width:Int,_ height:Int,_ draw:(NSRect)->Void)->NSBitmapImageRep {
            let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
            NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep);draw(NSRect(x:0,y:0,width:width,height:height));NSGraphicsContext.restoreGraphicsState();return rep
        }
        let source=NSImage(contentsOf:URL(fileURLWithPath:"Resources/Brand/HopusIcon.png")) ?? NSImage(size:NSSize(width:1024,height:1024))
        for happy in [false,true] { let mark=bitmap(256,256) { rect in source.draw(in:rect) };try mark.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(happy ? "HopusMarkHappy.png":"HopusMark.png")) }
        let icon=bitmap(1024,1024) { rect in source.draw(in:rect) }
        let png=icon.representation(using:.png,properties:[:])!;try png.write(to:output.appendingPathComponent("HopusIcon.png"))
        let iconset=output.appendingPathComponent("HopusIcon.iconset");try FileManager.default.createDirectory(at:iconset,withIntermediateDirectories:true)
        let image=NSImage(data:png)!
        for size in [16,32,128,256,512] { for factor in [1,2] {
            let pixels=size*factor;let rep=bitmap(pixels,pixels) { rect in NSGraphicsContext.current?.imageInterpolation = .high;image.draw(in:rect) }
            try rep.representation(using:.png,properties:[:])!.write(to:iconset.appendingPathComponent("icon_\(size)x\(size)\(factor==2 ? "@2x":"").png"))
        } }
        let banner=bitmap(1280,640) { rect in
            NSColor(srgbRed:0.992,green:0.965,blue:0.935,alpha:1).setFill();rect.fill()
            source.draw(in:NSRect(x:75,y:115,width:410,height:410))
            let font=NSFont.systemFont(ofSize:118,weight:.bold);let rounded=NSFont(descriptor:font.fontDescriptor.withDesign(.rounded)!,size:118)!
            ("Hopus" as NSString).draw(at:NSPoint(x:515,y:315),withAttributes:[.font:rounded,.foregroundColor:NSColor(srgbRed:0.55,green:0.20,blue:0.04,alpha:1)])
            ("Your files, a little brighter." as NSString).draw(at:NSPoint(x:523,y:265),withAttributes:[.font:NSFont.systemFont(ofSize:32,weight:.medium),.foregroundColor:NSColor(srgbRed:0.62,green:0.28,blue:0.08,alpha:1)])
            ("Convert. Edit. Organize. Download." as NSString).draw(at:NSPoint(x:523,y:208),withAttributes:[.font:NSFont.systemFont(ofSize:23),.foregroundColor:NSColor(srgbRed:0.45,green:0.28,blue:0.16,alpha:1)])
        }
        try banner.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("HopusSocial.png"))
        print(output.path)
    }
}
