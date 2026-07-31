//
//  NativeGifView.swift
//  ShuoDesignSystem
//
//  Created by Matthew Sebastian Lesmana on 28/07/26.
//

import ImageIO
import SwiftUI
import UIKit

/// Plays a looping GIF from an asset-catalog data set.
///
/// **Decoding never happens on the main thread, and never twice for the same asset.**
/// The mascot loop is 165 frames at 1080×1080, and `UIImage.animatedImage(with:duration:)`
/// needs every one of them decoded up front. Doing that inline in `makeUIView` — which is
/// what this did — froze the main thread for the seconds it took, and a frozen main thread
/// is a frozen navigation bar: ‹ on the loading screen rendered as an empty glass capsule
/// until the decode finished, and taps aimed at it queued up and were delivered afterwards,
/// to whichever screen the first tap had already navigated to.
///
/// Decoded loops are shared through `GifImageLoader`, so the second and third loading
/// screen in a flow show it in the frame they appear, and the frames are evicted rather
/// than held when memory gets tight.
struct NativeGifView: UIViewRepresentable {
    let gifName: String

    func makeUIView(context _: Context) -> GifContainerView {
        let containerView = GifContainerView()
        containerView.load(gifName: gifName)
        return containerView
    }

    func updateUIView(_ uiView: GifContainerView, context _: Context) {
        uiView.load(gifName: gifName)
    }
}

/// Hosts the animating image view and owns the asynchronous load behind it.
final class GifContainerView: UIView {
    private let imageView = UIImageView()

    /// The asset this view has already asked for. SwiftUI calls `updateUIView` on every
    /// re-render, and re-requesting a 165-frame decode each time would replace the stall
    /// this class exists to remove with a slower one.
    private var requestedName: String?
    private var loadTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureHierarchy()
    }

    deinit {
        loadTask?.cancel()
    }

    override var intrinsicContentSize: CGSize {
        .zero
    }

    /// Shows `gifName`, decoding it off the main thread if it is not already in memory.
    func load(gifName: String) {
        guard requestedName != gifName else { return }
        requestedName = gifName
        loadTask?.cancel()

        // Already decoded — by an earlier screen, or by the prewarm the create flow kicks
        // off at the purpose step. Assign it now so the loop animates from its first frame
        // rather than blinking through an empty box.
        if let cached = GifImageLoader.cached(gifName) {
            show(cached)
            return
        }

        imageView.stopAnimating()
        imageView.image = nil

        loadTask = Task { [weak self] in
            let image = await GifImageLoader.image(gifName)
            guard !Task.isCancelled, let self, let image, requestedName == gifName else { return }
            show(image)
        }
    }

    private func show(_ image: UIImage) {
        imageView.image = image
        imageView.startAnimating()
    }

    private func configureHierarchy() {
        imageView.backgroundColor = .clear
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}

/// Decodes animated GIFs once and shares the result.
///
/// `@MainActor` for the bookkeeping only — the cache and the in-flight table are read and
/// written from view code, while the decode itself runs detached (CLAUDE.md §6). An
/// `NSCache` rather than a dictionary because the decoded loop is tens of megabytes of
/// bitmap: worth keeping while the flow is showing loading screens, not worth keeping
/// through a memory warning.
@MainActor
enum GifImageLoader {
    /// Longest edge frames are decoded to, in pixels. 480 is the 160 pt box `LoadingView`
    /// gives them at @3x — decoding the source's full 1080 px would cost time and memory
    /// for detail that is never shown.
    ///
    /// One value for every caller, not a parameter: the cache is keyed by asset name, so a
    /// second call at a different size would be served the first size's frames.
    private static let maxPixelSize = 480

    private static let cache = NSCache<NSString, UIImage>()

    /// One decode per asset, shared. Two loading screens overlap during the push from
    /// transcription into analysis, and both ask for the same loop in the same frame.
    private static var inFlight: [String: Task<UIImage?, Never>] = [:]

    /// The decoded loop, if it is already in memory.
    static func cached(_ name: String) -> UIImage? {
        cache.object(forKey: name as NSString)
    }

    /// Starts decoding `name` now so a screen that shows it later does not have to wait.
    ///
    /// Fire-and-forget, and cheap to call speculatively: already decoded or already
    /// decoding both return immediately. Runs at `.utility` rather than `.userInitiated` —
    /// nothing is waiting on it, and it must not compete with a live recording.
    static func prewarm(_ name: String) {
        guard cached(name) == nil, inFlight[name] == nil else { return }
        Task { _ = await image(name, priority: .utility) }
    }

    /// The decoded loop, decoding it off the main thread if needed. `nil` when the asset
    /// is missing or holds no decodable frames — the caller simply shows nothing, since a
    /// decorative loop is not worth an error state.
    static func image(_ name: String, priority: TaskPriority = .userInitiated) async -> UIImage? {
        if let cached = cached(name) {
            return cached
        }

        // Joins the prewarm rather than racing it, so a loading screen that appears
        // mid-decode waits for the frames already being produced.
        if let existing = inFlight[name] {
            return await existing.value
        }

        // Read before the hop: everything on this type is main-actor state, and the
        // decode deliberately runs where none of it is reachable.
        let pixelSize = maxPixelSize
        let task = Task.detached(priority: priority) {
            GifDecoder.decode(assetNamed: name, maxPixelSize: pixelSize)
        }
        inFlight[name] = task

        let image = await task.value
        inFlight[name] = nil
        if let image {
            cache.setObject(image, forKey: name as NSString)
        }
        return image
    }
}

/// Turns GIF data from the asset catalog into an animated `UIImage`.
///
/// Pure ImageIO work with no isolation of its own, so it can run wherever it is called
/// from — which is always off the main thread.
private enum GifDecoder {
    static func decode(assetNamed name: String, maxPixelSize: Int) -> UIImage? {
        guard
            let data = NSDataAsset(name: name, bundle: .main)?.data,
            let source = CGImageSourceCreateWithData(data as CFData, nil)
        else {
            return nil
        }

        let frames = frames(from: source, maxPixelSize: maxPixelSize)
        guard !frames.isEmpty else { return nil }

        return UIImage.animatedImage(with: frames, duration: duration(from: source))
    }

    private static func frames(from source: CGImageSource, maxPixelSize: Int) -> [UIImage] {
        (0 ..< CGImageSourceGetCount(source)).compactMap { index in
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                // Pays the decode here, on a background thread, rather than letting the
                // image view pay it per frame on the main thread while animating.
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            ]

            guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else {
                return nil
            }

            return UIImage(cgImage: image)
        }
    }

    private static func duration(from source: CGImageSource) -> TimeInterval {
        let frameCount = CGImageSourceGetCount(source)
        let totalDuration = (0 ..< frameCount).reduce(0) { partialResult, index in
            partialResult + frameDuration(at: index, source: source)
        }

        return totalDuration > 0 ? totalDuration : TimeInterval(frameCount) * 0.1
    }

    private static func frameDuration(at index: Int, source: CGImageSource) -> TimeInterval {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
            let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        else {
            return 0.1
        }

        let unclampedDelay = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? TimeInterval
        let clampedDelay = gifProperties[kCGImagePropertyGIFDelayTime] as? TimeInterval
        let delay = unclampedDelay ?? clampedDelay ?? 0.1

        return delay < 0.02 ? 0.1 : delay
    }
}
