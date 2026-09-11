import XCTest
import simd
import AVFoundation
#if canImport(UIKit)
import UIKit
import SwiftUI
import CryptoKit
#endif
@testable import PlanetCalm

final class PlanetCalmTests: XCTestCase {
    func testAutomaticEncountersAcrossEveryDurationAndManySeeds() {
        for minutes in 5...55 {
            let duration = Double(minutes * 60)
            for seed in 0..<100 {
                let plan = AutumnBranchPlan(duration: duration, seed: UInt64(seed), tuning: .standard, isFullTree: true)
                let schedule = plan.encounters
                XCTAssertEqual(schedule, AutumnEncounterSchedule(duration: duration, seed: UInt64(seed), deer: plan.deerEnding))
                XCTAssertGreaterThan(schedule.decisions.count, 0)
                XCTAssertEqual(Set(schedule.birds.map { $0.moment.id }).count, schedule.birds.count)
                XCTAssertLessThanOrEqual(plan.deerEnding.restingTime, duration - 8)
                for flight in schedule.birds {
                    XCTAssertGreaterThanOrEqual(flight.startTime, 22)
                    XCTAssertLessThanOrEqual(flight.startTime + flight.duration, min(duration * 0.82, plan.deerEnding.startTime - 8))
                    XCTAssertTrue((23...32).contains(flight.duration))
                    XCTAssertEqual(schedule.bird(at: flight.startTime), flight)
                    XCTAssertNil(schedule.bird(at: flight.startTime + flight.duration + 0.01))
                    for breeze in plan.gusts {
                        XCTAssertTrue(breeze.endTime + 6 <= flight.startTime || breeze.startTime >= flight.startTime + flight.duration + 8)
                    }
                }
                for pair in zip(schedule.birds, schedule.birds.dropFirst()) {
                    XCTAssertGreaterThanOrEqual(pair.1.startTime - (pair.0.startTime + pair.0.duration), 90)
                }
                for pair in zip(schedule.decisions, schedule.decisions.dropFirst()) {
                    XCTAssertTrue((21.999...44.001).contains(pair.1.time - pair.0.time))
                }
                XCTAssertNil(schedule.bird(at: duration))
                XCTAssertGreaterThan(plan.gusts.last!.startTime, duration * 0.85)
                XCTAssertLessThan(plan.gusts.last!.startTime, duration)
            }
        }
    }

    func testEncounterPopulationIsVariedAndCalmAtFiveAndFiftyFiveMinutes() {
        for minutes in [5, 55] {
            var birdCounts: [Int] = []
            var windCounts: [Int] = []
            var firstTimes = Set<Double>()
            var rightSources = 0
            var totalSources = 0
            var quietCount = 0
            for seed in 0..<500 {
                let plan = AutumnBranchPlan(duration: Double(minutes * 60), seed: UInt64(seed), tuning: .standard, isFullTree: true)
                birdCounts.append(plan.encounters.birds.count)
                windCounts.append(plan.gusts.count)
                firstTimes.insert(plan.encounters.decisions.first!.time)
                quietCount += plan.encounters.decisions.filter { $0.kind == .quiet }.count
                rightSources += plan.windPassages.filter { $0.direction.x < 0 }.count
                totalSources += plan.windPassages.count
            }
            let meanBirds = Double(birdCounts.reduce(0, +)) / 500
            let meanWind = Double(windCounts.reduce(0, +)) / 500
            print("ENCOUNTER PACING \(minutes)m: birds mean=\(meanBirds), range=\(birdCounts.min()!)...\(birdCounts.max()!); breezes mean=\(meanWind)")
            XCTAssertGreaterThan(firstTimes.count, 490)
            XCTAssertGreaterThan(Set(birdCounts).count, 1)
            XCTAssertGreaterThan(quietCount, 500)
            XCTAssertTrue((0.4...0.6).contains(Double(rightSources) / Double(totalSources)))
            XCTAssertTrue(minutes == 5 ? (0.4...2).contains(meanBirds) : (6...16).contains(meanBirds))
            XCTAssertTrue(minutes == 5 ? (2...6).contains(meanWind) : (25...60).contains(meanWind))
        }
    }

    func testAutomaticEncounterDirectorAgreementAndManualOverride() throws {
        let duration = 900.0
        let plan = AutumnBranchPlan(duration: duration, seed: 42, tuning: .standard, isFullTree: true)
        let directed = AutumnTreeDirector().makePlan(for: .init(duration: duration, randomSeed: 42))
        XCTAssertEqual(Set(directed.moments.map(\.id)), Set((plan.gusts + plan.encounters.birds.map(\.moment) + [plan.deerEnding.moment]).map(\.id)))
        let bird = try XCTUnwrap(plan.encounters.birds.first)
        let manual = AutumnOrigamiFlight(startTime: bird.startTime - 5, seed: 99, tuning: .init())
        XCTAssertEqual(plan.encounters.bird(at: bird.startTime, manual: manual), manual)
        XCTAssertNil(plan.encounters.bird(at: manual.startTime + manual.duration + 0.01, manual: manual))
        // Skipping over a visit (background/lock) cannot queue or replay it later.
        XCTAssertNil(plan.encounters.bird(at: bird.startTime + bird.duration + 1))
        XCTAssertNil(plan.encounters.bird(at: duration))
    }

    func testAutomaticEncountersRespectLongGustTuning() {
        var tuning = AutumnBranchTuning.standard
        tuning.gustDuration = 15
        for seed in 0..<100 {
            let plan = AutumnBranchPlan(duration: 3300, seed: UInt64(seed), tuning: tuning, isFullTree: true)
            XCTAssertLessThanOrEqual(plan.gusts.last!.endTime + 6, plan.duration)
            for flight in plan.encounters.birds {
                for breeze in plan.gusts {
                    XCTAssertTrue(breeze.endTime + 6 <= flight.startTime || breeze.startTime >= flight.startTime + flight.duration + 8)
                }
            }
        }
    }

    func testFiftyFiveMinuteRandomizedStoryRetainsGroundedLeafBed() throws {
        let reference = try LeafGravityLabConfiguration.gate3Bundled.get()
        for seed: UInt64 in [0, 42, 499] {
            let plan = AutumnBranchPlan(duration: 3300, seed: seed, tuning: .standard, isFullTree: true)
            let simulation = AutumnBranchSimulation(plan: plan, reference: reference)
            let end = simulation.sample(at: 3300)
            XCTAssertTrue(end.leaves.allSatisfy { $0.phase == .landed || $0.phase == .settled })
            let retained = end.leaves.filter { (-80...820).contains($0.x) }.count
            print("55 MINUTE CARPET seed=\(seed): \(retained)/\(end.leaves.count)")
            XCTAssertGreaterThanOrEqual(Double(retained) / Double(end.leaves.count), 0.85)
        }
    }


    func testDeerEndingGuaranteedAcrossDurationsAndTuning() {
        let stage = AutumnDeerEncounter.Stage(left:-80,right:820)
        for minutes in [1,2,5,17,25,50,55] {
            for speed in [0.7,1.0,1.3] {
                var tuning = AutumnDeerTuning()
                tuning.speed=speed; tuning.settlingSeconds=12
                let duration=Double(minutes*60)
                let deer=AutumnDeerEncounter.scheduled(duration:duration,tuning:tuning)
                XCTAssertGreaterThanOrEqual(deer.startTime,0)
                XCTAssertLessThanOrEqual(deer.restingTime,duration-8)
                XCTAssertNil(deer.sample(at:deer.startTime-0.01,stage:stage))
                XCTAssertEqual(deer.sample(at:duration,stage:stage)?.phase,.resting)
                XCTAssertEqual(deer.sample(at:duration+100,stage:stage)?.root,
                    deer.sample(at:duration,stage:stage)?.root)
                XCTAssertEqual(deer.sample(at:duration,stage:stage,reduceMotion:true)?.phase,.resting)
            }
        }
    }

    func testDeerHoovesStayPlantedAndGeometryFinite() {
        let deer=AutumnDeerEncounter(startTime:0,tuning:.init())
        for stage in [AutumnDeerEncounter.Stage(left:-80,right:820),.init(left:-400,right:1300)] {
            var contacts=0
            for t in stride(from:0.0,through:deer.duration+2,by:1.0/30) {
                let pose=deer.sample(at:t,stage:stage)!
                let next=deer.sample(at:t+0.001,stage:stage)!
                for leg in 0..<4 where pose.hooves[leg].planted && next.hooves[leg].planted {
                    XCTAssertLessThan(simd_distance(pose.hooves[leg].point,next.hooves[leg].point),0.0001)
                    contacts += 1
                }
                XCTAssertLessThan(abs(next.root-pose.root),0.3)
                for face in AutumnDeerMesh.faces(pose) {
                    for v in face.vertices {
                        XCTAssertTrue(v.x.isFinite && v.y.isFinite && v.z.isFinite)
                        XCTAssertGreaterThan(v.y,-1.5,"Paper must clear the floor throughout lowering, not only at rest.")
                    }
                }
            }
            XCTAssertGreaterThan(contacts,200)
        }
    }

    func testDeerStudyDoesNotPersistPerformance() throws {
        var record=AutumnBranchRecord()
        record.deer = AutumnDeerStudy()
        record.deer?.encounter = .init(startTime:30,tuning:.init())
        let data=try JSONEncoder().encode(record.settingsOnly)
        let restored=try JSONDecoder().decode(AutumnBranchRecord.self,from:data)
        XCTAssertNil(restored.deer?.encounter)
        XCTAssertNotNil(restored.deer)
    }

    func testDeerLegsReachTheirContactsAcrossTuningLimits() {
        for size in [0.75,1.0,1.2] {
            for speed in [0.7,1.3] {
                for position in [0.56,0.76] {
                    var tuning=AutumnDeerTuning()
                    tuning.size=size;tuning.speed=speed;tuning.restingPosition=position
                    let deer=AutumnDeerEncounter(startTime:0,tuning:tuning)
                    for stage in [AutumnDeerEncounter.Stage(left:-80,right:820),.init(left:-400,right:1300)] {
                        var worst=0.0
                        for t in stride(from:0.0,through:deer.duration,by:1.0/30) {
                            let pose=deer.sample(at:t,stage:stage)!
                            for leg in 0..<4 {
                                let front=leg<2
                                let root=SIMD3<Double>(front ? -44 : 43,front ? pose.shoulder : pose.hip,0)
                                let hoof=SIMD3<Double>((pose.hooves[leg].point.x-pose.root)/size,
                                    pose.hooves[leg].point.y/size+3,0)
                                let upper=front ? 47.0 : 53.0,lower=front ? 51.0 : 52.0
                                let knee=AutumnDeerMesh.knee(root:root,foot:hoof,upper:upper,lower:lower,bend:front ? -1 : 1)
                                worst=max(worst,abs(simd_distance(knee,hoof)-lower))
                            }
                        }
                        XCTAssertLessThan(worst,0.05,"Limb stretch: size \(size), speed \(speed), position \(position), stage \(stage.width)")
                    }
                }
            }
        }
    }

    @MainActor
    func testDeerNativePosesAndReducedMotionAcrossViewports() throws {
        let plan=AutumnBranchPlan(duration:120,seed:42,tuning:.standard,isFullTree:true)
        let simulation=AutumnBranchSimulation(plan:plan,reference:try LeafGravityLabConfiguration.gate3Bundled.get())
        let encounter=plan.deerEnding
        for size in [CGSize(width:393,height:852),CGSize(width:820,height:1180),CGSize(width:1180,height:820)] {
            for localTime in [12.0,20,23,25,31] {
                let time=encounter.startTime+localTime
                let scene=AutumnBranchCanvas(includesAtmosphere:false,size:size,
                    frame:simulation.sample(at:time),progress:time/120,tuning:.standard,reduceMotion:false,
                    elapsedTime:time,birdPlan:plan,deerEncounter:encounter)
                let renderer=ImageRenderer(content:scene)
                let image=try XCTUnwrap(renderer.uiImage)
                let attachment=XCTAttachment(image:image)
                attachment.name="deer-native-\(Int(size.width))-\(Int(localTime))"
                attachment.lifetime = .keepAlways;add(attachment)
            }
        }
        let stage=AutumnDeerEncounter.Stage(left:-80,right:820)
        XCTAssertNil(encounter.sample(at:encounter.startTime+1,stage:stage,reduceMotion:true))
        let rest=try XCTUnwrap(encounter.sample(at:120,stage:stage,reduceMotion:true))
        XCTAssertEqual(rest.phase,.resting)
        for face in AutumnDeerMesh.faces(rest) {
            for v in face.vertices { XCTAssertGreaterThan(v.y,-1.5,"Folded paper must not sink beneath its ground plane.") }
        }
        let shared=AutumnTreeDirector().makePlan(for:.init(duration:120,randomSeed:42))
        XCTAssertEqual(shared.moments.first { $0.id == encounter.moment.id },encounter.moment)
    }

