import UIKit

/// The current tree uses native branches/ground and five independent paper masks.
enum AutumnArtwork {
    static let assetIDs = [
        "hill-far-left", "hill-mid-right",
        "leaf-maple-yellow", "leaf-maple-orange", "leaf-maple-red"
    ]

    static func assetURL(named name: String, bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: name, withExtension: "png", subdirectory: "SceneV1")
    }
}

final class AutumnArtworkCache: @unchecked Sendable {
    static let shared = AutumnArtworkCache()
    private let cache = NSCache<NSString, UIImage>()

    func image(named name: String) -> UIImage? {
        if let image = cache.object(forKey: name as NSString) { return image }
        guard let url = AutumnArtwork.assetURL(named: name),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return image
    }
}
