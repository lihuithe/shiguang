import Photos
import ShiGuangCore
import SwiftUI

struct SettingsView: View {
    /// 重置瀏覽記錄後，首頁需要重新抽組
    let onHistoryReset: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var confirmReset: ResetScope?

    enum ResetScope: Identifiable {
        case current, screenshots, all
        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
            Form {
                browsingSection
                gestureSection
                displaySection
                syncSection
                historySection
                demoSection
                permissionSection
                aboutSection
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .confirmationDialog(
                resetTitle,
                isPresented: Binding(get: { confirmReset != nil }, set: { if !$0 { confirmReset = nil } }),
                titleVisibility: .visible,
                presenting: confirmReset
            ) { scope in
                Button("重置", role: .destructive) { performReset(scope) }
            } message: { _ in
                Text("重置后，看过的内容会重新出现在随机回顾里。")
            }
            .alert("无法开启提醒", isPresented: Binding(
                get: { model.reminderError != nil },
                set: { if !$0 { model.reminderError = nil } }
            )) {
                Button("去设置") { openSystemSettings() }
                Button("好", role: .cancel) {}
            } message: {
                Text(model.reminderError ?? "")
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - 區塊

    private var browsingSection: some View {
        Section {
            Stepper(value: model.binding(\.groupSize), in: AppSettings.groupSizeRange, step: 5) {
                HStack {
                    Text("每组数量")
                    Spacer()
                    Text("\(model.settings.groupSize) 张").foregroundStyle(.secondary)
                }
            }
            Picker("回顾分类", selection: model.binding(\.category)) {
                ForEach(MediaCategory.allCases) { category in
                    Label(category.title, systemImage: category.systemImage).tag(category)
                }
            }
        } header: {
            Text("浏览")
        } footer: {
            Text("每次随机抽出一组，看完一组再统一确认删除。看过的内容 3 年内不会重复出现。")
        }
    }

    private var gestureSection: some View {
        Section("手势与反馈") {
            Toggle("双击收藏", isOn: model.binding(\.doubleTapToFavorite))
            Toggle("震动反馈", isOn: model.binding(\.hapticsEnabled))
            Toggle("删除动画", isOn: model.binding(\.deleteAnimationEnabled))
        }
    }

    private var displaySection: some View {
        Section {
            Toggle("HDR 显示", isOn: model.binding(\.hdrEnabled))
            if model.settings.hdrEnabled {
                Toggle("低亮度时自动关闭 HDR", isOn: model.binding(\.hdrAutoOffInLowBrightness))
            }
            Toggle("实况照片自动播放", isOn: model.binding(\.livePhotoAutoplay))
            Toggle("实况照片静音", isOn: model.binding(\.livePhotoMuted))
            Toggle("视频自动播放", isOn: model.binding(\.videoAutoplay))
            Toggle("视频默认静音", isOn: model.binding(\.videoMuted))
            Toggle("显示拍摄日期", isOn: model.binding(\.showDate))
            if model.settings.showDate {
                Picker("日期格式", selection: model.binding(\.dateStyle)) {
                    ForEach(DateDisplayStyle.allCases) { style in
                        Text("\(style.title)（\(DateDisplay.format(Date(timeIntervalSince1970: 1_615_000_000), style: style, calendar: model.calendar))）")
                            .tag(style)
                    }
                }
            }
        } header: {
            Text("显示")
        } footer: {
            Text("长按视频可 2 倍速播放。")
        }
    }

    private var syncSection: some View {
        Section {
            Toggle("iCloud 同步浏览记录", isOn: model.binding(\.iCloudSyncEnabled))
            Toggle("每日回顾提醒", isOn: model.binding(\.dailyReminderEnabled))
            if model.settings.dailyReminderEnabled {
                DatePicker("提醒时间", selection: reminderTime, displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("同步与提醒")
        } footer: {
            Text("开启同步后，在 iPhone 和 iPad 上看过的内容都不会重复出现。只同步浏览记录，不上传任何照片。")
        }
    }

    private var historySection: some View {
        Section {
            LabeledContent("已记录", value: "\(model.history.viewedCount) 个")
            Button("重置「\(model.settings.category.title)」浏览记录") { confirmReset = .current }
            if model.settings.category != .screenshots {
                Button("重置截图浏览记录") { confirmReset = .screenshots }
            }
            Button("重置全部浏览记录", role: .destructive) { confirmReset = .all }
        } header: {
            Text("浏览记录")
        }
    }

    private var demoSection: some View {
        Section {
            Toggle("演示模式", isOn: model.binding(\.demoMode))
        } footer: {
            Text("用示范图片代替你的真实照片，适合录屏或给别人演示，不会显示或删除任何真实内容。")
        }
    }

    private var permissionSection: some View {
        Section("相册权限") {
            LabeledContent("当前权限", value: permissionText)
            if model.authorization == .limited {
                Button("管理可访问的照片") {
                    model.library.presentLimitedLibraryPicker()
                }
            }
            Button("打开系统设置") { openSystemSettings() }
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
            NavigationLink("手势说明") { GestureHelpView() }
        } header: {
            Text("关于")
        } footer: {
            Text("拾光不需要登录，没有订阅，不收集任何数据。所有照片处理都只在本机进行。")
        }
    }

    // MARK: - 輔助

    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(from: DateComponents(
                    hour: model.settings.reminderHour,
                    minute: model.settings.reminderMinute
                )) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                model.updateSettings {
                    $0.reminderHour = c.hour ?? 21
                    $0.reminderMinute = c.minute ?? 0
                }
            }
        )
    }

    private var permissionText: String {
        switch model.authorization {
        case .authorized: return "完全访问"
        case .limited: return "部分照片"
        case .denied: return "已拒绝"
        case .restricted: return "受限制"
        case .notDetermined: return "未授权"
        @unknown default: return "未知"
        }
    }

    private var resetTitle: String {
        switch confirmReset {
        case .current: return "重置「\(model.settings.category.title)」浏览记录？"
        case .screenshots: return "重置截图浏览记录？"
        case .all: return "重置全部浏览记录？"
        case nil: return ""
        }
    }

    private func performReset(_ scope: ResetScope) {
        switch scope {
        case .current:
            model.resetHistory(for: model.settings.category)
        case .screenshots:
            model.resetHistory(for: .screenshots)
        case .all:
            model.resetHistory(for: .all)
        }
        onHistoryReset()
        Haptics.success()
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}

struct GestureHelpView: View {
    var body: some View {
        List {
            Section("首页") {
                HelpRow(icon: "arrow.up", text: "上滑：标记删除，看完一组后统一确认")
                HelpRow(icon: "arrow.down", text: "下滑：收藏（同步到系统相册的「个人收藏」）并看下一张")
                HelpRow(icon: "arrow.left", text: "左滑：保留，看下一张")
                HelpRow(icon: "arrow.right", text: "右滑：回到上一张")
                HelpRow(icon: "hand.tap", text: "双击：收藏 / 取消收藏")
                HelpRow(icon: "arrow.down.right.and.arrow.up.left", text: "双指捏合：回到那天")
                HelpRow(icon: "arrow.uturn.backward", text: "撤销按钮：撤回上一步操作")
            }
            Section("视频与实况") {
                HelpRow(icon: "hand.point.up.left", text: "长按视频：2 倍速播放，松手恢复")
                HelpRow(icon: "livephoto", text: "实况照片会自动播放，可在设置中关闭")
            }
            Section("回到那天") {
                HelpRow(icon: "calendar", text: "查看这张照片拍摄当天的所有照片、视频和截图")
                HelpRow(icon: "checkmark.circle", text: "点「选择」可以批量删除相似照片")
            }
        }
        .navigationTitle("手势说明")
    }
}

private struct HelpRow: View {
    let icon: String
    let text: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: icon).foregroundStyle(Color.accentColor)
        }
    }
}