    @MainActor
    func testSceneVolumeAndMuteOnlyAffectOutput() {
        let synth = PerformanceSynthesizer()
        synth.setOutput(volume: 0.3, isMuted: false)
        XCTAssertEqual(synth.effectiveVolume, 0.3, accuracy: 0.0001)
        synth.setOutput(volume: 0.3, isMuted: true)
        XCTAssertEqual(synth.effectiveVolume, 0)
        XCTAssertEqual(synth.volume, 0.3, accuracy: 0.0001)
        synth.setOutput(volume: 0.8, isMuted: true)
        XCTAssertEqual(synth.effectiveVolume, 0)
        synth.setOutput(volume: 0.8, isMuted: false)
        XCTAssertEqual(synth.effectiveVolume, 0.8, accuracy: 0.0001)
        synth.setOutput(volume: 2, isMuted: false)
        XCTAssertEqual(synth.effectiveVolume, 1)
        synth.setOutput(volume: -1, isMuted: false)
        XCTAssertEqual(synth.effectiveVolume, 0)
        synth.setOutput(volume: .nan, isMuted: false)
        XCTAssertEqual(synth.effectiveVolume, 0)
    }

    func testWholeMinuteDurationsAndSliderMapping() throws {
        for minutes in FocusDuration.minuteRange {
            let duration = try XCTUnwrap(FocusDuration(minutes: minutes))
            XCTAssertEqual(duration.rawValue, minutes * 60)
            XCTAssertEqual(duration.minutes, minutes)
            XCTAssertEqual(FocusDuration(rawValue: minutes * 60), duration)
            XCTAssertEqual(FocusDuration.minutes(at: Double(minutes - 5) / 50), minutes)
            XCTAssertEqual(try JSONDecoder().decode(FocusDuration.self,
                from: JSONEncoder().encode(duration)), duration)
        }
        for invalid in [-1, 0, 4, 56, Int.max] {
            XCTAssertNil(FocusDuration(minutes: invalid))
        }
        XCTAssertNil(FocusDuration(rawValue: 3301))
        XCTAssertThrowsError(try JSONDecoder().decode(FocusDuration.self, from: Data("3301".utf8)))
        XCTAssertEqual(try JSONDecoder().decode(FocusDuration.self, from: Data("1500".utf8)), .twentyFiveMinutes)
        XCTAssertEqual(FocusDuration.minutes(at: -1), 5)
        XCTAssertEqual(FocusDuration.minutes(at: 2), 55)
        XCTAssertEqual(FocusDuration.minutes(at: .nan), 5)
        for stop in stride(from: 10, through: 50, by: 5) {
            for delta in [-0.65, 0.65] {
                XCTAssertEqual(FocusDuration.minutes(at: (Double(stop) + delta - 5) / 50), stop)
            }
            for delta in [-1, 1] {
                XCTAssertEqual(FocusDuration.minutes(at: Double(stop + delta - 5) / 50), stop + delta)
            }
        }
        let duration = try XCTUnwrap(FocusDuration(minutes: 17))
        let start = Date(timeIntervalSince1970: 1000)
        let session = PerformanceSession(duration: duration, startedAt: start, randomSeed: 42)
        XCTAssertEqual(session.remainingTime(at: start), 1020)
        XCTAssertEqual(session.progress(at: start.addingTimeInterval(510)), 0.5)
        XCTAssertEqual(session.progress(at: start.addingTimeInterval(1020)), 1)
    }

    func testSessionLedgerCommitsCompletionOnceAndCreditsOnlyCompletion() async throws {
        let persistence = MemoryLedgerPersistence()
        let ledger = SessionLedgerStore(persistence: persistence)
        let start = Date(timeIntervalSince1970: 10_000)
        let attempt = SessionAttempt(
            storyID: "retired-story",
            plannedSeconds: 300,
            startedAt: start,
            randomSeed: 42
        )

        _ = try await ledger.create(attempt)
        let first = try await ledger.terminalize(id: attempt.id, event: .completed)
        let second = try await ledger.terminalize(
            id: attempt.id,
            event: .cancelled(occurredAt: start.addingTimeInterval(301))
        )

        XCTAssertEqual(first.outcome, .completed)
        XCTAssertEqual(first.terminalAt, start.addingTimeInterval(300))
        XCTAssertEqual(first.creditedSeconds, 300)
        XCTAssertEqual(second, first)
        let attempts = try await ledger.attempts()
        XCTAssertEqual(attempts.count, 1)
    }

    func testSessionLedgerPreservesTerminalResultAgainstLateDistraction() async throws {
        let ledger = SessionLedgerStore(persistence: MemoryLedgerPersistence())
        let start = Date(timeIntervalSince1970: 20_000)
        let attempt = SessionAttempt(
            storyID: Story.autumnTree.rawValue,
            plannedSeconds: 300,
            startedAt: start,
            randomSeed: 7
        )
        _ = try await ledger.create(attempt)
        let distractedBeforeCompletion = try await ledger.terminalize(
            id: attempt.id,
            event: .distracted(
                occurredAt: start.addingTimeInterval(299),
                observedAt: start.addingTimeInterval(299)
            )
        )
        XCTAssertEqual(distractedBeforeCompletion.outcome, .distracted)
        XCTAssertEqual(distractedBeforeCompletion.creditedSeconds, 0)

        let completedAttempt = SessionAttempt(
            storyID: Story.autumnTree.rawValue,
            plannedSeconds: 300,
            startedAt: start.addingTimeInterval(1_000),
            randomSeed: 8
        )
        _ = try await ledger.create(completedAttempt)
        _ = try await ledger.terminalize(id: completedAttempt.id, event: .completed)

        let lateDistraction = try await ledger.terminalize(
            id: completedAttempt.id,
            event: .distracted(
                occurredAt: completedAttempt.startedAt.addingTimeInterval(299),
                observedAt: completedAttempt.startedAt.addingTimeInterval(305)
            )
        )

        XCTAssertEqual(lateDistraction.outcome, .completed)
        XCTAssertEqual(lateDistraction.terminalAt, completedAttempt.scheduledEndAt)
        XCTAssertEqual(lateDistraction.creditedSeconds, 300)
    }

    func testSessionLedgerReconcilesOrphansReloadsAndDoesNotResurrectDeletion() async throws {
        let persistence = MemoryLedgerPersistence()
        let firstStore = SessionLedgerStore(persistence: persistence)
        let attempt = SessionAttempt(
            storyID: "future-story",
            plannedSeconds: 600,
            startedAt: Date(timeIntervalSince1970: 30_000),
            randomSeed: 99
        )
        _ = try await firstStore.create(attempt)

        let reloadedStore = SessionLedgerStore(persistence: persistence)
        let reconciled = try await reloadedStore.reconcileOrphanedAttempts(
            observedAt: Date(timeIntervalSince1970: 30_010)
        )
        XCTAssertEqual(reconciled.first?.storyID, "future-story")
        XCTAssertEqual(reconciled.first?.outcome, .interrupted)
        XCTAssertNil(reconciled.first?.terminalAt)
        XCTAssertEqual(reconciled.first?.creditedSeconds, 0)

        try await reloadedStore.delete(ids: [attempt.id])
        do {
            _ = try await reloadedStore.terminalize(id: attempt.id, event: .completed)
            XCTFail("A late callback must not recreate a deleted record")
        } catch let error as SessionLedgerError {
            XCTAssertEqual(error, .attemptNotFound)
        }
    }

    func testTerminalHistoryExportPreservesExistingLedgerAndExcludesRunningAttempts() async throws {
        let persistence = MemoryLedgerPersistence()
        let writer = SessionLedgerStore(persistence: persistence)
        let terminal = SessionAttempt(
            storyID: "retired-story",
            plannedSeconds: 300,
            startedAt: Date(timeIntervalSince1970: 31_000),
            randomSeed: 1
        )
        _ = try await writer.create(terminal)
        _ = try await writer.terminalize(id: terminal.id, event: .completed)

        let running = SessionAttempt(
            storyID: "future-story",
            plannedSeconds: 600,
            startedAt: Date(timeIntervalSince1970: 32_000),
            randomSeed: 2
        )
        _ = try await writer.create(running)

        // A fresh storage owner reads the existing v1 ledger without migration.
        let reader = SessionLedgerStore(persistence: persistence)
        let exported = try await reader.exportTerminalHistory()

        XCTAssertEqual(exported.records.count, 1)
        XCTAssertEqual(exported.records.first?.id, terminal.id)
        XCTAssertEqual(exported.records.first?.storyID, "retired-story")
        XCTAssertEqual(exported.records.first?.startedAt, terminal.startedAt)
        XCTAssertEqual(exported.records.first?.scheduledEndAt, terminal.scheduledEndAt)
        XCTAssertEqual(exported.records.first?.outcome, .completed)
        XCTAssertEqual(exported.records.first?.creditedSeconds, 300)
        XCTAssertFalse(exported.records.contains(where: { $0.id == running.id }))
    }

    func testTerminalHistoryMigratesV1LedgerWithoutChangingItsTerminalFacts() async throws {
        var terminal = SessionAttempt(
            storyID: "retired-story",
            plannedSeconds: 300,
            startedAt: Date(timeIntervalSince1970: 32_500),
            randomSeed: 12
        )
        terminal.outcome = .completed
        terminal.terminalAt = terminal.scheduledEndAt
        terminal.creditedSeconds = terminal.plannedSeconds
        let legacyData = try JSONEncoder().encode(LegacyLedgerEnvelope(
            schemaVersion: 1,
            attempts: [terminal],
            deletedAttemptIDs: []
        ))

        let ledger = SessionLedgerStore(persistence: MemoryLedgerPersistence(initialData: legacyData))
        let exported = try await ledger.exportTerminalHistory()
        let migratedAttempts = try await ledger.attempts()

        XCTAssertEqual(exported.records, [try XCTUnwrap(TerminalSessionHistoryRecord(terminal))])
        XCTAssertEqual(migratedAttempts, [terminal])
    }

    func testTerminalHistoryImportIsIdempotentAndDoesNotScheduleHealthWork() async throws {
        let source = SessionLedgerStore(persistence: MemoryLedgerPersistence())
        let attempt = SessionAttempt(
            storyID: Story.autumnTree.rawValue,
            plannedSeconds: 300,
            startedAt: Date(timeIntervalSince1970: 33_000),
            randomSeed: 3,
            healthWriteRequested: true
        )
        _ = try await source.create(attempt)
        _ = try await source.terminalize(id: attempt.id, event: .completed)
        let exported = try await source.exportTerminalHistory()

        let destination = SessionLedgerStore(persistence: MemoryLedgerPersistence())
        _ = try await destination.mergeTerminalHistory(exported)
        _ = try await destination.mergeTerminalHistory(exported)

        let importedAttempts = try await destination.attempts()
        let imported = try XCTUnwrap(importedAttempts.first)
        XCTAssertEqual(importedAttempts.count, 1)
        XCTAssertEqual(imported.id, attempt.id)
        XCTAssertEqual(imported.outcome, .completed)
        XCTAssertEqual(imported.creditedSeconds, 300)
        XCTAssertFalse(imported.healthWriteRequested)
        XCTAssertEqual(imported.healthSyncState, .notRequested)
    }

    func testTerminalHistoryImportPreservesLocalActiveAndConflictingTerminalAttempts() async throws {
        let id = UUID()
        let startedAt = Date(timeIntervalSince1970: 34_000)
        let local = SessionLedgerStore(persistence: MemoryLedgerPersistence())
        let active = SessionAttempt(
            id: id,
            storyID: Story.autumnTree.rawValue,
            plannedSeconds: 300,
            startedAt: startedAt,
            randomSeed: 4,
            healthWriteRequested: true
        )
        _ = try await local.create(active)

        let conflictingRecord = TerminalSessionHistoryRecord(
            id: id,
            storyID: Story.contemporaryLotus.rawValue,
            plannedSeconds: 600,
            startedAt: startedAt,
            scheduledEndAt: startedAt.addingTimeInterval(600),
            timeZoneIdentifier: TimeZone.current.identifier,
            calendarIdentifier: String(describing: Calendar.current.identifier),
            randomSeed: 5,
            outcome: .cancelled,
            terminalAt: startedAt.addingTimeInterval(20),
            observedAt: startedAt.addingTimeInterval(20),
            creditedSeconds: 0
        )
        _ = try await local.mergeTerminalHistory(.init(records: [conflictingRecord], deletedAttemptIDs: []))

        let activeAttempts = try await local.attempts()
        let preservedActive = try XCTUnwrap(activeAttempts.first)
        XCTAssertEqual(preservedActive, active)
        XCTAssertTrue(preservedActive.healthWriteRequested)
        XCTAssertEqual(preservedActive.healthSyncState, .pending)

        _ = try await local.terminalize(id: id, event: .completed)
        _ = try await local.mergeTerminalHistory(.init(records: [conflictingRecord], deletedAttemptIDs: []))

        let terminalAttempts = try await local.attempts()
        let preservedTerminal = try XCTUnwrap(terminalAttempts.first)
        XCTAssertEqual(preservedTerminal.outcome, .completed)
        XCTAssertEqual(preservedTerminal.creditedSeconds, 300)
        XCTAssertTrue(preservedTerminal.healthWriteRequested)
        XCTAssertEqual(preservedTerminal.healthSyncState, .pending)
    }

