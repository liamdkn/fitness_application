import PhotosUI
import SwiftUI

extension RewardProgress {
    /// "★ 22 / 30 · 8 on-plan days to go".
    var summary: String {
        switch reward.goalKind {
        case .stars: "\u{2605} \(value) / \(target) \u{00b7} \(remainingText)"
        case .streak: "\u{1F525} \(value) / \(target) days \u{00b7} \(remainingText)"
        case .perfectWeeks: "\(value) / \(target) perfect weeks \u{00b7} \(remainingText)"
        case .phaseComplete: "\(value)% / \(target)% on plan \u{00b7} \(remainingText)"
        }
    }
}

/// A reward's photo, from a signed URL, or a gift icon without one.
struct RewardPhotoView: View {
    let path: String?
    var size: CGFloat = 44
    var cornerRadius: CGFloat = 10

    @State private var url: URL?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius).fill(Color.secondary.opacity(0.15))
            if let url {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ProgressView()
                }
            } else {
                Image(systemName: "gift.fill").foregroundStyle(AppColor.star)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: path) {
            guard let path else { url = nil; return }
            url = try? await RewardRepository().signedURL(path: path)
        }
    }
}

/// Photo, title and a progress bar.
struct RewardProgressRow: View {
    let progress: RewardProgress

