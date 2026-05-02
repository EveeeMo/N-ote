import SwiftData
import SwiftUI

/// 新词组浏览；「完成本组」后入库并排复习。
struct NewWordsGroupSessionView: View {
    let unit: BundledUnitDTO
    let planId: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @StateObject private var speech = SpanishSpeechService()
    @State private var commitError: String?

    var body: some View {
        NavigationStack {
            List {
                Section(unit.title) {
                    ForEach(Array(unit.words.enumerated()), id: \.offset) { _, w in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(w.es)
                                    .font(.headline)
                                Text(w.zh)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(w.pos)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer(minLength: 0)
                            Button {
                                speech.speakSpanish(w.es)
                            } label: {
                                Image(systemName: "speaker.wave.2.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("朗读")
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("新词本组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    commit()
                } label: {
                    Text("完成本组（加入词库）")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .padding()
                .background(.bar)
            }
            .alert("无法保存", isPresented: Binding(
                get: { commitError != nil },
                set: { if !$0 { commitError = nil } }
            )) {
                Button("好", role: .cancel) { commitError = nil }
            } message: {
                Text(commitError ?? "")
            }
            .onDisappear {
                speech.stop()
            }
        }
    }

    private func commit() {
        do {
            try LearningPlanService.commitCompletedGroup(unit: unit, planId: planId, context: modelContext)
            dismiss()
        } catch {
            commitError = error.localizedDescription
        }
    }
}