    func testTerminalHistoryDeletionMarkerDefeatsStaleImportedRecord() async throws {
        let source = SessionLedgerStore(persistence: MemoryLedgerPersistence())
        let attempt = SessionAttempt(
            storyID: "future-story",
            plannedSeconds: 300,
            startedAt: Date(timeIntervalSince1970: 35_000),
            randomSeed: 6
        )
        _ = try await source.create(attempt)
        _ = try await source.terminalize(id: attempt.id, event: .cancelled(occurredAt: attempt.startedAt))
        let staleExport = try await source.exportTerminalHistory()

        let destination = SessionLedgerStore(persistence: MemoryLedgerPersistence())
        _ = try await destination.mergeTerminalHistory(staleExport)
        try await destination.delete(ids: [attempt.id])
        _ = try await destination.mergeTerminalHistory(staleExport)

        let remainingAttempts = try await destination.attempts()
        XCTAssertTrue(remainingAttempts.isEmpty)
        let result = try await destination.exportTerminalHistory()
        XCTAssertTrue(result.deletedAttemptIDs.contains(attempt.id))
        XCTAssertFalse(result.records.contains(where: { $0.id == attempt.id }))
    }

    func testTerminalHistoryImportRejectsMalformedAndConflictingTransportRecords() async throws {
        let startedAt = Date(timeIntervalSince1970: 36_000)
        let malformedCredit = TerminalSessionHistoryRecord(
            id: UUID(),
            storyID: Story.autumnTree.rawValue,
            plannedSeconds: 300,
            startedAt: startedAt,
            scheduledEndAt: startedAt.addingTimeInterval(300),
            timeZoneIdentifier: TimeZone.current.identifier,
            calendarIdentifier: String(describing: Calendar.current.identifier),
            randomSeed: 7,
            outcome: .completed,
            terminalAt: startedAt.addingTimeInterval(300),
            observedAt: nil,
            creditedSeconds: 1
        )
        let malformedOutcome = TerminalSessionHistoryRecord(
            id: UUID(),
            storyID: Story.autumnTree.rawValue,
            plannedSeconds: 300,
            startedAt: startedAt,
            scheduledEndAt: startedAt.addingTimeInterval(300),
            timeZoneIdentifier: TimeZone.current.identifier,
            calendarIdentifier: String(describing: Calendar.current.identifier),
            randomSeed: 8,
            outcome: .running,
            terminalAt: nil,
            observedAt: nil,
            creditedSeconds: 0
        )
        let conflictID = UUID()
        let validConflict = TerminalSessionHistoryRecord(
            id: conflictID,
            storyID: Story.autumnTree.rawValue,
            plannedSeconds: 300,
            startedAt: startedAt,
            scheduledEndAt: startedAt.addingTimeInterval(300),
            timeZoneIdentifier: TimeZone.current.identifier,
            calendarIdentifier: String(describing: Calendar.current.identifier),
            randomSeed: 9,
            outcome: .completed,
            terminalAt: startedAt.addingTimeInterval(300),
            observedAt: nil,
            creditedSeconds: 300
        )
        let conflictingCopy = TerminalSessionHistoryRecord(
            id: conflictID,
            storyID: Story.contemporaryLotus.rawValue,
            plannedSeconds: 300,
            startedAt: startedAt,
            scheduledEndAt: startedAt.addingTimeInterval(300),
            timeZoneIdentifier: TimeZone.current.identifier,
            calendarIdentifier: String(describing: Calendar.current.identifier),
            randomSeed: 9,
            outcome: .completed,
            terminalAt: startedAt.addingTimeInterval(300),
            observedAt: nil,
            creditedSeconds: 300
        )

        let ledger = SessionLedgerStore(persistence: MemoryLedgerPersistence())
        let result = try await ledger.mergeTerminalHistory(.init(
            records: [malformedCredit, malformedOutcome, validConflict, conflictingCopy],
            deletedAttemptIDs: []
        ))

        XCTAssertEqual(result.ignoredRecordIDs, [malformedCredit.id, malformedOutcome.id, conflictID])
        let attempts = try await ledger.attempts()
        XCTAssertTrue(attempts.isEmpty)
    }

    func testTerminalHistoryDefersActiveDeletionAcrossRestartThenAppliesIt() async throws {
        let persistence = MemoryLedgerPersistence()
        let id = UUID()
        let startedAt = Date(timeIntervalSince1970: 37_000)
        let active = SessionAttempt(
            id: id,
            storyID: Story.autumnTree.rawValue,
            plannedSeconds: 300,
            startedAt: startedAt,
            randomSeed: 10
        )
        let firstStore = SessionLedgerStore(persistence: persistence)
        _ = try await firstStore.create(active)

        let deferred = try await firstStore.mergeTerminalHistory(.init(
            records: [],
            deletedAttemptIDs: [id]
        ))
        XCTAssertEqual(deferred.deferredDeletionIDs, [id])
        let activeAttempts = try await firstStore.attempts()
        XCTAssertTrue(activeAttempts.contains(where: { $0.id == id && !$0.isTerminal }))

        let reloadedStore = SessionLedgerStore(persistence: persistence)
        _ = try await reloadedStore.reconcileOrphanedAttempts(observedAt: startedAt.addingTimeInterval(20))

        let reconciledAttempts = try await reloadedStore.attempts()
        XCTAssertTrue(reconciledAttempts.isEmpty)
        let exported = try await reloadedStore.exportTerminalHistory()
        XCTAssertTrue(exported.deletedAttemptIDs.contains(id))

        let replayResult = try await reloadedStore.mergeTerminalHistory(.init(
            records: [],
            deletedAttemptIDs: [id]
        ))
        XCTAssertTrue(replayResult.deferredDeletionIDs.isEmpty)
        let replayedAttempts = try await reloadedStore.attempts()
        XCTAssertTrue(replayedAttempts.isEmpty)
    }

    func testTerminalHistoryImportAllowsWallClockAdjustedUnfinishedOutcome() async throws {
        let startedAt = Date(timeIntervalSince1970: 38_000)
        let clockAdjustedCancellation = TerminalSessionHistoryRecord(
            id: UUID(),
            storyID: Story.autumnTree.rawValue,
            plannedSeconds: 300,
            startedAt: startedAt,
            scheduledEndAt: startedAt.addingTimeInterval(300),
            timeZoneIdentifier: TimeZone.current.identifier,
            calendarIdentifier: String(describing: Calendar.current.identifier),
            randomSeed: 11,
            outcome: .cancelled,
            terminalAt: startedAt.addingTimeInterval(-60),
            observedAt: startedAt.addingTimeInterval(-60),
            creditedSeconds: 0
        )

        let ledger = SessionLedgerStore(persistence: MemoryLedgerPersistence())
        let result = try await ledger.mergeTerminalHistory(.init(
            records: [clockAdjustedCancellation],
            deletedAttemptIDs: []
        ))
        let attempts = try await ledger.attempts()

        XCTAssertTrue(result.ignoredRecordIDs.isEmpty)
        XCTAssertEqual(attempts.first?.id, clockAdjustedCancellation.id)
        XCTAssertEqual(attempts.first?.outcome, .cancelled)
        XCTAssertEqual(attempts.first?.creditedSeconds, 0)
    }

    func testHistoryOwnershipPreventsAImportAndOfflineASessionFromEnteringB() async throws {
        let accountA = SessionHistoryAccountKey(userRecordName: "account-A")
        let accountB = SessionHistoryAccountKey(userRecordName: "account-B")
        let startedAt = Date(timeIntervalSince1970: 39_000)
        let importedA = TerminalSessionHistoryRecord(
            id: UUID(),
            storyID: Story.autumnTree.rawValue,
            plannedSeconds: 300,
            startedAt: startedAt,
            scheduledEndAt: startedAt.addingTimeInterval(300),
            timeZoneIdentifier: TimeZone.current.identifier,
            calendarIdentifier: String(describing: Calendar.current.identifier),
            randomSeed: 12,
            outcome: .completed,
            terminalAt: startedAt.addingTimeInterval(300),
            observedAt: nil,
            creditedSeconds: 300
        )
        let ledger = SessionLedgerStore(persistence: MemoryLedgerPersistence())
        try await ledger.prepareHistoryAccount(accountA)
        let importedResult = try await ledger.mergeTerminalHistory(
            .init(records: [importedA], deletedAttemptIDs: []),
            for: accountA
        )
        XCTAssertTrue(importedResult.rejectedOwnershipIDs.isEmpty)

        // The app records this while A is known but sync is disabled. Creation
        // assigns A immediately; no later UI callback is required to claim it.
        let offlineA = SessionAttempt(
            storyID: Story.contemporaryLotus.rawValue,
            plannedSeconds: 300,
            startedAt: startedAt.addingTimeInterval(1_000),
            randomSeed: 13
        )
        _ = try await ledger.create(offlineA)
        _ = try await ledger.terminalize(id: offlineA.id, event: .completed)

        try await ledger.prepareHistoryAccount(accountB)
        let bClaim = try await ledger.claimUnownedHistory(for: accountB)
        let bExport = try await ledger.exportTerminalHistory(for: accountB)
        let replayToB = try await ledger.mergeTerminalHistory(
            .init(records: [importedA], deletedAttemptIDs: []),
            for: accountB
        )

        XCTAssertTrue(bClaim.acceptedIDs.isEmpty)
        XCTAssertEqual(bClaim.rejectedIDs, [importedA.id, offlineA.id])
        XCTAssertTrue(bExport.records.isEmpty)
        XCTAssertEqual(replayToB.rejectedOwnershipIDs, [importedA.id])
        let aExport = try await ledger.exportTerminalHistory(for: accountA)
        XCTAssertEqual(
            Set(aExport.records.map(\.id)),
            [importedA.id, offlineA.id]
        )
    }

    @MainActor
    func testSessionRuntimeUsesContinuousElapsedNotWallDate() {
        let start = Date(timeIntervalSince1970: 40_000)
        let clock = ContinuousClock()
        let startedInstant = clock.now
        let runtime = SessionRuntime(session: PerformanceSession(
            duration: .fiveMinutes,
            startedAt: start,
            randomSeed: 5
        ), startedInstant: startedInstant)

        let stable = runtime.sample(at: startedInstant.advanced(by: .seconds(120)))
        XCTAssertEqual(stable.elapsedTime, 120)
        XCTAssertEqual(stable.progress, 0.4)
        XCTAssertEqual(stable.remainingTime, 180)
        XCTAssertFalse(stable.isComplete)
        XCTAssertEqual(runtime.sample(at: startedInstant.advanced(by: .seconds(301))).elapsedTime, 300)
    }

    @MainActor
    func testLifecycleRejectsConcurrentStartAndDoesNotClaimStorageSuccess() async throws {
        let persistence = MemoryLedgerPersistence()
        let lifecycle = SessionLifecycle(ledger: SessionLedgerStore(persistence: persistence))
        await lifecycle.prepareForLaunch(observedAt: Date(timeIntervalSince1970: 50_000))
        XCTAssertTrue(lifecycle.isReady)

        let first = try await lifecycle.begin(
            story: .autumnTree,
            duration: .fiveMinutes,
            startedAt: Date(timeIntervalSince1970: 50_001)
        )
        XCTAssertEqual(first.session.duration, .fiveMinutes)
        do {
            _ = try await lifecycle.begin(story: .autumnTree, duration: .fiveMinutes)
            XCTFail("A second window must not start an overlapping session")
        } catch let error as SessionLedgerError {
            XCTAssertEqual(error, .activeSessionExists)
        }

        let failingPersistence = ToggleFailingLedgerPersistence()
        let failing = SessionLifecycle(ledger: SessionLedgerStore(persistence: failingPersistence))
        await failing.prepareForLaunch()
        XCTAssertTrue(failing.isReady)
        await failingPersistence.failWrites()
        do {
            _ = try await failing.begin(story: .autumnTree, duration: .fiveMinutes)
            XCTFail("A failed durable write must not start a visible session")
        } catch {
            XCTAssertNil(failing.activeRuntime)
        }
    }

    @MainActor
    func testLifecycleRetriesFailedCancellationWithItsOriginalEventTime() async throws {
        let persistence = ToggleFailingLedgerPersistence()
        let lifecycle = SessionLifecycle(ledger: SessionLedgerStore(persistence: persistence))
        let start = Date(timeIntervalSince1970: 60_000)
        await lifecycle.prepareForLaunch(observedAt: start)
        let runtime = try await lifecycle.begin(story: .autumnTree, duration: .fiveMinutes, startedAt: start)

        await persistence.failWrites()
        do {
            _ = try await lifecycle.cancel(id: runtime.id, at: start.addingTimeInterval(10))
            XCTFail("The cancelled result must not be shown when its save fails")
        } catch {
            XCTAssertNotNil(lifecycle.activeRuntime)
            XCTAssertTrue(lifecycle.hasPendingTerminalEvent)
        }

        await persistence.allowWrites()
        let retried = try await lifecycle.cancel(id: runtime.id, at: start.addingTimeInterval(400))
        XCTAssertEqual(retried.outcome, .cancelled)
        XCTAssertEqual(retried.terminalAt, start.addingTimeInterval(10))
        XCTAssertEqual(retried.creditedSeconds, 0)
        XCTAssertFalse(lifecycle.hasPendingTerminalEvent)
    }

