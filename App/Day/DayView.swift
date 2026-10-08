import ShiGuangCore
import SwiftUI

/// 「回到那天」：看看某張照片拍攝當天的所有照片、影片與截圖，順手清掉相似照片。
struct DayView: View {
    let anchor: MediaItem

    enum Filter: String, CaseIterable, Identifiable {
        case all, photos, videos, screenshots
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "全部"
            case .photos: return "照片"
            case .videos: return "视频"
            case .screenshots: return "截图"
            }
        }
        func contains(_ item: MediaItem) -> Bool {
            switch self {
            case .all: return true
            case .photos: return MediaCategory.photos.contains(item)
            case .videos: return item.kind == .video
            case .screenshots: return item.isScreenshot
            }
        }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var filter: Filter = .all
    @State private var isSelecting = false
    @State private var selection = Set<String>()
    @State private var preview: PreviewTarget?
    @State private var isDeleting = false
    @State private var errorMessage: String?

    struct PreviewTarget: Identifiable {
        let id = UUID()
        let items: [MediaItem]
        let startID: String
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    private var filtered: [MediaItem] { items.filter(filter.contains) }

    var body: some View {
        NavigationStack {
            ScrollViewReader { reader in
                ScrollView {
                    header
                    filterBar
                    if isLoading {
                        ProgressView().tint(.white).padding(40)
                    } else if filtered.isEmpty {
                        Text("这一天没有\(filter == .all ? "内容" : filter.title)")
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(40)
                    } else {
                        LazyVGrid(columns: columns, spacing: 3) {
                            ForEach(filtered) { item in
                                cell(for: item).id(item.id)
                            }
                        }
                    }
                    Color.clear.frame(height: 100)
                }
                .onChange(of: isLoading) { _, loading in
                    guard !loading else { return }
                    reader.scrollTo(anchor.id, anchor: .center)
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("回到那天")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("返回") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(isSelecting ? "取消" : "选择") {
                        isSelecting.toggle()
                        selection.removeAll()
                    }
                    .disabled(filtered.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isSelecting {
                    selectionBar
                }
            }
            .fullScreenCover(item: $preview) { target in
                DayPreviewView(items: target.items, startID: target.startID) { deleted in
                    items.removeAll { deleted.contains($0.id) }
                }
                .environment(model)
            }
            .alert("出错了", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .preferredColorScheme(.dark)
        .task {
            guard let date = anchor.creationDate else {
                isLoading = false
                return
            }
            items = model.dayItems(for: date)
            isLoading = false
        }
    }

    // MARK: - 區塊

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let date = anchor.creationDate {
                Text(DateDisplay.format(date, style: .full, calendar: model.calendar))
                    .font(.title2.weight(.bold))
                Text(DateDisplay.relative(date, now: Date(), calendar: model.calendar))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }
            if !isLoading {
                Text(countSummary)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var countSummary: String {
        let photos = items.filter { $0.kind == .photo && !$0.isScreenshot }.count
        let videos = items.filter { $0.kind == .video }.count
        let shots = items.filter(\.isScreenshot).count
        var parts: [String] = []
        if photos > 0 { parts.append("\(photos) 张照片") }
        if videos > 0 { parts.append("\(videos) 个视频") }
        if shots > 0 { parts.append("\(shots) 张截图") }
        return parts.isEmpty ? "这一天没有其他内容" : "这一天拍了 " + parts.joined(separator: "、")
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Filter.allCases) { option in
                    let count = items.filter(option.contains).count
                    Button {
                        filter = option
                        selection.removeAll()
                    } label: {
                        Text("\(option.title) \(count)")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(filter == option ? Color.white : Color.white.opacity(0.12), in: Capsule())
                            .foregroundStyle(filter == option ? .black : .white)
                    }
                    .disabled(option != .all && count == 0)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func cell(for item: MediaItem) -> some View {
        let selected = selection.contains(item.id)
        return ThumbnailView(item: item, side: 130)
            .overlay {
                if item.id == anchor.id {
                    Rectangle().strokeBorder(Color.accentColor, lineWidth: 3)
                }
            }
            .overlay {
                if selected { Color.black.opacity(0.35) }
            }
            .overlay(alignment: .bottomLeading) {
                ThumbnailBadges(item: item, isFavorite: item.isFavorite)
            }
            .overlay(alignment: .topTrailing) {
                if isSelecting {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selected ? Color.red : Color.white)
                        .background(Circle().fill(.black.opacity(0.3)))
                        .padding(6)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if isSelecting {
                    if selected { selection.remove(item.id) } else { selection.insert(item.id) }
                    Haptics.tick()
                } else {
                    preview = PreviewTarget(items: filtered, startID: item.id)
                }
            }
    }

    private var selectionBar: some View {
        HStack {
            Button(selection.count == filtered.count ? "全不选" : "全选") {
                if selection.count == filtered.count {
                    selection.removeAll()
                } else {
                    selection = Set(filtered.map(\.id))
                }
            }
            Spacer()
            Button(role: .destructive) {
                Task { await deleteSelection() }
            } label: {
                HStack {
                    if isDeleting { ProgressView() }
                    Text(selection.isEmpty ? "删除" : "删除 \(selection.count) 项")
                }
                .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(selection.isEmpty || isDeleting)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private func deleteSelection() async {
        let targets = items.filter { selection.contains($0.id) }
        isDeleting = true
        defer { isDeleting = false }
        do {
            guard try await model.delete(targets) else { return }
            Haptics.success()
            items.removeAll { selection.contains($0.id) }
            selection.removeAll()
            isSelecting = false
        } catch {
            errorMessage = "删除失败：\(error.localizedDescription)"
        }
    }
}

/// 在「回到那天」中全螢幕翻看當天內容，可直接收藏或刪除。
struct DayPreviewView: View {
    let items: [MediaItem]
    let startID: String
    let onDeleted: (Set<String>) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var currentID: String = ""
    @State private var visible: [MediaItem] = []
    @State private var favorites = Set<String>()
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $currentID) {
                ForEach(visible) { item in
                    MediaContentView(item: item, isActive: item.id == currentID)
                        .tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            VStack {
                HStack {
                    CircleIconButton(systemName: "xmark") { dismiss() }
                    Spacer()
                    if let index = visible.firstIndex(where: { $0.id == currentID }) {
                        Text("\(index + 1)/\(visible.count)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer()
                if let item = visible.first(where: { $0.id == currentID }) {
                    VStack(spacing: 12) {
                        if let date = item.creationDate {
                            Text(date.formatted(date: .omitted, time: .shortened))
                                .font(.subheadline)
                                .foregroundStyle(.white)
                        }
                        HStack(spacing: 24) {
                            CircleIconButton(
                                systemName: favorites.contains(item.id) ? "heart.fill" : "heart",
                                size: 50,
                                tint: favorites.contains(item.id) ? .pink : .white
                            ) {
                                toggleFavorite(item)
                            }
                            CircleIconButton(systemName: "trash.fill", size: 50, tint: .red) {
                                Task { await delete(item) }
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            visible = items
            currentID = startID
            favorites = Set(items.filter(\.isFavorite).map(\.id))
        }
        .onChange(of: currentID) { _, id in
            if let item = visible.first(where: { $0.id == id }) {
                model.markViewed(item)
            }
        }
        .alert("出错了", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func toggleFavorite(_ item: MediaItem) {
        let newValue = !favorites.contains(item.id)
        if newValue { favorites.insert(item.id) } else { favorites.remove(item.id) }
        Haptics.favorite()
        model.setFavorite(newValue, item: item)
    }

    private func delete(_ item: MediaItem) async {
        do {
            guard try await model.delete([item]) else { return }
            Haptics.delete()
            onDeleted([item.id])
            guard let index = visible.firstIndex(of: item) else { return }
            visible.remove(at: index)
            if visible.isEmpty {
                dismiss()
            } else {
                currentID = visible[min(index, visible.count - 1)].id
            }
        } catch {
            errorMessage = "删除失败：\(error.localizedDescription)"
        }
    }
}
