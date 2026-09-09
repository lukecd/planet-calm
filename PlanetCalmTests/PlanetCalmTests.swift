import XCTest
#if canImport(UIKit)
import UIKit
import SpriteKit
import SwiftUI
import CryptoKit
#endif
@testable import PlanetCalm

final class PlanetCalmTests: XCTestCase {
    func testStoryChooserKeepsSmallSquarePreviewsAcrossDevices() {
        let phone = StoryChooserLayout(
            size: CGSize(width: 430, height: 932),
            safeAreaInsets: EdgeInsets()
        )
        let tabletPortrait = StoryChooserLayout(
            size: CGSize(width: 834, height: 1_194),
            safeAreaInsets: EdgeInsets()
        )
        let tabletLandscape = StoryChooserLayout(
            size: CGSize(width: 1_194, height: 834),
            safeAreaInsets: EdgeInsets()
        )

        XCTAssertEqual(phone.previewSide, 133.3, accuracy: 0.001)
        XCTAssertEqual(tabletPortrait.previewSide, 244)
        XCTAssertEqual(tabletLandscape.previewSide, 244)
        XCTAssertLessThan(phone.previewSide * 2 + phone.choiceSpacing, 430)
        XCTAssertLessThan(tabletPortrait.previewSide * 2 + tabletPortrait.choiceSpacing, 834)
        XCTAssertLessThan(tabletLandscape.previewSide * 2 + tabletLandscape.choiceSpacing, 1_194)
    }

    func testSplashHasOneAddressableSlotForEveryApprovedActor() {
        XCTAssertEqual(SplashSceneActorID.allCases.count, 15)
        XCTAssertEqual(
            Set(SplashSceneActorID.allCases.map(\.rawValue)),
            Set([
                "background", "wordmark", "sun",
                "waveRearPeriwinkle", "waveRearDeep", "waveWarmReveal",
                "waveMiddleLavender", "waveMiddleBlue", "waveFrontDeep",
                "waveFrontPeriwinkle", "waveFrontLavender",
                "lotusLeft", "lotusCenter", "lotusRight", "navigation"
            ])
        )
        XCTAssertEqual(SplashLotusPetalID.allCases.count, 8)
    }

    func testPerformanceClockUsesStableElapsedTime() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let clock = PerformanceClock(startedAt: start)

