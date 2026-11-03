import XCTest
import CoreGraphics
@testable import HopusCore

final class ImageFFmpegQualityRangeTests: XCTestCase {
    /// WebP is encoded by FFmpeg. Its quality must use the same 0.01...1 range as the
    /// ImageIO formats; a huge CLI value used to trap while building the arguments.
    func testWebPQualityOutsideZeroToOneIsClampedLikeImageIOFormats() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("HopusWebPQuality-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let previous = ProcessInfo.processInfo.environment["HOPUS_FFMPEG"]
        defer {
            try? FileManager.default.removeItem(at: dir)
            if let previous { setenv("HOPUS_FFMPEG", previous, 1) } else { unsetenv("HOPUS_FFMPEG") }
        }
        let log = dir.appendingPathComponent("arguments.txt"), fake = dir.appendingPathComponent("ffmpeg")
        try "#!/bin/sh\nprintf '%s\\n' \"$@\" > '\(log.path)'\nexit 1\n".write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        setenv("HOPUS_FFMPEG", fake.path, 1)
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        for (quality, expected) in [(1e300, "100"), (1.5, "100"), (-5, "1"), (0.8, "80")] {
            try? FileManager.default.removeItem(at: log)
            XCTAssertThrowsError(try ImageEngine.write(image, to: dir.appendingPathComponent("\(UUID().uuidString).webp"), quality: quality))
            let arguments = try String(contentsOf: log, encoding: .utf8).split(separator: "\n").map(String.init)
            let index = try XCTUnwrap(arguments.firstIndex(of: "-quality"))
            XCTAssertEqual(arguments[index + 1], expected, "quality \(quality)")
        }
    }
}
