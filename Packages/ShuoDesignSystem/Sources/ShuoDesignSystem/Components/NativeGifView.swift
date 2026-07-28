//
//  File.swift
//  ShuoDesignSystem
//
//  Created by Matthew Sebastian Lesmana on 28/07/26.
//

import SwiftUI
import ImageIO
import UIKit

struct NativeGifView: UIViewRepresentable {
    let gifName: String

    func makeUIView(context: Context) -> GifContainerView {
        let containerView = GifContainerView()
        let imageView = UIImageView()
        imageView.backgroundColor = .clear
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false

        containerView.addSubview(imageView)
        containerView.imageView = imageView
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: containerView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        configure(imageView)
        return containerView
    }

    func updateUIView(_ uiView: GifContainerView, context: Context) {
        guard uiView.imageView?.image == nil else { return }
        uiView.imageView.map(configure)
    }

    private func configure(_ imageView: UIImageView) {
        guard let animatedImage = animatedImage() else { return }
        imageView.image = animatedImage
        imageView.startAnimating()
    }

    private func animatedImage() -> UIImage? {
        guard
            let data = NSDataAsset(name: gifName, bundle: .main)?.data,
            let source = CGImageSourceCreateWithData(data as CFData, nil)
        else {
            return nil
        }

        let frames = frames(from: source)
        guard !frames.isEmpty else { return nil }

        return UIImage.animatedImage(
            with: frames,
            duration: duration(from: source)
        )
    }

    private func frames(from source: CGImageSource) -> [UIImage] {
        (0..<CGImageSourceGetCount(source)).compactMap { index in
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: 480,
            ]

            guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else {
                return nil
            }

            return UIImage(cgImage: image)
        }
    }

    private func duration(from source: CGImageSource) -> TimeInterval {
        let frameCount = CGImageSourceGetCount(source)
        let totalDuration = (0..<frameCount).reduce(0) { partialResult, index in
            partialResult + frameDuration(at: index, source: source)
        }

        return totalDuration > 0 ? totalDuration : TimeInterval(frameCount) * 0.1
    }

    private func frameDuration(at index: Int, source: CGImageSource) -> TimeInterval {
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

final class GifContainerView: UIView {
    weak var imageView: UIImageView?

    override var intrinsicContentSize: CGSize {
        .zero
    }
}
