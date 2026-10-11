import AppKit
import ImageIO
import UniformTypeIdentifiers

/// An image waiting to go out with a prompt. The file lives in NotchGate's own
/// folder (a path without spaces) so Claude Code can read it from the prompt.
struct ImageAttachment: Identifiable, Equatable {
    let id: UUID
    let url: URL
    /// Small preview for the composer's thumbnail strip.
    let thumbnail: NSImage

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

/// Turns pasted, dropped or copied images into `ImageAttachment` files.
///
/// File URLs win over raw image data: Finder puts the file's icon on the
/// pasteboard too, and that icon is never what the user meant.
@MainActor
enum ImageIntake {
    /// Formats Claude reads as-is; anything else (HEIC, TIFF, BMP…) becomes PNG.
    static let passthroughExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp"]
    /// Attached files are kept this long so Claude can still open them later in the turn.
    static let retention: TimeInterval = 2 * 24 * 3600

    static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("NotchGate/Images", isDirectory: true)
    }

    private static let fileURLsOnly: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
    private static let imageFileURLs: [NSPasteboard.ReadingOptionKey: Any] = [
        .urlReadingFileURLsOnly: true,
        .urlReadingContentsConformToTypes: [UTType.image.identifier],
    ]

    /// Cheap check (nothing is read or written): does the pasteboard hold images?
    static func canRead(_ pasteboard: NSPasteboard) -> Bool {
        if pasteboard.canReadObject(forClasses: [NSURL.self], options: fileURLsOnly) {
            return pasteboard.canReadObject(forClasses: [NSURL.self], options: imageFileURLs)
        }
        return pasteboard.canReadItem(withDataConformingToTypes: [UTType.image.identifier])
    }

    /// Saves every image on the pasteboard, up to `limit`.
    static func attachments(from pasteboard: NSPasteboard, limit: Int = .max) -> [ImageAttachment] {
        guard limit > 0, canRead(pasteboard) else { return [] }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: imageFileURLs) as? [URL], !urls.isEmpty {
            return urls.prefix(limit).compactMap(importFile)
        }
        let images = pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage] ?? []
        return images.prefix(limit).compactMap(importImage)
    }

    /// Copies (or converts) an image file into the attachments folder.
    static func importFile(_ source: URL) -> ImageAttachment? {
        let name = sanitizedName(source.deletingPathExtension().lastPathComponent)
        let ext = source.pathExtension.lowercased()
        if passthroughExtensions.contains(ext) {
            guard let destination = prepareDestination(name: name, ext: ext == "jpeg" ? "jpg" : ext),
                  (try? FileManager.default.copyItem(at: source, to: destination)) != nil else { return nil }
            return attachment(at: destination)
        }
        guard let image = NSImage(contentsOf: source) else { return nil }
        return importImage(image, name: name)
    }

    /// Writes in-memory image data (a screenshot on the clipboard, an image
    /// dragged out of a browser) as PNG.
    static func importImage(_ image: NSImage) -> ImageAttachment? {
        importImage(image, name: "image")
    }

    /// Deletes attachments older than `retention`.
    static func purgeOld(now: Date = .now) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, now.timeIntervalSince(modified) > retention {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    // MARK: Private

    private static func importImage(_ image: NSImage, name: String) -> ImageAttachment? {
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]),
              let destination = prepareDestination(name: name, ext: "png"),
              (try? png.write(to: destination)) != nil else { return nil }
        return attachment(at: destination)
    }

    private static func attachment(at url: URL) -> ImageAttachment? {
        guard let thumbnail = makeThumbnail(url) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return ImageAttachment(id: UUID(), url: url, thumbnail: thumbnail)
    }

    /// A unique path in the attachments folder, e.g. `…/Images/3fa2c1-screenshot.png`.
    private static func prepareDestination(name: String, ext: String) -> URL? {
        guard (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil else {
            return nil
        }
        let prefix = UUID().uuidString.prefix(6).lowercased()
        return directory.appendingPathComponent("\(prefix)-\(name).\(ext)")
    }

    /// Keeps names readable for Claude but free of spaces and shell-special characters.
    static func sanitizedName(_ raw: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        let mapped = String(raw.map { allowed.contains($0) ? $0 : "-" })
        let collapsed = mapped.split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
        return collapsed.isEmpty ? "image" : String(collapsed.prefix(40))
    }

    private static func makeThumbnail(_ url: URL, maxPixels: Int = 120) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixels,
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
    }
}