        XCTAssertEqual(clock.elapsed(at: start.addingTimeInterval(2.5)), 2.5)
        XCTAssertEqual(clock.elapsed(at: start.addingTimeInterval(-1)), 0)
        XCTAssertEqual(clock.startedAt, start)
    }

    func testPerformanceRunnerIsAStableResumableTransport() {
        let start = Date(timeIntervalSinceReferenceDate: 4_000)
        let session = PerformanceSession(
            duration: .oneMinute,
            startedAt: start,
            randomSeed: 42
        )
        let runner = PerformanceRunner(session: session)

        let middle = runner.sample(at: start.addingTimeInterval(30))
        XCTAssertEqual(middle.elapsedTime, 30)
        XCTAssertEqual(middle.progress, 0.5)
        XCTAssertEqual(middle.remainingTime, 30)
        XCTAssertFalse(middle.isComplete)

        let completed = runner.sample(at: start.addingTimeInterval(90))
        XCTAssertEqual(completed.elapsedTime, 60)
        XCTAssertEqual(completed.progress, 1)
        XCTAssertEqual(completed.remainingTime, 0)
        XCTAssertTrue(completed.isComplete)
    }

    func testSplashPerformancePlanKeepsOneSeededSoundChoicePerEvent() {
        let session = PerformanceSession(
            duration: .twoMinutes,
            startedAt: .distantPast,
            randomSeed: 8_173
        )
        let plan = SplashPerformancePlan(
            session: session,
            scoreEvents: SplashPerformanceScore.events(seed: session.randomSeed)
        )
        let scheduled = SplashScheduledPerformanceEvent(
            event: SplashPerformanceScore.noteEvents[3],
            scheduledStartBeat: 44
        )

        let firstSelection = plan.soundSource(for: scheduled)
        XCTAssertEqual(firstSelection, plan.soundSource(for: scheduled))
        XCTAssertEqual(firstSelection.tonalSlot, scheduled.event.tonalSlot)
        XCTAssertEqual(firstSelection.role, .pad)
    }

    func testAtmosphereUsesContinuousVisualAndMusicalPoolCrossfades() {
        let night = SplashAtmosphereDirector.sample(progress: 0)
        XCTAssertEqual(night.palette, .night)
        XCTAssertEqual(night.weights.night, 1)
        XCTAssertEqual(night.weights.twilight, 0)
        XCTAssertEqual(night.weights.daylight, 0)

        let firstCrossfade = SplashAtmosphereDirector.sample(progress: 0.25)
        XCTAssertEqual(firstCrossfade.weights.night, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(firstCrossfade.weights.twilight, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(firstCrossfade.weights.daylight, 0)

        let twilight = SplashAtmosphereDirector.sample(progress: 0.5)
        XCTAssertEqual(twilight.palette, .twilight)
        XCTAssertEqual(twilight.weights.night, 0)
        XCTAssertEqual(twilight.weights.twilight, 1)

        let daylight = SplashAtmosphereDirector.sample(progress: 1)
        XCTAssertEqual(daylight.palette, .daylight)
        XCTAssertEqual(daylight.weights.night, 0)
        XCTAssertEqual(daylight.weights.twilight, 0)
        XCTAssertEqual(daylight.weights.daylight, 1)

        XCTAssertEqual(
            SplashAtmosphereDirector.sample(
                at: SplashAtmosphereDirector.suggestedCycleDuration
            ),
            daylight
        )
    }

    func testFutureSoundSelectionIsDeterministicAndKeepsPoolAtEventStart() {
        let daylight = SplashAtmosphereDirector.sample(progress: 1)
        let selection = SplashAtmosphereDirector.soundSource(
            eventOrdinal: 12,
            tonalSlot: 5,
            role: .pad,
            atmosphere: daylight,
            octaveOffset: 1
        )
        XCTAssertEqual(selection.pool, .daylight)
        XCTAssertEqual(selection.role, .pad)
        XCTAssertEqual(selection.tonalSlot, 5)
        XCTAssertEqual(selection.octaveOffset, 1)
        XCTAssertEqual(
            selection,
            SplashAtmosphereDirector.soundSource(
                eventOrdinal: 12,
                tonalSlot: 5,
                role: .pad,
                atmosphere: daylight,
                octaveOffset: 1
            )
        )

        let blend = SplashAtmosphereDirector.sample(progress: 0.25)
        let selectedPools = Set((0..<64).map {
            SplashAtmosphereDirector.soundSource(
                eventOrdinal: $0,
                tonalSlot: $0 % 8,
                role: .melodicOneShot,
                atmosphere: blend
            ).pool
        })
        XCTAssertTrue(selectedPools.contains(.night))
        XCTAssertTrue(selectedPools.contains(.twilight))
        XCTAssertFalse(selectedPools.contains(.daylight))
    }

    func testSunriseGeometryAndTransportAgreement() {
        for size in [CGSize(width: 393, height: 852), CGSize(width: 852, height: 393),
                     CGSize(width: 820, height: 1180), CGSize(width: 1180, height: 820)] {
            let layout = SplashLayout(size: size)
            let first = layout.risingSunCenter(progress: 0)
            XCTAssertEqual(layout.sunriseHorizon - (first.y - layout.sunDiameter / 2),
                           layout.sunDiameter * 0.1, accuracy: 0.0001)
            XCTAssertEqual(layout.risingSunCenter(progress: 1), layout.sunCenter)
            var previousY = first.y
            for step in 0...20 {
                let center = layout.risingSunCenter(progress: Double(step) / 20)
                XCTAssertLessThanOrEqual(center.y, previousY)
                XCTAssertEqual(center.x, layout.sunCenter.x)
                previousY = center.y
            }
        }
        let startedAt = Date(timeIntervalSince1970: 1000)
        for duration in [FocusDuration.oneMinute, .twoMinutes] {
            let session = PerformanceSession(duration: duration, startedAt: startedAt, randomSeed: 42)
            for step in 0...20 {
                let progress = Double(step) / 20
                let time = startedAt.addingTimeInterval(duration.timeInterval * progress)
                let automatic = SplashAtmosphereDirector.sample(progress: PerformanceRunner(session: session).sample(at: time).progress)
                let manual = SplashAtmosphereDirector.sample(progress: progress)
                XCTAssertEqual(automatic.sunrise, manual.sunrise)
                XCTAssertEqual(automatic.weights, manual.weights)
            }
        }
        XCTAssertEqual(SplashSunriseState(progress: -.infinity).progress, 0)
        XCTAssertEqual(SplashSunriseState(progress: 2).progress, 1)
        let samples = (0...20).map { SplashSunriseState(progress: Double($0) / 20) }
        XCTAssertEqual(samples.first!.solarElevationRadians, -0.004, accuracy: 0.00001)
        XCTAssertEqual(samples.last!.solarElevationRadians, 0.21, accuracy: 0.00001)
        XCTAssertTrue(zip(samples, samples.dropFirst()).allSatisfy {
            $0.exposure <= $1.exposure && $0.paperSpread <= $1.paperSpread
        })
    }

    func testWarmPerceptualPaletteRouteAvoidsTheOldOliveMidpoint() {
        let twilightCanvas = SplashAtmospherePalette.twilight.canvas
        let daylightCanvas = SplashAtmospherePalette.daylight.canvas
        let oldRGBMidpoint = SplashColorComponents(
            twilightCanvas.red + (daylightCanvas.red - twilightCanvas.red) * 0.36,
            twilightCanvas.green + (daylightCanvas.green - twilightCanvas.green) * 0.36,
            twilightCanvas.blue + (daylightCanvas.blue - twilightCanvas.blue) * 0.36
        )
        let warmMidpoint = twilightCanvas.blended(
            toward: daylightCanvas,
            amount: 0.36,
            hueRoute: .warm
        )

        XCTAssertGreaterThan(oldRGBMidpoint.green, oldRGBMidpoint.blue)
        XCTAssertGreaterThan(warmMidpoint.red, warmMidpoint.green)
    }

    func testSplashPerformanceUsesApprovedTempoAndMeditativeOverlappingTravel() {
        XCTAssertEqual(SplashPerformanceScore.tempo.beatsPerMinute, 65)
        XCTAssertEqual(SplashPerformanceScore.tempo.beatsPerBar, 4)
        XCTAssertEqual(
            SplashPerformanceScore.tempo.secondsPerBeat,
            60.0 / 65.0,
            accuracy: 0.000_001
        )
        XCTAssertEqual(SplashPerformanceScore.droneStartTime, 0)
        XCTAssertEqual(SplashPerformanceScore.noteCycleBeats, 32)
        XCTAssertEqual(
            SplashMotionTiming.ribbonEntranceCompleteTime,
            3.51,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            SplashMotionTiming.entranceCompleteTime,
            SplashLotusChoreography.entryEnd,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            SplashMotionTiming.entranceCompleteTime,
            4.46,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            SplashMotionTiming.interactionReadyTime,
            3.51,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            SplashMotionTiming.exitCompleteTime,
            1.50,
            accuracy: 0.000_001
        )

        XCTAssertEqual(SplashMotionTiming.entryProgress(for: 0, elapsed: 0), 0)
        XCTAssertEqual(SplashMotionTiming.entryProgress(for: 0, elapsed: 2.25), 1)
        XCTAssertEqual(SplashMotionTiming.entryProgress(for: 7, elapsed: 1.50), 0)
        XCTAssertEqual(
            SplashMotionTiming.entryProgress(
                for: 7,
                elapsed: SplashMotionTiming.ribbonEntranceCompleteTime
            ),
            1,
            accuracy: 0.000_001
        )

        XCTAssertEqual(
            SplashMotionTiming.exitProgress(for: 7, count: 8, elapsed: 1.15),
            1
        )
        XCTAssertEqual(
            SplashMotionTiming.exitProgress(for: 0, count: 8, elapsed: 1.50),
            1
        )
    }

    func testSplashWaveVoicesHaveStableTonalSlotsAndScoredPolyphony() {
        let voices = SplashPerformanceScore.waveVoices
        XCTAssertEqual(voices.count, SplashMotionTiming.ribbonCount)
        XCTAssertEqual(Set(voices.map(\.tonalSlot)), Set(0..<8))
        XCTAssertEqual(Set(voices.map { $0.actorID.rawValue }).count, 8)
        XCTAssertEqual(
            Set(SplashPerformanceScore.noteEvents.map(\.tonalSlot)),
            Set(0..<8)
        )

        var stablePolyphony = Set<Int>()
        for step in 320...640 {
            let scoreBeat = Double(step) / 10
            let cycleBeat = scoreBeat.truncatingRemainder(
                dividingBy: SplashPerformanceScore.noteCycleBeats
            )
            let activeCount = SplashPerformanceScore.noteEvents.filter {
                SplashPerformanceScore.repeatingSample(
                    for: $0,
                    scoreBeat: scoreBeat,
                    cycleBeat: cycleBeat
                ) != nil
            }.count
            stablePolyphony.insert(activeCount)
        }
        XCTAssertEqual(stablePolyphony, [4])

        let attackElapsed = SplashMotionTiming.noteScoreStartTime
            + 3 * SplashPerformanceScore.tempo.secondsPerBeat
        let attackSamples = voices.map {
            SplashPerformanceScore.waveMotionSample(
                for: $0.actorID,
                performanceElapsed: attackElapsed
            )
        }
        XCTAssertEqual(attackSamples.filter { $0.amplitude > 0 }.count, 1)
        XCTAssertEqual(attackSamples.filter { $0.bedAmplitude > 0 }.count, 4)
        XCTAssertEqual(attackSamples.filter(\.isMoving).count, 4)
        XCTAssertTrue(attackSamples.allSatisfy {
            $0.amplitude >= 0
                && $0.amplitude
                    <= SplashMotionTiming.maximumMotionAmount + 0.000_001
        })

        let firstEvent = SplashPerformanceScore.noteEvents[0]
        let nearStart = firstEvent.sample(at: firstEvent.startBeat + 0.25)
        let nearEnd = firstEvent.sample(at: firstEvent.endBeat - 0.25)
        XCTAssertNotNil(nearStart)
        XCTAssertNotNil(nearEnd)
        XCTAssertEqual(
            firstEvent.sample(at: firstEvent.startBeat - 0.01),
            nil
        )
        XCTAssertEqual(
            firstEvent.sample(at: firstEvent.endBeat),
            nil
        )
    }

    func testSplashPresentationSeparatesTravelFromLivingMotion() {
        let initial = SplashScenePresentation.sample(
            performanceElapsed: 0,
            exitElapsed: nil,
            reduceMotion: false
        )
        XCTAssertFalse(initial.isInteractive)
        XCTAssertEqual(initial.waveMotionAmount, 0)
        XCTAssertEqual(
            initial.horizontalTravelFactor(
                forWaveAt: 0,
                edge: .trailing,
                count: 8
            ),
            1
        )

        let settled = SplashScenePresentation.sample(
            performanceElapsed: SplashMotionTiming.entranceCompleteTime,
            exitElapsed: nil,
            reduceMotion: false
        )
        XCTAssertTrue(settled.isInteractive)
        XCTAssertEqual(
            settled.horizontalTravelFactor(
                forWaveAt: 0,
                edge: .trailing,
                count: 8
            ),
            0
        )

        let almostReady = SplashScenePresentation.sample(
            performanceElapsed: SplashMotionTiming.interactionReadyTime - 0.01,
            exitElapsed: nil,
            reduceMotion: false
        )
        let readyDuringFlowers = SplashScenePresentation.sample(
            performanceElapsed: SplashMotionTiming.interactionReadyTime,
            exitElapsed: nil,
            reduceMotion: false
        )
        XCTAssertFalse(almostReady.isInteractive)
        XCTAssertTrue(readyDuringFlowers.isInteractive)
        XCTAssertGreaterThan(settled.waveMotionAmount, 0)

        let activeNoteElapsed = SplashMotionTiming.noteScoreStartTime
            + 3 * SplashPerformanceScore.tempo.secondsPerBeat
        let living = SplashScenePresentation.sample(
            performanceElapsed: activeNoteElapsed,
            exitElapsed: nil,
            reduceMotion: false
        )
        XCTAssertGreaterThan(living.waveMotionAmount, 0)
        XCTAssertGreaterThan(living.waveMotionPhase, 0)

        let exiting = SplashScenePresentation.sample(
            performanceElapsed: 30,
            exitElapsed: SplashMotionTiming.exitCompleteTime,
            reduceMotion: false
        )
        XCTAssertFalse(exiting.isInteractive)
        XCTAssertEqual(
            exiting.horizontalTravelFactor(
                forWaveAt: 0,
                edge: .trailing,
                count: 8
            ),
            -1
        )

        let reduced = SplashScenePresentation.sample(
            performanceElapsed: 30,
            exitElapsed: 0.4,
            reduceMotion: true
        )
        XCTAssertEqual(reduced, .presented)
        XCTAssertTrue(reduced.isInteractive)
    }

    func testSplashDroneAndPadsBeginWithIntroWithoutChangingZeroAmountGeometry() {
        XCTAssertEqual(
            SplashMotionTiming.noteScoreTime(
                at: SplashMotionTiming.entranceCompleteTime
            ),
            SplashMotionTiming.entranceCompleteTime
        )
        XCTAssertEqual(
            SplashMotionTiming.noteScoreTime(
                at: SplashMotionTiming.noteScoreStartTime
            ),
            0
        )

        let activePresentation = SplashScenePresentation.sample(
            performanceElapsed: SplashMotionTiming.entranceCompleteTime,
            exitElapsed: nil,
            reduceMotion: false
        )
        let activeSamples = SplashWaveGenerator.formulas.map {
            activePresentation.waveMotionSample(for: $0.id)
        }
        XCTAssertEqual(activeSamples.filter(\.isMoving).count, 4)

        for step in 0...640 {
            let elapsed = SplashMotionTiming.entranceCompleteTime
                + Double(step) / 10 * SplashPerformanceScore.tempo.secondsPerBeat
            let samples = SplashPerformanceScore.waveVoices.map {
                SplashPerformanceScore.waveMotionSample(
                    for: $0.actorID,
                    performanceElapsed: elapsed
                )
            }
            XCTAssertEqual(
                samples.filter(\.isMoving).count,
                4,
                "Expected four active ribbon actors at elapsed \(elapsed)"
            )
        }

        let resting = SplashWaveGenerator.ribbons()
        let scoredRest = SplashWaveGenerator.ribbons(motionAmount: 0)
        XCTAssertEqual(resting.count, scoredRest.count)
        for index in resting.indices {
            XCTAssertEqual(resting[index].top, scoredRest[index].top)
            XCTAssertEqual(resting[index].bottom, scoredRest[index].bottom)
        }
    }

    func testSplashLotusesCascadeByPetalAndExitInExactReverse() {
        let beforeEntry = SplashLotusChoreography.sample(
            for: .lotusLeft,
            entryElapsed: SplashLotusChoreography.firstStart
        )
        XCTAssertEqual(beforeEntry, .hidden)

        let leftMidFanTime = SplashLotusChoreography.firstStart + 0.25
        let leftMidFan = SplashLotusChoreography.sample(
            for: .lotusLeft,
            entryElapsed: leftMidFanTime
        )
        XCTAssertGreaterThan(leftMidFan.centerOpacity, 0)
        XCTAssertGreaterThan(leftMidFan.fanProgress, 0)
        XCTAssertEqual(leftMidFan.heartOpacity, 0)

        let cascadeTime = SplashLotusChoreography.firstStart
            + SplashLotusChoreography.cascadeStagger
            + 0.42
        let left = SplashLotusChoreography.sample(
            for: .lotusLeft,
            entryElapsed: cascadeTime
        )
        let center = SplashLotusChoreography.sample(
            for: .lotusCenter,
            entryElapsed: cascadeTime
        )
        let right = SplashLotusChoreography.sample(
            for: .lotusRight,
            entryElapsed: cascadeTime
        )
        XCTAssertGreaterThan(left.fanProgress, center.fanProgress)
        XCTAssertGreaterThan(center.centerOpacity, right.centerOpacity)

        let entryElapsed = SplashLotusChoreography.firstStart + 0.55
        let exitElapsed = (
            SplashLotusChoreography.entryEnd - entryElapsed
        ) / SplashLotusChoreography.activeDuration
            * SplashLotusChoreography.exitDuration
        let entering = SplashScenePresentation.sample(
            performanceElapsed: entryElapsed,
            exitElapsed: nil,
            reduceMotion: false
        )
        let exiting = SplashScenePresentation.sample(
            performanceElapsed: 30,
            exitElapsed: exitElapsed,
            reduceMotion: false
        )
        for actorID in SplashLotusChoreography.order {
            XCTAssertEqual(
                entering.lotusAnimation(for: actorID),
                exiting.lotusAnimation(for: actorID)
            )
        }

        let completedExit = SplashScenePresentation.sample(
            performanceElapsed: 30,
            exitElapsed: SplashLotusChoreography.exitDuration,
            reduceMotion: false
        )
        for actorID in SplashLotusChoreography.order {
            XCTAssertEqual(completedExit.lotusAnimation(for: actorID), .hidden)
        }

        let interruptedEntryElapsed = SplashLotusChoreography.firstStart + 0.30
        let justBeforeExit = SplashScenePresentation.sample(
            performanceElapsed: interruptedEntryElapsed,
            exitElapsed: nil,
            reduceMotion: false
        )
        let exitStart = SplashScenePresentation.sample(
            performanceElapsed: interruptedEntryElapsed,
            exitElapsed: 0,
            reduceMotion: false
        )
        for actorID in SplashLotusChoreography.order {
            XCTAssertEqual(
                exitStart.lotusAnimation(for: actorID),
                justBeforeExit.lotusAnimation(for: actorID)
            )
        }
    }

    func testSplashRibbonUnfurlUsesZeroWidthProceduralFrontiers() {
        let ribbons = SplashWaveGenerator.ribbons(motionAmount: 0)
        let trailingRibbon = ribbons[0]
        let leadingRibbon = ribbons[1]

        let leadingEntry = SplashWaveGenerator.applying(
            .entering(progress: 0.42, edge: .leading),
            to: leadingRibbon
        )
        XCTAssertEqual(leadingEntry.top.last!.x, 0.42, accuracy: 0.000_001)
        XCTAssertEqual(leadingEntry.bottom.last!.x, 0.42, accuracy: 0.000_001)
        XCTAssertEqual(leadingEntry.top.last!.y, leadingEntry.bottom.last!.y, accuracy: 0.000_001)
        XCTAssertGreaterThan(leadingEntry.bottom.first!.y - leadingEntry.top.first!.y, 0.01)

        let trailingEntry = SplashWaveGenerator.applying(
            .entering(progress: 0.42, edge: .trailing),
            to: trailingRibbon
        )
        XCTAssertEqual(trailingEntry.top.first!.x, 0.58, accuracy: 0.000_001)
        XCTAssertEqual(trailingEntry.bottom.first!.x, 0.58, accuracy: 0.000_001)
        XCTAssertEqual(trailingEntry.top.first!.y, trailingEntry.bottom.first!.y, accuracy: 0.000_001)

        let leadingExit = SplashWaveGenerator.applying(
            .exiting(progress: 0.55, entryEdge: .leading),
            to: leadingRibbon
        )
        XCTAssertEqual(leadingExit.top.first!.x, 0.55, accuracy: 0.000_001)
        XCTAssertEqual(leadingExit.top.first!.y, leadingExit.bottom.first!.y, accuracy: 0.000_001)

        let trailingExit = SplashWaveGenerator.applying(
            .exiting(progress: 0.55, entryEdge: .trailing),
            to: trailingRibbon
        )
        XCTAssertEqual(trailingExit.top.last!.x, 0.45, accuracy: 0.000_001)
        XCTAssertEqual(trailingExit.top.last!.y, trailingExit.bottom.last!.y, accuracy: 0.000_001)

        let completedEntry = SplashWaveGenerator.applying(
            .entering(progress: 1, edge: .leading),
            to: leadingRibbon
        )
        XCTAssertEqual(completedEntry.top, leadingRibbon.top)
        XCTAssertEqual(completedEntry.bottom, leadingRibbon.bottom)

        let notStarted = SplashWaveGenerator.applying(
            .entering(progress: 0, edge: .leading),
            to: leadingRibbon
        )
        let completedExit = SplashWaveGenerator.applying(
            .exiting(progress: 1, entryEdge: .leading),
            to: leadingRibbon
        )
        XCTAssertTrue(notStarted.top.isEmpty)
        XCTAssertTrue(notStarted.bottom.isEmpty)
        XCTAssertTrue(completedExit.top.isEmpty)
        XCTAssertTrue(completedExit.bottom.isEmpty)
    }

    func testSplashNotePacketsAreDeterministicLocalizedAndRestrained() {
        let activeElapsed = SplashMotionTiming.noteScoreStartTime
            + 5 * SplashPerformanceScore.tempo.secondsPerBeat
        let presentation = SplashScenePresentation.sample(
            performanceElapsed: activeElapsed,
            exitElapsed: nil,
            reduceMotion: false
        )
        let resting = SplashWaveGenerator.ribbons()
        let motionSamples = SplashWaveGenerator.formulas.map {
            presentation.waveMotionSample(for: $0.id)
        }
        XCTAssertEqual(motionSamples.filter { $0.amplitude > 0 }.count, 2)

        let packetOnlySamples = motionSamples.map {
            SplashWaveMotionSample(
                phase: $0.phase,
                amplitude: $0.amplitude,
                packetCenter: $0.packetCenter,
                packetHalfWidth: $0.packetHalfWidth
            )
        }

        let firstSample = SplashWaveGenerator.ribbons(
            motionSamples: packetOnlySamples
        )
        let secondSample = SplashWaveGenerator.ribbons(
            motionSamples: packetOnlySamples
        )

        var maximumDisplacement: CGFloat = 0
        var changedSamples = 0
        var unchangedSamplesOutsidePackets = 0

        for index in resting.indices {
            XCTAssertEqual(firstSample[index].top, secondSample[index].top)
            XCTAssertEqual(firstSample[index].bottom, secondSample[index].bottom)

            for sampleIndex in resting[index].top.indices {
                let x = resting[index].top[sampleIndex].x
                let topDelta = abs(
                    firstSample[index].top[sampleIndex].y
                        - resting[index].top[sampleIndex].y
                )
                let bottomDelta = abs(
                    firstSample[index].bottom[sampleIndex].y
                        - resting[index].bottom[sampleIndex].y
                )
                maximumDisplacement = max(maximumDisplacement, topDelta, bottomDelta)
                if max(topDelta, bottomDelta) > 0.000_001 {
                    changedSamples += 1
                }

                let packetGain = SplashWaveGenerator.travelingPacketGain(
                    at: x,
                    center: packetOnlySamples[index].packetCenter,
                    halfWidth: packetOnlySamples[index].packetHalfWidth
                )
                if packetGain == 0 {
                    XCTAssertEqual(topDelta, 0, accuracy: 0.000_001)
                    XCTAssertEqual(bottomDelta, 0, accuracy: 0.000_001)
                    unchangedSamplesOutsidePackets += 1
                }

                XCTAssertGreaterThan(
                    firstSample[index].bottom[sampleIndex].y
                        - firstSample[index].top[sampleIndex].y,
                    0.01
                )
            }
        }

        XCTAssertGreaterThan(maximumDisplacement, 0.000_5)
        XCTAssertLessThan(maximumDisplacement, 0.08)
        XCTAssertGreaterThan(changedSamples, 0)
        XCTAssertGreaterThan(unchangedSamplesOutsidePackets, changedSamples)

        let early = SplashPerformanceScore.waveMotionSample(
            for: .waveRearPeriwinkle,
            performanceElapsed:
                SplashMotionTiming.noteScoreStartTime
                + 4 * SplashPerformanceScore.tempo.secondsPerBeat
        )
        let later = SplashPerformanceScore.waveMotionSample(
            for: .waveRearPeriwinkle,
            performanceElapsed:
                SplashMotionTiming.noteScoreStartTime
                + 6 * SplashPerformanceScore.tempo.secondsPerBeat
        )
        XCTAssertGreaterThan(later.packetCenter, early.packetCenter)
    }

    func testSplashLivingMotionIsPerceptibleOverOneSecond() {
        let startTime = SplashMotionTiming.noteScoreStartTime
            + 5 * SplashPerformanceScore.tempo.secondsPerBeat
        let endTime = startTime + 1
        let startPresentation = SplashScenePresentation.sample(
            performanceElapsed: startTime,
            exitElapsed: nil,
            reduceMotion: false
        )
        let endPresentation = SplashScenePresentation.sample(
            performanceElapsed: endTime,
            exitElapsed: nil,
            reduceMotion: false
        )
        let startRibbons = SplashWaveGenerator.ribbons(
            motionSamples: SplashWaveGenerator.formulas.map {
                startPresentation.waveMotionSample(for: $0.id)
            }
        )
        let endRibbons = SplashWaveGenerator.ribbons(
            motionSamples: SplashWaveGenerator.formulas.map {
                endPresentation.waveMotionSample(for: $0.id)
            }
        )

        var maximumOneSecondDisplacement: CGFloat = 0
        for ribbonIndex in startRibbons.indices {
            for sampleIndex in startRibbons[ribbonIndex].top.indices {
                maximumOneSecondDisplacement = max(
                    maximumOneSecondDisplacement,
                    abs(
                        endRibbons[ribbonIndex].top[sampleIndex].y
                            - startRibbons[ribbonIndex].top[sampleIndex].y
                    ),
                    abs(
                        endRibbons[ribbonIndex].bottom[sampleIndex].y
                            - startRibbons[ribbonIndex].bottom[sampleIndex].y
                    )
                )
            }
        }

        XCTAssertGreaterThan(maximumOneSecondDisplacement, 0.001)
        XCTAssertLessThan(maximumOneSecondDisplacement, 0.03)

        let cycleStart = SplashMotionTiming.entranceCompleteTime
            + SplashPerformanceScore.noteCycleBeats
                * SplashPerformanceScore.tempo.secondsPerBeat
        for step in 0..<64 {
            let sampleTime = cycleStart
                + Double(step) * 0.5
                    * SplashPerformanceScore.tempo.secondsPerBeat
            let nextTime = sampleTime + 0.75
            let first = SplashWaveGenerator.ribbons(
                motionSamples: SplashWaveGenerator.formulas.map {
                    SplashPerformanceScore.waveMotionSample(
                        for: $0.id,
                        performanceElapsed: sampleTime
                    )
                }
            )
            let second = SplashWaveGenerator.ribbons(
                motionSamples: SplashWaveGenerator.formulas.map {
                    SplashPerformanceScore.waveMotionSample(
                        for: $0.id,
                        performanceElapsed: nextTime
                    )
                }
            )

            let perceptibleRibbonCount = first.indices.filter { ribbonIndex in
                first[ribbonIndex].top.indices.contains { sampleIndex in
                    abs(
                        first[ribbonIndex].top[sampleIndex].y
                            - second[ribbonIndex].top[sampleIndex].y
                    ) > 0.000_6
                        || abs(
                            first[ribbonIndex].bottom[sampleIndex].y
                                - second[ribbonIndex].bottom[sampleIndex].y
                        ) > 0.000_6
                }
            }.count

            XCTAssertGreaterThanOrEqual(
                perceptibleRibbonCount,
                3,
                "Expected at least three visibly moving ribbons at elapsed \(sampleTime)"
            )
        }
    }

    func testSplashWavePhaseNeverRestartsAtNoteBoundaries() {
        let frameInterval = 1.0 / 120.0
        let cycleOffset = SplashPerformanceScore.noteCycleBeats
            * SplashPerformanceScore.tempo.secondsPerBeat

        for event in SplashPerformanceScore.noteEvents {
            let boundary = cycleOffset
                + event.startBeat * SplashPerformanceScore.tempo.secondsPerBeat
            guard let voice = SplashPerformanceScore.waveVoices.first(
                where: { $0.tonalSlot == event.tonalSlot }
            ) else {
                XCTFail("Missing wave voice for tonal slot \(event.tonalSlot)")
                continue
            }
            let before = SplashPerformanceScore.waveMotionSample(
                for: voice.actorID,
                performanceElapsed: boundary - frameInterval
            )
            let after = SplashPerformanceScore.waveMotionSample(
                for: voice.actorID,
                performanceElapsed: boundary + frameInterval
            )
            let expectedAdvance = 2 * frameInterval
                * SplashMotionTiming.motionPhaseUnitsPerSecond

            XCTAssertEqual(
                Double(after.phase - before.phase),
                expectedAdvance,
                accuracy: 0.000_01
            )
            XCTAssertEqual(after.bedPhase, after.phase)
        }
    }

    func testSplashMotionTuningPreservesPhaseWhileSpeedChanges() {
        var tuning = SplashMotionTuning.standard
        let elapsed = SplashMotionTiming.noteScoreStartTime
            + 8
        let activeTime = SplashMotionTiming.noteScoreTime(at: elapsed)
        let phaseBeforeChange = tuning.phaseTime(at: activeTime)

        tuning.setSpeedMultiplier(3, performanceElapsed: elapsed)

        XCTAssertEqual(
            tuning.phaseTime(at: activeTime),
            phaseBeforeChange,
            accuracy: 0.000_001
        )
        XCTAssertEqual(tuning.speedMultiplier, 3)

        let laterActiveTime = SplashMotionTiming.noteScoreTime(
            at: elapsed + 2
        )
        XCTAssertEqual(
            tuning.phaseTime(at: laterActiveTime),
            phaseBeforeChange + (laterActiveTime - activeTime) * 3,
            accuracy: 0.000_001
        )

        tuning.setAmountMultiplier(8)
        XCTAssertEqual(tuning.amountMultiplier, 2)

        tuning.reset(performanceElapsed: elapsed + 2)
        XCTAssertEqual(tuning.speedMultiplier, 1)
        XCTAssertEqual(tuning.amountMultiplier, 1)
    }
    func testSplashADSRDefinesEveryNoteLifecycleBoundary() throws {
        let envelope = SplashPerformanceScore.noteEnvelope
        let gateBeats = 10.0

        let attackStart = try XCTUnwrap(
            envelope.sample(localBeat: 0, gateBeats: gateBeats)
        )
        XCTAssertEqual(attackStart.stage, .attack)
        XCTAssertEqual(attackStart.value, 0)

        let decayStart = try XCTUnwrap(
            envelope.sample(
                localBeat: envelope.attackBeats,
                gateBeats: gateBeats
            )
        )
        XCTAssertEqual(decayStart.stage, .decay)
        XCTAssertEqual(decayStart.value, 1, accuracy: 0.000_001)

        let sustainStart = try XCTUnwrap(
            envelope.sample(
                localBeat: envelope.attackBeats + envelope.decayBeats,
                gateBeats: gateBeats
            )
        )
        XCTAssertEqual(sustainStart.stage, .sustain)
        XCTAssertEqual(
            sustainStart.value,
            envelope.sustainLevel,
            accuracy: 0.000_001
        )

        let releaseStart = try XCTUnwrap(
            envelope.sample(localBeat: gateBeats, gateBeats: gateBeats)
        )
        XCTAssertEqual(releaseStart.stage, .release)
        XCTAssertEqual(
            releaseStart.value,
            envelope.sustainLevel,
            accuracy: 0.000_001
        )
        XCTAssertNil(
            envelope.sample(
                localBeat: gateBeats + envelope.releaseBeats,
                gateBeats: gateBeats
            )
        )
    }

    func testSplashTravelingPacketHasSmoothCompactSupport() {
        let center: CGFloat = 0.4
        let halfWidth: CGFloat = 0.2

        XCTAssertEqual(
            SplashWaveGenerator.travelingPacketGain(
                at: center,
                center: center,
                halfWidth: halfWidth
            ),
            1,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            SplashWaveGenerator.travelingPacketGain(
                at: center - halfWidth,
                center: center,
                halfWidth: halfWidth
            ),
            0
        )
        XCTAssertEqual(
            SplashWaveGenerator.travelingPacketGain(
                at: center + halfWidth,
                center: center,
                halfWidth: halfWidth
            ),
            0
        )
        XCTAssertEqual(
            SplashWaveGenerator.travelingPacketGain(
                at: center - halfWidth / 2,
                center: center,
                halfWidth: halfWidth
            ),
            SplashWaveGenerator.travelingPacketGain(
                at: center + halfWidth / 2,
                center: center,
                halfWidth: halfWidth
            ),
            accuracy: 0.000_001
        )
    }




    func testSplashUsesResponsiveCompositionModes() {
        XCTAssertEqual(
            SplashLayout.mode(for: CGSize(width: 1_366, height: 1_024)),
            .wideLandscape
        )
        XCTAssertEqual(
            SplashLayout.mode(for: CGSize(width: 852, height: 393)),
            .compactLandscape
        )
        XCTAssertEqual(
            SplashLayout.mode(for: CGSize(width: 1_024, height: 1_366)),
            .tabletPortrait
        )
        XCTAssertEqual(
            SplashLayout.mode(for: CGSize(width: 393, height: 852)),
            .phonePortrait
        )
    }

    func testSplashWaveWorldDoesNotReshapeAcrossRotation() {
        let iPadLandscape = SplashLayout(size: CGSize(width: 1_180, height: 820))
        let iPadPortrait = SplashLayout(size: CGSize(width: 820, height: 1_180))
        XCTAssertEqual(iPadLandscape.waveWorldSize, iPadPortrait.waveWorldSize)
        XCTAssertEqual(
            iPadLandscape.waveWorldVerticalOffset,
            iPadPortrait.waveWorldVerticalOffset
        )
        XCTAssertEqual(iPadLandscape.sunDiameter, iPadPortrait.sunDiameter)
        XCTAssertEqual(iPadLandscape.wordmarkFontSize, iPadPortrait.wordmarkFontSize)
        XCTAssertEqual(iPadLandscape.navigationFontSize, iPadPortrait.navigationFontSize)

        let iPhoneLandscape = SplashLayout(size: CGSize(width: 874, height: 402))
        let iPhonePortrait = SplashLayout(size: CGSize(width: 402, height: 874))
        XCTAssertEqual(iPhoneLandscape.waveWorldSize, iPhonePortrait.waveWorldSize)
        XCTAssertEqual(
            iPhoneLandscape.waveWorldVerticalOffset,
            iPhonePortrait.waveWorldVerticalOffset
        )
        XCTAssertEqual(iPhoneLandscape.sunDiameter, iPhonePortrait.sunDiameter)
        XCTAssertEqual(iPhoneLandscape.wordmarkFontSize, iPhonePortrait.wordmarkFontSize)
        XCTAssertEqual(iPhoneLandscape.navigationFontSize, iPhonePortrait.navigationFontSize)
    }

    func testSplashWaveGeneratorMaintainsSymmetricCoverageEnvelope() {
        let coverage = SplashWaveGenerator.coverageRibbon()
        let pointCount = coverage.top.count
        var largestOuterCenterDifference: CGFloat = 0

        for leftIndex in 0..<(pointCount / 2) {
            let rightIndex = pointCount - 1 - leftIndex
            let leftTop = coverage.top[leftIndex].y
            let rightTop = coverage.top[rightIndex].y
            let leftBottom = coverage.bottom[leftIndex].y
            let rightBottom = coverage.bottom[rightIndex].y

            XCTAssertEqual(
                leftBottom - leftTop,
                rightBottom - rightTop,
                accuracy: 0.000_001
            )
            largestOuterCenterDifference = max(
                largestOuterCenterDifference,
                abs((leftTop + leftBottom) / 2 - (rightTop + rightBottom) / 2)
            )
        }

        XCTAssertGreaterThan(largestOuterCenterDifference, 0.01)

        for motionPhase in [CGFloat(0), 0.25, 0.75, 1] {
            let ribbons = SplashWaveGenerator.ribbons(motionPhase: motionPhase)
            XCTAssertEqual(ribbons.count, 8)

            for ribbon in ribbons {
                XCTAssertEqual(ribbon.top.count, pointCount)
                XCTAssertEqual(ribbon.bottom.count, pointCount)
                for index in ribbon.top.indices {
                    XCTAssertGreaterThan(ribbon.bottom[index].y - ribbon.top[index].y, 0.01)
                }
            }
        }
    }

    func testSplashWaveGeneratorHasNoLocalCurvatureSpikes() {
        for motionPhase in [CGFloat(0), 0.25, 0.75, 1] {
            for ribbon in SplashWaveGenerator.ribbons(motionPhase: motionPhase) {
                for (edgeName, edge) in [
                    ("top", ribbon.top),
                    ("bottom", ribbon.bottom)
                ] {
                    var largestThirdDifference: CGFloat = 0
                    for index in 0..<(edge.count - 3) {
                        let difference = edge[index + 3].y
                            - 3 * edge[index + 2].y
                            + 3 * edge[index + 1].y
                            - edge[index].y
                        largestThirdDifference = max(largestThirdDifference, abs(difference))
                    }

                    XCTAssertLessThan(
                        largestThirdDifference,
                        0.009,
                        "\(ribbon.id.rawValue) \(edgeName) at phase \(motionPhase) developed a visible local curvature spike"
                    )
                }
            }
        }
    }

    func testSplashWaveCoverageEnvelopeContainsEveryIndependentRibbon() {
        let coverage = SplashWaveGenerator.coverageRibbon()

        for motionPhase in [CGFloat(0), 0.25, 0.75, 1] {
            let ribbons = SplashWaveGenerator.ribbons(motionPhase: motionPhase)
            for ribbon in ribbons {
                for sampleIndex in ribbon.top.indices {
                    XCTAssertGreaterThanOrEqual(
                        ribbon.top[sampleIndex].y,
                        coverage.top[sampleIndex].y - 0.000_001,
                        "\(ribbon.id.rawValue) escaped above the coverage sheet"
                    )
                    XCTAssertLessThanOrEqual(
                        ribbon.bottom[sampleIndex].y,
                        coverage.bottom[sampleIndex].y + 0.000_001,
                        "\(ribbon.id.rawValue) escaped below the coverage sheet"
                    )
                }
            }
        }
    }

    func testSplashWaveCenterlinesHaveReferenceLevelPhaseCounterpoint() {
        let ribbons = SplashWaveGenerator.ribbons()

        let fullSynchrony = phaseSynchrony(ribbons: ribbons, range: 0...SplashWaveGenerator.sampleCount)
        let portraitStart = SplashWaveGenerator.sampleCount / 3
        let portraitEnd = SplashWaveGenerator.sampleCount * 2 / 3
        let portraitSynchrony = phaseSynchrony(
            ribbons: ribbons,
            range: portraitStart...portraitEnd
        )

        XCTAssertLessThan(fullSynchrony, 0.48)
        XCTAssertLessThan(portraitSynchrony, 0.50)
        XCTAssertGreaterThan(fullSynchrony, 0.24)
        XCTAssertGreaterThan(portraitSynchrony, 0.24)
    }

    func testProgressIsNormalizedAndClamped() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let session = FocusSession(story: .autumnTree, duration: .fifteenMinutes, startedAt: start)

        XCTAssertEqual(session.progress(at: start.addingTimeInterval(-5)), 0)
        XCTAssertEqual(session.progress(at: start.addingTimeInterval(450)), 0.5)
        XCTAssertEqual(session.progress(at: start.addingTimeInterval(1_200)), 1)
    }

    private func phaseSynchrony(
        ribbons: [SplashWaveRibbon],
        range: ClosedRange<Int>
    ) -> CGFloat {
        let centers = ribbons.map { ribbon in
            ribbon.top.indices.map { index in
                (ribbon.top[index].y + ribbon.bottom[index].y) / 2
            }
        }
        let slopes = centers.map { centerline in
            range.dropLast().map { index in centerline[index + 1] - centerline[index] }
        }
        let magnitudes = slopes.flatMap { $0.map(abs) }.sorted()
        let scale = max(magnitudes[Int(CGFloat(magnitudes.count - 1) * 0.60)], 0.000_001)
        let sampleCount = slopes[0].count

        let agreement = (0..<sampleCount).map { index -> CGFloat in
            let signedMotion = slopes.reduce(CGFloat.zero) { partial, ribbonSlopes in
                partial + tanh(ribbonSlopes[index] / scale)
            } / CGFloat(slopes.count)
            return abs(signedMotion)
        }
        return agreement.reduce(0, +) / CGFloat(agreement.count)
    }

    func testAutumnTreeRevealsDeerNearCompletion() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let session = FocusSession(
            story: .autumnTree,
            duration: .fifteenMinutes,
            startedAt: start,
            randomSeed: 42
        )
        let player = StoryPlayer(session: session)

        let beforeReveal = player.performance(
            at: start.addingTimeInterval(855),
            reduceMotion: false
        )
        let duringReveal = player.performance(
            at: start.addingTimeInterval(882),
            reduceMotion: false
        )

        XCTAssertFalse(beforeReveal.visualState.contains(.autumnDeerVisible))
        XCTAssertTrue(duringReveal.visualState.contains(.autumnDeerVisible))
    }

    func testContemporaryLotusUsesTheSharedStoryPlayerAndStaticReducedMotionState() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let session = FocusSession(
            story: .contemporaryLotus,
            duration: .twentyFiveMinutes,
            startedAt: start,
            randomSeed: 94
        )
        let player = StoryPlayer(session: session)

        XCTAssertTrue(player.scheduledMoments.isEmpty)
        XCTAssertEqual(
            player.performance(at: start.addingTimeInterval(750), reduceMotion: false).beat,
            .contemporaryLotusPondStill
        )
        XCTAssertEqual(
            player.performance(at: start.addingTimeInterval(750), reduceMotion: true).beat,
            .contemporaryLotusPondStill
        )
        XCTAssertTrue(
            player.performance(at: start.addingTimeInterval(750), reduceMotion: true)
                .visualState.contains(.contemporaryLotusPondStage)
        )
    }

