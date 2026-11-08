import Foundation
import HealthKit
@preconcurrency import WorkoutKit

// The SDK's authorization state is a value-only Int-backed enum, but its
// declaration doesn't currently advertise Sendable. It crosses into this
// main-actor service only as a value.
extension WorkoutScheduler.AuthorizationState: @retroactive @unchecked Sendable {}

/// Converts scheduled runs in the iPhone plan into workouts shown in the
/// system Workout app on Apple Watch. The source plan remains the app's
/// existing planned-runs data; no workout or route data is uploaded here.
@MainActor
struct RunWorkoutSyncService {
    private let scheduler = WorkoutScheduler.shared

    enum SyncError: LocalizedError {
        case watchUnavailable
        case permissionDenied

        var errorDescription: String? {
            switch self {
            case .watchUnavailable:
                "Apple Watch workout scheduling isn't available on this device. Make sure your Watch is paired and try again."
            case .permissionDenied:
                "Allow Fitness Tracker to add scheduled workouts, then try again."
            }
        }
    }

    /// Puts just `next` on the Watch's schedule and takes the plan's other scheduled runs off it,
    /// so the Watch only ever holds the one run that's coming up. Returns whether it was scheduled.
    func syncNextRun(_ next: PlannedRun?, planRuns: [PlannedRun]) async throws -> Bool {
        guard WorkoutScheduler.isSupported else { throw SyncError.watchUnavailable }

        if await scheduler.authorizationState != .authorized {
            guard await scheduler.requestAuthorization() == .authorized else {
                throw SyncError.permissionDenied
            }
        }

        // Clear only workouts whose IDs belong to runs in this plan. Other
        // apps' workouts, and the user's manually-created workouts, are kept.
        let planRunIDs = Set(planRuns.map(\.id))
        for item in await scheduler.scheduledWorkouts where planRunIDs.contains(item.plan.id) {
            await scheduler.remove(item.plan, at: item.date)
        }

        guard let next else { return false }
        let date = Calendar.current.dateComponents([.year, .month, .day], from: next.day)
        await scheduler.schedule(makeWorkoutPlan(for: next), at: date)
        return (await scheduler.scheduledWorkouts).contains { $0.plan.id == next.id }
    }

    /// A pace alert of plus or minus 5% around a pace, when the Watch can use one.
    private func paceAlert(secPerKm: Double?) -> (any WorkoutAlert)? {
        guard let pace = secPerKm, pace > 0 else { return nil }
        let centerSpeed = 1000 / pace
        let alert = SpeedRangeAlert(
            target: Measurement(value: centerSpeed * 0.95, unit: UnitSpeed.metersPerSecond)
                ... Measurement(value: centerSpeed * 1.05, unit: UnitSpeed.metersPerSecond),
            metric: .average
        )
        return CustomWorkout.supportsAlert(alert, activity: .running, location: .outdoor) ? alert : nil
    }

    private func goal(for step: RunStep) -> WorkoutGoal {
        if let distance = step.distanceM, distance > 0 { return .distance(distance, .meters) }
        if let seconds = step.seconds, seconds > 0 { return .time(Double(seconds), .seconds) }
        return .open
    }

    private func workoutStep(_ step: RunStep, name: String) -> WorkoutStep {
        WorkoutStep(
            goal: goal(for: step),
            alert: paceAlert(secPerKm: step.paceSecPerKm.map(Double.init)),
            displayName: step.paceSecPerKm.map { "\(name) \u{00b7} \(PaceText.format($0))" } ?? name
        )
    }

    private func makeWorkoutPlan(for run: PlannedRun) -> WorkoutPlan {
        // The pace to hold for the main part: one that was entered, else the
        // one implied by distance and time.
        let derivedPace: Double? = {
            guard let distanceKm = run.targetDistanceKm, distanceKm > 0,
                  let durationMinutes = run.targetDurationMin, durationMinutes > 0
            else { return nil }
            return Double(durationMinutes * 60) / distanceKm
        }()
        let mainPace = run.mainPaceSec.map(Double.init) ?? derivedPace

        var stepTitleParts = [run.runType.displayName]
        if let mainPace, let label = RunFormat.pace(seconds: mainPace, meters: 1000) { stepTitleParts.append(label) }
        if let notes = run.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            stepTitleParts.append(notes)
        }

        let blocks: [IntervalBlock]
        if let custom = run.blocks, !custom.isEmpty {
            blocks = custom.map { block in
                var steps = [IntervalStep(.work, step: workoutStep(block.work, name: "Work"))]
                if let recovery = block.recovery {
                    steps.append(IntervalStep(.recovery, step: workoutStep(recovery, name: "Recover")))
                }
                return IntervalBlock(steps: steps, iterations: max(block.reps, 1))
            }
        } else {
            let workGoal: WorkoutGoal
            // The total includes the warm-up and cool-down, so the main step is what's left of it.
            if let distanceKm = run.mainDistanceKm, distanceKm > 0 {
                workGoal = .distance(distanceKm * 1000, .meters)
            } else if let durationMinutes = run.targetDurationMin, durationMinutes > 0 {
                workGoal = .time(Double(durationMinutes * 60), .seconds)
            } else {
                workGoal = .open
            }
            blocks = [
                IntervalBlock(steps: [
                    IntervalStep(.work, step: WorkoutStep(
                        goal: workGoal,
                        alert: paceAlert(secPerKm: mainPace),
                        displayName: stepTitleParts.joined(separator: " \u{00b7} ")
                    ))
                ])
            ]
        }

        // Distance only, and only what was set: no km means no warm-up or cool-down. (A run
        // saved before this by time keeps its minutes.)
        let warmup = easyStep(name: "Warm Up", km: run.warmupKm, minutes: run.warmupMin ?? 0, paceSec: run.warmupPaceSec)
        let cooldown = easyStep(name: "Cool Down", km: run.cooldownKm, minutes: run.cooldownMin ?? 0, paceSec: run.cooldownPaceSec)

        let workout = CustomWorkout(
            activity: .running,
            location: .outdoor,
            displayName: "\(run.runType.displayName) Run",
            warmup: warmup,
            blocks: blocks,
            cooldown: cooldown
        )

        return WorkoutPlan(.custom(workout), id: run.id)
    }

    /// A warm-up or cool-down: by distance when a distance is set (0 means none),
    /// otherwise by minutes (0 means none).
    private func easyStep(name: String, km: Double?, minutes: Int, paceSec: Int?) -> WorkoutStep? {
        let paceText = paceSec.map { " \u{00b7} \(PaceText.format($0))" } ?? ""
        if let km {
            guard km > 0 else { return nil }
            return WorkoutStep(
                goal: .distance(km * 1000, .meters),
                alert: paceAlert(secPerKm: paceSec.map(Double.init)),
                displayName: "\(name) \u{00b7} \(RunFormat.km(km))" + paceText
            )
        }
        guard minutes > 0 else { return nil }
        return WorkoutStep(
            goal: .time(Double(minutes * 60), .seconds),
            alert: paceAlert(secPerKm: paceSec.map(Double.init)),
            displayName: "\(name) \u{00b7} \(minutes) min" + paceText
        )
    }
}
