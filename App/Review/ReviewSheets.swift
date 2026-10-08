import Photos
import ShiGuangCore
import SwiftUI

/// 「有待刪除的照片」：看完一組或中途返回時出現。預設全部勾選，點縮圖取消勾選即保留。
struct PendingDeletionSheet: View {
    @Bindable var review: ReviewModel

    @State private var kept = Set<String>()
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    private var selected: [MediaItem] {
        review.session.pendingDeletion.filter { !kept.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("有待删除的\(review.noun)")
                    .font(.title3.weight(.bold))
                HStack {
                    Spacer()
                    CircleIconButton(systemName: "xmark", size: 34) {
                        review.closePending()
                    }
                    .disabled(review.isDeleting)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 16)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(review.session.pendingDeletion) { item in
                        let isSelected = !kept.contains(item.id)
                        ThumbnailView(item: item, side: 130)
                            .overlay(alignment: .bottomLeading) {
                                ThumbnailBadges(item: item)
                            }
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(Color.white, isSelected ? Color.green : Color.black.opacity(0.3))
                                    .padding(6)
                            }
                            .opacity(isSelected ? 1 : 0.45)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .onTapGesture {
                                if isSelected { kept.insert(item.id) } else { kept.remove(item.id) }
                                Haptics.tick()
                            }
                    }
                }
                .padding(.horizontal, 16)

                Text("轻点可以取消勾选，留下这张。删除的内容会移到「最近删除」，30 天内可以恢复。")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .padding(20)
            }

            HStack(spacing: 12) {
                Button {
                    review.discardPending()
                } label: {
                    Text(review.kind == .photos ? "放弃，回到首页" : "放弃，继续看")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.12), in: Capsule())
                        .foregroundStyle(.white)
                }
                Button {
                    Task { await review.confirmDeletion(of: selected) }
                } label: {
                    HStack(spacing: 6) {
                        if review.isDeleting { ProgressView().tint(.white) }
                        Text(selected.isEmpty ? "确认" : "确认删除")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.red, in: Capsule())
                    .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .disabled(review.isDeleting)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(Color(white: 0.11).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
        .alert("出错了", isPresented: Binding(
            get: { review.errorMessage != nil },
            set: { if !$0 { review.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(review.errorMessage ?? "")
        }
    }
}

/// 點資訊條的 ⓘ：拍攝時間、地點、尺寸、大小、檔名，並可「回到那天」。
struct MediaInfoSheet: View {
    let item: MediaItem
    let onBackToDay: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var fileSize: Int64?
    @State private var filename: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row("拍摄时间", DateDisplay.format(item.creationDate, style: .full, calendar: model.calendar) + timeText)
                    if let date = item.creationDate {
                        row("距今", DateDisplay.relative(date, now: Date(), calendar: model.calendar))
                    }
                    row("地点", model.locations.name(for: item) ?? "没有位置信息")
                }
                Section {
                    row("类型", typeText)
                    if item.pixelWidth > 0 {
                        row("尺寸", "\(item.pixelWidth) × \(item.pixelHeight)")
                    }
                    if item.kind == .video {
                        row("时长", DurationText.format(item.duration))
                    }
                    if let fileSize {
                        row("大小", ByteSize.format(fileSize))
                    }
                    if let filename {
                        row("文件名", filename)
                    }
                }
                Section {
                    Button {
                        dismiss()
                        onBackToDay()
                    } label: {
                        Label("回到那天", systemImage: "calendar")
                    }
                    .disabled(item.creationDate == nil)
                }
            }
            .navigationTitle("详细信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            model.locations.resolve(item)
            guard let asset = fetchAsset(item.id) else { return }
            fileSize = PhotoLibraryService.fileSize(of: asset)
            filename = PhotoLibraryService.originalFilename(of: asset)
        }
    }

    private var timeText: String {
        guard let date = item.creationDate else { return "" }
        return " " + date.formatted(date: .omitted, time: .shortened)
    }

    private var typeText: String {
        if item.kind == .video { return "视频" }
        if item.isScreenshot { return "截屏" }
        if item.isAnimated { return "动图" }
        if item.isLivePhoto { return "实况照片" }
        return "照片"
    }

    private func row(_ title: String, _ value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

/// 第一次瀏覽幾張後出現：「回到那天」操作方式，像縮小照片那樣雙指捏合。
struct DayTutorialSheet: View {
    let item: MediaItem?
    let dismissAction: () -> Void

    @State private var pinched = false

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("「回到那天」操作方式")
                    .font(.headline)
                Text("像缩小照片那样双指捏合")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.top, 24)

            ZStack {
                Group {
                    if let item {
                        ThumbnailView(item: item, side: 220)
                    } else {
                        RoundedRectangle(cornerRadius: 12).fill(Color.green.opacity(0.4))
                    }
                }
                .frame(width: 170, height: 210)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .scaleEffect(pinched ? 0.72 : 1)

                // 兩個手指觸點往中間靠攏
                Circle().fill(.white).frame(width: 16, height: 16)
                    .shadow(radius: 3)
                    .offset(x: pinched ? 12 : 48, y: pinched ? -18 : -70)
                Circle().fill(.white).frame(width: 16, height: 16)
                    .shadow(radius: 3)
                    .offset(x: pinched ? -12 : -40, y: pinched ? 18 : 64)
            }
            .frame(height: 230)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    pinched = true
                }
            }

            Button(action: dismissAction) {
                Text("我知道了")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.14).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
    }
}