#if !SWIFT_PACKAGE
    @MainActor
    func testContemporaryLotusStageUsesIndependentBundledLayers() throws {
        let resources = try ContemporaryLotusStageResources(bundle: .main)

        XCTAssertEqual(resources.layout.id, "standard-ipad-landscape")
        XCTAssertEqual(resources.layout.width, 1_448)
        XCTAssertEqual(resources.layout.height, 1_006)
        XCTAssertNotEqual(resources.layout.background.assetID, resources.layout.mainPadStem.assetID)

        let backgroundURL = try XCTUnwrap(
            ContemporaryLotusStageResources.assetURL(named: resources.layout.background.assetID)
        )
        let padURL = try XCTUnwrap(
            ContemporaryLotusStageResources.assetURL(named: resources.layout.mainPadStem.assetID)
        )
        let background = try XCTUnwrap(UIImage(contentsOfFile: backgroundURL.path)?.cgImage)
        let pad = try XCTUnwrap(UIImage(contentsOfFile: padURL.path)?.cgImage)

        XCTAssertEqual(background.width, 1_448)
        XCTAssertEqual(background.height, 1_086)
        XCTAssertEqual(pad.width, 1_536)
        XCTAssertEqual(pad.height, 1_024)
        XCTAssertFalse([.none, .noneSkipFirst, .noneSkipLast].contains(pad.alphaInfo))

        let backgroundHash = SHA256.hash(data: try Data(contentsOf: backgroundURL))
            .map { String(format: "%02x", $0) }.joined()
        let padHash = SHA256.hash(data: try Data(contentsOf: padURL))
            .map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(backgroundHash, "e033575b591c2b17dcf32ce4830441fab640047f04116771c5fd5c9b5af47dd2")
        XCTAssertEqual(padHash, "dc47fbb35cbd6af363aa05d575b736f32b86250ac07c9d55a2fb6bb2ba35f618")
    }