    func testRepeatedTerminalReadDoesNotRequireAnotherWrite() async throws {
        let persistence = ToggleFailingLedgerPersistence()
        let ledger = SessionLedgerStore(persistence: persistence)
        let attempt = SessionAttempt(
            storyID: Story.autumnTree.rawValue,
            plannedSeconds: 300,
            startedAt: Date(timeIntervalSince1970: 70_000),
            randomSeed: 4
        )
        _ = try await ledger.create(attempt)
        let completed = try await ledger.terminalize(id: attempt.id, event: .completed)
        await persistence.failWrites()
        let repeated = try await ledger.terminalize(
            id: attempt.id,
            event: .cancelled(occurredAt: attempt.scheduledEndAt)
        )
        XCTAssertEqual(repeated, completed)
    }

    @MainActor
    func testLifecycleSerializesOverlappingTerminalCallsBeforeReturningWaiters() async throws {
        let persistence = SuspendedLedgerPersistence()
        let lifecycle = SessionLifecycle(ledger: SessionLedgerStore(persistence: persistence))
        let start = Date(timeIntervalSince1970: 80_000)
        await lifecycle.prepareForLaunch(observedAt: start)
        let runtime = try await lifecycle.begin(story: .autumnTree, duration: .fiveMinutes, startedAt: start)
        await persistence.suspendNextSave()

        let cancellation = Task { @MainActor in
            let attempt = try await lifecycle.cancel(id: runtime.id, at: start.addingTimeInterval(10))
            return (attempt, lifecycle.activeOutcome)
        }
        await persistence.waitUntilSaveSuspended()
        let distraction = Task { @MainActor in
            let attempt = try await lifecycle.recordDistraction(
                id: runtime.id,
                occurredAt: start.addingTimeInterval(9),
                observedAt: start.addingTimeInterval(11)
            )
            return (attempt, lifecycle.activeOutcome)
        }
        await persistence.releaseSave()

        let first = try await cancellation.value
        let second = try await distraction.value
        XCTAssertEqual(first.0.outcome, .cancelled)
        XCTAssertEqual(second.0, first.0)
        XCTAssertEqual(first.1, .cancelled)
        XCTAssertEqual(second.1, .cancelled)
        XCTAssertEqual(lifecycle.activeOutcome, .cancelled)
        XCTAssertEqual(lifecycle.activeRuntime?.id, runtime.id)

        lifecycle.dismissActivePresentation(id: runtime.id)
        let replacement = try await lifecycle.begin(story: .autumnTree, duration: .fiveMinutes)
        do {
            _ = try await lifecycle.cancel(id: runtime.id)
            XCTFail("A stale scene action must not change the replacement session")
        } catch let error as SessionLedgerError {
            XCTAssertEqual(error, .attemptNotFound)
        }
        XCTAssertEqual(lifecycle.activeRuntime?.id, replacement.id)
    }

