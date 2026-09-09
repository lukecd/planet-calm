import Foundation
import SwiftUI

/// The long-form light state shared by the paper scene and its future sound banks.
/// It intentionally has no renderer clock or audio side effects: callers sample it
/// from their own canonical performance time or from the temporary tuning control.
enum SplashAtmospherePoolID: Int, CaseIterable, Sendable {
    case night
    case twilight
    case daylight

    var displayName: String {
        switch self {
        case .night: "Night"
        case .twilight: "Twilight"
        case .daylight: "Daylight"
        }
    }
}

/// RGB kept as data rather than `Color`, so a palette can be deterministically
/// interpolated, tested, documented, and eventually shared with non-SwiftUI renderers.
struct SplashColorComponents: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    init(_ hex: Int) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }

    init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    /// A perceptual hue path prevents a blue-to-yellow transition from passing through
    /// the olive mixtures that direct RGB interpolation creates. `warm` deliberately
    /// travels blue -> violet -> red -> orange -> yellow when that is the art direction.
    func blended(
        toward other: Self,
        amount: Double,
        hueRoute: SplashHueRoute = .shortest
    ) -> Self {
        let amount = min(max(amount, 0), 1)
        if amount == 0 { return self }
        if amount == 1 { return other }
        let start = oklch
        let end = other.oklch
        let hueDelta = hueRoute.delta(from: start.hue, to: end.hue)
        let l = start.lightness + (end.lightness - start.lightness) * amount
        let c = start.chroma + (end.chroma - start.chroma) * amount
        let h = start.hue + hueDelta * amount
        return Self(oklch: .init(lightness: l, chroma: c, hue: h))
    }

    private var oklch: SplashOKLCH {
        let linearRed = Self.linearized(red)
        let linearGreen = Self.linearized(green)
        let linearBlue = Self.linearized(blue)
        let l = 0.4122214708 * linearRed
            + 0.5363325363 * linearGreen
            + 0.0514459929 * linearBlue
        let m = 0.2119034982 * linearRed
            + 0.6806995451 * linearGreen
            + 0.1073969566 * linearBlue
        let s = 0.0883024619 * linearRed
            + 0.2817188376 * linearGreen
            + 0.6299787005 * linearBlue
        let lRoot = cbrt(l)
        let mRoot = cbrt(m)
        let sRoot = cbrt(s)
        let lightness = 0.2104542553 * lRoot
            + 0.7936177850 * mRoot
            - 0.0040720468 * sRoot
        let a = 1.9779984951 * lRoot
            - 2.4285922050 * mRoot
            + 0.4505937099 * sRoot
        let b = 0.0259040371 * lRoot
            + 0.7827717662 * mRoot
            - 0.8086757660 * sRoot
        return .init(
            lightness: lightness,
            chroma: hypot(a, b),
            hue: atan2(b, a) * 180 / .pi
        )
    }

    private init(oklch: SplashOKLCH) {
        let a = oklch.chroma * cos(oklch.hue * .pi / 180)
        let b = oklch.chroma * sin(oklch.hue * .pi / 180)
        let lRoot = oklch.lightness + 0.3963377774 * a + 0.2158037573 * b
        let mRoot = oklch.lightness - 0.1055613458 * a - 0.0638541728 * b
        let sRoot = oklch.lightness - 0.0894841775 * a - 1.2914855480 * b
        let l = lRoot * lRoot * lRoot
        let m = mRoot * mRoot * mRoot
        let s = sRoot * sRoot * sRoot
        let linearRed = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let linearGreen = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let linearBlue = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        red = Self.sRGB(linearRed)
        green = Self.sRGB(linearGreen)
        blue = Self.sRGB(linearBlue)
    }

    private static func linearized(_ component: Double) -> Double {
        component <= 0.04045
            ? component / 12.92
            : pow((component + 0.055) / 1.055, 2.4)
    }

    private static func sRGB(_ component: Double) -> Double {
        let component = min(max(component, 0), 1)
        return component <= 0.0031308
            ? component * 12.92
            : 1.055 * pow(component, 1 / 2.4) - 0.055
    }

    private init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

