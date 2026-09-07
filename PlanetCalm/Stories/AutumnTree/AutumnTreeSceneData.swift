import Foundation

struct AutumnTreeSceneResources: Sendable {
    let compositions: AutumnCompositionDocument
    let leafLayout: AutumnLeafLayout
    let terrainAdjustments: AutumnTerrainAdjustments

    static let bundled: Result<AutumnTreeSceneResources, AutumnTreeSceneResourceError> = {
        do {
            return .success(try AutumnTreeSceneResources(bundle: .main))
        } catch let error as AutumnTreeSceneResourceError {
            return .failure(error)
        } catch {
            return .failure(.invalidData("unknown"))
        }
    }()

    init(bundle: Bundle) throws {
        compositions = try Self.decode(
            AutumnCompositionDocument.self,
            named: "compositions",
            bundle: bundle
        )
        leafLayout = try Self.decode(
            AutumnLeafLayout.self,
            named: "leaf-layout",
            subdirectory: "SceneV1",
            bundle: bundle
        )
        terrainAdjustments = try Self.decode(
            AutumnTerrainAdjustments.self,
            named: "terrain-adjustments",
            subdirectory: "SceneV2",
            bundle: bundle
        )

        for deviceID in ["iphone", "ipadPortrait", "ipadLandscape"]
        where compositions.devices[deviceID] == nil {
            throw AutumnTreeSceneResourceError.missingComposition(deviceID)
        }

        for assetID in Self.requiredAssetIDs where Self.assetURL(named: assetID, bundle: bundle) == nil {
            throw AutumnTreeSceneResourceError.missingAsset(assetID)
        }
    }

    static func assetURL(named assetID: String, bundle: Bundle = .main) -> URL? {
        bundle.url(
            forResource: assetID,
            withExtension: "png",
            subdirectory: "SceneV1"
        )
    }

    func composition(for viewport: CGSize) -> AutumnDeviceComposition {
        let key = AutumnSceneDevice.compositionKey(for: viewport)
        return compositions.devices[key] ?? compositions.devices["iphone"]!
    }

    private static let requiredAssetIDs = [
        "sky-paper",
        "ground-base",
        "hill-far-left",
        "hill-far-right",
        "hill-mid-left",
        "hill-mid-right",
        "hill-foreground-left",
        "hill-foreground-right",
        "tree-trunk-branches",
        "leaf-maple-red",
        "leaf-maple-orange",
        "leaf-maple-yellow",
        "leaf-maple-olive",
        "leaf-oak-red",
        "leaf-oak-gold",
        "leaf-small-orange",
        "leaf-small-red",
        "leaf-settled",
        "focus-button-play"
    ]

    private static func decode<Value: Decodable>(
        _ type: Value.Type,
        named name: String,
        subdirectory: String = "SceneV1",
        bundle: Bundle
    ) throws -> Value {
        guard let url = bundle.url(
            forResource: name,
            withExtension: "json",
            subdirectory: subdirectory
        ) else {
            throw AutumnTreeSceneResourceError.missingData(name)
        }

        do {
            return try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
        } catch {
            throw AutumnTreeSceneResourceError.invalidData(name)
        }
    }
}

enum AutumnSceneDevice {
    static func compositionKey(for viewport: CGSize) -> String {
        if viewport.width > viewport.height {
            return "ipadLandscape"
        }
        if viewport.width / max(viewport.height, 1) >= 0.62 {
            return "ipadPortrait"
        }
        return "iphone"
    }
}

enum AutumnTreeSceneResourceError: LocalizedError, Sendable {
    case missingData(String)
    case invalidData(String)
    case missingComposition(String)
    case missingAsset(String)

    var errorDescription: String? {
        switch self {
        case .missingData(let name):
            "Missing Autumn scene data: \(name).json"
        case .invalidData(let name):
            "Could not decode Autumn scene data: \(name).json"
        case .missingComposition(let name):
            "Missing Autumn scene composition: \(name)"
        case .missingAsset(let name):
            "Missing Autumn scene asset: \(name).png"
        }
    }
}

struct AutumnCompositionDocument: Decodable, Sendable {
    let devices: [String: AutumnDeviceComposition]
}

struct AutumnTerrainAdjustments: Decodable, Sendable {
    let groundVerticalOverlap: [String: Double]
}

struct AutumnDeviceComposition: Decodable, Sendable {
    let id: String
    let width: Double
    let height: Double
    let tree: AutumnRect
    let ui: AutumnUILayout
    let terrain: AutumnTerrainLayout
}

struct AutumnRect: Decodable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct AutumnUILayout: Decodable, Sendable {
    let timerX: Double
    let timerY: Double
    let timerSize: Double
    let subtitleY: Double
    let buttonX: Double
    let buttonY: Double
    let buttonSize: Double
    let beginY: Double
    let completionY: Double
}

struct AutumnTerrainLayout: Decodable, Sendable {
    let farLeft: AutumnVerticalPlacement
    let farRight: AutumnVerticalPlacement
    let midLeft: AutumnVerticalPlacement
    let midRight: AutumnVerticalPlacement
    let ground: AutumnVerticalPlacement
    let foregroundLeft: AutumnVerticalPlacement
    let foregroundRight: AutumnVerticalPlacement
}

struct AutumnVerticalPlacement: Decodable, Sendable {
    let y: Double
    let height: Double
}

struct AutumnLeafLayout: Decodable, Sendable {
    let canonicalSeed: UInt64
    let canopy: [AutumnCanopyLeaf]
    let groundLeaves: [AutumnGroundLeaf]
}

struct AutumnCanopyLeaf: Decodable, Identifiable, Sendable {
    let id: String
    let assetId: String
    let x: Double
    let y: Double
    let rotation: Double
    let scale: Double
    let depth: String
    let dropAt: Double
}

struct AutumnGroundLeaf: Decodable, Identifiable, Sendable {
    let id: String
    let assetId: String
    let x: Double
    let y: Double
    let size: Double
    let rotation: Double
}