    @MainActor
    func testPreferencesFallBackSafelyAndPersistSessionChoices() {
        let suite = "PlanetCalmTests.preferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set("missing-story", forKey: "preferences.selected-story.v1")
        defaults.set("missing-appearance", forKey: "preferences.interface-appearance.v1")
        defaults.set(1, forKey: "preferences.duration-seconds.v1")
        defaults.set(3.0, forKey: "preferences.volume.v1")

        let preferences = AppPreferences(defaults: defaults)
        XCTAssertEqual(preferences.selectedStory, .autumnTree)
        XCTAssertEqual(preferences.lastDuration, .fiveMinutes)
        XCTAssertEqual(preferences.volume, 1)
        XCTAssertEqual(preferences.interfaceAppearance, .system)

        preferences.selectedStory = .contemporaryLotus
        preferences.lastDuration = .twentyFiveMinutes
        preferences.volume = 0.35
        preferences.isMuted = true
        preferences.interfaceAppearance = .dark

        let reloaded = AppPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.selectedStory, .contemporaryLotus)
        XCTAssertEqual(reloaded.lastDuration, .twentyFiveMinutes)
        XCTAssertEqual(reloaded.volume, 0.35)
        XCTAssertTrue(reloaded.isMuted)
        XCTAssertEqual(reloaded.interfaceAppearance, .dark)
        defaults.removePersistentDomain(forName: suite)
    }

    @MainActor
    func testLifecycleRejectsHistoryDeletionDuringActiveSessionAndDeletesTerminalHistory() async throws {
        let persistence = MemoryLedgerPersistence()
        let lifecycle = SessionLifecycle(ledger: SessionLedgerStore(persistence: persistence))
        let start = Date(timeIntervalSince1970: 90_000)
        await lifecycle.prepareForLaunch(observedAt: start)
        let runtime = try await lifecycle.begin(story: .autumnTree, duration: .fiveMinutes, startedAt: start)

        do {
            try await lifecycle.deleteHistory()
            XCTFail("An active session must prevent history deletion")
        } catch let error as SessionLedgerError {
            XCTAssertEqual(error, .activeSessionExists)
        }

        _ = try await lifecycle.cancel(id: runtime.id, at: start.addingTimeInterval(5))
        lifecycle.dismissActivePresentation(id: runtime.id)
        try await lifecycle.deleteHistory()

        let reader = SessionLedgerStore(persistence: persistence)
        let remaining = try await reader.attempts()
        XCTAssertTrue(remaining.isEmpty)
    }

    @MainActor
    func testIdleTimerCoordinatorKeepsOtherWindowRequestWhenOneWindowLeaves() {
        let coordinator = FocusIdleTimerCoordinator()
        let firstWindow = UUID()
        let secondWindow = UUID()

        coordinator.update(requestID: firstWindow, isEligible: true)
        coordinator.update(requestID: secondWindow, isEligible: true)
        coordinator.update(requestID: secondWindow, isEligible: false)
        XCTAssertTrue(coordinator.keepsScreenAwake)

        coordinator.remove(requestID: firstWindow)
        XCTAssertFalse(coordinator.keepsScreenAwake)
    }

    @MainActor
    func testLiveActivityCoordinatorUpdatesOneSessionAndCleansStaleActivities() async {
        let driver = LiveActivityDriverSpy(availability: .available)
        let coordinator = LiveActivitySessionCoordinator(driver: driver)
        let descriptor = PlanetFocusCountdownDescriptor(
            sessionID: UUID(),
            storyTitle: "Autumn Tree",
            scheduledEndAt: Date(timeIntervalSince1970: 100_300)
        )

        await coordinator.synchronize(descriptor: descriptor, isEnabled: true)
        await coordinator.synchronize(descriptor: descriptor, isEnabled: true)

        XCTAssertEqual(driver.endedExcept, [descriptor.sessionID, descriptor.sessionID])
        XCTAssertEqual(driver.started, [descriptor, descriptor])
        XCTAssertEqual(coordinator.status, .active(descriptor.sessionID))

        await coordinator.reconcile(activeDescriptor: nil, isEnabled: true)
        XCTAssertEqual(driver.endAllCount, 1)
        XCTAssertEqual(coordinator.status, .inactive)
    }

    @MainActor
    func testLiveActivityCoordinatorDoesNotTreatUnavailableDisplayAsSessionFailure() async {
        let descriptor = PlanetFocusCountdownDescriptor(
            sessionID: UUID(),
            storyTitle: "Autumn Tree",
            scheduledEndAt: Date(timeIntervalSince1970: 100_300)
        )
        let systemDisabled = LiveActivityDriverSpy(availability: .disabledBySystem)
        let disabledCoordinator = LiveActivitySessionCoordinator(driver: systemDisabled)

        await disabledCoordinator.synchronize(descriptor: descriptor, isEnabled: true)
        XCTAssertEqual(disabledCoordinator.status, .disabledBySystem)
        XCTAssertTrue(systemDisabled.started.isEmpty)
        XCTAssertEqual(systemDisabled.endAllCount, 0)

        let preferenceDisabled = LiveActivityDriverSpy(availability: .available)
        let preferenceCoordinator = LiveActivitySessionCoordinator(driver: preferenceDisabled)
        await preferenceCoordinator.synchronize(descriptor: descriptor, isEnabled: false)
        XCTAssertEqual(preferenceCoordinator.status, .disabledByPreference)
        XCTAssertEqual(preferenceDisabled.endAllCount, 1)
        XCTAssertTrue(preferenceDisabled.started.isEmpty)
    }

    func testCountdownDisplayRangeRejectsExpiredAndAcceptsFutureEndDates() {
        let now = Date(timeIntervalSince1970: 100_000)

        XCTAssertNil(
            PlanetFocusCountdownDisplay.timerInterval(
                endingAt: now.addingTimeInterval(-1),
                now: now
            )
        )
        XCTAssertNil(PlanetFocusCountdownDisplay.timerInterval(endingAt: now, now: now))
        XCTAssertEqual(
            PlanetFocusCountdownDisplay.timerInterval(
                endingAt: now.addingTimeInterval(1),
                now: now
            ),
            now...now.addingTimeInterval(1)
        )
    }

    @MainActor
    func testLaterDisabledIntentPreventsDelayedOlderRequest() async {
        let driver = DelayedEndAllExceptDriver()
        let coordinator = LiveActivitySessionCoordinator(driver: driver)
        let descriptor = PlanetFocusCountdownDescriptor(
            sessionID: UUID(),
            storyTitle: "Autumn Tree",
            scheduledEndAt: Date(timeIntervalSince1970: 100_300)
        )

        let first = Task {
            await coordinator.synchronize(descriptor: descriptor, isEnabled: true)
        }
        await driver.waitUntilEndAllExceptIsSuspended()

        let second = Task {
            await coordinator.synchronize(descriptor: nil, isEnabled: false)
        }
        await Task.yield()
        await driver.resumeBarrier()
        await first.value
        await second.value

        let snapshot = await driver.snapshot()
        XCTAssertTrue(snapshot.started.isEmpty)
        XCTAssertEqual(snapshot.endAllCount, 1)
        XCTAssertEqual(coordinator.status, .disabledByPreference)
    }

    private struct LegacyLedgerEnvelope: Codable {
        let schemaVersion: Int
        let attempts: [SessionAttempt]
        let deletedAttemptIDs: Set<UUID>
    }

    private actor MemoryLedgerPersistence: SessionLedgerPersistence {
        private var data: Data?

        init(initialData: Data? = nil) {
            self.data = initialData
        }

        func load() -> Data? { data }

        func save(_ data: Data) {
            self.data = data
        }
    }

    private final class LiveActivityDriverSpy: LiveActivityDriving, @unchecked Sendable {
        var availability: LiveActivityAvailability
        private(set) var started: [PlanetFocusCountdownDescriptor] = []
        private(set) var ended: [UUID] = []
        private(set) var endedExcept: [UUID] = []
        private(set) var endAllCount = 0

        init(availability: LiveActivityAvailability) {
            self.availability = availability
        }

        func startOrUpdate(_ descriptor: PlanetFocusCountdownDescriptor) async throws {
            started.append(descriptor)
        }

        func end(sessionID: UUID) async {
            ended.append(sessionID)
        }

        func endAll() async {
            endAllCount += 1
        }

        func endAll(except sessionID: UUID) async {
            endedExcept.append(sessionID)
        }
    }

    private actor DelayedEndAllExceptDriver: LiveActivityDriving {
        nonisolated let availability: LiveActivityAvailability = .available
        private var started: [PlanetFocusCountdownDescriptor] = []
        private var endAllCount = 0
        private var reachedBarrier = false
        private var barrierWaiter: CheckedContinuation<Void, Never>?
        private var releaseContinuation: CheckedContinuation<Void, Never>?

        func startOrUpdate(_ descriptor: PlanetFocusCountdownDescriptor) async throws {
            started.append(descriptor)
        }

        func end(sessionID: UUID) async {}

        func endAll() async {
            endAllCount += 1
        }

        func endAll(except sessionID: UUID) async {
            reachedBarrier = true
            barrierWaiter?.resume()
            barrierWaiter = nil
            await withCheckedContinuation { continuation in
                releaseContinuation = continuation
            }
        }

        func waitUntilEndAllExceptIsSuspended() async {
            if reachedBarrier { return }
            await withCheckedContinuation { continuation in
                barrierWaiter = continuation
            }
        }

        func resumeBarrier() {
            releaseContinuation?.resume()
            releaseContinuation = nil
        }

        func snapshot() -> (started: [PlanetFocusCountdownDescriptor], endAllCount: Int) {
            (started, endAllCount)
        }
    }

    private actor ToggleFailingLedgerPersistence: SessionLedgerPersistence {
        private var shouldFailWrites = false

        func load() -> Data? { nil }

        func save(_ data: Data) throws {
            guard shouldFailWrites else { return }
            throw CocoaError(.fileWriteOutOfSpace)
        }

        func failWrites() {
            shouldFailWrites = true
        }

        func allowWrites() {
            shouldFailWrites = false
        }
    }

    private actor SuspendedLedgerPersistence: SessionLedgerPersistence {
        private var data: Data?
        private var suspendsNextSave = false
        private var saveContinuation: CheckedContinuation<Void, Never>?
        private var enteredContinuation: CheckedContinuation<Void, Never>?

        func load() -> Data? { data }

        func save(_ data: Data) async {
            if suspendsNextSave {
                suspendsNextSave = false
                await withCheckedContinuation { continuation in
                    saveContinuation = continuation
                    enteredContinuation?.resume()
                    enteredContinuation = nil
                }
            }
            self.data = data
        }

        func suspendNextSave() {
            suspendsNextSave = true
        }

        func releaseSave() {
            saveContinuation?.resume()
            saveContinuation = nil
        }

        func waitUntilSaveSuspended() async {
            guard saveContinuation == nil else { return }
            await withCheckedContinuation { continuation in
                enteredContinuation = continuation
            }
        }
    }

    private var origamiStage: AutumnBirdStage {
        AutumnBirdStage(camera: AutumnBirdCamera(center: SIMD2(350, 420)),
            left: -120, right: 900, sun: SIMD2(720, 360))
    }

    func testAutumnPersistsSettingsWithoutSessionEvents() throws {
        var record = AutumnBranchRecord()
        record.tuning.windStrength = 0.7
        record.manualGusts = [10, 20]
        record.bird = AutumnBirdStudy(tuning: .init(),
            flight: AutumnOrigamiFlight(startTime: 12, seed: 42, tuning: .init()))
        let saved = try JSONDecoder().decode(AutumnBranchRecord.self,
            from: JSONEncoder().encode(record.settingsOnly))
        XCTAssertEqual(saved.tuning, record.tuning)
        XCTAssertEqual(saved.bird?.tuning, record.bird?.tuning)
        XCTAssertTrue(saved.manualGusts.isEmpty)
        XCTAssertNil(saved.bird?.flight)
        XCTAssertNotNil(record.bird?.flight)
    }

    func testOrigamiApprovedDeparture() throws {
        let flight = AutumnOrigamiFlight(startTime: 0, seed: 42, tuning: .init())
        // Golden poses recorded before the entrance refinement: position, yaw,
        // pitch, bank, wing root, tip fold. Include wind and the takeoff boundary.
        let expected: [[Double]] = [
            [14, 626.95352390816, 471.1507935499891, 0, 0.32, 0, 0, 0.78, 0.12],
            [14.5, 626.5935212304759, 475.8630668945984, 5.800512897246634,
             -0.05579727474057722, 0.07200241088867188, -0.004689980275183604, 0.711692833868121, 0.1422531209354835],
            [16, 623.1767624777244, 528.7489325812933, 74.30796540737369,
             -1.5918282627667006, 0.4, 0.0688358842591385, -0.23030390558915204, -0.05269648824875167],
            [20, 785.6275829818198, 647.8675171257858, 334.48548020027306,
             -0.6316049206267196, 0.04404864691239153, 0.022088701500144126, 0.3340304564829871, 0.018364354788892298],
            [24, 1233.719038358092, 611.5310635951438, 604.9725079654074,
             -0.48008265504927744, -0.16510094651621623, 0.07889834359379089, 0.8723764974524965, 0.22988220503976398],
            [26, 1521.1348533123683, 552.6648896948018, 749.6470641784249,
             -0.46306865250497803, -0.18715703280686002, 0.13159157106695163, 0.7623512581747254, 0.29269648824875344]]
        for row in expected {
            let time = row[0]
            let pose = try XCTUnwrap(flight.sample(at: time, frame: AutumnCanopy.frame(),
                stage: origamiStage, wind: SIMD2(0.3, -0.2)))
            let actual = [pose.position.x, pose.position.y, pose.position.z,
                          pose.yaw, pose.pitch, pose.bank, pose.wingAngle, pose.tipFold]
            for (value, baseline) in zip(actual, row.dropFirst()) {
                XCTAssertEqual(value, baseline, accuracy: 1e-9, "Departure changed at \(time)")
            }
            XCTAssertEqual(pose.legFold, 0)
        }
    }

    func testOrigamiEntranceDepthBrakingAndSettling() throws {
        for speed in [0.5, 1, 1.5] {
            for depth in [0.0, 1, 1.5] {
                var tuning = AutumnBirdTuning()
                tuning.speed = speed
                tuning.depth = depth
                let flight = AutumnOrigamiFlight(startTime: 0, seed: 42, tuning: tuning)
                func pose(_ u: Double) throws -> AutumnBirdPose {
                    try XCTUnwrap(flight.sample(at: u * flight.approachDuration,
                        frame: AutumnCanopy.frame(), stage: origamiStage, wind: .zero))
                }
                let distant = try pose(0.25), near = try pose(0.76), landed = try pose(1)
                XCTAssertGreaterThan(distant.position.z, 300 * depth - 0.01)
                XCTAssertEqual(near.position.z, -105 * depth, accuracy: 0.01)
                XCTAssertEqual(landed.position, AutumnOrigamiFlight.perch(in: AutumnCanopy.frame()))
                XCTAssertEqual(landed.legFold, 0)
                XCTAssertLessThan(distant.legFold, -1)
                XCTAssertEqual(try pose(0.96).wingAngle, 0.10, accuracy: 1e-9)
                if depth > 0 {
                    XCTAssertGreaterThan(origamiStage.camera.magnification(at: near.position.z),
                        origamiStage.camera.magnification(at: distant.position.z))
                    // Far panels really render behind the tree; near panels in front.
                    for (sample, behind) in [(distant, true), (near, false)] {
                        for face in AutumnOrigamiMesh.faces(wing: sample.wingAngle,
                            tipFold: sample.tipFold, legFold: sample.legFold) {
                            let vertices = [sample.transform(face.a), sample.transform(face.b), sample.transform(face.c)]
                            XCTAssertEqual(AutumnOrigamiMesh.clipped(vertices, behindTree: behind).count, 3)
                        }
                    }
                }
                // No positional or velocity discontinuity at either route join.
                for join in [0.45, 0.76, 1.0] {
                    let h = 0.00001
                    let left = try pose(join - h).position
                    let center = try pose(join).position
                    let right = try pose(join + h).position
                    let v0 = (center - left) / (h * flight.approachDuration)
                    let v1 = (right - center) / (h * flight.approachDuration)
                    XCTAssertLessThan(simd_distance(v0, v1), 0.15)
                }
                for u in stride(from: 0.0, through: 1.0, by: 0.01) {
                    let p = try pose(u)
                    XCTAssertTrue([p.position.x, p.position.y, p.position.z, p.yaw,
                                   p.pitch, p.bank, p.wingAngle, p.legFold].allSatisfy(\.isFinite))
                }
                let settled = try XCTUnwrap(flight.sample(at: flight.approachDuration + 1.1,
                    frame: AutumnCanopy.frame(), stage: origamiStage, wind: .zero))
                XCTAssertEqual(settled.wingAngle, 0.78)
                XCTAssertEqual(settled.pitch, 0)
            }
        }
    }

    func testOrigamiPerspectiveAndFiniteStoryEvent() throws {
        let camera = origamiStage.camera
        XCTAssertEqual(camera.magnification(at: 0), 1, accuracy: 1e-12)
        XCTAssertLessThan(camera.magnification(at: 600), 0.70)
        for z in [0.0, 200, 800] {
            let point = SIMD2(610.0, 400)
            XCTAssertLessThan(simd_length(camera.project(camera.unproject(point, z: z)) - point), 1e-9)
        }
        let flight = AutumnOrigamiFlight(startTime: 4, seed: 42, tuning: .init())
        let frame = AutumnCanopy.frame()
        XCTAssertNil(flight.sample(at: 3.99, frame: frame, stage: origamiStage, wind: .zero))
        XCTAssertNil(flight.sample(at: flight.moment.endTime, frame: frame, stage: origamiStage, wind: .zero))
        let perched = try XCTUnwrap(flight.sample(at: 14, frame: frame, stage: origamiStage, wind: .zero))
        let distant = try XCTUnwrap(flight.sample(at: 27, frame: frame, stage: origamiStage, wind: .zero))
        XCTAssertEqual(perched.phase, .perched)
        XCTAssertEqual(perched.position.z, 0)
        XCTAssertGreaterThan(distant.position.z, 300)
        XCTAssertLessThan(camera.magnification(at: distant.position.z), 0.8)
    }

    func testOrigamiLandingTracksBranchAndTransitionIsContinuous() throws {
        let flight = AutumnOrigamiFlight(startTime: 0, seed: 42, tuning: .init())
        var frame = AutumnCanopy.frame()
        let a = try XCTUnwrap(flight.sample(at: 10, frame: frame, stage: origamiStage, wind: SIMD2(1, 1)))
        XCTAssertEqual(a.position, AutumnOrigamiFlight.perch(in: frame))
        frame.limbAngles[0] = 0.03
        frame.canopyCurves = AutumnCanopy.curves(angles: frame.limbAngles)
        let b = try XCTUnwrap(flight.sample(at: 10, frame: frame, stage: origamiStage, wind: .zero))
        XCTAssertEqual(b.position, AutumnOrigamiFlight.perch(in: frame))
        XCTAssertGreaterThan(simd_distance(a.position, b.position), 5)
        for boundary in [flight.approachDuration,
                         flight.approachDuration + flight.perchDuration] {
            let before = try XCTUnwrap(flight.sample(at: boundary - 0.001, frame: frame, stage: origamiStage, wind: .zero))
            let after = try XCTUnwrap(flight.sample(at: boundary + 0.001, frame: frame, stage: origamiStage, wind: .zero))
            XCTAssertLessThan(simd_distance(before.position, after.position), 0.01)
            XCTAssertEqual(before.wingAngle, after.wingAngle, accuracy: 0.001)
        }
    }

    func testOrigamiWindPausePersistenceAndReducedMotion() throws {
        let flight = AutumnOrigamiFlight(startTime: 0, seed: 42, tuning: .init())
        let frame = AutumnCanopy.frame()
        let calm = try XCTUnwrap(flight.sample(at: 4, frame: frame, stage: origamiStage, wind: .zero))
        let windy = try XCTUnwrap(flight.sample(at: 4, frame: frame, stage: origamiStage, wind: SIMD2(0.8, 0.1)))
        XCTAssertGreaterThan(simd_distance(calm.position, windy.position), 5)
        let restored = try JSONDecoder().decode(AutumnOrigamiFlight.self, from: JSONEncoder().encode(flight))
        XCTAssertEqual(calm, restored.sample(at: 4, frame: frame, stage: origamiStage, wind: .zero))
        var clock = PerformanceSession(duration: .fiveMinutes, startedAt: .distantPast, randomSeed: 42)
        clock.pause(at: Date.distantPast.addingTimeInterval(4))
        XCTAssertEqual(clock.elapsedTime(at: .now), 4)
        XCTAssertEqual(calm, flight.sample(at: clock.elapsedTime(at: .now), frame: frame, stage: origamiStage, wind: .zero))
        XCTAssertNil(flight.sample(at: 4, frame: frame, stage: origamiStage, wind: .zero, reduceMotion: true))
        let reduced = flight.sample(at: 9, frame: frame, stage: origamiStage, wind: .zero, reduceMotion: true)
        XCTAssertEqual(reduced, flight.sample(at: 12, frame: frame, stage: origamiStage, wind: SIMD2(1, 0), reduceMotion: true))
        let oldRecord = AutumnBranchRecord(tuning: .standard, manualGusts: [3])
        let decoded = try JSONDecoder().decode(AutumnBranchRecord.self, from: JSONEncoder().encode(oldRecord))
        XCTAssertEqual(decoded.manualGusts, [3])
        XCTAssertNil(decoded.bird)
    }

    func testOrigamiPaperPanelsKeepTheirEdgeLengths() {
        let triangle = [SIMD3(0.0, 0, -1), SIMD3(1.0, 0, 1), SIMD3(0.0, 1, 1)]
        let front = AutumnOrigamiMesh.clipped(triangle, behindTree: false)
        let back = AutumnOrigamiMesh.clipped(triangle, behindTree: true)
        XCTAssertEqual(front.count, 3)
        XCTAssertEqual(back.count, 4)
        XCTAssertTrue(front.allSatisfy { $0.z <= 0 })
        XCTAssertTrue(back.allSatisfy { $0.z >= 0 })
        let baseline = AutumnOrigamiMesh.faces(wing: 0, tipFold: 0)
        for angle in stride(from: -0.5, through: 1.1, by: 0.1) {
            let mesh = AutumnOrigamiMesh.faces(wing: angle, tipFold: angle * 0.3, legFold: -abs(angle))
            XCTAssertEqual(mesh.count, baseline.count)
            for (a, b) in zip(baseline, mesh) {
                XCTAssertEqual(simd_distance(a.a, a.b), simd_distance(b.a, b.b), accuracy: 1e-8)
                XCTAssertEqual(simd_distance(a.b, a.c), simd_distance(b.b, b.c), accuracy: 1e-8)
                XCTAssertEqual(simd_distance(a.c, a.a), simd_distance(b.c, b.a), accuracy: 1e-8)
                XCTAssertGreaterThan(simd_length(simd_cross(b.b-b.a, b.c-b.a)), 0.01)
            }
        }
    }

    @MainActor
    func testOrigamiNativeCompositionSnapshots() throws {
        let reference = try LeafGravityLabConfiguration.gate3Bundled.get()
        let plan = AutumnBranchPlan(duration: 120, seed: 42, tuning: .standard, isFullTree: true)
        let simulation = AutumnBranchSimulation(plan: plan, reference: reference)
        let flight = AutumnOrigamiFlight(startTime: 0, seed: 42, tuning: .init())
        for (name, size) in [("ipad-tall", CGSize(width: 820, height: 1180)),
                             ("ipad-wide", CGSize(width: 1180, height: 820)),
                             ("phone", CGSize(width: 393, height: 852))] {
            for time in [3.0, 4, 5, 6, 7, 8, 9, 10, 20, 23] {
                let scene = AutumnBranchCanvas(includesAtmosphere: false, size: size,
                    frame: simulation.sample(at: time), progress: 0.3, tuning: .standard,
                    reduceMotion: false, birdFlight: flight, elapsedTime: time, birdPlan: plan)
                let renderer = ImageRenderer(content: scene)
                renderer.scale = 1
                let image = try XCTUnwrap(renderer.uiImage)
                XCTAssertEqual(image.size, size)
                let attachment = XCTAttachment(image: image)
                attachment.name = "origami-\(name)-\(Int(time))"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }
    @MainActor
    func testAutumnFullTreeWideLayoutSnapshot() throws {
        let reference = try LeafGravityLabConfiguration.gate3Bundled.get()
        let simulation = AutumnBranchSimulation(
            plan: .init(duration: 120, seed: 42, tuning: .standard, isFullTree: true), reference: reference)
        let size = CGSize(width: 1180, height: 820)
        let scene = AutumnBranchCanvas(includesAtmosphere: false, size: size, frame: simulation.sample(at: 12),
            progress: 0.25, tuning: .standard, reduceMotion: false)
            .background(Color(red: 0.15, green: 0.20, blue: 0.28))
        let renderer = ImageRenderer(content: scene)
        renderer.scale = 1
        let snapshot = try XCTUnwrap(renderer.uiImage)
        XCTAssertEqual(snapshot.size, size)
        let attachment = XCTAttachment(image: snapshot)
        attachment.name = "autumn-wide-native-layout-no-metal-sky"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testAutumnEveryLeafHasASeededReleaseAndTimeToLand() throws {
        let reference = try LeafGravityLabConfiguration.gate3Bundled.get()
        for duration in [60.0, 120, 900, 3000] {
            let plan = AutumnBranchPlan(duration: duration, seed: 42, tuning: .standard, isFullTree: true)
            XCTAssertEqual(plan.leafReleases.count, AutumnCanopy.shoots.count)
            XCTAssertEqual(Set(plan.leafReleases.map(\.id)).count, AutumnCanopy.shoots.count)
            XCTAssertEqual(plan.leafReleases,
                AutumnBranchPlan(duration: duration, seed: 42, tuning: .standard, isFullTree: true).leafReleases)
            let sorted = plan.leafReleases.map(\.startTime).sorted()
            XCTAssertGreaterThan(sorted.first!, 0)
            XCTAssertLessThan(sorted.last!, min(duration * 0.81, duration - 15))
            XCTAssertLessThan(sorted.filter { $0 <= duration * 0.25 }.count, sorted.count / 3)
            XCTAssertTrue(plan.gusts.contains { $0.startTime > sorted.last! },
                          "Keep a ground-only breeze after the canopy empties.")
            let simulation = AutumnBranchSimulation(plan: plan, reference: reference)
            let start = Date()
            let beforeLastBreeze = simulation.sample(at: duration * 0.86)
            let end = simulation.sample(at: duration)
            print("AUTUMN COMPLETE duration=\(duration), replaySeconds=\(Date().timeIntervalSince(start)), attached=\(end.leaves.filter { $0.phase == .attached }.count), airborne=\(end.leaves.filter { $0.phase == .falling }.count)")
            XCTAssertTrue(end.leaves.allSatisfy { $0.phase == .landed || $0.phase == .settled })
            XCTAssertTrue(end.leaves.allSatisfy { $0.releasedAt != nil })
            for leaf in end.leaves {
                XCTAssertEqual(leaf.releasedAt!, plan.leafReleases[leaf.id].startTime,
                               accuracy: AutumnBranchSimulation.step + 1e-8)
                XCTAssertEqual(leaf.y, leaf.groundLevel)
            }
            let grounded = beforeLastBreeze.leaves.filter { $0.phase == .landed || $0.phase == .settled }
            let moved = grounded.filter { abs(end.leaves[$0.id].x - $0.x) > 0.5 }
            print("LATE CARPET duration=\(duration): \(moved.count)/\(grounded.count) moved")
            XCTAssertGreaterThan(moved.count, 0, "The final breeze must still move some grounded leaves.")
            XCTAssertLessThan(moved.count, grounded.count, "A breeze must not move the entire carpet.")
        }
        let first = AutumnBranchPlan(duration: 900, seed: 42, tuning: .standard, isFullTree: true)
        let other = AutumnBranchPlan(duration: 900, seed: 43, tuning: .standard, isFullTree: true)
        XCTAssertNotEqual(first.leafReleases.map(\.startTime), other.leafReleases.map(\.startTime))
        let manual = AutumnBranchPlan(duration: 900, seed: 42, tuning: .standard,
                                      manualGusts: [20], isFullTree: true)
        XCTAssertEqual(first.leafReleases, manual.leafReleases)
    }

    func testAutumnConnectedWindGroundFrictionAndSelectivity() {
        var leaves = (0..<20).map { id in
            var leaf = AutumnBranchLeaf(id: id)
            leaf.x = 220 + Double(id) * 22
            leaf.groundLevel = -Double(id % 5) * 8
            leaf.y = leaf.groundLevel
            leaf.phase = .settled
            leaf.contactTime = 3
            leaf.groundTilt = AutumnGroundContact.flatTilt
            leaf.size = 0.6
            return leaf
        }
        let initial = leaves
        for _ in 0..<120 {
            for id in leaves.indices { AutumnGroundContact.integrate(&leaves[id], wind: 0.045, dt: 1.0/120) }
        }
        XCTAssertEqual(leaves.map(\.x), initial.map(\.x), "Background air must not make flat paper crawl.")
        for _ in 0..<720 {
            for id in leaves.indices { AutumnGroundContact.integrate(&leaves[id], wind: 0.65, dt: 1.0/120) }
        }
        let moved = zip(initial, leaves).filter { abs($0.x - $1.x) > 5 }.count
        print("GROUND WIND SELECTIVITY: \(moved)/\(leaves.count) moved")
        XCTAssertGreaterThan(moved, 2)
        XCTAssertLessThan(moved, leaves.count - 2)
        XCTAssertTrue(leaves.contains { abs($0.angle) > 0.05 })
        for _ in 0..<1200 {
            for id in leaves.indices { AutumnGroundContact.integrate(&leaves[id], wind: 0, dt: 1.0/120) }
        }
        for leaf in leaves {
            XCTAssertEqual(leaf.phase, .settled)
            XCTAssertEqual(leaf.vx, 0)
            XCTAssertEqual(leaf.y, leaf.groundLevel)
            XCTAssertEqual(leaf.groundShadow(sunX: 700, sunHeight: 80).x, leaf.x)
        }
    }

    func testAutumnConnectedWindTravelsAndReawakensGroundLeaves() throws {
        let reference = try LeafGravityLabConfiguration.gate3Bundled.get()
        let plan = AutumnBranchPlan(duration: 120, seed: 42, tuning: .standard, isFullTree: true)
        // Direction and spatial onset are covered by the passage tests.
        let simulation = AutumnBranchSimulation(plan: plan, reference: reference)
        let before = simulation.sample(at: 40)
        let after = simulation.sample(at: 65)
        let grounded = before.leaves.filter { $0.phase == .settled }
        let moved = grounded.filter { abs(after.leaves[$0.id].x - $0.x) > 4 }
        print("SECOND GUST: \(moved.count)/\(grounded.count) grounded leaves moved; distances=\(grounded.map { Int(after.leaves[$0.id].x - $0.x) })")
        XCTAssertGreaterThan(grounded.count, 5)
        XCTAssertGreaterThan(moved.count, 0)
        XCTAssertLessThan(moved.count, grounded.count)
        XCTAssertEqual(after, AutumnBranchSimulation(plan: plan, reference: reference).sample(at: 65))
        XCTAssertEqual(simulation.sample(at: 40), before)
        var quiet = AutumnBranchTuning.standard
        quiet.windStrength = 0.15
        let gentle = AutumnBranchSimulation(plan: .init(duration: 120, seed: 42, tuning: quiet, isFullTree: true), reference: reference)
        XCTAssertGreaterThan(gentle.sample(at: 35).leaves.filter { $0.phase != .attached }.count, 0,
                             "Seasonal release must still progress in gentle air.")
    }

    func testAutumnConnectedWindStrongGustsStayFiniteAndPause() throws {
        let reference = try LeafGravityLabConfiguration.gate3Bundled.get()
        var tuning = AutumnBranchTuning.standard
        tuning.windStrength = 1.2
        tuning.flexibility = 2
        tuning.damping = 0.4
        let simulation = AutumnBranchSimulation(plan: .init(duration: 120, seed: 901, tuning: tuning,
            manualGusts: [10, 11, 12], isFullTree: true), reference: reference)
        for time in stride(from: 0.0, through: 120, by: 0.25) {
            let frame = simulation.sample(at: time)
            XCTAssertEqual(frame.canopyCurves[0].start, SIMD2(350, 0))
            for leaf in frame.leaves {
                XCTAssertTrue(leaf.x.isFinite && leaf.y.isFinite && leaf.angle.isFinite)
                XCTAssertGreaterThanOrEqual(leaf.y, leaf.groundLevel)
                if leaf.phase == .landed || leaf.phase == .settled {
                    XCTAssertEqual(leaf.y, leaf.groundLevel)
                    XCTAssertLessThan(abs(leaf.vx), 300)
                }
            }
        }
        let start = Date(timeIntervalSince1970: 1000)
        var session = PerformanceSession(duration: .twoMinutes, startedAt: start, randomSeed: 901)
        session.pause(at: start.addingTimeInterval(52))
        let paused = simulation.sample(at: session.elapsedTime(at: start.addingTimeInterval(60)))
        XCTAssertEqual(paused, simulation.sample(at: session.elapsedTime(at: start.addingTimeInterval(100))))
        let restored = try JSONDecoder().decode(PerformanceSession.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(paused, AutumnBranchSimulation(plan: simulation.plan, reference: reference)
            .sample(at: restored.elapsedTime(at: start.addingTimeInterval(110))))
    }

    @MainActor
    func testAutumnConnectedWindReducedMotionKeepsGroundLeavesStill() throws {
        let reference = try LeafGravityLabConfiguration.gate3Bundled.get()
        let simulation = AutumnBranchSimulation(plan: .init(duration: 120, seed: 42,
            tuning: .standard, isFullTree: true), reference: reference)
        let before = simulation.sample(at: 40), after = simulation.sample(at: 65)
        func canvas(_ frame: AutumnBranchFrame) -> AutumnBranchCanvas {
            AutumnBranchCanvas(size: CGSize(width: 820, height: 1180), frame: frame,
                progress: 0.5, tuning: .standard, reduceMotion: true)
        }
        for leaf in before.leaves where leaf.phase != .attached {
            let a = canvas(before).renderLeaf(leaf)
            let b = canvas(after).renderLeaf(after.leaves[leaf.id])
            XCTAssertEqual(a.x, b.x)
            XCTAssertEqual(a.y, b.y)
            XCTAssertEqual(a.angle, b.angle)
            XCTAssertEqual(b.vx, 0)
            XCTAssertEqual(b.groundTilt, AutumnGroundContact.flatTilt)
        }
    }

    func testAutumnSpatialWindVariesAndRetainsLeafCarpet() throws {
        let reference = try LeafGravityLabConfiguration.gate3Bundled.get()
        for seed: UInt64 in [42, 17, 901] {
            let plan = AutumnBranchPlan(duration: 120, seed: seed, tuning: .standard, isFullTree: true)
            XCTAssertEqual(plan, AutumnBranchPlan(duration: 120, seed: seed, tuning: .standard, isFullTree: true))
            // Sources are independent random choices, not compulsory alternation.
            XCTAssertFalse(plan.windPassages.isEmpty)
            XCTAssertGreaterThan(Set(plan.windPassages.map(\.origin.y)).count, 1)
            XCTAssertGreaterThan(Set(plan.gusts.map(\.duration)).count, 1)
            for (passage, moment) in zip(plan.windPassages, plan.gusts) {
                let near = passage.origin + passage.direction * 30
                let far = passage.origin + passage.direction * 630
                let onset = moment.startTime + 1.5
                let early = passage.velocity(at: near, seconds: onset, moment: moment)
                let late = passage.velocity(at: far, seconds: onset, moment: moment)
                XCTAssertGreaterThan(hypot(early.x, early.y), hypot(late.x, late.y))
                let end = moment.startTime + moment.duration + 10
                XCTAssertEqual(passage.velocity(at: near, seconds: end, moment: moment), .zero)
            }
            let simulation = AutumnBranchSimulation(plan: plan, reference: reference)
            let frame = simulation.sample(at: 120)
            let ground = frame.leaves.filter { $0.phase == .landed || $0.phase == .settled }
            XCTAssertEqual(ground.count, frame.leaves.count, "Every seeded tree must end fully grounded.")
            // The narrow camera is 900 units wide around the 740-unit scaffold:
            // its visible ground includes 80 units on either side, as in Canvas.
            let retained = ground.filter { (-80...820).contains($0.x) }
            print("CARPET seed \(seed): \(retained.count)/\(ground.count) retained; x=\(ground.map { Int($0.x) })")
            XCTAssertGreaterThan(ground.count, 5)
            XCTAssertGreaterThanOrEqual(Double(retained.count) / Double(max(1, ground.count)), 0.85)
        }
        let short = AutumnBranchPlan(duration: 300, seed: 42, tuning: .standard, isFullTree: true)
        let long = AutumnBranchPlan(duration: 3000, seed: 42, tuning: .standard, isFullTree: true)
        XCTAssertGreaterThan(long.gusts.count, short.gusts.count)
        XCTAssertEqual(short.windPassages, Array(long.windPassages.prefix(short.gusts.count)))
        XCTAssertTrue(long.gusts.allSatisfy { (6...11).contains($0.duration) })
        let manual = AutumnBranchPlan(duration: 300, seed: 42, tuning: .standard, manualGusts: [30], isFullTree: true)
        XCTAssertEqual(Array(manual.windPassages.prefix(short.gusts.count)), short.windPassages)
        XCTAssertEqual(Array(manual.gusts.prefix(short.gusts.count)), short.gusts)
        var loose = AutumnBranchLeaf(id: 5)
        loose.phase = .settled; loose.x = 610; loose.size = 0.6
        loose.contactTime = 3; loose.groundTilt = AutumnGroundContact.flatTilt
        var sheltered = loose
        for _ in 0..<720 {
            AutumnGroundContact.integrate(&loose, wind: -0.75, dt: 1.0/120)
            AutumnGroundContact.integrate(&sheltered, wind: -0.75, dt: 1.0/120, neighbours: 3)
        }
        XCTAssertLessThan(loose.x, 600, "Right-origin wind must push left.")
        XCTAssertLessThan(abs(sheltered.x - 610), abs(loose.x - 610) * 0.3)
    }

    func testAutumnFullTreeHierarchyAndStemAttachments() throws {
        let reference = try LeafGravityLabConfiguration.gate3Bundled.get()
        let plan = AutumnBranchPlan(duration: 120, seed: 42, tuning: .standard, isFullTree: true)
        let simulation = AutumnBranchSimulation(plan: plan, reference: reference)
        XCTAssertEqual(simulation.sample(at: 0).leaves.count, AutumnCanopy.shoots.count)
        XCTAssertGreaterThan(AutumnCanopy.shoots.count, 150)
        for time in stride(from: 0.0, through: 30, by: 0.1) {
            let frame = simulation.sample(at: time)
            XCTAssertEqual(frame.canopyCurves[0].start, SIMD2(350, 0))
            for (index, limb) in AutumnCanopy.limbs.enumerated() {
                XCTAssertGreaterThan(limb.width, limb.tipWidth)
                guard let parent = limb.parent else { continue }
                XCTAssertLessThan(parent, index)
                XCTAssertEqual(frame.canopyCurves[index].start, frame.canopyCurves[parent].point(limb.at))
            }
            for leaf in frame.leaves where leaf.phase == .attached {
                let tip = AutumnBranchSimulation.twigTip(id: leaf.id, frame: frame)
                let stem = AutumnBranchLeafGeometry.stemOffset(id: leaf.artwork, angle: leaf.angle, turn: leaf.turn)
                XCTAssertEqual(leaf.x + stem.x * leaf.size, tip.x, accuracy: 0.000001)
                XCTAssertEqual(leaf.y + stem.y * leaf.size, tip.y, accuracy: 0.000001)
            }
        }
    }

    func testAutumnFullTreeReplayReleaseAndLandingDepth() throws {
        let reference = try LeafGravityLabConfiguration.gate3Bundled.get()
        let plan = AutumnBranchPlan(duration: 120, seed: 42, tuning: .standard, isFullTree: true)
        let simulation = AutumnBranchSimulation(plan: plan, reference: reference)
        var previous = simulation.sample(at: 0)
        var releases = 0
        for tick in 1...3600 {
            let frame = simulation.sample(at: Double(tick)/120)
            for (before, after) in zip(previous.leaves, frame.leaves) {
                XCTAssertTrue(after.x.isFinite && after.y.isFinite && after.angle.isFinite)
                if before.phase == .attached && after.phase == .falling {
                    releases += 1
                    XCTAssertLessThan(hypot(after.x-before.x, after.y-before.y), 1)
                    XCTAssertLessThan(abs(after.angle-before.angle), 0.1)
                }
                if after.phase == .settled {
                    XCTAssertEqual(after.y, after.groundLevel)
                    let shadow = after.groundShadow(sunX: 700, sunHeight: 80)
                    XCTAssertEqual(shadow.x, after.x, accuracy: 0.000001)
                    XCTAssertEqual(shadow.verticalScale, cos(after.groundTilt), accuracy: 0.000001)
                }
            }
            previous = frame
        }
        XCTAssertGreaterThan(releases, 5)
        XCTAssertLessThan(releases, previous.leaves.count / 3, "The first quarter should thin the canopy, not empty it.")
        XCTAssertGreaterThan(Set(previous.leaves.filter { $0.phase == .settled }.map(\.groundLevel)).count, 5)
        let direct = AutumnBranchSimulation(plan: plan, reference: reference)
        XCTAssertEqual(previous, direct.sample(at: 30))
        XCTAssertEqual(simulation.sample(at: 12), direct.sample(at: 12))
    }

    func testAutumnCheckpointDeterministicPhysicsAndSettling() throws {
        let reference = try LeafGravityLabConfiguration.gate3Bundled.get()
        let plan = AutumnBranchPlan(duration: 120, seed: 42, tuning: .standard)
        let stepped = AutumnBranchSimulation(plan: plan, reference: reference)
        for time in stride(from: 0.0, through: 80, by: 0.1) { _ = stepped.sample(at: time) }
        let direct = AutumnBranchSimulation(plan: plan, reference: reference)
        XCTAssertEqual(stepped.sample(at: 80), direct.sample(at: 80))
        let end = direct.sample(at: 120)
        XCTAssertEqual(end.leaves.count, 6)
        XCTAssertEqual(end.leaves.filter { $0.phase == .settled }.count, 3)
        for leaf in end.leaves {
            XCTAssertTrue(leaf.x.isFinite && leaf.y.isFinite && leaf.angle.isFinite)
            XCTAssertGreaterThanOrEqual(leaf.y, 0)
        }
        XCTAssertEqual(direct.sample(at: 20),
            AutumnBranchSimulation(plan: plan, reference: reference).sample(at: 20))
    }

    func testAutumnCheckpointStemStaysOnTwigDuringFlutter() throws {
        let reference = try LeafGravityLabConfiguration.gate3Bundled.get()
        for seed: UInt64 in [42, 17, 901] {
            let simulation = AutumnBranchSimulation(
                plan: .init(duration: 120, seed: seed, tuning: .standard), reference: reference)
            for tick in 0...3600 {
                let frame = simulation.sample(at: Double(tick) / 120)
                for leaf in frame.leaves where leaf.phase == .attached {
                    let joint = AutumnBranchSimulation.twigTip(id: leaf.id, frame: frame)
                    let stem = AutumnBranchLeafGeometry.stemOffset(
                        id: leaf.id, angle: leaf.angle, turn: leaf.turn)
                    XCTAssertEqual(leaf.x + stem.x, joint.x, accuracy: 0.000001)
                    XCTAssertEqual(leaf.y + stem.y, joint.y, accuracy: 0.000001)
                }
            }
        }
    }

    func testAutumnCheckpointGroundContactAndShadow() throws {
        let reference = try LeafGravityLabConfiguration.gate3Bundled.get()
        let simulation = AutumnBranchSimulation(
            plan: .init(duration: 120, seed: 42, tuning: .standard), reference: reference)
        var contacts = Set<Int>()
        for tick in 0...3600 {
            let frame = simulation.sample(at: Double(tick) / 120)
            for leaf in frame.leaves where leaf.phase == .landed || leaf.phase == .settled {
                contacts.insert(leaf.id)
                XCTAssertEqual(leaf.y, 0, accuracy: 0.000001)
                for sunX in [-400.0, 0, 600, 1200] {
                    let shadow = leaf.groundShadow(sunX: sunX, sunHeight: 80)
                    XCTAssertEqual(shadow.x, leaf.x, accuracy: 0.000001)
                    if leaf.phase == .settled {
                        // Same silhouette, yaw, roll, and flattened footprint as the paper.
                        XCTAssertEqual(shadow.verticalScale, cos(leaf.groundTilt), accuracy: 0.000001)
                    }
                }
            }
        }
        XCTAssertEqual(contacts, Set([1, 3, 5]))
        var airborne = AutumnBranchLeaf(id: 1)
        airborne.x = 300; airborne.y = 100
        XCTAssertLessThan(airborne.groundShadow(sunX: 600, sunHeight: 200).x, airborne.x)
        XCTAssertEqual(airborne.groundShadow(sunX: 600, sunHeight: 200).verticalScale, 0.25)
    }

    func testAutumnCheckpointReleaseContinuityAndPause() throws {
        let reference = try LeafGravityLabConfiguration.gate3Bundled.get()
        let simulation = AutumnBranchSimulation(plan: .init(duration: 120, seed: 42, tuning: .standard), reference: reference)
        var previous = simulation.sample(at: 0)
        var releases = 0
        for tick in 1...3600 {
            let frame = simulation.sample(at: Double(tick) / 120)
            for (before, after) in zip(previous.leaves, frame.leaves) where before.phase == .attached && after.phase == .falling {
                releases += 1
                XCTAssertLessThan(hypot(after.x - before.x, after.y - before.y), 1)
                XCTAssertLessThan(abs(after.angle - before.angle), 0.1)
                XCTAssertEqual(after.releasedAt, frame.time)
            }
            previous = frame
        }
        XCTAssertEqual(releases, 3)
        let start = Date(timeIntervalSince1970: 100)
        var session = PerformanceSession(duration: .twoMinutes, startedAt: start, randomSeed: 42)
        session.pause(at: start.addingTimeInterval(15))
        let frozen = simulation.sample(at: session.elapsedTime(at: start.addingTimeInterval(20)))
        XCTAssertEqual(frozen, simulation.sample(at: session.elapsedTime(at: start.addingTimeInterval(60))))
        let restored = try JSONDecoder().decode(PerformanceSession.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(frozen, AutumnBranchSimulation(plan: simulation.plan, reference: reference)
            .sample(at: restored.elapsedTime(at: start.addingTimeInterval(70))))
    }

    func testAutumnCheckpointWindDurationAndManualEvents() throws {
        let short = AutumnBranchPlan(duration: 300, seed: 42, tuning: .standard)
        let long = AutumnBranchPlan(duration: 3000, seed: 42, tuning: .standard)
        XCTAssertEqual(short.gusts.map(\.duration), long.gusts.map(\.duration))
        XCTAssertEqual(long.gusts[0].startTime, short.gusts[0].startTime * 10)
        let manual = AutumnBranchPlan(duration: 120, seed: 42, tuning: .standard, manualGusts: [3])
        XCTAssertEqual(manual.gusts.last?.startTime, 3)
        XCTAssertNotNil(manual.gusts.last?.audioCue)
        XCTAssertEqual(manual.gusts.last?.visualCue?.effect.rawValue, "autumn.wind")
        let record = AutumnBranchRecord(tuning: .standard, manualGusts: [3])
        XCTAssertEqual(record, try JSONDecoder().decode(AutumnBranchRecord.self, from: JSONEncoder().encode(record)))
    }

    @MainActor
    func testMusicRunnerLiveAudioOutput() async throws {
        let synth = PerformanceSynthesizer()
        let session = PerformanceSession(duration: .oneMinute,
            startedAt: Date().addingTimeInterval(-12), randomSeed: 650_208)
        synth.play(session: session, events: SplashMusicDirector.events(for: session))
        for _ in 0..<30 {
            if synth.outputLevel > 0.001 { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertGreaterThan(synth.outputLevel, 0.001, synth.status)
        print("Live synth output peak: \(synth.outputLevel)")
        synth.stop()
        XCTAssertEqual(synth.outputLevel, 0)
    }

    func testMusicRunnerPauseResumeAndPersistence() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        var session = PerformanceSession(duration: .fiveMinutes, startedAt: start, randomSeed: 42)
        session.pause(at: start.addingTimeInterval(40))
        session.pause(at: start.addingTimeInterval(60))
        XCTAssertEqual(session.elapsedTime(at: start.addingTimeInterval(100)), 40)
        XCTAssertEqual(session.remainingTime(at: start.addingTimeInterval(100)), 260)
        session = try JSONDecoder().decode(PerformanceSession.self, from: JSONEncoder().encode(session))
        XCTAssertTrue(session.isPaused)
        session.resume(at: start.addingTimeInterval(100))
        XCTAssertEqual(session.elapsedTime(at: start.addingTimeInterval(110)), 50)
        XCTAssertEqual(session.progress(at: start.addingTimeInterval(360)), 1)
        XCTAssertEqual(session.focusSession(for: .autumnTree).elapsedTime(at: start.addingTimeInterval(110)), 50)
    }

    func testMusicRunnerFiniteScoreContinuityAndDeterminism() {
        for duration in [FocusDuration.oneMinute, .fiveMinutes, .fiftyMinutes] {
            for seed: UInt64 in [42, 650_208, 91_337] {
                let session = PerformanceSession(duration: duration, randomSeed: seed)
                let events = SplashMusicDirector.events(for: session)
                XCTAssertEqual(events, SplashMusicDirector.events(for: session))
                XCTAssertEqual(Set(events.map(\.id)).count, events.count)
                XCTAssertTrue(events.contains { $0.role == .drone })
                XCTAssertTrue(events.contains { $0.role == .melody })
                let endBeat = duration.timeInterval / SplashPerformanceScore.tempo.secondsPerBeat
                for event in events {
                    XCTAssertFalse(event.isRepeating)
                    XCTAssertLessThanOrEqual(event.endBeat, endBeat + 0.000001)
                    XCTAssertGreaterThanOrEqual(event.gateBeats, event.envelope.attackBeats + event.envelope.decayBeats)
                    XCTAssertTrue((0...7).contains(event.tonalSlot))
                }
                for beat in stride(from: 5.0, to: endBeat - 7, by: 1) {
                    let active = events.filter { ($0.sample(at: beat)?.value ?? 0) > 0.015 }
                    XCTAssertGreaterThanOrEqual(Set(active.map(\.tonalSlot)).count, 3, "seed \(seed), beat \(beat)")
                    XCTAssertLessThanOrEqual(active.count, 12)
                    XCTAssertTrue(active.contains { $0.role == .drone }, "Drone gap at \(beat)")
                }
                XCTAssertEqual(SplashPerformanceScore.diagnostics(
                    durationMinutes: duration.timeInterval / 60, events: events).longestSilentBeats, 0)
                let all = SplashPerformanceScore.scheduledEvents(around: endBeat / 2,
                    radiusBeats: endBeat / 2, events: events)
                XCTAssertEqual(all.count, events.count, "Finite events must not repeat")
                XCTAssertTrue(SplashPerformanceScore.scheduledEvents(around: endBeat + 50,
                    radiusBeats: 10, events: events).isEmpty)
            }
        }
        let a = SplashMusicDirector.events(for: .init(duration: .fiveMinutes, randomSeed: 42))
        let b = SplashMusicDirector.events(for: .init(duration: .fiveMinutes, randomSeed: 43))
        XCTAssertNotEqual(a, b)
    }

    func testMusicRunnerAudioAndVisualShareEvents() {
        let session = PerformanceSession(duration: .fiveMinutes, randomSeed: 42)
        let events = SplashMusicDirector.events(for: session)
        let plan = SplashPerformancePlan(session: session, scoreEvents: events)
        for event in events {
            let scheduled = SplashScheduledPerformanceEvent(event: event, scheduledStartBeat: event.startBeat)
            let key = plan.soundSource(for: scheduled)
            let voice = PerformanceSynthVoice(event: event, source: key)
            XCTAssertEqual(key.octaveOffset, event.octaveOffset)
            XCTAssertEqual(voice.event, event)
            XCTAssertEqual(voice.sample(at: (event.startBeat - 0.001) * voice.secondsPerBeat), 0)
            XCTAssertEqual(voice.sample(at: (event.endBeat + 0.001) * voice.secondsPerBeat), 0)
            let middle = event.startBeat + event.totalBeats * 0.5
            XCTAssertEqual(SplashPerformanceScore.scheduledSample(for: event, scoreBeat: middle)?.envelope,
                           event.sample(at: middle))
            XCTAssertEqual(key, plan.soundSource(for: scheduled))
        }
    }

    func testMusicRunnerRendersAudition() throws {
        let session = PerformanceSession(duration: .oneMinute, randomSeed: 650_208)
        let events = SplashMusicDirector.events(for: session)
        let plan = SplashPerformancePlan(session: session, scoreEvents: events)
        let voices = events.map { PerformanceSynthVoice(event: $0,
            source: plan.soundSource(for: .init(event: $0, scheduledStartBeat: $0.startBeat))) }
        let rate = 22050.0
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("splash-synth-audition.wav")
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
        var peak = 0.0
        var energy = 0.0
        let frameCount = Int(session.duration.timeInterval * rate)
        for blockStart in stride(from: 0, to: frameCount, by: 1024) {
            let count = min(1024, frameCount - blockStart)
            buffer.frameLength = AVAudioFrameCount(count)
            let active = voices.filter {
                $0.event.endBeat * $0.secondsPerBeat > Double(blockStart) / rate
                    && $0.event.startBeat * $0.secondsPerBeat < Double(blockStart + count) / rate
            }
            let data = try XCTUnwrap(buffer.floatChannelData?[0])
            for frame in 0..<count {
                let time = Double(blockStart + frame) / rate
                let value = tanh(active.reduce(0.0) { $0 + $1.sample(at: time) }) * 0.65
                XCTAssertTrue(value.isFinite)
                data[frame] = Float(value)
                peak = max(peak, abs(value))
                energy += value * value
            }
            try file.write(from: buffer)
        }
        XCTAssertGreaterThan(peak, 0.02)
        XCTAssertLessThan(peak, 0.7)
        XCTAssertGreaterThan(sqrt(energy / Double(frameCount)), 0.005)
        print("Synth audition peak=\(peak), RMS=\(sqrt(energy / Double(frameCount))), events=\(events.count)")
        let attachment = XCTAttachment(contentsOfFile: url)
        attachment.name = "splash-synth-audition.wav"
        attachment.lifetime = .keepAlways
        add(attachment)
    }


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

    @MainActor
    func testHomeAmbientPlaybackUsesAContinuousFiveMinuteRiseAndSetCycle() {
        let start = Date(timeIntervalSince1970: 10_000)
        let ambient = SplashAmbientPlayback(startedAt: start)

        XCTAssertEqual(ambient.progress(at: start), 0, accuracy: 0.000_001)
        XCTAssertEqual(ambient.progress(at: start.addingTimeInterval(150)), 0.5, accuracy: 0.000_001)
        XCTAssertEqual(ambient.progress(at: start.addingTimeInterval(300)), 1, accuracy: 0.000_001)
        XCTAssertEqual(ambient.progress(at: start.addingTimeInterval(450)), 0.5, accuracy: 0.000_001)
        XCTAssertEqual(ambient.progress(at: start.addingTimeInterval(600)), 0, accuracy: 0.000_001)
        XCTAssertEqual(ambient.progress(at: start.addingTimeInterval(750)), 0.5, accuracy: 0.000_001)

        let beforeTurn = ambient.progress(at: start.addingTimeInterval(299.9))
        let afterTurn = ambient.progress(at: start.addingTimeInterval(300.1))
        XCTAssertEqual(beforeTurn, afterTurn, accuracy: 0.000_001)
        XCTAssertEqual(ambient.elapsed(at: start.addingTimeInterval(450)), 450)
    }

    @MainActor
    func testHomeAmbientPlaybackDoesNotStartForSilentProcessInitialization() {
        let ambient = SplashAmbientPlayback()
        let backgroundLaunch = Date(timeIntervalSince1970: 30_000)
        XCTAssertFalse(ambient.isActive)
        XCTAssertEqual(ambient.progress(at: backgroundLaunch), 0)
        ambient.beginIfNeeded(at: backgroundLaunch)
        XCTAssertEqual(ambient.elapsed(at: backgroundLaunch.addingTimeInterval(12)), 12)
    }

    @MainActor
    func testHomeAmbientPlaybackRetainsBrowseTimeAndOnlyResetsAfterMeditationBegins() {
        let start = Date(timeIntervalSince1970: 20_000)
        let ambient = SplashAmbientPlayback(startedAt: start)
        let browsingReturn = start.addingTimeInterval(173)

        // Settings, stats, stories, and setup do not own this process-wide clock.
        XCTAssertEqual(
            ambient.progress(at: browsingReturn),
            0.5 - 0.5 * cos(2 * .pi * 173 / 600),
            accuracy: 0.000_001
        )
        ambient.stop()
        XCTAssertFalse(ambient.isActive)
        XCTAssertEqual(ambient.progress(at: browsingReturn), 0, accuracy: 0.000_001)

        let homeAfterMeditation = browsingReturn.addingTimeInterval(20)
        ambient.restart(at: homeAfterMeditation)
        XCTAssertTrue(ambient.isActive)
        XCTAssertEqual(ambient.progress(at: homeAfterMeditation), 0, accuracy: 0.000_001)
    }

    @MainActor
    func testHomeAmbientPlaybackOnlyStopsAfterSuccessfulFocusStart() async {
        enum StartError: Error { case persistenceFailed }
        let ambient = SplashAmbientPlayback(startedAt: .distantPast)

        do {
            _ = try await ambient.stopAfterSuccessfulFocusStart { () async throws -> Int in
                throw StartError.persistenceFailed
            }
            XCTFail("A failed persistence start should reach the setup error UI")
        } catch {
            XCTAssertTrue(ambient.isActive)
        }

        let result = try? await ambient.stopAfterSuccessfulFocusStart { 42 }
        XCTAssertEqual(result, 42)
        XCTAssertFalse(ambient.isActive)
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

    @MainActor
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
        // Ambient cloud drift receives wall-clock elapsed, never the returning
        // sunrise progress, so a sunset does not run the cloud layer backward.
        let ambient = SplashAmbientPlayback(startedAt: startedAt)
        XCTAssertGreaterThan(
            ambient.elapsed(at: startedAt.addingTimeInterval(450)),
            ambient.elapsed(at: startedAt.addingTimeInterval(300))
        )
        XCTAssertEqual(
            ambient.progress(at: startedAt.addingTimeInterval(450)),
            ambient.progress(at: startedAt.addingTimeInterval(150)),
            accuracy: 0.000_001
        )
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
        XCTAssertEqual(SplashMotionTiming.cloudEntryDelay, 4.66, accuracy: 0.000_001)
        XCTAssertEqual(SplashMotionTiming.cloudEntryDuration, 0.60, accuracy: 0.000_001)
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
        XCTAssertEqual(initial.cloudOpacity, 0)
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
        XCTAssertEqual(settled.cloudOpacity, 0)

        let cloudMidpoint = SplashScenePresentation.sample(
            performanceElapsed: SplashMotionTiming.cloudEntryDelay
                + SplashMotionTiming.cloudEntryDuration / 2,
            exitElapsed: nil,
            reduceMotion: false
        )
        XCTAssertEqual(cloudMidpoint.cloudOpacity, 0.5, accuracy: 0.000_001)

        let cloudSettled = SplashScenePresentation.sample(
            performanceElapsed: SplashMotionTiming.cloudEntryDelay
                + SplashMotionTiming.cloudEntryDuration,
            exitElapsed: nil,
            reduceMotion: false
        )
        XCTAssertEqual(cloudSettled.cloudOpacity, 1, accuracy: 0.000_001)

        let interruptedBeforeCloud = SplashScenePresentation.sample(
            performanceElapsed: SplashMotionTiming.cloudEntryDelay - 0.01,
            exitElapsed: 0,
            reduceMotion: false
        )
        XCTAssertEqual(interruptedBeforeCloud.cloudOpacity, 0)

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
        XCTAssertEqual(reduced.cloudOpacity, 1)
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

        let onset = AutumnDeerEncounter.scheduled(duration:session.duration.timeInterval).startTime
        let beforeReveal = player.performance(
            at: start.addingTimeInterval(onset-0.01),
            reduceMotion: false
        )
        let duringReveal = player.performance(
            at: start.addingTimeInterval(onset+0.01),
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

    @MainActor
    func testAutumnArtworkContainsOnlyCurrentMasks() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: Bundle.main.bundleURL.appendingPathComponent("CastV1").path))
        let expected = Set(AutumnArtwork.assetIDs.map { $0 + ".png" })
        let folder = try XCTUnwrap(AutumnArtwork.assetURL(named: "leaf-maple-red")?.deletingLastPathComponent())
        let bundled = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertEqual(Set(bundled), expected, "Retired plates/layouts must not ship in the app.")
        for name in AutumnArtwork.assetIDs {
            let image = try XCTUnwrap(AutumnArtworkCache.shared.image(named: name))
            let pixels = try rgbaPixels(image)
            let alpha = stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
            XCTAssertTrue(alpha.contains(0), "\(name) must retain genuine transparent cutout space")
            XCTAssertTrue(alpha.contains { $0 > 200 }, "\(name) must retain opaque paper")
        }
        XCTAssertNil(Bundle.main.url(forResource: "terrain-adjustments", withExtension: "json", subdirectory: "SceneV2"))
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