private struct SplashOKLCH {
    let lightness: Double
    let chroma: Double
    let hue: Double
}

enum SplashHueRoute {
    case shortest
    case warm

    func delta(from start: Double, to end: Double) -> Double {
        let normalizedStart = start < 0 ? start + 360 : start
        let normalizedEnd = end < 0 ? end + 360 : end
        switch self {
        case .shortest:
            return (normalizedEnd - normalizedStart + 540)
                .truncatingRemainder(dividingBy: 360) - 180
        case .warm:
            let delta = (normalizedEnd - normalizedStart)
                .truncatingRemainder(dividingBy: 360)
            return delta < 0 ? delta + 360 : delta
        }
    }
}

/// Renderer-independent sunrise state, sampled from the same progress as sound pools.
/// Coefficients live here so manual scrubbing, playback, and tests cannot diverge.
struct SplashSunriseState: Equatable, Sendable {
    let progress: Double
    let solarElevationRadians: Double
    let exposure: Double
    let paperSpread: Double
    let paperAmount: Double
    let cloudTime: Double

    // Foreground inks change sooner than the decorative wave palette. Holding the
    // pale twilight ink through the warm sky makes the narrow lettering disappear.
    var titleInk: SplashColorComponents { ink(from: .init(0xAEC7FB), start: 0.48, end: 0.49) }
    var navigationInk: SplashColorComponents { ink(from: .init(0xD5DDFB), start: 0.54, end: 0.55) }
    var selectedInk: SplashColorComponents { ink(from: .init(0xF7A337), start: 0.54, end: 0.55) }

    private func ink(from night: SplashColorComponents, start: Double, end: Double) -> SplashColorComponents {
        let t = min(max((progress - start) / (end - start), 0), 1)
        let amount = t * t * (3 - 2 * t)
        let day = SplashColorComponents(0x183A90)
        // A brief neutral ink handoff, not a decorative hue rotation through green.
        return .init(night.red + (day.red - night.red) * amount,
                     night.green + (day.green - night.green) * amount,
                     night.blue + (day.blue - night.blue) * amount)
    }

    init(progress rawProgress: Double) {
        let p = rawProgress.isFinite ? min(max(rawProgress, 0), 1) : 0
        progress = p
        solarElevationRadians = -0.004 + 0.214 * p
        exposure = 0.12 + 1.4 * pow(p, 0.75)
        paperSpread = 0.12 + 0.70 * p / max(0.001, 1.001 - p)
        let t = min(p / 0.90, 1)
        paperAmount = t * t * (3 - 2 * t)
        cloudTime = p * 180
    }
}

struct SplashAtmospherePalette: Equatable, Sendable {
    let canvas: SplashColorComponents
    let waveDeep: SplashColorComponents
    let waveMid: SplashColorComponents
    let wavePeriwinkle: SplashColorComponents
    let waveLavender: SplashColorComponents
    let waveCoral: SplashColorComponents
    let wavePink: SplashColorComponents
    let type: SplashColorComponents
    let accent: SplashColorComponents
    let navigationSelected: SplashColorComponents
    let sunCutEdge: SplashColorComponents

    static let night = Self(
        canvas: .init(0x0A1124),
        waveDeep: .init(0x0D3690),
        waveMid: .init(0x2D50A8),
        wavePeriwinkle: .init(0x516BAF),
        waveLavender: .init(0x836FB3),
        waveCoral: .init(0x0D3690),
        wavePink: .init(0x516BAF),
        type: .init(0xAEC7FB),
        accent: .init(0xF7A337),
        navigationSelected: .init(0xF7A337),
        sunCutEdge: .init(0xD68628)
    )

    /// A cool intermediary rather than a literal sunrise. It preserves contrast while
    /// the music banks can begin overlapping before the full paper-gold state arrives.
    static let twilight = Self(
        canvas: .init(0x1B2E4C),
        waveDeep: .init(0x1E4C9D),
        waveMid: .init(0x4B70B9),
        wavePeriwinkle: .init(0x798DC4),
        waveLavender: .init(0xA080BD),
        waveCoral: .init(0x7464AD),
        wavePink: .init(0x9B77B8),
        type: .init(0xD5DDFB),
        accent: .init(0xF4B64C),
        navigationSelected: .init(0xE28A4B),
        sunCutEdge: .init(0xC98735)
    )

