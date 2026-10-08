import ShiGuangCore
import SwiftUI

/// 統計分頁（對照原版「使用统计」）：照片 / 截屏 / 視頻各自的查看、刪除、清理，騰出空間佔比，重置瀏覽記錄。
struct StatsView: View {
    /// 重置瀏覽記錄後，照片與視頻分頁要重新抽組
    let onHistoryReset: () -> Void

    @Environment(AppModel.self) private var model
    @State private var showSettings = false
    @State private var showResetOptions = false

    private var stats: UsageStats { model.stats }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(StatsBucket.allCases) { bucket in
                        BucketCard(bucket: bucket, stat: stats.stat(for: bucket))
                    }
                    freedSpaceCard
                    resetRow
                    streakFooter
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("使用统计")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            SettingsView(onHistoryReset: onHistoryReset)
                .environment(model)
        }
    }

    // MARK: - 騰出空間

    private var freedSpaceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("腾出空间", systemImage: "externaldrive")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
            Text(ByteSize.format(stats.bytesFreed))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            GeometryReader { proxy in
                HStack(spacing: 2) {
                    if stats.bytesFreed == 0 {
                        Capsule().fill(.white.opacity(0.12))
                    } else {
                        ForEach(StatsBucket.allCases) { bucket in
                            let share = stats.freedShare(of: bucket)
                            if share > 0 {
                                Rectangle()
                                    .fill(color(for: bucket))
                                    .frame(width: max(proxy.size.width * share - 2, 2))
                            }
                        }
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 6)

            HStack(spacing: 14) {
                ForEach(StatsBucket.allCases) { bucket in
                    HStack(spacing: 4) {
                        Circle().fill(color(for: bucket)).frame(width: 6, height: 6)
                        Text("\(bucket.title) \(Int((stats.freedShare(of: bucket) * 100).rounded()))%")
                    }
                }
            }
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.6))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var resetRow: some View {
        Button {
            showResetOptions = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("重置浏览记录")
                        .font(.subheadline.weight(.semibold))
                    Text("浏览了 \(model.history.viewedCount) 个项目，其中 \(stats.totalDeleted) 个已删除。")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.white.opacity(0.4))
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        // 掛在這一行上，iPad 與 iOS 26 的彈出選單會指向這裡
        .confirmationDialog("重置浏览记录", isPresented: $showResetOptions, titleVisibility: .visible) {
            Button("重置「\(model.settings.category.title)」") { reset(model.settings.category) }
            Button("重置视频") { reset(.videos) }
            Button("重置全部", role: .destructive) { reset(.all) }
        } message: {
            Text("重置后，看过的内容会重新出现在随机回顾里。")
        }
    }

    @ViewBuilder
    private var streakFooter: some View {
        let streak = stats.streak(asOf: Date(), calendar: model.calendar)
        if streak > 0 || stats.groupsCompleted > 0 {
            Text("已经连续回顾 \(streak) 天，完成了 \(stats.groupsCompleted) 组")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.45))
                .padding(.top, 8)
        }
    }

    private func color(for bucket: StatsBucket) -> Color {
        switch bucket {
        case .photo: return .blue
        case .screenshot: return .orange
        case .video: return .green
        }
    }

    private func reset(_ category: MediaCategory) {
        model.resetHistory(for: category)
        onHistoryReset()
        Haptics.success()
    }
}

/// 單一類別的卡片：查看 / 刪除 / 清理
private struct BucketCard: View {
    let bucket: StatsBucket
    let stat: BucketStat

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(bucket.title, systemImage: bucket.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            HStack(alignment: .top) {
                metric(title: "查看", icon: "eye.fill", tint: .blue, value: "\(stat.viewed)")
                metric(title: "删除", icon: "trash.fill", tint: .red, value: "\(stat.deleted)")
                metric(title: "清理", icon: "leaf.fill", tint: .green, value: ByteSize.format(stat.bytesFreed))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func metric(title: String, icon: String, tint: Color, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption2.weight(.medium))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
