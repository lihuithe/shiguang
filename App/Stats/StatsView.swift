import Charts
import ShiGuangCore
import SwiftUI

/// 統計頁：只展示「已經做了多少」，不展示「還剩多少」。
struct StatsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var range = 14

    private var stats: UsageStats { model.stats }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    hero
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        StatTile(title: "已浏览", value: "\(stats.totalViewed)", unit: "张", icon: "eye.fill", tint: .blue)
                        StatTile(title: "已删除", value: "\(stats.totalDeleted)", unit: "张", icon: "trash.fill", tint: .red)
                        StatTile(title: "释放空间", value: ByteSize.format(stats.bytesFreed), unit: "", icon: "internaldrive.fill", tint: .green)
                        StatTile(title: "收藏", value: "\(stats.totalFavorited)", unit: "张", icon: "heart.fill", tint: .pink)
                        StatTile(title: "完成组数", value: "\(stats.groupsCompleted)", unit: "组", icon: "square.stack.fill", tint: .orange)
                        StatTile(title: "连续回顾", value: "\(stats.streak(asOf: Date(), calendar: model.calendar))", unit: "天", icon: "flame.fill", tint: .yellow)
                    }
                    chart
                    footer
                }
                .padding(16)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("统计")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var hero: some View {
        let today = stats.stat(on: Date(), calendar: model.calendar)
        return VStack(alignment: .leading, spacing: 8) {
            Text("今天")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(today.viewed)").font(.system(size: 44, weight: .bold, design: .rounded))
                Text("张回忆").font(.headline)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("删除 \(today.deleted) 张")
                    Text("释放 \(ByteSize.format(today.bytesFreed))")
                }
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
            }
            if stats.totalViewed > 0 {
                Text("你一共删掉了看过内容的 \(Int((stats.deletionRate * 100).rounded()))%，留下的都是珍贵的。")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var chart: some View {
        let days = stats.lastDays(range, asOf: Date(), calendar: model.calendar)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最近 \(range) 天").font(.headline)
                Spacer()
                Picker("范围", selection: $range) {
                    Text("7 天").tag(7)
                    Text("14 天").tag(14)
                    Text("30 天").tag(30)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            Chart {
                ForEach(days, id: \.date) { day in
                    BarMark(
                        x: .value("日期", day.date, unit: .day),
                        y: .value("数量", day.stat.viewed)
                    )
                    .foregroundStyle(by: .value("类型", "浏览"))
                    BarMark(
                        x: .value("日期", day.date, unit: .day),
                        y: .value("数量", day.stat.deleted)
                    )
                    .foregroundStyle(by: .value("类型", "删除"))
                }
            }
            .chartForegroundStyleScale(["浏览": Color.blue, "删除": Color.red])
            .frame(height: 200)
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var footer: some View {
        VStack(spacing: 4) {
            if let first = stats.firstUseDate {
                Text("从 \(DateDisplay.format(first, style: .numeric, calendar: model.calendar)) 开始，你已经回顾了 \(model.history.viewedCount) 个不同的回忆")
            }
            Text("所有数据只保存在你的设备上")
        }
        .font(.footnote)
        .foregroundStyle(.white.opacity(0.45))
        .multilineTextAlignment(.center)
        .padding(.top, 8)
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .foregroundStyle(tint)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if !unit.isEmpty {
                    Text(unit).font(.footnote).foregroundStyle(.white.opacity(0.6))
                }
            }
            .foregroundStyle(.white)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