    /// Provisional daylight endpoint based on the yellow paper reference. Its exact
    /// final hues remain a visual decision; geometry, texture, and depth are unchanged.
    static let daylight = Self(
        canvas: .init(0xFFCE58),
        waveDeep: .init(0x1E3F99),
        waveMid: .init(0x3A52AA),
        wavePeriwinkle: .init(0x9B70BF),
        waveLavender: .init(0xA86FBA),
        waveCoral: .init(0xF06A52),
        wavePink: .init(0xE43D79),
        type: .init(0x183A90),
        accent: .init(0xF27A40),
        navigationSelected: .init(0x183A90),
        sunCutEdge: .init(0xC85332)
    )

    static func blended(
        from start: Self,
        to end: Self,
        amount: Double
    ) -> Self {
        Self(
            canvas: start.canvas.blended(toward: end.canvas, amount: amount, hueRoute: .warm),
            waveDeep: start.waveDeep.blended(toward: end.waveDeep, amount: amount),
            waveMid: start.waveMid.blended(toward: end.waveMid, amount: amount),
            wavePeriwinkle: start.wavePeriwinkle.blended(toward: end.wavePeriwinkle, amount: amount, hueRoute: .warm),
            waveLavender: start.waveLavender.blended(toward: end.waveLavender, amount: amount, hueRoute: .warm),
            waveCoral: start.waveCoral.blended(toward: end.waveCoral, amount: amount, hueRoute: .warm),
            wavePink: start.wavePink.blended(toward: end.wavePink, amount: amount, hueRoute: .warm),
            type: start.type.blended(toward: end.type, amount: amount),
            accent: start.accent.blended(toward: end.accent, amount: amount),
            navigationSelected: start.navigationSelected.blended(toward: end.navigationSelected, amount: amount),
            sunCutEdge: start.sunCutEdge.blended(toward: end.sunCutEdge, amount: amount)
        )
    }

    func waveColor(for actorID: SplashSceneActorID) -> Color {
        switch actorID {
        case .waveRearDeep:
            waveDeep.color
        case .waveMiddleBlue:
            waveMid.color
        case .waveRearPeriwinkle:
            wavePeriwinkle.color
        case .waveMiddleLavender, .waveFrontLavender:
            waveLavender.color
        case .waveWarmReveal:
            accent.color
        case .waveFrontDeep:
            waveCoral.color
        case .waveFrontPeriwinkle:
            wavePink.color
        default:
            canvas.color
        }
    }

    func waveCutEdgeColor(for actorID: SplashSceneActorID) -> Color {
        switch actorID {
        case .waveRearDeep:
            waveDeep.blended(toward: canvas, amount: 0.25).color
        case .waveMiddleBlue:
            waveMid.blended(toward: canvas, amount: 0.25).color
        case .waveRearPeriwinkle:
            wavePeriwinkle.blended(toward: canvas, amount: 0.27).color
        case .waveMiddleLavender, .waveFrontLavender:
            waveLavender.blended(toward: canvas, amount: 0.25).color
        case .waveWarmReveal:
            sunCutEdge.color
        case .waveFrontDeep:
            waveCoral.blended(toward: canvas, amount: 0.25).color
        case .waveFrontPeriwinkle:
            wavePink.blended(toward: canvas, amount: 0.25).color
        default:
            canvas.color
        }
    }
}

struct SplashAtmosphereWeights: Equatable, Sendable {
    let night: Double
    let twilight: Double
    let daylight: Double

    func weight(of pool: SplashAtmospherePoolID) -> Double {
        switch pool {
        case .night: night
        case .twilight: twilight
        case .daylight: daylight
        }
    }
}

struct SplashAtmosphereSample: Equatable, Sendable {
    let progress: Double
    let palette: SplashAtmospherePalette
    let weights: SplashAtmosphereWeights
    let sunrise: SplashSunriseState