    var body: some View {
        HStack(spacing: 12) {
            RewardPhotoView(path: progress.reward.photoPath)
            VStack(alignment: .leading, spacing: 4) {
                Text(progress.reward.title).font(.subheadline.weight(.semibold))
                ProgressView(value: progress.fraction)
                    .tint(AppColor.star)
                Text(progress.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Settings -> Rewards

struct RewardsView: View {
    @StateObject private var viewModel = CoachViewModel()
    @State private var showingEditor = false
    @State private var rewardToDelete: Reward?
    @AppStorage(StreakNudgeService.enabledKey) private var nudgeEnabled = true
    @Environment(\.openURL) private var openURL

    private var phaseRewardIds: Set<UUID> { Set(viewModel.rewardProgress.map(\.reward.id)) }
    private var earned: [RewardProgress] { viewModel.rewardProgress.filter { $0.isAchieved && !$0.reward.isClaimed } }
    private var shelf: [Reward] { viewModel.rewards.filter(\.isClaimed) }
    private var earlierPhases: [Reward] { viewModel.rewards.filter { !$0.isClaimed && !phaseRewardIds.contains($0.id) } }

    var body: some View {
        List {
            Section {
                Toggle("Streak reminder at 21:30", isOn: $nudgeEnabled)
            } footer: {
                Text("A nudge when you have a streak and today isn't on plan yet.")
            }
            .listRowBackground(AppRowBackground())

            if !earned.isEmpty {
                Section("Earned") {
                    ForEach(earned) { progress in
                        HStack {
                            RewardProgressRow(progress: progress)
                            Button("Claim") { claim(progress.reward) }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .listRowBackground(AppRowBackground())
            }

            Section("Working towards") {
                if viewModel.activeRewards.isEmpty {
                    Text("Nothing yet. Set a prize for yourself and earn it with the days you control.")
                        .foregroundStyle(.secondary)
                }
                ForEach(viewModel.activeRewards) { progress in
                    RewardProgressRow(progress: progress)
                        .swipeActions { Button("Delete", role: .destructive) { rewardToDelete = progress.reward } }
                }
                Button { showingEditor = true } label: { Label("Add a reward", systemImage: "plus") }
            }
            .listRowBackground(AppRowBackground())

            if !shelf.isEmpty {
                Section("Trophy shelf") {
                    ForEach(shelf) { reward in trophyRow(reward) }
                }
                .listRowBackground(AppRowBackground())
            }

            if !earlierPhases.isEmpty {
                Section("From earlier phases") {
                    ForEach(earlierPhases) { reward in
                        HStack {
                            RewardPhotoView(path: reward.photoPath)
                            VStack(alignment: .leading) {
                                Text(reward.title)
                                Text(reward.goalKind.targetText(Int(reward.goalValue))).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions { Button("Delete", role: .destructive) { rewardToDelete = reward } }
                    }
                }
                .listRowBackground(AppRowBackground())
            }
        }
        .appScreen()
        .navigationTitle("Rewards")
        .task { await viewModel.load() }
        .sheet(isPresented: $showingEditor) {
            RewardEditorView(phaseStartedAt: viewModel.phaseStartedAt, phaseEnd: viewModel.phaseEndDate) {
                await viewModel.load()
            }
        }
        .confirmationDialog("Delete this reward?", isPresented: Binding(get: { rewardToDelete != nil }, set: { if !$0 { rewardToDelete = nil } })) {
            Button("Delete Reward", role: .destructive) {
                if let reward = rewardToDelete {
                    Task {
                        try? await RewardRepository().delete(reward)
                        await viewModel.load()
                    }
                }
            }
        }
    }

    private func trophyRow(_ reward: Reward) -> some View {
        HStack(spacing: 12) {
            RewardPhotoView(path: reward.photoPath)
            VStack(alignment: .leading, spacing: 2) {
                Text(reward.title).font(.subheadline.weight(.semibold))
                Text(([
                    reward.achievedAt.map { "Earned " + $0.formatted(date: .abbreviated, time: .omitted) },
                    reward.price.map { $0.formatted(.currency(code: Locale.current.currency?.identifier ?? "EUR")) }
                ] as [String?]).compactMap { $0 }.joined(separator: " \u{00b7} "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "trophy.fill").foregroundStyle(AppColor.star)
        }
    }

    private func claim(_ reward: Reward) {
        Task {
            await viewModel.claim(reward)
            if let link = reward.link, let url = RewardLink.url(from: link) { openURL(url) }
        }
    }
}

enum RewardLink {
    /// A link typed without a scheme still opens.
    static func url(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed.contains("://") ? trimmed : "https://" + trimmed)
    }
}

// MARK: - Setting one up

struct RewardEditorView: View {
    let phaseStartedAt: String?
    let phaseEnd: Date?
    var onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var kind: RewardGoalKind = .stars
    @State private var value = 30
    @State private var hasDeadline = true
    @State private var deadline = Date()
    @State private var priceText = ""
    @State private var link = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var isSaving = false
    @State private var errorMessage: String?

    private static let defaults: [RewardGoalKind: Int] = [.stars: 30, .streak: 14, .perfectWeeks: 3, .phaseComplete: 85]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What is it?", text: $title, prompt: Text("[YOUR PRIZE]"))
                    photoRow
                    TextField("Price (optional)", text: $priceText).keyboardType(.decimalPad)
                    TextField("Link (optional)", text: $link)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("The prize")
                }

                Section {
                    Picker("Earn it by", selection: $kind) {
                        ForEach(RewardGoalKind.allCases) { Text($0.displayName).tag($0) }
                    }
                    .onChange(of: kind) { _, new in value = Self.defaults[new] ?? 10 }
                    Stepper(value: $value, in: range, step: kind == .phaseComplete ? 5 : 1) {
                        Text(kind.targetText(value))
                    }
                    Toggle("Deadline", isOn: $hasDeadline)
                    if hasDeadline { DatePicker("By", selection: $deadline, displayedComponents: .date) }
                } header: {
                    Text("The goal")
                } footer: {
                    Text("Goals are about the days you control, never the scale: it can swing 2-3 kg from water after one big day.")
                }

                Section("Ideas") {
                    preset("7-day streak: a small treat for yourself", .streak, 7)
                    preset("3 perfect weeks: a bigger buy", .perfectWeeks, 3)
                    preset("Finish the phase at 85% on plan: the big one", .phaseComplete, 85)
                }

                if let errorMessage { Text(errorMessage).foregroundStyle(AppColor.error) }
            }
            .navigationTitle("New reward")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear { if let phaseEnd { deadline = phaseEnd } }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) { photoData = ImageCompression.compress(data) }
                }
            }
        }
    }

    private var range: ClosedRange<Int> {
        switch kind {
        case .stars: 1...200
        case .streak: 2...120
        case .perfectWeeks: 1...12
        case .phaseComplete: 50...100
        }
    }

    private var photoRow: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            HStack {
                if let photoData, let image = UIImage(data: photoData) {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "photo")
                }
                Text(photoData == nil ? "Add a photo (optional)" : "Change photo")
            }
        }
    }

    private func preset(_ text: String, _ kind: RewardGoalKind, _ value: Int) -> some View {
        Button(text) {
            self.kind = kind
            self.value = value
        }
        .foregroundStyle(.primary)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await RewardRepository().create(
                title: title.trimmingCharacters(in: .whitespaces),
                photo: photoData,
                price: Double(priceText.replacingOccurrences(of: ",", with: ".")),
                link: link.trimmingCharacters(in: .whitespaces).isEmpty ? nil : link.trimmingCharacters(in: .whitespaces),
                goalKind: kind, goalValue: Double(value), phaseStartedAt: phaseStartedAt,
                deadline: hasDeadline ? deadline : nil
            )
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
