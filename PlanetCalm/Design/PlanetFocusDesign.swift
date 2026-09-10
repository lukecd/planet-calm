import CoreText
import SwiftUI

enum PlanetFocusPalette {
    static let canvasInk = Color(red: 10 / 255, green: 17 / 255, blue: 36 / 255)
    static let waveDeep = Color(red: 13 / 255, green: 54 / 255, blue: 144 / 255)
    static let waveMid = Color(red: 45 / 255, green: 80 / 255, blue: 168 / 255)
    static let wavePeriwinkle = Color(red: 81 / 255, green: 107 / 255, blue: 175 / 255)
    static let waveLavender = Color(red: 131 / 255, green: 111 / 255, blue: 179 / 255)
    static let typePaleBlue = Color(red: 174 / 255, green: 199 / 255, blue: 251 / 255)
    static let warmYellow = Color(red: 247 / 255, green: 163 / 255, blue: 55 / 255)
}

enum PlanetFocusTypography {
    private static let fontResources = [
        (name: "Aladin-Regular", extension: "ttf"),
        (name: "SueEllenFrancisco-Regular", extension: "ttf")
    ]

    private static let registration: Void = {
        for resource in fontResources {
            guard let url = Bundle.main.url(
                forResource: resource.name,
                withExtension: resource.extension,
                subdirectory: "Fonts"
            ) else {
                continue
            }

            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    static func registerBundledFonts() {
        _ = registration
    }

    static func wordmark(size: CGFloat) -> Font {
        .custom("Aladin-Regular", size: size, relativeTo: .largeTitle)
    }

    static func navigation(size: CGFloat) -> Font {
        .custom("SueEllenFrancisco", size: size, relativeTo: .body)
    }

    /// Standard San Francisco for functional UI; handwriting belongs to story titles.
    static func interface(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .default).weight(weight)
    }
}