    static let night = SplashAtmosphereDirector.sample(progress: 0)

    var dominantPool: SplashAtmospherePoolID {
        if weights.daylight > weights.twilight, weights.daylight > weights.night {
            return .daylight
        }
        if weights.twilight > weights.night {
            return .twilight
        }
        return .night
    }

    var displayLabel: String {
        "\(dominantPool.displayName) \(Int((progress * 100).rounded()))%"
    }
}

typealias SplashSoundRole = PerformanceSoundRole
typealias SplashSoundAssetKey = PerformanceSoundAssetKey<SplashAtmospherePoolID>

enum SplashAtmosphereDirector {
    /// The eventual automatic arc should run across minutes, not the visual frame rate.
    static let suggestedCycleDuration: TimeInterval = 12 * 60

    static func sample(progress rawProgress: Double) -> SplashAtmosphereSample {
        let progress = min(max(rawProgress, 0), 1)
        let sunrise = SplashSunriseState(progress: progress)
        if progress <= 0.5 {
            let transition = progress * 2
            return SplashAtmosphereSample(
                progress: progress,
                palette: .blended(from: .night, to: .twilight, amount: transition),
                weights: .init(night: 1 - transition, twilight: transition, daylight: 0),
                sunrise: sunrise
            )
        }

        let transition = (progress - 0.5) * 2
        return SplashAtmosphereSample(
            progress: progress,
            palette: .blended(from: .twilight, to: .daylight, amount: transition),
            weights: .init(night: 0, twilight: 1 - transition, daylight: transition),
            sunrise: sunrise
        )
    }

    static func sample(at performanceElapsed: TimeInterval) -> SplashAtmosphereSample {
        sample(progress: performanceElapsed / suggestedCycleDuration)
    }

    /// Picks the bank only when a future scored event begins. A release therefore keeps
    /// its original source while the visual atmosphere and later events continue moving.
    static func soundSource(
        eventOrdinal: Int,
        tonalSlot: Int,
        role: SplashSoundRole,
        atmosphere: SplashAtmosphereSample,
        octaveOffset: Int = 0
    ) -> SplashSoundAssetKey {
        let unit = deterministicUnit(eventOrdinal: eventOrdinal, tonalSlot: tonalSlot)
        let blend = PerformancePoolBlend(first: atmosphere.weights.night,
            middle: atmosphere.weights.twilight, last: atmosphere.weights.daylight)
        let pool: SplashAtmospherePoolID = [.night, .twilight, .daylight][blend.index(forUnit: unit)]
        return SplashSoundAssetKey(
            pool: pool,
            role: role,
            tonalSlot: min(max(tonalSlot, 0), 7),
            octaveOffset: octaveOffset
        )
    }

    /// The production-facing selection path. An event keeps this key for its full
    /// attack and release, even while the world progresses into another pool.
    /// The run seed gives each session controlled variety without ever rolling at
    /// render time.
    static func soundSource(
        eventID: String,
        sessionSeed: UInt64,
        tonalSlot: Int,
        role: SplashSoundRole,
        atmosphere: SplashAtmosphereSample,
        octaveOffset: Int = 0
    ) -> SplashSoundAssetKey {
        var random = SeededRandomNumberGenerator(
            seed: sessionSeed ^ StableSeed.hash(eventID)
        )
        let unit = random.unitInterval()
        let blend = PerformancePoolBlend(first: atmosphere.weights.night,
            middle: atmosphere.weights.twilight, last: atmosphere.weights.daylight)
        let pool: SplashAtmospherePoolID = [.night, .twilight, .daylight][blend.index(forUnit: unit)]
        return SplashSoundAssetKey(
            pool: pool,
            role: role,
            tonalSlot: min(max(tonalSlot, 0), 7),
            octaveOffset: octaveOffset
        )
    }

    private static func deterministicUnit(eventOrdinal: Int, tonalSlot: Int) -> Double {
        let value = (eventOrdinal &* 1_103_515_245 &+ tonalSlot &* 12_345)
            & 0x7FFF_FFFF
        return Double(value) / Double(0x7FFF_FFFF)
    }
}