#endif

    func testRandomMomentScheduleIsDeterministicForSessionSeed() {
        let scheduler = RandomMomentScheduler()
        let rule = makeGustRule()
        let session = StorySessionContext(duration: 900, randomSeed: 1234)

        let firstPlan = scheduler.moments(for: rule, session: session)
        let secondPlan = scheduler.moments(for: rule, session: session)

        XCTAssertFalse(firstPlan.isEmpty)
        XCTAssertEqual(firstPlan, secondPlan)
    }

    func testRandomMomentScheduleChangesWithSessionSeed() {
        let scheduler = RandomMomentScheduler()
        let rule = makeGustRule()

        let firstPlan = scheduler.moments(
            for: rule,
            session: StorySessionContext(duration: 900, randomSeed: 1)
        )
        let secondPlan = scheduler.moments(
            for: rule,
            session: StorySessionContext(duration: 900, randomSeed: 2)
        )

        XCTAssertNotEqual(firstPlan, secondPlan)
    }

    func testRandomMomentCarriesSynchronizedVisualAndAudioCues() throws {
        let moments = RandomMomentScheduler().moments(
            for: makeGustRule(),
            session: StorySessionContext(duration: 900, randomSeed: 99)
        )
        let gust = try XCTUnwrap(moments.first)

        XCTAssertEqual(gust.visualCue?.effect, StoryEffectID(rawValue: "gust"))
        XCTAssertEqual(gust.audioCue?.assetID, "wind-gust")
        XCTAssertEqual(gust.audioCue?.bus, .atmosphere)
        XCTAssertTrue((90...585).contains(gust.startTime))
    }

    func testRandomMomentRulesRespectWindowCooldownAndValueBounds() {
        let rule = RandomMomentRule(
            id: "bounded-gust",
            progressWindow: 0.10...0.65,
            evaluationInterval: 10...10,
            triggerChance: 1,
            cooldown: 30...30,
            duration: 2...5,
            intensity: 0.2...0.8,
            visualEffect: StoryEffectID(rawValue: "gust")
        )
        let moments = RandomMomentScheduler().moments(
            for: rule,
            session: StorySessionContext(duration: 600, randomSeed: 7)
        )

        XCTAssertFalse(moments.isEmpty)
        XCTAssertTrue(moments.allSatisfy { (60...390).contains($0.startTime) })
        XCTAssertTrue(moments.allSatisfy { (2...5).contains($0.duration) })
        XCTAssertTrue(moments.allSatisfy { (0.2...0.8).contains($0.intensity) })

        for pair in zip(moments, moments.dropFirst()) {
            XCTAssertGreaterThanOrEqual(pair.1.startTime - pair.0.startTime, 30)
        }
    }

    func testReduceMotionRemovesAutumnLeafIntensity() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let session = FocusSession(
            story: .autumnTree,
            duration: .fifteenMinutes,
            startedAt: start,
            randomSeed: 42
        )
        let player = StoryPlayer(session: session)
        let midpoint = start.addingTimeInterval(450)

        XCTAssertGreaterThan(
            player.performance(at: midpoint, reduceMotion: false).visualState[.autumnLeafIntensity],
            0
        )
        XCTAssertEqual(
            player.performance(at: midpoint, reduceMotion: true).visualState[.autumnLeafIntensity],
            0
        )
    }

    func testAutumnCastMomentsAreDeterministicContainedAndSeparated() throws {
        let director = AutumnTreeDirector()
        for duration in [60.0, 120, 300, 900, 1_500, 3_000] {
            let context = StorySessionContext(duration: duration, randomSeed: 42)
            let plan = director.makePlan(for: context)
            XCTAssertEqual(plan, director.makePlan(for: context))
            let bird = try XCTUnwrap(plan.moments.first { $0.visualCue?.effect == .autumnBirdFlock })
            let rabbit = try XCTUnwrap(plan.moments.first { $0.visualCue?.effect == .autumnRabbitPeek })
            XCTAssertEqual(plan.moments.filter { $0.visualCue?.effect == .autumnBirdFlock }.count, 1)
            XCTAssertEqual(plan.moments.filter { $0.visualCue?.effect == .autumnRabbitPeek }.count, 1)
            XCTAssertEqual(bird.duration, 18)
            XCTAssertEqual(rabbit.duration, 8)
            XCTAssertGreaterThanOrEqual(bird.startTime, duration * 0.35)
            XCTAssertLessThanOrEqual(bird.endTime, duration * 0.65 + 1e-12)
            XCTAssertGreaterThanOrEqual(rabbit.startTime, duration * 0.70)
            XCTAssertLessThanOrEqual(rabbit.endTime, duration * 0.84 + 1e-12)
            XCTAssertLessThanOrEqual(bird.endTime, rabbit.startTime)
            XCTAssertLessThan(rabbit.endTime, duration * 0.96)
        }
        XCTAssertNotEqual(
            director.makePlan(for: StorySessionContext(duration: 900, randomSeed: 41)),
            director.makePlan(for: StorySessionContext(duration: 900, randomSeed: 42))
        )
    }

    func testAutumnCastDebugDurationsStayRealTimeAndExpiredEventsDoNotReplay() throws {
        let director = AutumnTreeDirector()
        for duration in [60.0, 120] {
            let plan = director.makePlan(for: StorySessionContext(duration: duration, randomSeed: 130_363))
            let bird = try XCTUnwrap(plan.moments.first { $0.id == .autumnBirdFlock })
            let rabbit = try XCTUnwrap(plan.moments.first { $0.id == .autumnRabbitPeek })
            XCTAssertEqual(bird.duration, AutumnCastSchedule.birdDuration)
            XCTAssertEqual(rabbit.duration, AutumnCastSchedule.rabbitDuration)
            let active = director.performance(
                at: StoryContext(
                    progress: bird.startTime / duration,
                    elapsedTime: bird.startTime + 7,
                    duration: duration,
                    reduceMotion: true
                ),
                plan: plan
            )
            XCTAssertTrue(active.activeMoments.contains { $0.id == .autumnBirdFlock })
            let expired = director.performance(
                at: StoryContext(
                    progress: min(1, (bird.endTime + 0.1) / duration),
                    elapsedTime: bird.endTime + 0.1,
                    duration: duration,
                    reduceMotion: false
                ),
                plan: plan
            )
            XCTAssertFalse(expired.activeMoments.contains { $0.id == .autumnBirdFlock })
        }
    }

#if !SWIFT_PACKAGE
    @MainActor
    func testAutumnCastAssetsLoadWithAcceptedHashesAndRegistration() throws {
        let images = try AutumnCastImages(bundle: .main)
        XCTAssertEqual(images.rabbitFrames.count, 12)
        XCTAssertEqual(images.birdFrames.count, 12)
        for (family, frames, urls) in [
            (images.resources.manifest.rabbit, images.rabbitFrames, images.resources.rabbitURLs),
            (images.resources.manifest.bird, images.birdFrames, images.resources.birdURLs)
        ] {
            XCTAssertEqual(family.dimensions, [512, 512])
            for index in frames.indices {
                let cgImage = try XCTUnwrap(frames[index].cgImage)
                XCTAssertEqual(cgImage.width, 512)
                XCTAssertEqual(cgImage.height, 512)
                XCTAssertNotEqual(cgImage.alphaInfo, .none)
                XCTAssertFalse([.noneSkipFirst, .noneSkipLast].contains(cgImage.alphaInfo))
                let hash = SHA256.hash(data: try Data(contentsOf: urls[index]))
                    .map { String(format: "%02x", $0) }.joined()
                XCTAssertEqual(hash, family.frames[index].sha256)
            }
        }

        let rabbitPixels = try images.rabbitFrames.map(rgbaPixels)
        let fixedBodyStart = 320 * 512 * 4
        for pixels in rabbitPixels.dropFirst() {
            XCTAssertEqual(Array(pixels[fixedBodyStart...]), Array(rabbitPixels[0][fixedBodyStart...]))
        }
    }
