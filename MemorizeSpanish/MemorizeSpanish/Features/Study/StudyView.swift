import SwiftData
import SwiftUI

struct StudyView: View {
    @Query(sort: \ReviewItem.nextReview) private var allReviewItems: [ReviewItem]

    @State private var showSession = false
    @State private var sessionItems: [ReviewItem] = []
    @State private var selectedTimelineDay: Int? = nil

    private let timelineHorizonDays = 7

    private var endOfToday: Date { AppTime.endOfToday() }

    private var dueReviewItems: [ReviewItem] {
        allReviewItems.filter { $0.nextReview < endOfToday && $0.word != nil }
    }

    private var dueCount: Int { dueReviewItems.count }

    private var timelineCounts: [Int] {
        (0 ..< timelineHorizonDays).map { offset in
            reviewItems(forDayOffset: offset, items: allReviewItems).count
        }
    }

    /// 与「只按自然日排期」一致：柱标签用日期语义，不涉及时刻。
    private var timelineDayLabels: [String] {
        (0 ..< timelineHorizonDays).map { calendarDayLabel(offset: $0) }
    }

    private var selectedDayReviewItems: [ReviewItem] {
        guard let day = selectedTimelineDay else { return [] }
        return reviewItems(forDayOffset: day, items: allReviewItems)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 16) {
                        VStack(spacing: 8) {
                            Text("今日待复习")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text("\(dueCount)")
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                            Text("按自然日，不含具体钟点")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Button {
                            startSession()
                        } label: {
                            Label("开始背诵", systemImage: "play.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(dueCount == 0)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
                } header: {
                    Text("复习")
                }

                Section {
                    NavigationLink {
                        DELELearningPlanView()
                    } label: {
                        Label("DELE 每日新词计划", systemImage: "text.book.closed.fill")
                    }
                } header: {
                    Text("学习计划")
                }

                Section {
                    ReviewPlanTimelineBars(counts: timelineCounts, dayLabels: timelineDayLabels, selectedDay: $selectedTimelineDay)
                    if selectedTimelineDay != nil, !selectedDayReviewItems.isEmpty {
                        ForEach(selectedDayReviewItems) { item in
                            if let word = item.word {
                                NavigationLink {
                                    EditWordView(word: word)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(word.spanish)
                                            .font(.body.weight(.medium))
                                        Text(word.chinese)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("复习计划")
                        if let idx = selectedTimelineDay {
                            Text("当前：\(calendarDayLabel(offset: idx)) · \(timelineCounts[safe: idx] ?? 0) 条")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("每根柱子为对应自然日应复习的词条数")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("学习")
            .onChange(of: showSession) { _, isShown in
                if !isShown {
                    sessionItems = []
                }
            }
            .fullScreenCover(isPresented: $showSession) {
                StudySessionView(items: sessionItems)
            }
        }
    }

    private func startSession() {
        sessionItems = dueReviewItems
        if !sessionItems.isEmpty {
            showSession = true
        }
    }

    private func calendarDayLabel(offset: Int) -> String {
        switch offset {
        case 0: return "今天"
        case 1: return "明天"
        case 2: return "后天"
        default:
            let cal = Calendar.current
            guard let d = cal.date(byAdding: .day, value: offset, to: AppTime.startOfLogicalToday) else { return "+\(offset)" }
            let f = DateFormatter()
            f.locale = Locale(identifier: "zh_Hans_CN")
            f.setLocalizedDateFormatFromTemplate("MMMd")
            return f.string(from: d)
        }
    }

    /// 第 0 天与「开始背诵」一致（含逾期）；之后按逻辑日切分。
    private func reviewItems(forDayOffset offset: Int, items: [ReviewItem]) -> [ReviewItem] {
        let withWord = items.filter { $0.word != nil }
        if offset == 0 {
            let end = AppTime.endOfToday()
            return withWord.filter { $0.nextReview < end }
                .sorted { $0.nextReview < $1.nextReview }
        }
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: offset, to: AppTime.startOfLogicalToday)!
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        return withWord.filter { $0.nextReview >= start && $0.nextReview < end }
            .sorted { $0.nextReview < $1.nextReview }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        (0 ..< count).contains(index) ? self[index] : nil
    }
}

// MARK: - 复习计划时间轴

private struct ReviewPlanTimelineBars: View {
    let counts: [Int]
    let dayLabels: [String]
    @Binding var selectedDay: Int?

    var body: some View {
        let maxC = max(counts.max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(0 ..< counts.count, id: \.self) { i in
                Button {
                    if selectedDay == i {
                        selectedDay = nil
                    } else {
                        selectedDay = i
                    }
                } label: {
                    VStack(spacing: 6) {
                        Text("\(counts[i])")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(counts[i] == 0 ? .tertiary : .primary)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(barColor(index: i))
                            .frame(height: CGFloat(counts[i]) / CGFloat(maxC) * 88 + 4)
                        Text(resolvedLabel(at: i))
                            .font(.caption2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(resolvedLabel(at: i))，\(counts[i]) 条待复习")
            }
        }
        .frame(height: 130)
        .padding(.vertical, 8)
    }

    private func resolvedLabel(at i: Int) -> String {
        guard i < dayLabels.count else { return "+\(i)" }
        return dayLabels[i]
    }

    private func barColor(index i: Int) -> Color {
        if counts[i] == 0 { return Color.secondary.opacity(0.15) }
        if selectedDay == i { return Color.accentColor }
        return Color.accentColor.opacity(0.75)
    }
}
