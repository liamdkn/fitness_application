import Combine
import Foundation

/// Loads what the Phase Report needs from the existing repositories and hands it to the
/// pure `PhaseReportCalculator`. All the maths is there; this only gathers data.
@MainActor
final class PhaseReportViewModel: ObservableObject {
    @Published var report: PhaseReport?
    @Published var isLoading = true
    @Published var message: String?

    func load() async {
        defer { isLoading = false }
        do {
            guard let current = try await GoalsRepository().fetchCurrentGoal() else {
                message = "No active phase. Start one in Settings, then My Goals."
                return
            }
            // Rows of the same phase (a mid-phase target change adds a row with the same start).
            let phaseGoals = try await GoalsRepository().fetchPastGoals(limit: 60).filter { $0.phaseStartedAt == current.phaseStartedAt }
            guard let start = DateFormatting.date(fromISODate: current.phaseStartedAt) else { return }
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
            let end = calendar.date(byAdding: .day, value: current.durationWeeks * 7, to: start) ?? start
            let firstMonday = DateFormatting.mondayOfWeek(containing: start)
            let dayBefore = calendar.date(byAdding: .day, value: -1, to: start) ?? start

            var input = PhaseReportInput(goals: phaseGoals.isEmpty ? [current] : phaseGoals)

            input.weights = try await BodyWeightRepository().fetchHistory(limit: 600)

            let nutrition = try await NutritionRepository().fetchDailyTotals(from: start, to: today)
            input.dailyCalories = Dictionary(nutrition.map { ($0.date, $0.calories) }, uniquingKeysWith: { _, latest in latest })

            input.checkins = (try? await DailyCheckinRepository().fetchRange(from: dayBefore, to: today)) ?? []
            input.dayFlags = (try? await DayFlagRepository().fetchRange(from: start, to: today)) ?? []
            input.plannedTreats = (try? await PlannedTreatRepository().fetchTreats(from: today, to: end)) ?? []

            let workouts = try await WorkoutRepository().fetchWorkouts(from: start, to: tomorrow).filter { $0.endedAt != nil }
            input.workouts = workouts.map { .init(id: $0.id, date: calendar.startOfDay(for: $0.performedAt)) }
            let sets = (try? await WorkoutRepository().fetchSets(workoutIds: workouts.map(\.id))) ?? []
            input.sets = sets.map { .init(workoutId: $0.workoutId, exerciseId: $0.exerciseId, reps: $0.reps, weightKg: $0.weightKg, isWarmup: $0.isWarmup) }
            let exercises = (try? await ExerciseRepository().fetchAll()) ?? []
            input.exerciseNames = Dictionary(exercises.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })

            let steps = (try? await HealthRepository().fetchStepLogs(from: firstMonday, to: today)) ?? []
            input.steps = Dictionary(steps.map { ($0.date, $0.stepCount) }, uniquingKeysWith: { _, latest in latest })
            input.cardio = (try? await CardioSessionRepository().fetchHistory(from: firstMonday, to: tomorrow)) ?? []

            let runningPlans = RunningPlanRepository()
            if let plan = try? await runningPlans.fetchActivePlan() {
                input.plannedRuns = (try? await runningPlans.fetchPlannedRuns(planId: plan.id)) ?? []
            }

            report = PhaseReportCalculator(input).report()
            message = report == nil ? "Couldn't build the report." : nil
        } catch {
            message = error.localizedDescription
        }
    }
}
