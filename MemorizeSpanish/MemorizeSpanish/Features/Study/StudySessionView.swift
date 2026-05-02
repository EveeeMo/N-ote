import SwiftData
import SwiftUI

struct StudySessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let items: [ReviewItem]

    @StateObject private var speech = SpanishSpeechService()
    @State private var index = 0
    @State private var showBack = false
    @State private var showConjugation = false

    @State private var sessionComplete = false
    @State private var rememberedCount = 0
    @State private var vagueCount = 0
    @State private var forgotCount = 0
    @State private var weakWords: [StudySessionSummary.WeakWord] = []

    private var currentItem: ReviewItem? {
        guard index >= 0, index < items.count else { return nil }
        return items[index]
    }

    private var currentWord: WordEntry? {
        currentItem?.word
    }

    var body: some View {
        NavigationStack {
            Group {
                if sessionComplete {
                    StudySessionSummaryView(
                        remembered: rememberedCount,
                        vague: vagueCount,
                        forgot: forgotCount,
                        weakWords: weakWords,
                        onDone: { dismiss() }
                    )
                } else if let word = currentWord {
                    VStack(spacing: 20) {
                        ProgressView(value: Double(index + 1), total: Double(max(items.count, 1)))
                            .padding(.horizontal)

                        Spacer(minLength: 8)

                        ZStack {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color(.secondarySystemGroupedBackground))
                                .shadow(color: .black.opacity(0.08), radius: 12, y: 6)

                            VStack(spacing: 16) {
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(word.spanish)
                                        .font(.largeTitle.weight(.semibold))
                                        .multilineTextAlignment(.center)
                                    Button {
                                        speech.speakSpanish(word.spanish)
                                    } label: {
                                        Image(systemName: "speaker.wave.2.circle.fill")
                                            .font(.title)
                                            .symbolRenderingMode(.hierarchical)
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("朗读西语")
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal)

                                Text(word.partOfSpeech)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))

                                if showBack {
                                    Divider().padding(.horizontal)
                                    Text(word.chinese)
                                        .font(.title3)
                                        .multilineTextAlignment(.center)
                                    if !word.userNote.isEmpty {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("备注")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text(word.userNote)
                                                .font(.body)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .padding()
                                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.tertiarySystemFill)))
                                    }
                                    if word.isVerb {
                                        Button("动词变位") { showConjugation = true }
                                            .buttonStyle(.bordered)
                                    }
                                } else {
                                    Color.clear
                                        .frame(height: 1)
                                }
                            }
                            .padding(24)
                        }
                        .padding(.horizontal)

                        Spacer(minLength: 8)

                        if !showBack {
                            Button("翻面") { withAnimation { showBack = true } }
                                .buttonStyle(.borderedProminent)
                        } else {
                            HStack(spacing: 12) {
                                gradeButton(title: "忘了", color: .red, grade: .forgot)
                                gradeButton(title: "模糊", color: .orange, grade: .vague)
                                gradeButton(title: "记得", color: .green, grade: .remembered)
                            }
                            .padding(.horizontal)
                        }
                    }
                    .sheet(isPresented: $showConjugation) {
                        VerbConjugationSheet(infinitive: word.infinitiveForConjugation)
                    }
                } else {
                    ContentUnavailableView("完成", systemImage: "checkmark.circle.fill")
                    Button("关闭") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle(sessionComplete ? "本轮回顾" : "背诵")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(sessionComplete ? "关闭" : "结束") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if !sessionComplete, let w = currentWord {
                        Button {
                            speech.speakSpanish(w.spanish)
                        } label: {
                            Label("发音", systemImage: "speaker.wave.2")
                        }
                        .accessibilityLabel("朗读西语")
                    }
                }
            }
            .onDisappear {
                speech.stop()
            }
        }
    }

    private func gradeButton(title: String, color: Color, grade: ReviewGrade) -> some View {
        Button(title) {
            guard let item = currentItem, let word = item.word else { return }
            recordGrade(grade, word: word)
            SRSScheduler.apply(grade: grade, item: item)
            try? modelContext.save()
            advance()
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
        .frame(maxWidth: .infinity)
    }

    private func recordGrade(_ grade: ReviewGrade, word: WordEntry) {
        switch grade {
        case .remembered:
            rememberedCount += 1
        case .vague:
            vagueCount += 1
            weakWords.append(
                StudySessionSummary.WeakWord(spanish: word.spanish, chinese: word.chinese, grade: grade)
            )
        case .forgot:
            forgotCount += 1
            weakWords.append(
                StudySessionSummary.WeakWord(spanish: word.spanish, chinese: word.chinese, grade: grade)
            )
        }
    }

    private func advance() {
        speech.stop()
        showBack = false
        showConjugation = false
        if index + 1 >= items.count {
            sessionComplete = true
        } else {
            index += 1
        }
    }
}

// MARK: - 本轮结束统计

private enum StudySessionSummary {}

extension StudySessionSummary {
    struct WeakWord: Identifiable {
        let id = UUID()
        let spanish: String
        let chinese: String
        let grade: ReviewGrade
    }
}

private struct StudySessionSummaryView: View {
    let remembered: Int
    let vague: Int
    let forgot: Int
    let weakWords: [StudySessionSummary.WeakWord]
    let onDone: () -> Void

    private var forgotList: [StudySessionSummary.WeakWord] {
        weakWords.filter { $0.grade == .forgot }
    }

    private var vagueList: [StudySessionSummary.WeakWord] {
        weakWords.filter { $0.grade == .vague }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 0) {
                    statCell(value: remembered, label: "记得", color: .green)
                    statCell(value: vague, label: "模糊", color: .orange)
                    statCell(value: forgot, label: "忘了", color: .red)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            if !forgotList.isEmpty {
                Section {
                    ForEach(forgotList) { w in
                        weakWordRow(w)
                    }
                } header: {
                    Label("忘了", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }

            if !vagueList.isEmpty {
                Section {
                    ForEach(vagueList) { w in
                        weakWordRow(w)
                    }
                } header: {
                    Label("模糊", systemImage: "questionmark.circle.fill")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Button {
                    onDone()
                } label: {
                    Text("完成")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .listRowBackground(Color.clear)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statCell(value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Text("\(value)")
                .font(.title.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func weakWordRow(_ w: StudySessionSummary.WeakWord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(w.spanish)
                .font(.headline)
            Text(w.chinese)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
