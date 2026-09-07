import Foundation

struct ContemporaryLotusStageResources: Sendable {
    let layout: ContemporaryLotusStageLayout

    static let bundled: Result<ContemporaryLotusStageResources, ContemporaryLotusResourceError> = {
        do {
            return .success(try ContemporaryLotusStageResources(bundle: .main))
        } catch let error as ContemporaryLotusResourceError {
            return .failure(error)
        } catch {
            return .failure(.invalidData("layout"))
        }
    }()

    init(bundle: Bundle) throws {
        guard let layoutURL = bundle.url(
            forResource: "layout",
            withExtension: "json",
            subdirectory: "PondStageV1"
        ) else {
            throw ContemporaryLotusResourceError.missingData("layout")
        }

        do {
            layout = try JSONDecoder().decode(
                ContemporaryLotusStageLayout.self,
                from: Data(contentsOf: layoutURL)
            )
        } catch {
            throw ContemporaryLotusResourceError.invalidData("layout")
        }

        for assetID in [layout.background.assetID, layout.mainPadStem.assetID]
        where Self.assetURL(named: assetID, bundle: bundle) == nil {
            throw ContemporaryLotusResourceError.missingAsset(assetID)
        }
    }

    static func assetURL(named assetID: String, bundle: Bundle = .main) -> URL? {
        bundle.url(
            forResource: assetID,
            withExtension: "png",
            subdirectory: "PondStageV1"
        )
    }
}

struct ContemporaryLotusStageLayout: Decodable, Equatable, Sendable {
    let id: String
    let width: Double
    let height: Double
    let background: ContemporaryLotusAssetPlacement
    let mainPadStem: ContemporaryLotusAssetPlacement
}

struct ContemporaryLotusAssetPlacement: Decodable, Equatable, Sendable {
    let assetID: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

enum ContemporaryLotusResourceError: LocalizedError, Sendable {
    case missingData(String)
    case invalidData(String)
    case missingAsset(String)

    var errorDescription: String? {
        switch self {
        case .missingData(let name):
            "Missing Contemporary Lotus stage data: \(name).json"
        case .invalidData(let name):
            "Could not decode Contemporary Lotus stage data: \(name).json"
        case .missingAsset(let name):
            "Missing Contemporary Lotus stage asset: \(name).png"
        }
    }
}
