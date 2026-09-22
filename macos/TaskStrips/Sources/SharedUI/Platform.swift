#if os(macOS)
import AppKit
#else
import UIKit
#endif
import CoreGraphics
import Foundation
import SwiftUI

/// The few things the shared screens need that AppKit and UIKit spell differently. Everything
/// else in SharedUI is plain SwiftUI; when a screen needs something that has no counterpart at
/// all (Show in Finder, say), it says so with #if where it's used rather than hiding it here.
enum Platform {
    static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    static func copy(_ image: CGImage) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([NSImage(cgImage: image, size: .zero)])
        #else
        UIPasteboard.general.image = UIImage(cgImage: image)
        #endif
    }

    /// A picture from a file on disk, or nil if it isn't one.
    static func image(contentsOf url: URL) -> Image? {
        #if os(macOS)
        NSImage(contentsOf: url).map(Image.init(nsImage:))
        #else
        UIImage(contentsOfFile: url.path).map(Image.init(uiImage:))
        #endif
    }

    /// Copies a file picked from outside the app. On iOS the picker hands back a URL that is only
    /// readable inside a security scope, and forgetting to open one fails as "file not found".
    static func withAccess<T>(to url: URL, _ body: (URL) throws -> T) rethrows -> T {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try body(url)
    }
}
