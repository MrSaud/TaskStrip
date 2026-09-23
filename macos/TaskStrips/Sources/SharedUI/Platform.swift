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
    /// "this Mac", "this iPhone" or "this iPad", for text that says where something lives.
    static var thisDevice: String {
        #if os(macOS)
        "this Mac"
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? "this iPad" : "this iPhone"
        #endif
    }

    /// "Click" or "Tap", for instructions that name the gesture.
    static var pointerVerb: String {
        #if os(macOS)
        "Click"
        #else
        "Tap"
        #endif
    }

    /// Where the user goes to allow notifications or the microphone.
    static var settingsApp: String {
        #if os(macOS)
        "System Settings"
        #else
        "Settings"
        #endif
    }

    /// Opens a link with whatever handles it — a browser, or Mail for a message a strip was
    /// filed from.
    static func open(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }

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

extension View {
    /// A Mac sheet or window's size. iOS sizes its own sheets to the screen, and a fixed width
    /// that suits a Mac window is wider than a phone.
    func macFrame(width: CGFloat? = nil, height: CGFloat? = nil) -> some View {
        #if os(macOS)
        frame(width: width, height: height)
        #else
        self
        #endif
    }

    func macFrame(minWidth: CGFloat, minHeight: CGFloat) -> some View {
        #if os(macOS)
        frame(minWidth: minWidth, minHeight: minHeight)
        #else
        self
        #endif
    }
}

extension View {
    /// Search that can be switched off, for a view that is only sometimes the one on screen. The
    /// Mac puts it in the toolbar, as it always has; iOS lets the navigation bar decide.
    @ViewBuilder
    func searchable(if enabled: Bool, text: Binding<String>, prompt: String) -> some View {
        if enabled {
            #if os(macOS)
            searchable(text: text, placement: .toolbar, prompt: prompt)
            #else
            searchable(text: text, prompt: prompt)
            #endif
        } else {
            self
        }
    }
}

extension View {
    /// A sheet on the Mac, full screen on iPhone and iPad — for the sketch canvas, where a sheet
    /// would take any downward stroke as a swipe to close it.
    func canvasPresentation<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(macOS)
        sheet(item: item, content: content)
        #else
        fullScreenCover(item: item, content: content)
        #endif
    }

    func canvasPresentation<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(macOS)
        sheet(isPresented: isPresented, content: content)
        #else
        fullScreenCover(isPresented: isPresented, content: content)
        #endif
    }
}