#endif

    func testRabbitPlaybackUsesAcceptedExposuresAndReducedMotionStill() {
        XCTAssertEqual(RabbitPeekConfiguration.frameCount, 12)
        XCTAssertEqual(RabbitPeekConfiguration.frameDuration, 0.2)
        XCTAssertEqual(RabbitPeekConfiguration.gestureDuration, 2.4)
        XCTAssertEqual(RabbitPeekConfiguration.appearance(at: -0.1, reduceMotion: false).opacity, 0)
        XCTAssertEqual(RabbitPeekConfiguration.appearance(at: 1.80, reduceMotion: false).frameIndex, 0)
        XCTAssertEqual(RabbitPeekConfiguration.appearance(at: 1.999, reduceMotion: false).frameIndex, 0)
        XCTAssertEqual(RabbitPeekConfiguration.appearance(at: 2.00, reduceMotion: false).frameIndex, 1)
        XCTAssertEqual(RabbitPeekConfiguration.appearance(at: 3.999, reduceMotion: false).frameIndex, 10)
        XCTAssertEqual(RabbitPeekConfiguration.appearance(at: 4.199, reduceMotion: false).frameIndex, 11)
        XCTAssertEqual(RabbitPeekConfiguration.appearance(at: 8, reduceMotion: false).opacity, 0)

        for time in stride(from: 0.0, through: 8.0, by: 0.1) {
            let still = RabbitPeekConfiguration.appearance(at: time, reduceMotion: true)
            XCTAssertEqual(still.frameIndex, RabbitPeekConfiguration.stableFrameIndex)
            XCTAssertEqual(still.horizontalOffset, time < 8 ? 0 : RabbitPeekConfiguration.hiddenHorizontalOffset)
        }
    }

    func testFlockApprovedCountsSizesExitSeparationAndForwardHeadings() throws {
        XCTAssertEqual(BirdFlockConfiguration.fixedStep, 1.0 / 60.0)
        for count in BirdFlockConfiguration.approvedCounts {
            for bodyLength in BirdFlockConfiguration.approvedBodyLengths {
                let config = try BirdFlockConfiguration(
                    count: count,
                    seed: 130_363,
                    bodyLength: bodyLength
                )
                let trajectory = BirdFlockTrajectory(configuration: config)
                let complete = trajectory.sample(at: 18)
                XCTAssertEqual(complete.agents.count, count)
                XCTAssertTrue(complete.exited, "\(count) birds at \(bodyLength) pt")
                XCTAssertGreaterThanOrEqual(trajectory.minimumSeparationEver, bodyLength * 1.18)
                XCTAssertTrue(trajectory.samples.allSatisfy { sample in
                    sample.agents.allSatisfy {
                        [$0.x, $0.y, $0.velocityX, $0.velocityY].allSatisfy(\.isFinite)
                            && $0.velocityX > 0
                    }
                })
            }
        }
    }

    func testFlockWingPhasesCorrectionsFollowersAndRelaunchSampling() throws {
        let config = try BirdFlockConfiguration(seed: 130_363)
        let trajectory = BirdFlockTrajectory(configuration: config)
        let phaseFrames = Set(trajectory.sample(at: 1.25).agents.map { $0.wingFrame(at: 1.25) })
        XCTAssertGreaterThanOrEqual(phaseFrames.count, 9)
        XCTAssertEqual(trajectory.leaderCorrections.count, 2)
        XCTAssertEqual(try BirdFlockTrajectory(configuration: BirdFlockConfiguration(seed: 230_003)).leaderCorrections.count, 1)
        XCTAssertEqual(trajectory.leaderCorrections.reduce(0) { $0 + $1.offset(at: 5) }, 0)
        XCTAssertEqual(trajectory.leaderCorrections.reduce(0) { $0 + $1.offset(at: 14) }, 0)

        for correction in trajectory.leaderCorrections {
            let corrected = BirdFlockSimulation.state(configuration: config, at: correction.peakTime)
            let baseline = BirdFlockSimulation.state(
                configuration: try BirdFlockConfiguration(seed: 130_363, leaderCorrectionScale: 0),
                at: correction.peakTime
            )
            XCTAssertGreaterThan(abs(corrected.agents[0].y - baseline.agents[0].y), 1.2)
            XCTAssertGreaterThan(abs(corrected.agents[1].y - baseline.agents[1].y), 0.2)
            XCTAssertLessThan(
                abs(corrected.agents[1].y - baseline.agents[1].y),
                abs(corrected.agents[0].y - baseline.agents[0].y)
            )
        }

        let restored = BirdFlockTrajectory(configuration: config)
        for time in [0.0, 1, 7, 7.794125442193649, 11.150824238086381, 18] {
            XCTAssertEqual(trajectory.sample(at: time), restored.sample(at: time))
        }
    }

    func testGravityGateRejectsHorizontalOrUpwardGravity() {
        XCTAssertThrowsError(
            try makeGravityConfiguration(
                gravity: PhysicsVector(x: 1, y: -1.2)
            ).validated()
        )
        XCTAssertThrowsError(
            try makeGravityConfiguration(
                gravity: PhysicsVector(x: 0, y: 90)
            ).validated()
        )
    }

    func testGravityGateAcceptsNormalizedPassiveLeafConfiguration() throws {
        let configuration = try makeGravityConfiguration().validated()

        XCTAssertEqual(configuration.gravity, PhysicsVector(x: 0, y: -1.2))
        XCTAssertGreaterThan(configuration.mass, 0)
        XCTAssertGreaterThanOrEqual(configuration.collisionHull.count, 3)
    }

    func testStillAirDragOpposesLeafVelocity() throws {
        let dragConfiguration = try makeDragConfiguration().validated()
        let velocity = PhysicsVector(x: 45, y: -120)
        let force = LeafAerodynamics.stillAirDrag(
            leafVelocity: velocity,
            configuration: dragConfiguration
        )

        XCTAssertLessThan(force.x * velocity.x + force.y * velocity.y, 0)
        XCTAssertLessThan(force.x, 0)
        XCTAssertGreaterThan(force.y, 0)
    }

    func testZeroRelativeAirflowProducesZeroDrag() throws {
        let force = LeafAerodynamics.stillAirDrag(
            leafVelocity: .zero,
            configuration: try makeDragConfiguration().validated()
        )

        XCTAssertEqual(force, .zero)
    }

    func testConfiguredDragSlowsPassiveFallRelativeToApprovedGate1Baseline() throws {
        let baseline = try makeGravityConfiguration().validated()
        let gate2 = try makeGravityConfiguration(
            stillAirDrag: makeDragConfiguration()
        ).validated()

        let baselineSpeed = simulatedVerticalSpeed(after: 3, configuration: baseline)
        let gate2Speed = simulatedVerticalSpeed(after: 3, configuration: gate2)

        XCTAssertLessThan(abs(gate2Speed), abs(baselineSpeed))
    }

    func testFlutterLiftIsBoundedOddAndReversesAcrossBroadside() throws {
        let config = try makeFlutterConfiguration().validated()
        for degrees in stride(from: -720.0, through: 720.0, by: 1) {
            let angle = degrees * .pi / 180
            let positive = LeafAerodynamics.liftCoefficient(angleOfAttack: angle, configuration: config)
            let negative = LeafAerodynamics.liftCoefficient(angleOfAttack: -angle, configuration: config)
            XCTAssertLessThanOrEqual(abs(positive), config.maximumLiftCoefficient)
            XCTAssertEqual(positive, -negative, accuracy: 1e-12)
        }
        for degrees in [0.0, 90, 180] {
            XCTAssertEqual(LeafAerodynamics.liftCoefficient(angleOfAttack: degrees * .pi / 180,
                                                           configuration: config), 0, accuracy: 1e-12)
        }
        XCTAssertGreaterThan(LeafAerodynamics.liftCoefficient(angleOfAttack: .pi / 4, configuration: config), 0)
        XCTAssertLessThan(LeafAerodynamics.liftCoefficient(angleOfAttack: 3 * .pi / 4, configuration: config), 0)
    }

    func testFlutterZeroAirflowProducesNoForceOrResistance() {
        let sample = flutterSample(velocity: .zero)
        XCTAssertEqual(sample.dragForceNewtons, .zero)
        XCTAssertEqual(sample.liftForceNewtons, .zero)
        XCTAssertEqual(sample.resistanceTorqueNewtonMeters, 0)
    }

    func testFlutterDragDissipatesAndLiftIsPerpendicularToLocalAirflow() {
        for rotation in [-2.0, -0.4, 0.0, 0.7, 2.5] {
            let sample = flutterSample(velocity: PhysicsVector(x: 40, y: -150), spin: 1.2, rotation: rotation)
            let air = sample.relativeAirVelocity
            XCTAssertGreaterThan(sample.dragForceNewtons.x * air.x + sample.dragForceNewtons.y * air.y, 0)
            XCTAssertEqual(sample.liftForceNewtons.x * air.x + sample.liftForceNewtons.y * air.y, 0, accuracy: 1e-12)
            XCTAssertTrue((0.18...1).contains(sample.projectedAreaFraction))
            XCTAssertLessThan(sample.resistanceTorqueNewtonMeters, 0)
        }
        XCTAssertGreaterThan(flutterSample(velocity: .zero, spin: -1).resistanceTorqueNewtonMeters, 0)
    }

    func testPressurePointTransformRotatesScalesThenTranslates() {
        let result = LeafAerodynamics.scenePoint(local: NormalizedPhysicsPoint(x: 0.1, y: 0.2),
                                                size: PhysicsVector(x: 100, y: 50),
                                                rotation: .pi / 2, position: PhysicsVector(x: 300, y: 400))
        XCTAssertEqual(result.x, 290, accuracy: 1e-10)
        XCTAssertEqual(result.y, 410, accuracy: 1e-10)
    }

    func testUniformHullCentroidAndPressureForceGenerateTorqueFromRest() {
        let hull = [NormalizedPhysicsPoint(x: -0.4, y: -0.2),
                    NormalizedPhysicsPoint(x: 0.2, y: -0.2),
                    NormalizedPhysicsPoint(x: 0.2, y: 0.4),
                    NormalizedPhysicsPoint(x: -0.4, y: 0.4)]
        let center = LeafAerodynamics.centerOfMass(hull: hull)
        XCTAssertEqual(center.x, -0.1, accuracy: 1e-12)
        XCTAssertEqual(center.y, 0.1, accuracy: 1e-12)
        let reversed = LeafAerodynamics.centerOfMass(hull: hull.reversed())
        XCTAssertEqual(center.x, reversed.x, accuracy: 1e-12)
        let sample = flutterSample(velocity: PhysicsVector(x: 0, y: -120))
        let arm = PhysicsVector(x: sample.centerOfPressure.x - sample.centerOfMass.x,
                                y: sample.centerOfPressure.y - sample.centerOfMass.y)
        XCTAssertGreaterThan(arm.x * sample.forceNewtons.y - arm.y * sample.forceNewtons.x, 0)
        XCTAssertEqual(sample.resistanceTorqueNewtonMeters, 0)
    }

    func testLocalAirflowIncludesRigidBodyRotationWithoutEnergyInjection() {
        let velocity = PhysicsVector(x: 30, y: -130)
        let spin = 0.8
        let sample = flutterSample(velocity: velocity, spin: spin)
        let rx = sample.centerOfPressure.x - sample.centerOfMass.x
        let ry = sample.centerOfPressure.y - sample.centerOfMass.y
        XCTAssertEqual(sample.relativeAirVelocity.x, -velocity.x + spin * ry, accuracy: 1e-12)
        XCTAssertEqual(sample.relativeAirVelocity.y, -velocity.y - spin * rx, accuracy: 1e-12)
        let force = sample.forceNewtons
        let translationalPower = force.x * velocity.x + force.y * velocity.y
        let rotationalPower = (rx * force.y - ry * force.x) * spin
        XCTAssertLessThan(translationalPower + rotationalPower, 0)
        XCTAssertEqual(sample, flutterSample(velocity: velocity, spin: spin))
    }

    func testResistanceCoupleHasZeroNetForceAndCorrectPhysicalMoment() {
        let center = PhysicsVector(x: 200, y: 300)
        let torque = -0.00001
        for rotation in [-1.0, 0, 1.2, 3.0] {
            let pair = LeafAerodynamics.resistanceCouple(torqueNewtonMeters: torque, center: center,
                                                       radiusScenePoints: 50, rotation: rotation,
                                                       scenePointsPerMeter: 150)
            XCTAssertEqual(pair.count, 2)
            XCTAssertEqual(pair.reduce(0) { $0 + $1.forceNewtons.x }, 0, accuracy: 1e-12)
            XCTAssertEqual(pair.reduce(0) { $0 + $1.forceNewtons.y }, 0, accuracy: 1e-12)
            let moment = pair.reduce(0.0) { sum, application in
                sum + ((application.scenePoint.x - center.x) * application.forceNewtons.y
                       - (application.scenePoint.y - center.y) * application.forceNewtons.x) / 150
            }
            XCTAssertEqual(moment, torque, accuracy: 1e-12)
        }
    }

    func testFlutterConfigurationRequiresDragAndRejectsInvalidPressurePoint() throws {
        var configuration = makeGravityConfiguration()
        configuration.passiveFlutter = makeFlutterConfiguration()
        XCTAssertThrowsError(try configuration.validated())
        let invalid = PassiveFlutterConfiguration(maximumLiftCoefficient: 0.45, liftResponse: .sinTwoAlpha,
                                                 chordAngleRadians: 0, edgeOnAreaFraction: 0.18,
                                                 centerOfPressure: NormalizedPhysicsPoint(x: 0.8, y: 0),
                                                 angularResistanceCoefficient: 0.2)
        XCTAssertThrowsError(try invalid.validated())
        let encoded = try JSONEncoder().encode(makeGravityConfiguration(stillAirDrag: makeDragConfiguration()))
        let decoded = try JSONDecoder().decode(LeafGravityLabConfiguration.self, from: encoded)
        XCTAssertNil(decoded.passiveFlutter)
    }

    func testWindSeedReplayAndFrameOrderIndependence() throws {
        let config = try makeWindConfiguration().validated()
        let field = WindField(configuration: config, seed: 42, mode: .gust)
        XCTAssertEqual(field, WindField(configuration: config, seed: 42, mode: .gust))
        XCTAssertNotEqual(field.gust, WindField(configuration: config, seed: 43, mode: .gust).gust)
        let sample = field.sample(at: .zero, elapsedTime: 1.4)
        _ = field.sample(at: .zero, elapsedTime: 9)
        _ = field.sample(at: .zero, elapsedTime: 0.1)
        XCTAssertEqual(sample, field.sample(at: PhysicsVector(x: 100, y: -200), elapsedTime: 1.4))
        let restored = try JSONDecoder().decode(WindFieldConfiguration.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(field, WindField(configuration: restored, seed: 42, mode: .gust))
    }

    func testSteadyWindIgnoresSeedTimeAndPosition() {
        let config = makeWindConfiguration()
        let first = WindField(configuration: config, seed: 42, mode: .steady)
        let second = WindField(configuration: config, seed: 99, mode: .steady)
        XCTAssertEqual(first, second)
        XCTAssertNil(first.gust)
        for time in [-1.0, 0, 1, 2, 10] {
            let sample = first.sample(at: PhysicsVector(x: time, y: -time), elapsedTime: time)
            XCTAssertEqual(sample.velocityMetersPerSecond, config.steadyVelocityMetersPerSecond)
            XCTAssertEqual(sample.gustEnvelope, 0)
            XCTAssertEqual(sample.phase, .steady)
        }
    }

    func testGustEnvelopeAttackPeakDecayAndContinuity() throws {
        let field = WindField(configuration: makeWindConfiguration(), seed: 42, mode: .gust)
        let gust = try XCTUnwrap(field.gust)
        let start = gust.startSeconds
        let peak = start + gust.attackSeconds
        let decay = peak + gust.peakSeconds
        XCTAssertEqual(gust.envelope(at: start - 1).value, 0)
        XCTAssertEqual(gust.envelope(at: start).value, 0)
        XCTAssertEqual(gust.envelope(at: start + gust.attackSeconds / 2).value, 0.5, accuracy: 1e-12)
        XCTAssertEqual(gust.envelope(at: peak).value, 1)
        XCTAssertEqual(gust.envelope(at: peak + gust.peakSeconds / 2).phase, .peak)
        XCTAssertEqual(gust.envelope(at: decay + gust.decaySeconds / 2).value, 0.5, accuracy: 1e-12)
        XCTAssertEqual(gust.envelope(at: gust.endSeconds).value, 0, accuracy: 1e-12)
        XCTAssertEqual(gust.envelope(at: gust.endSeconds + 10).phase, .ended)
        let epsilon = 1e-6
        for boundary in [start, peak, decay, gust.endSeconds] {
            let left = gust.envelope(at: boundary - epsilon).value
            let center = gust.envelope(at: boundary).value
            let right = gust.envelope(at: boundary + epsilon).value
            XCTAssertEqual(left, right, accuracy: 1e-9)
            XCTAssertEqual((center - left) / epsilon, (right - center) / epsilon, accuracy: 1e-4)
        }
        for step in 0...500 {
            XCTAssertTrue((0...1).contains(gust.envelope(at: Double(step) / 100).value))
        }
        XCTAssertEqual(field.sample(at: .zero, elapsedTime: gust.endSeconds + 1).velocityMetersPerSecond,
                       field.steadyVelocityMetersPerSecond)
    }

    func testGustPlansStayWithinAllConfiguredBounds() throws {
        let config = makeWindConfiguration()
        func check(_ value: Double, _ range: WindParameterRange, file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertGreaterThanOrEqual(value, range.minimum - 1e-12, file: file, line: line)
            XCTAssertLessThanOrEqual(value, range.maximum + 1e-12, file: file, line: line)
        }
        for seed in UInt64(0)..<256 {
            let gust = try XCTUnwrap(WindField(configuration: config, seed: seed, mode: .gust).gust)
            check(gust.startSeconds, config.gust.startSeconds)
            check(gust.attackSeconds, config.gust.attackSeconds)
            check(gust.peakSeconds, config.gust.peakSeconds)
            check(gust.decaySeconds, config.gust.decaySeconds)
            check(hypot(gust.velocityMetersPerSecond.x, gust.velocityMetersPerSecond.y), config.gust.speedMetersPerSecond)
            check(atan2(gust.velocityMetersPerSecond.y, gust.velocityMetersPerSecond.x), config.gust.directionRadians)
        }
    }

    func testExternalAirUsesRelativeVelocityAndPreservesZeroWindBaseline() {
        func sample(air: PhysicsVector, velocity: PhysicsVector, spin: Double = 0) -> LeafAerodynamicSample {
            LeafAerodynamics.sample(airVelocity: air, leafVelocity: velocity, angularVelocity: spin,
                rotation: 0, position: PhysicsVector(x: 300, y: 400), leafSize: PhysicsVector(x: 100, y: 100),
                centerOfMass: NormalizedPhysicsPoint(x: 0, y: 0), drag: makeDragConfiguration(), flutter: makeFlutterConfiguration())
        }
        let velocity = PhysicsVector(x: 40, y: -150)
        XCTAssertEqual(sample(air: .zero, velocity: velocity, spin: 1.2), flutterSample(velocity: velocity, spin: 1.2))
        let advecting = sample(air: velocity, velocity: velocity)
        XCTAssertEqual(advecting.relativeAirVelocity, .zero)
        XCTAssertEqual(advecting.dragForceNewtons, .zero)
        XCTAssertEqual(advecting.liftForceNewtons, .zero)
        let windDriven = sample(air: PhysicsVector(x: 120, y: 0), velocity: PhysicsVector(x: 40, y: 0))
        XCTAssertGreaterThan(windDriven.dragForceNewtons.x, 0) // Accelerates toward air, not against world velocity.
        XCTAssertEqual(sample(air: PhysicsVector(x: 80, y: 0), velocity: .zero), windDriven)
    }

    func testInvalidWindConfigurationIsRejected() throws {
        let valid = makeWindConfiguration()
        let invalid = WindFieldConfiguration(steadyVelocityMetersPerSecond: .zero,
            gust: GustConfiguration(startSeconds: valid.gust.startSeconds,
                attackSeconds: WindParameterRange(minimum: 0, maximum: 0), peakSeconds: valid.gust.peakSeconds,
                decaySeconds: valid.gust.decaySeconds, speedMetersPerSecond: valid.gust.speedMetersPerSecond,
                directionRadians: valid.gust.directionRadians), debugVectorSeconds: 0.7)
        XCTAssertThrowsError(try invalid.validated())
        XCTAssertFalse(WindParameterRange(minimum: 2, maximum: 1).isValid)
        XCTAssertFalse(WindParameterRange(minimum: .nan, maximum: 1).isValid)
        var config = makeGravityConfiguration(stillAirDrag: makeDragConfiguration())
        config.wind = valid
        XCTAssertThrowsError(try config.validated())
        config.passiveFlutter = makeFlutterConfiguration()
        XCTAssertNoThrow(try config.validated())
    }

    private func makeWindConfiguration() -> WindFieldConfiguration {
        WindFieldConfiguration(steadyVelocityMetersPerSecond: PhysicsVector(x: 0.25, y: 0),
            gust: GustConfiguration(startSeconds: WindParameterRange(minimum: 0.9, maximum: 1.15),
                attackSeconds: WindParameterRange(minimum: 0.45, maximum: 0.65),
                peakSeconds: WindParameterRange(minimum: 0.2, maximum: 0.3),
                decaySeconds: WindParameterRange(minimum: 0.8, maximum: 1.1),
                speedMetersPerSecond: WindParameterRange(minimum: 0.6, maximum: 0.9),
                directionRadians: WindParameterRange(minimum: -0.12, maximum: 0.12)), debugVectorSeconds: 0.7)
    }

#if !SWIFT_PACKAGE
    func testGroupPlanReconstructsAndDifferentSeedsVary() throws {
        let config = try LeafGroupConfiguration.bundled.get()
        let reference = try LeafGravityLabConfiguration.gate4Bundled.get()
        let first = try LeafGroupPlan(configuration: config, reference: reference, seed: 42)
        XCTAssertEqual(first, try LeafGroupPlan(configuration: config, reference: reference, seed: 42))
        XCTAssertNotEqual(first.members, try LeafGroupPlan(configuration: config, reference: reference, seed: 43).members)
        XCTAssertEqual(first, try JSONDecoder().decode(LeafGroupPlan.self, from: JSONEncoder().encode(first)))
        XCTAssertEqual(Set(first.members.map(\.id)).count, 6)
    }

    func testGroupSizeAreaMassAndReleaseBoundsAcrossSeeds() throws {
        let config = try LeafGroupConfiguration.bundled.get()
        let reference = try LeafGravityLabConfiguration.gate4Bundled.get()
        let area = try XCTUnwrap(reference.stillAirDrag).referenceAreaSquareMeters
        func contains(_ value: Double, _ range: WindParameterRange) -> Bool {
            (range.minimum...range.maximum).contains(value)
        }
        for seed in UInt64(0)..<256 {
            let plan = try LeafGroupPlan(configuration: config, reference: reference, seed: seed)
            XCTAssertEqual(plan.members.count, 6)
            var strata = Set<Int>()
            for leaf in plan.members {
                XCTAssertTrue(contains(leaf.linearScale, config.linearScale))
                strata.insert(Int((leaf.linearScale - config.linearScale.minimum)
                    / (config.linearScale.maximum - config.linearScale.minimum) * 6))
                XCTAssertTrue(contains(leaf.arealDensityScale, config.arealDensityScale))
                XCTAssertEqual(leaf.areaSquareMeters, area * pow(leaf.linearScale, 2), accuracy: 1e-12)
                XCTAssertEqual(leaf.massKilograms, reference.mass * pow(leaf.linearScale, 2) * leaf.arealDensityScale, accuracy: 1e-12)
                XCTAssertEqual(leaf.massKilograms / leaf.areaSquareMeters, reference.mass / area * leaf.arealDensityScale, accuracy: 1e-12)
                XCTAssertTrue(contains(leaf.centerOfPressure.x, config.pressureX))
                XCTAssertTrue(contains(leaf.centerOfPressure.y, config.pressureY))
                XCTAssertTrue(contains(leaf.releasePoint.x, config.releaseX))
                XCTAssertTrue(contains(leaf.releasePoint.y, config.releaseY))
                XCTAssertTrue(contains(leaf.releaseSeconds, config.releaseSeconds))
                XCTAssertTrue(contains(leaf.initialTiltRadians, config.initialTiltRadians))
                XCTAssertTrue(contains(leaf.initialVelocityMetersPerSecond.x, config.initialVelocityX))
                XCTAssertTrue(contains(leaf.initialVelocityMetersPerSecond.y, config.initialVelocityY))
                XCTAssertEqual(leaf.initialAngularVelocity, 0)
                XCTAssertTrue(config.assetIDs.contains(leaf.assetID))
            }
            XCTAssertEqual(strata.count, 6)
        }
    }

    func testGroupAirIsSharedAndPreservesApprovedWindSeed() throws {
        let reference = try LeafGravityLabConfiguration.gate4Bundled.get()
        let config = try LeafGroupConfiguration.bundled.get()
        let plan = try LeafGroupPlan(configuration: config, reference: reference, seed: 42)
        let windConfig = try XCTUnwrap(reference.wind)
        let field = plan.wind(reference: windConfig)
        XCTAssertEqual(field, WindField(configuration: windConfig, seed: 42, mode: .gust))
        for time in [0.0, 0.5, 1.5, 2, 3, 6] {
            let expected = field.sample(at: .zero, elapsedTime: time)
            for leaf in plan.members {
                XCTAssertEqual(field.sample(at: PhysicsVector(x: leaf.releasePoint.x, y: leaf.releasePoint.y), elapsedTime: time), expected)
            }
        }
    }

    func testGroupAreaChangesForceAndDensityChangesAcceleration() throws {
        let reference = try LeafGravityLabConfiguration.gate4Bundled.get()
        let plan = try LeafGroupPlan(configuration: LeafGroupConfiguration.bundled.get(), reference: reference, seed: 42)
        let drag = try XCTUnwrap(reference.stillAirDrag)
        let flutter = try XCTUnwrap(reference.passiveFlutter)
        var forcePerArea: Double?
        var scaledAcceleration: Double?
        for leaf in plan.members {
            let sample = LeafAerodynamics.sample(airVelocity: PhysicsVector(x: 40, y: 0),
                leafVelocity: PhysicsVector(x: 0, y: -150), angularVelocity: 0, rotation: 0.3,
                position: .zero, leafSize: PhysicsVector(x: 100 * leaf.linearScale, y: 100 * leaf.linearScale),
                centerOfMass: NormalizedPhysicsPoint(x: 0, y: 0), drag: leaf.drag(from: drag), flutter: leaf.flutter(from: flutter))
            let magnitude = hypot(sample.forceNewtons.x, sample.forceNewtons.y)
            let normalizedForce = magnitude / leaf.areaSquareMeters
            let normalizedAcceleration = magnitude / leaf.massKilograms * leaf.arealDensityScale
            if let forcePerArea { XCTAssertEqual(normalizedForce, forcePerArea, accuracy: 1e-12) }
            if let scaledAcceleration { XCTAssertEqual(normalizedAcceleration, scaledAcceleration, accuracy: 1e-12) }
            forcePerArea = normalizedForce
            scaledAcceleration = normalizedAcceleration
        }
    }

    func testInvalidGroupCountAndScaleAreRejected() throws {
        let config = try LeafGroupConfiguration.bundled.get()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
        json["count"] = 5
        var decoded = try JSONDecoder().decode(LeafGroupConfiguration.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertThrowsError(try decoded.validated())
        json["count"] = 6
        json["linearScale"] = ["minimum": -0.5, "maximum": 1.0]
        decoded = try JSONDecoder().decode(LeafGroupConfiguration.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertThrowsError(try decoded.validated())
    }

    @MainActor
    func testTerrainProfileMatchesBundledArtworkAndRejectsInvalidBounds() throws {
        let config = try LeafTerrainConfiguration.bundled.get()
        XCTAssertEqual(try config.validated(), config)
        let url = try XCTUnwrap(AutumnTreeSceneResources.assetURL(named: config.assetID))
        let data = try Data(contentsOf: url)
        XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), config.sourceSHA256)
        let image = try XCTUnwrap(UIImage(data: data)?.cgImage)
        XCTAssertEqual(image.width, config.sourcePixelWidth)
        XCTAssertEqual(image.height, config.sourcePixelHeight)
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var maximumError = 0.0
        for x in 0..<width {
            let y = try XCTUnwrap((0..<height).first { pixels[($0 * width + x) * 4 + 3] >= config.alphaThreshold })
            let edge = 1 - Double(y) / Double(height - 1)
            maximumError = max(maximumError, abs(edge - config.surfaceHeight(at: Double(x) / Double(width - 1))))
        }
        // < 2.2 scene points for the proof's 610-point viewport, including paper-edge texture.
        XCTAssertLessThan(maximumError, 0.012)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
        for (key, value) in [("friction", -1.0), ("restitution", 0.8), ("quietContactSeconds", 0.0)] {
            var invalid = object
            invalid[key] = value
            let decoded = try JSONDecoder().decode(LeafTerrainConfiguration.self, from: JSONSerialization.data(withJSONObject: invalid))
            XCTAssertThrowsError(try decoded.validated())
        }
        object["surface"] = [["x": 1.0, "y": 0.5], ["x": 0.0, "y": 0.5]]
        let reversed = try JSONDecoder().decode(LeafTerrainConfiguration.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try reversed.validated())
    }

    func testSettlingRequiresContinuousQuietSupportAndResets() throws {
        let config = try LeafTerrainConfiguration.bundled.get()
        var state = LeafSettlingTracker()
        XCTAssertFalse(state.update(touchingGround: false, linearSpeed: 0, angularSpeed: 0, deltaTime: 10, configuration: config))
        XCTAssertFalse(state.hasTouchedGround)
        XCTAssertFalse(state.update(touchingGround: true, linearSpeed: 0, angularSpeed: 0, deltaTime: 0.4, configuration: config))
        XCTAssertTrue(state.hasTouchedGround)
        XCTAssertFalse(state.update(touchingGround: true, linearSpeed: 0.2, angularSpeed: 0, deltaTime: 0.4, configuration: config))
        XCTAssertEqual(state.quietSeconds, 0)
        XCTAssertFalse(state.update(touchingGround: true, linearSpeed: 0, angularSpeed: 1, deltaTime: 1, configuration: config))
        XCTAssertFalse(state.update(touchingGround: true, linearSpeed: .nan, angularSpeed: 0, deltaTime: 1, configuration: config))
        XCTAssertFalse(state.update(touchingGround: true, linearSpeed: 0, angularSpeed: 0, deltaTime: 0.4, configuration: config))
        XCTAssertFalse(state.update(touchingGround: false, linearSpeed: 0, angularSpeed: 0, deltaTime: 0.1, configuration: config))
        XCTAssertEqual(state.quietSeconds, 0)
        XCTAssertFalse(state.update(touchingGround: true, linearSpeed: 0, angularSpeed: 0, deltaTime: 0.4, configuration: config))
        XCTAssertTrue(state.update(touchingGround: true, linearSpeed: 0, angularSpeed: 0, deltaTime: 0.3, configuration: config))
        XCTAssertTrue(state.isSettled)
        XCTAssertFalse(state.update(touchingGround: true, linearSpeed: 0, angularSpeed: 0, deltaTime: 1, configuration: config))
        state = LeafSettlingTracker()
        XCTAssertFalse(state.isSettled)
        XCTAssertFalse(state.hasTouchedGround)
    }

    func testLeafCollidersMatchOpaqueArtworkAtEveryDegree() throws {
        let catalog = try LeafCollisionCatalog.bundled.get()
        XCTAssertEqual(Set(catalog.shapes.map(\.assetID)), Set(try LeafGroupConfiguration.bundled.get().assetIDs))
        let oldHull = try LeafGravityLabConfiguration.gate4Bundled.get().collisionHull
        var originalRedGap = 0.0
        for shape in catalog.shapes {
            let bitmap = try decodedBitmap(assetID: shape.assetID)
            XCTAssertEqual(bitmap.width, shape.sourcePixelWidth)
            XCTAssertEqual(bitmap.height, shape.sourcePixelHeight)
            let url = try XCTUnwrap(AutumnTreeSceneResources.assetURL(named: shape.assetID))
            XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined(), shape.sourceSHA256)
            let boundary = opaqueBoundary(bitmap, threshold: catalog.alphaThreshold)
            let aspect = Double(bitmap.height) / Double(bitmap.width)
            // Every fitted vertex is an actual opaque pixel center, never padding.
            for p in shape.hull {
                let x = Int(((p.x + 0.5) * Double(bitmap.width) - 0.5).rounded())
                let y = Int(((0.5 - p.y) * Double(bitmap.height) - 0.5).rounded())
                XCTAssertGreaterThanOrEqual(Int(bitmap.pixels[(y * bitmap.width + x) * 4 + 3]), catalog.alphaThreshold)
            }
            for degrees in 0..<360 {
                let angle = Double(degrees) * .pi / 180
                func support(_ p: NormalizedPhysicsPoint) -> Double { p.x * sin(angle) + p.y * aspect * cos(angle) }
                let visible = try XCTUnwrap(boundary.map(support).min())
                let fitted = try XCTUnwrap(shape.hull.map(support).min())
                XCTAssertEqual(visible, fitted, accuracy: 1e-10, "\(shape.assetID), angle \(degrees)")
                if shape.assetID == "leaf-maple-red" {
                    originalRedGap = max(originalRedGap, visible - (oldHull.map(support).min() ?? 0))
                }
            }
        }
        // The same measurement detects the reported defect in the previous collider.
        XCTAssertGreaterThan(originalRedGap, 0.04)
    }

    func testLeafColliderCatalogRejectsMalformedShapes() throws {
        let catalog = try LeafCollisionCatalog.bundled.get()
        let original = try XCTUnwrap(catalog.shapes.first)
        func shape(_ hull: [NormalizedPhysicsPoint]) -> LeafCollisionShape {
            LeafCollisionShape(assetID: original.assetID, sourceSHA256: original.sourceSHA256,
                sourcePixelWidth: original.sourcePixelWidth, sourcePixelHeight: original.sourcePixelHeight, hull: hull)
        }
        XCTAssertThrowsError(try shape(Array(original.hull.reversed())).validate())
        XCTAssertThrowsError(try shape(Array(original.hull.prefix(2))).validate())
        XCTAssertThrowsError(try shape([.init(x: -.infinity, y: 0)] + original.hull).validate())
        XCTAssertThrowsError(try shape([.init(x: -0.4, y: -0.4), .init(x: 0.4, y: -0.4),
                                      .init(x: 0, y: 0), .init(x: 0.4, y: 0.4), .init(x: -0.4, y: 0.4)]).validate())
        XCTAssertThrowsError(try LeafCollisionCatalog(alphaThreshold: 128, contactInsetPoints: 2.5, shapes: [original, original]).validated())
        XCTAssertThrowsError(try LeafCollisionCatalog(alphaThreshold: 0, contactInsetPoints: 2.5, shapes: [original]).validated())
        XCTAssertThrowsError(try LeafCollisionCatalog(alphaThreshold: 128, contactInsetPoints: .nan, shapes: [original]).validated())
        XCTAssertThrowsError(try catalog.shape(for: "missing-leaf"))
    }

    func testLeafCollisionCoreHasUniformScenePointInsetAtDifferentSizes() throws {
        let catalog = try LeafCollisionCatalog.bundled.get()
        for shape in catalog.shapes {
            for width in [28.0, 55.0, 100.0, 150.0] {
                let height = width * Double(shape.sourcePixelHeight) / Double(shape.sourcePixelWidth)
                let core = try shape.collisionHull(width: width, height: height, inset: catalog.contactInsetPoints)
                XCTAssertGreaterThanOrEqual(core.count, 3)
                for p in core {
                    let distances = shape.hull.indices.map { i -> Double in
                        let a = shape.hull[i], b = shape.hull[(i + 1) % shape.hull.count]
                        let dx = (b.x - a.x) * width, dy = (b.y - a.y) * height
                        return (dx * (p.y - a.y) * height - dy * (p.x - a.x) * width) / hypot(dx, dy)
                    }
                    XCTAssertGreaterThanOrEqual(try XCTUnwrap(distances.min()), catalog.contactInsetPoints - 1e-8)
                    XCTAssertEqual(try XCTUnwrap(distances.min()), catalog.contactInsetPoints, accuracy: 1e-8)
                }
            }
            XCTAssertThrowsError(try shape.collisionHull(width: 1, height: 1, inset: catalog.contactInsetPoints))
            XCTAssertThrowsError(try shape.collisionHull(width: .nan, height: 10, inset: catalog.contactInsetPoints))
        }
    }

    private struct Bitmap {
        let width: Int
        let height: Int
        let pixels: [UInt8]
    }

    private func rgbaPixels(_ image: UIImage) throws -> [UInt8] {
        let cgImage = try XCTUnwrap(image.cgImage)
        var pixels = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(
                data: bytes.baseAddress,
                width: cgImage.width,
                height: cgImage.height,
                bitsPerComponent: 8,
                bytesPerRow: cgImage.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            )!
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        }
        return pixels
    }

    private func decodedBitmap(assetID: String) throws -> Bitmap {
        let url = try XCTUnwrap(AutumnTreeSceneResources.assetURL(named: assetID))
        let image = try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return Bitmap(width: image.width, height: image.height, pixels: pixels)
    }

    private func opaqueBoundary(_ bitmap: Bitmap, threshold: Int) -> [NormalizedPhysicsPoint] {
        func opaque(_ x: Int, _ y: Int) -> Bool {
            x >= 0 && x < bitmap.width && y >= 0 && y < bitmap.height
                && bitmap.pixels[(y * bitmap.width + x) * 4 + 3] >= threshold
        }
        var points: [NormalizedPhysicsPoint] = []
        for y in 0..<bitmap.height {
            for x in 0..<bitmap.width where opaque(x, y) {
                if !opaque(x-1, y) || !opaque(x+1, y) || !opaque(x, y-1) || !opaque(x, y+1) {
                    points.append(.init(x: (Double(x) + 0.5) / Double(bitmap.width) - 0.5,
                                        y: 0.5 - (Double(y) + 0.5) / Double(bitmap.height)))
                }
            }
        }
        return points
    }

    @MainActor
    func testTerrainNativeLandingAndReplayKeepSettledPoses() async throws {
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = windowScene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: windowScene)
        let model = LeafGroupLabModel()
        window.rootViewController = UIHostingController(rootView: LeafGroupLabView(model: model).environment(\.scenePhase, .active))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        try await Task.sleep(for: .milliseconds(600))
        let group = try LeafGroupConfiguration.bundled.get()
        let catalog = try LeafCollisionCatalog.bundled.get()
        var visibleBoundaries: [String: [NormalizedPhysicsPoint]] = [:]
        for id in group.assetIDs { visibleBoundaries[id] = opaqueBoundary(try decodedBitmap(assetID: id), threshold: catalog.alphaThreshold) }
        let ground = try decodedBitmap(assetID: "ground-base")
        let groundTop = try (0..<ground.width).map { x -> Double in
            let row = try XCTUnwrap((0..<ground.height).first { ground.pixels[($0 * ground.width + x) * 4 + 3] >= 128 })
            return 1 - (Double(row) + 0.5) / Double(ground.height)
        }
        for seed: UInt64 in [42, 43, 43, 44] {
            if model.scene?.plan.seed == seed {
                model.scene?.replay()
            } else {
                model.newTrial(seed: seed, reducedMotion: false, diagnostics: false, terrainEnabled: true)
            }
            let scene = try XCTUnwrap(model.scene)
            let terrain = try XCTUnwrap(scene.terrain)
            let nodes = scene.children.compactMap { $0 as? SKSpriteNode }.filter { $0.name?.hasPrefix("group-leaf-") == true }
            XCTAssertEqual(nodes.count, 6)
            for node in nodes {
                XCTAssertTrue(node.physicsBody?.usesPreciseCollisionDetection == true)
                XCTAssertEqual(try XCTUnwrap(node.physicsBody).friction, CGFloat(terrain.friction), accuracy: 1e-6)
                XCTAssertEqual(try XCTUnwrap(node.physicsBody).restitution, CGFloat(terrain.restitution), accuracy: 1e-6)
                XCTAssertEqual(node.physicsBody?.collisionBitMask, 2)
            }
            for _ in 0..<200 {
                try await Task.sleep(for: .milliseconds(100))
                if model.diagnostics.settled == 6 || model.diagnostics.failed { break }
            }
            XCTAssertTrue(scene.view?.scene === scene)
            XCTAssertFalse(model.diagnostics.failed, "Trial \(seed): \(model.diagnostics)")
            XCTAssertEqual(model.diagnostics.settled, 6, "Trial \(seed): \(model.diagnostics)")
            for member in scene.plan.members {
                let node = try XCTUnwrap(scene.childNode(withName: "group-leaf-\(member.id)") as? SKSpriteNode)
                let points = try XCTUnwrap(visibleBoundaries[member.assetID])
                let clearance = points.map { p -> Double in
                    let x = p.x * node.size.width, y = p.y * node.size.height
                    let worldX = node.position.x + x * cos(node.zRotation) - y * sin(node.zRotation)
                    let worldY = node.position.y + x * sin(node.zRotation) + y * cos(node.zRotation)
                    let column = min(ground.width - 1, max(0, Int(worldX / scene.size.width * Double(ground.width))))
                    return worldY - groundTop[column] * scene.size.height * terrain.renderedHeightFraction
                }.min() ?? .infinity
                print("visible-contact,seed=\(seed),leaf=\(member.id),asset=\(member.assetID),gapPoints=\(clearance)")
                XCTAssertLessThanOrEqual(clearance, 2.0, "Visible leaf must meet artwork, not just an invisible collider")
                XCTAssertGreaterThanOrEqual(clearance, -2.0, "Visible leaf must not tunnel into artwork")
            }
            let poses = nodes.map { [$0.position.x, $0.position.y, $0.zRotation] }
            scene.setDiagnosticsVisible(true)
            try await Task.sleep(for: .milliseconds(700))
            XCTAssertEqual(nodes.map { [$0.position.x, $0.position.y, $0.zRotation] }, poses)
            for node in nodes {
                XCTAssertFalse(node.isHidden)
                XCTAssertEqual(node.physicsBody?.isDynamic, false)
                XCTAssertEqual(node.physicsBody?.velocity, .zero)
                XCTAssertEqual(node.physicsBody?.angularVelocity, 0)
            }
        }
        model.scene?.reset()
        XCTAssertEqual(model.diagnostics.settled, 0)
        XCTAssertEqual(model.diagnostics.state, "ready")
        model.scene?.setReducedMotion(true)
        model.scene?.replay()
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(model.diagnostics.released, 0)
        XCTAssertEqual(model.diagnostics.state, "static preview")
    }

    @MainActor
    func testGroupNativeHostKeepsNewTrialAndReplayRendering() async throws {
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = windowScene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: windowScene)
        let model = LeafGroupLabModel()
        window.rootViewController = UIHostingController(rootView: LeafGroupLabView(model: model, terrainEnabled: false).environment(\.scenePhase, .active))
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        try await Task.sleep(for: .milliseconds(600))
        let first = try XCTUnwrap(model.scene)
        XCTAssertTrue(first.view?.scene === first)
        first.replay()
        try await Task.sleep(for: .milliseconds(900))
        XCTAssertGreaterThan(model.diagnostics.elapsed, 0.3)
        XCTAssertEqual(model.diagnostics.released, 6)
        for seed: UInt64 in [71, 72, 73] {
            model.newTrial(seed: seed, reducedMotion: false, diagnostics: false)
            let current = try XCTUnwrap(model.scene)
            try await Task.sleep(for: .milliseconds(900))
            XCTAssertTrue(current.view?.scene === current, "Trial \(seed) must be the displayed scene")
            XCTAssertFalse(current.isPaused, "Trial \(seed) scene was paused by its host")
            XCTAssertEqual(current.view?.isPaused, false)
            XCTAssertGreaterThan(model.diagnostics.elapsed, 0.3, "New trial must receive real frame callbacks")
            XCTAssertEqual(model.diagnostics.released, 6)
            for member in current.plan.members {
                let node = try XCTUnwrap(current.childNode(withName: "group-leaf-\(member.id)"))
                XCTAssertLessThan(node.position.y, current.size.height * member.releasePoint.y,
                                  "Each released leaf must physically descend")
            }
            current.replay()
            try await Task.sleep(for: .milliseconds(900))
            XCTAssertGreaterThan(model.diagnostics.elapsed, 0.3, "Replay must receive real frame callbacks")
            XCTAssertEqual(model.diagnostics.released, 6)
        }
    }

    @MainActor
    func testGroupSceneResetDiagnosticsAndReducedMotionPreservePhysicalState() throws {
        let config = try LeafGroupConfiguration.bundled.get()
        let reference = try LeafGravityLabConfiguration.gate4Bundled.get()
        let plan = try LeafGroupPlan(configuration: config, reference: reference, seed: 42)
        var images: [String: UIImage] = [:]
        for id in config.assetIDs {
            let url = try XCTUnwrap(AutumnTreeSceneResources.assetURL(named: id))
            images[id] = try XCTUnwrap(UIImage(contentsOfFile: url.path))
        }
        let scene = try LeafGroupScene(size: CGSize(width: 1000, height: 760), reference: reference, plan: plan, images: images)
        let nodes = scene.children.compactMap { $0 as? SKSpriteNode }
        XCTAssertEqual(nodes.count, 6)
        let positions = nodes.map(\.position)
        let rotations = nodes.map(\.zRotation)
        scene.setDiagnosticsVisible(true)
        scene.setDiagnosticsVisible(false)
        XCTAssertEqual(nodes.map(\.position), positions)
        XCTAssertEqual(nodes.map(\.zRotation), rotations)
        for (node, leaf) in zip(nodes, plan.members) {
            let body = try XCTUnwrap(node.physicsBody)
            XCTAssertEqual(body.mass, leaf.massKilograms, accuracy: 1e-8)
            XCTAssertEqual(body.angularVelocity, 0)
            XCTAssertEqual(body.collisionBitMask, 0)
            XCTAssertEqual(body.fieldBitMask, 0)
            XCTAssertEqual(body.linearDamping, 0)
            XCTAssertEqual(body.angularDamping, 0)
        }
        scene.setReducedMotion(true)
        scene.replay()
        scene.update(100)
        scene.update(200)
        XCTAssertFalse(scene.isRunning)
        XCTAssertEqual(nodes.map(\.position), positions)
        XCTAssertEqual(nodes.map(\.zRotation), rotations)
        scene.setReducedMotion(false)
        var released = 0
        scene.diagnosticsHandler = { released = $0.released }
        scene.replay()
        for tick in 0...10 { scene.update(Double(tick) / 10); scene.didSimulatePhysics() }
        XCTAssertEqual(released, 6)
        scene.reset()
        XCTAssertFalse(scene.isRunning)
        XCTAssertEqual(nodes.map(\.position), positions)
        XCTAssertEqual(nodes.map(\.zRotation), rotations)
    }

    func testAutumnReviewPlansKeepStableIdentitiesAndSharedMoments() throws {
        let resources = try AutumnTreeSceneResources.bundled.get()
        let reference = try LeafGravityLabConfiguration.gate4Bundled.get()
        let three = AutumnLeafReviewDirector(layout: resources.leafLayout, count: 3, reference: reference)
        let twelve = AutumnLeafReviewDirector(layout: resources.leafLayout, count: 12, reference: reference)
        let context = StorySessionContext(duration: 60, randomSeed: 42)
        XCTAssertEqual(three.selectedLeaves(seed: 42).map(\.id), Array(twelve.selectedLeaves(seed: 42).prefix(3)).map(\.id))
        XCTAssertEqual(twelve.selectedLeaves(seed: 42).count, 12)
        XCTAssertNotEqual(twelve.selectedLeaves(seed: 42).map(\.id), twelve.selectedLeaves(seed: 43).map(\.id))
        let plan = twelve.makePlan(for: context)
        XCTAssertEqual(plan, twelve.makePlan(for: context))
        XCTAssertEqual(plan.moments.count, 13)
        XCTAssertEqual(Set(plan.moments.map(\.id)).count, 13)
        for moment in plan.moments {
            XCTAssertNotNil(moment.visualCue)
            XCTAssertNotNil(moment.audioCue)
            XCTAssertGreaterThanOrEqual(moment.startTime, 6)
            XCTAssertLessThanOrEqual(moment.startTime, 60 * AutumnLeafReview.endProgress)
        }
        let session = FocusSession(story: .autumnTree, duration: .oneMinute, startedAt: Date(), randomSeed: 42)
        let player = StoryPlayer(session: session, module: AutumnLeafReviewModule(layout: resources.leafLayout, count: 12, reference: reference))
        XCTAssertEqual(player.moments(startingAfter: session.startedAt, through: session.endDate), plan.moments)
        let longer = twelve.makePlan(for: StorySessionContext(duration: 120, randomSeed: 42))
        for (a, b) in zip(plan.moments, longer.moments) {
            if a.visualCue?.effect.rawValue == "autumn-review.air" {
                XCTAssertEqual(b.startTime - a.startTime, 6, accuracy: 1e-10)
            } else { XCTAssertEqual(b.startTime, a.startTime * 2, accuracy: 1e-10) }
            XCTAssertEqual(a.duration, b.duration)
            XCTAssertEqual(a.id, b.id)
        }
        let productionPlan = AutumnTreeDirector().makePlan(for: context)
        XCTAssertEqual(productionPlan.moments.filter { $0.id == .autumnBirdFlock }.count, 1)
        XCTAssertEqual(productionPlan.moments.filter { $0.id == .autumnRabbitPeek }.count, 1)
    }

    func testAutumnDepthAndIrregularCadenceStaySeeded() throws {
        let resources = try AutumnTreeSceneResources.bundled.get()
        let director = try AutumnLeafReviewDirector(layout: resources.leafLayout, count: 12,
            reference: LeafGravityLabConfiguration.gate4Bundled.get())
        for seed in UInt64(40)...50 {
            let leaves = director.selectedLeaves(seed: seed)
            for depth in AutumnLeafDepth.allCases {
                XCTAssertEqual(leaves.filter { depth.accepts($0) }.count, 4)
            }
            let back = leaves.filter { AutumnLeafDepth.back.accepts($0) }
            let front = leaves.filter { AutumnLeafDepth.foreground.accepts($0) }
            XCTAssertLessThan(back.map(\.scale).max()!, front.map(\.scale).min()!)
            let times = director.releaseTimes(duration: 60, seed: seed, count: 12)
            XCTAssertEqual(times, director.releaseTimes(duration: 60, seed: seed, count: 12))
            XCTAssertEqual(times.first!, 6, accuracy: 1e-9)
            XCTAssertEqual(times.last!, 46.8, accuracy: 1e-9)
            let gaps = zip(times.dropFirst(), times).map(-)
            XCTAssertEqual(gaps.filter { $0 < 2 }.count, 2)
            XCTAssertGreaterThan(gaps.filter { $0 > 3 }.count, 6)
            XCTAssertNotEqual(times, director.releaseTimes(duration: 60, seed: seed + 1, count: 12))
        }
    }

    func testSheetTipsOnlyAfterContactAndProjectsAlongTerrain() {
        var sheet = LeafSheetContact()
        sheet.advance(supported: false, dt: 10, gravity: 1.2, heightMeters: 0.4, angle: 0)
        XCTAssertEqual(sheet, LeafSheetContact(), "Airborne physics must have no sheet correction")
        for _ in 0..<1200 {
            sheet.advance(supported: true, dt: 1.0 / 120, gravity: 1.2, heightMeters: 0.4, angle: 0.15)
        }
        XCTAssertTrue(sheet.isFlat)
        XCTAssertEqual(sheet.speed, 0)
        for rotation in stride(from: 0.0, to: Double.pi * 2, by: 0.1) {
            let point = CGPoint(x: 0, y: 20)
            let projected = sheet.project(point: point, rotation: rotation)
            let normal = -projected.x * sin(0.15) + projected.y * cos(0.15)
            XCTAssertLessThanOrEqual(abs(normal), 20 * LeafSheetContact.flatProjection + 1e-9)
        }
    }

    func testAutumnGroundWindIsBoundedSpatialAndUnchangedAloft() {
        XCTAssertEqual(AutumnLeafReview.windScale(heightMeters: -1), 0)
        XCTAssertEqual(AutumnLeafReview.windScale(heightMeters: 0), 0)
        XCTAssertEqual(AutumnLeafReview.windScale(heightMeters: 0.125), 0.5)
        XCTAssertEqual(AutumnLeafReview.windScale(heightMeters: 0.25), 1)
        XCTAssertEqual(AutumnLeafReview.windScale(heightMeters: 1), 1)
        let samples = (0...100).map { AutumnLeafReview.windScale(heightMeters: Double($0) / 100) }
        XCTAssertTrue(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 })
        XCTAssertTrue(samples.allSatisfy { (0...1).contains($0) })
    }

    @MainActor
    func testAutumnReviewGeometryAndLifecycleReconstruction() throws {
        let resources = try AutumnTreeSceneResources.bundled.get()
        let reference = try LeafGravityLabConfiguration.gate4Bundled.get()
        let start = Date().addingTimeInterval(10)
        let record = AutumnLeafReviewRecord(session: FocusSession(story: .autumnTree, duration: .oneMinute,
            startedAt: start, randomSeed: 42), count: 12, savedAt: start)
        for size in [CGSize(width: 390, height: 844), CGSize(width: 834, height: 1194), CGSize(width: 1194, height: 690)] {
            let scene = try AutumnLeafIntegrationScene(size: size, record: record, resources: resources, reference: reference, reduceMotion: false)
            XCTAssertEqual(scene.bodies.count, 12)
            for (id, body) in scene.bodies {
                var identityCount = 0
                scene.enumerateChildNodes(withName: "//\(id)") { _, _ in identityCount += 1 }
                XCTAssertEqual(identityCount, 1, "No duplicate attached leaf")
                let source = try XCTUnwrap(resources.leafLayout.canopy.first { $0.id == id })
                let image = try XCTUnwrap(UIImage(contentsOfFile: XCTUnwrap(AutumnTreeSceneResources.assetURL(named: source.assetId)).path))
                let pose = scene.geometry.leafPose(source, imageSize: image.size)
                // SpriteKit stores transforms at float precision internally.
                XCTAssertEqual(body.node.position.x, pose.position.x, accuracy: 0.0001)
                XCTAssertEqual(body.node.position.y, pose.position.y, accuracy: 0.0001)
                XCTAssertEqual(body.node.size.width, pose.size.width, accuracy: 0.00001)
                XCTAssertEqual(body.node.size.height, pose.size.height, accuracy: 0.00001)
                XCTAssertEqual(body.node.zRotation, pose.rotation, accuracy: 0.000001)
                XCTAssertEqual(body.member.massKilograms, reference.mass * pow(body.member.linearScale, 2) * body.member.arealDensityScale, accuracy: 1e-12)
                let position = body.node.position, rotation = body.node.zRotation
                body.release()
                XCTAssertEqual(body.node.position, position)
                XCTAssertEqual(body.node.zRotation, rotation)
                XCTAssertEqual(body.node.physicsBody?.angularVelocity, 0)
            }
            let liveDate = start.addingTimeInterval(49)
            let saved = scene.checkpoint(at: liveDate)
            XCTAssertEqual(try JSONDecoder().decode(AutumnLeafReviewRecord.self, from: JSONEncoder().encode(saved)), saved)
            scene.reconcile(saved, at: liveDate.addingTimeInterval(0.1))
            for (id, body) in scene.bodies {
                let moment = try XCTUnwrap(scene.moments.first { $0.visualCue?.effect.rawValue == id })
                XCTAssertTrue(body.released)
                XCTAssertEqual(body.finished, !moment.isActive(at: 49.1))
            }
            for body in scene.bodies.values { body.node.zRotation += 0.7 }
            scene.reconcile(saved, at: start.addingTimeInterval(80))
            XCTAssertEqual(scene.reconstructedIDs.count, 12)
            XCTAssertTrue(scene.bodies.values.allSatisfy { $0.finished && $0.node.physicsBody?.isDynamic == false })
            for body in scene.bodies.values {
                let actual = try XCTUnwrap(body.node.warpGeometry as? SKWarpGeometryGrid)
                let expected = body.sheet.warp(size: body.node.size, rotation: body.node.zRotation)
                for vertex in 0..<4 { XCTAssertEqual(actual.destPosition(at: vertex), expected.destPosition(at: vertex)) }
            }
            let settled = scene.checkpoint(at: start.addingTimeInterval(80))
            scene.reconcile(settled, at: start.addingTimeInterval(85))
            XCTAssertEqual(scene.checkpoint(at: start.addingTimeInterval(85)).bodies, settled.bodies)
            let resized = try AutumnLeafIntegrationScene(size: CGSize(width: size.width + 40, height: size.height),
                record: settled, resources: resources, reference: reference, reduceMotion: false)
            resized.reconcile(settled, at: start.addingTimeInterval(85))
            XCTAssertEqual(resized.reconstructedIDs.count, 12, "A changed viewport must not reuse old screen-space contact")
            let reduced = try AutumnLeafIntegrationScene(size: size, record: saved, resources: resources, reference: reference, reduceMotion: true)
            reduced.reconcile(saved, at: liveDate.addingTimeInterval(0.1))
            XCTAssertTrue(reduced.bodies.values.allSatisfy(\.finished))
        }
    }

    @MainActor
    func testAutumnRetiredSceneCannotPublishIntoReplay() throws {
        let suite = "gate6-retired-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AutumnLeafIntegrationModel(defaults: defaults)
        model.configure(size: CGSize(width: 1194, height: 690), reducedMotion: false, diagnostics: false)
        let old = try XCTUnwrap(model.scene)
        model.start(count: 12, seed: 43, reducedMotion: false, diagnostics: false)
        let expected = model.record
        let status = model.status
        old.checkpointHandler?(old.checkpoint(at: Date().addingTimeInterval(70)))
        old.statusHandler?("stale scene status")
        XCTAssertEqual(model.record, expected)
        XCTAssertEqual(model.status, status)
        XCTAssertEqual(AutumnLeafIntegrationModel(defaults: defaults).record, expected)
    }

    @MainActor
    func testAutumnStaticAccentsLieAlongTheirSurface() throws {
        let resources = try AutumnTreeSceneResources.bundled.get()
        let start = Date().addingTimeInterval(10)
        let scene = try AutumnLeafIntegrationScene(size: CGSize(width: 1194, height: 690),
            record: AutumnLeafReviewRecord(session: FocusSession(story: .autumnTree, duration: .oneMinute,
                startedAt: start, randomSeed: 42), count: 3, savedAt: start), resources: resources,
            reference: LeafGravityLabConfiguration.gate4Bundled.get(), reduceMotion: true)
        for (id, asset, depth) in [("ground-oak-gold-02", "leaf-oak-gold", AutumnLeafDepth.foreground),
                                   ("ground-settled-01", "leaf-settled", .middle)] {
            let node = try XCTUnwrap(scene.childNode(withName: "//\(id)") as? SKSpriteNode)
            let warp = try XCTUnwrap(node.warpGeometry as? SKWarpGeometryGrid)
            let surface = try XCTUnwrap(scene.surfaces[depth])
            let origin = warp.destPosition(at: 0), right = warp.destPosition(at: 1), top = warp.destPosition(at: 2)
            let points = try opaqueBoundary(decodedBitmap(assetID: asset), threshold: 128).map { p in
                let v = origin + Float(p.x + 0.5) * (right - origin) + Float(p.y + 0.5) * (top - origin)
                let x = (Double(v.x) - 0.5) * node.size.width, y = (Double(v.y) - 0.5) * node.size.height
                return CGPoint(x: x * cos(node.zRotation) - y * sin(node.zRotation),
                               y: x * sin(node.zRotation) + y * cos(node.zRotation))
            }
            let width = points.map(\.x).max()! - points.map(\.x).min()!
            let height = points.map(\.y).max()! - points.map(\.y).min()!
            XCTAssertLessThan(height / width, 0.65, "The source defect was an upright/stem-balanced accent: \(id)")
            let gap = points.map { node.position.y + $0.y - surface.height(at: node.position.x + $0.x) }.min()!
            XCTAssertEqual(gap, 0, accuracy: 0.05)
            XCTAssertEqual(node.zPosition, depth.zPosition)
            if depth == .middle {
                XCTAssertLessThan(node.size.width, scene.geometry.composition.width * scene.geometry.scale * 0.03,
                                  "The distant completion maple must not retain its oversized foreground scale")
            }
        }
    }

    @MainActor
    func testAutumnNativeThreeThenTwelveLandAndReplay() async throws {
        let suite = "gate6-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AutumnLeafIntegrationModel(defaults: defaults)
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = windowScene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: AutumnLeafIntegrationView(model: model).environment(\.scenePhase, .active))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        try await Task.sleep(for: .seconds(2))
        for (count, seed) in [(3, UInt64(42)), (12, UInt64(42)), (12, UInt64(43))] {
            model.start(count: count, seed: seed, reducedMotion: false, diagnostics: false)
            let scene = try XCTUnwrap(model.scene)
            for _ in 0..<900 {
                try await Task.sleep(for: .milliseconds(100))
                if scene.failed || scene.bodies.values.allSatisfy(\.finished) { break }
            }
            XCTAssertTrue(scene.view?.scene === scene)
            XCTAssertFalse(scene.failed, model.status)
            XCTAssertEqual(scene.bodies.values.filter(\.finished).count, count, model.status)
            XCTAssertTrue(scene.reconstructedIDs.isEmpty, "Normal moving proof must never use restored rest poses")
            for (id, body) in scene.bodies {
                XCTAssertTrue(body.sheet.isFlat, "A quiet upright leaf must never count as settled")
                let surface = try XCTUnwrap(scene.surfaces[scene.depths[id]!])
                XCTAssertEqual(body.node.zPosition, scene.depths[id]!.zPosition)
                XCTAssertEqual(body.node.physicsBody?.collisionBitMask, scene.depths[id]!.collisionMask)
                let bitmap = try decodedBitmap(assetID: body.member.assetID)
                let boundary = opaqueBoundary(bitmap, threshold: 128)
                let gap = boundary.map { p -> Double in
                    let x = p.x * body.node.size.width, y = p.y * body.node.size.height
                    let projected = body.sheet.project(point: CGPoint(x: x, y: y), rotation: body.node.zRotation)
                    let worldX = body.node.position.x + projected.x
                    let worldY = body.node.position.y + projected.y
                    return worldY - surface.height(at: worldX)
                }.min() ?? .infinity
                print("gate6-contact,count=\(count),seed=\(seed),id=\(body.node.name ?? ""),gap=\(gap)")
                XCTAssertLessThanOrEqual(gap, 2)
                XCTAssertGreaterThanOrEqual(gap, -2)
            }
            let poses = scene.checkpoint(at: Date()).bodies
            model.suspend()
            try await Task.sleep(for: .milliseconds(500))
            model.configure(size: scene.size, reducedMotion: false, diagnostics: false)
            XCTAssertEqual(model.scene?.checkpoint(at: Date()).bodies, poses)
            let relaunched = AutumnLeafIntegrationModel(defaults: defaults)
            XCTAssertEqual(relaunched.record.session, model.record.session)
            XCTAssertEqual(relaunched.record.bodies, poses)
        }
        for seed: UInt64 in [43, 43] {
            model.start(count: 3, seed: seed, reducedMotion: false, diagnostics: false)
            let scene = try XCTUnwrap(model.scene)
            try await Task.sleep(for: .seconds(9))
            XCTAssertTrue(scene.view?.scene === scene)
            XCTAssertEqual(scene.bodies.values.filter(\.released).count, 1)
            XCTAssertTrue(scene.reconstructedIDs.isEmpty)
            for body in scene.bodies.values where body.released {
                XCTAssertLessThan(body.node.position.y, body.member.releasePoint.y * scene.size.height)
            }
        }
        model.suspend()
    }

    func testBundledGateBaselinesAndGate3AreIsolated() throws {
        let gate1 = try LeafGravityLabConfiguration.gate1Bundled.get()
        let gate2 = try LeafGravityLabConfiguration.gate2Bundled.get()
        let gate3 = try LeafGravityLabConfiguration.gate3Bundled.get()
        var gate4 = try LeafGravityLabConfiguration.gate4Bundled.get()
        XCTAssertNil(gate1.wind)
        XCTAssertNil(gate2.wind)
        XCTAssertNil(gate3.wind)
        XCTAssertNotNil(gate4.wind)
        XCTAssertEqual(gate4.wind, makeWindConfiguration())
        gate4.wind = nil
        XCTAssertEqual(gate4, gate3)
        XCTAssertNil(gate1.stillAirDrag)
        XCTAssertNil(gate1.passiveFlutter)
        XCTAssertNotNil(gate2.stillAirDrag)
        XCTAssertNil(gate2.passiveFlutter)
        XCTAssertNotNil(gate3.passiveFlutter)
        XCTAssertEqual(gate3.gravity, gate1.gravity)
        XCTAssertEqual(gate3.mass, gate1.mass)
        XCTAssertEqual(gate3.releasePoint, gate1.releasePoint)
        XCTAssertEqual(gate3.stillAirDrag, gate2.stillAirDrag)
        XCTAssertEqual(gate3.collisionHull, Array(gate2.collisionHull.reversed()))
    }
