import UIKit

/// Gets a picked or taken photo ready to upload: upright, at most 512 px on
/// its longest side, JPEG at 0.8. Small enough to send on a slow connection.
enum ProfilePhoto {
    static let maxSide: CGFloat = 512
    static let quality: CGFloat = 0.8

    /// The size the photo is drawn at, in pixels: never larger than it was,
    /// and never under 1 px a side (a 9999×1 strip would otherwise round to
    /// 512×0, which can't be drawn).
    static func scaledSize(for size: CGSize, maxSide: CGFloat = maxSide) -> CGSize {
        let longest = max(size.width, size.height)
        let scale = longest > maxSide ? maxSide / longest : 1
        return CGSize(
            width: max(1, min(maxSide, (size.width * scale).rounded())),
            height: max(1, min(maxSide, (size.height * scale).rounded()))
        )
    }

    /// Downscaled pixels for `image`, or `nil` when it has no size to draw.
    /// Drawing also applies the photo's orientation, so camera shots come
    /// out upright.
    static func downscaled(_ image: UIImage, maxSide: CGFloat = maxSide) -> UIImage? {
        let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        guard pixels.width.isFinite, pixels.height.isFinite, pixels.width > 0, pixels.height > 0 else { return nil }
        let target = scaledSize(for: pixels, maxSide: maxSide)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    static func jpeg(from image: UIImage) -> Data? {
        downscaled(image)?.jpegData(compressionQuality: quality)
    }

    static func jpeg(from data: Data) -> Data? {
        UIImage(data: data).flatMap(jpeg(from:))
    }
}