#endif

    private func makeFlutterConfiguration() -> PassiveFlutterConfiguration {
        PassiveFlutterConfiguration(maximumLiftCoefficient: 0.45, liftResponse: .sinTwoAlpha,
                                    chordAngleRadians: 0, edgeOnAreaFraction: 0.18,
                                    centerOfPressure: NormalizedPhysicsPoint(x: 0.08, y: 0.16),
                                    angularResistanceCoefficient: 0.2)
    }

    private func flutterSample(velocity: PhysicsVector, spin: Double = 0, rotation: Double = 0) -> LeafAerodynamicSample {
        LeafAerodynamics.stillAirFlutter(leafVelocity: velocity, angularVelocity: spin, rotation: rotation,
                                        position: PhysicsVector(x: 300, y: 400),
                                        leafSize: PhysicsVector(x: 100, y: 100),
                                        centerOfMass: NormalizedPhysicsPoint(x: 0, y: 0),
                                        drag: makeDragConfiguration(), flutter: makeFlutterConfiguration())
    }

    private func makeGustRule() -> RandomMomentRule {
        RandomMomentRule(
            id: "gust",
            progressWindow: 0.10...0.65,
            evaluationInterval: 8...20,
            triggerChance: 1,
            cooldown: 15...40,
            duration: 2...5,
            intensity: 0.2...0.8,
            visualEffect: StoryEffectID(rawValue: "gust"),
            audioCue: StoryAudioCue(assetID: "wind-gust", bus: .atmosphere)
        )
    }

    private func makeGravityConfiguration(
        gravity: PhysicsVector = PhysicsVector(x: 0, y: -1.2),
        stillAirDrag: StillAirDragConfiguration? = nil
    ) -> LeafGravityLabConfiguration {
        LeafGravityLabConfiguration(
            gravity: gravity,
            mass: 0.002,
            assetID: "leaf-maple-red",
            leafWidthFraction: 0.13,
            releasePoint: NormalizedPhysicsPoint(x: 0.5, y: 0.82),
            collisionHull: [
                NormalizedPhysicsPoint(x: -0.4, y: 0),
                NormalizedPhysicsPoint(x: 0, y: 0.4),
                NormalizedPhysicsPoint(x: 0.4, y: 0),
                NormalizedPhysicsPoint(x: 0, y: -0.4)
            ],
            offscreenMarginFraction: 0.12,
            diagnosticsUpdateInterval: 0.1,
            stillAirDrag: stillAirDrag
        )
    }

    private func makeDragConfiguration() -> StillAirDragConfiguration {
        StillAirDragConfiguration(
            airDensityKilogramsPerCubicMeter: 1.225,
            dragCoefficient: 1.1,
            referenceAreaSquareMeters: 0.004,
            projectedAreaFraction: 1,
            scenePointsPerMeter: 150,
            debugVelocityVectorSeconds: 0.32,
            debugForceVectorPointsPerNewton: 24_000
        )
    }

    private func simulatedVerticalSpeed(
        after duration: TimeInterval,
        configuration: LeafGravityLabConfiguration
    ) -> Double {
        let timeStep = 1.0 / 120.0
        let scenePointsPerMeter = configuration.stillAirDrag?.scenePointsPerMeter ?? 150
        var velocity = 0.0

        for _ in 0..<Int(duration / timeStep) {
            let dragNewtons = configuration.stillAirDrag.map {
                LeafAerodynamics.stillAirDrag(
                    leafVelocity: PhysicsVector(x: 0, y: velocity),
                    configuration: $0
                ).y
            } ?? 0
            let accelerationMetersPerSecondSquared = configuration.gravity.y
                + dragNewtons / configuration.mass
            velocity += accelerationMetersPerSecondSquared * scenePointsPerMeter * timeStep
        }
        return velocity
    }
}
