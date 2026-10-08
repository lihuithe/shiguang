import ShiGuangCore
import SwiftUI

/// 一組看完後的結算頁：確認要刪除的項目，可點擊取消或加入標記，長按回去重看。
struct GroupReviewView: View {
    @Bindable var vm: BrowserViewModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 4)

    var body: some View {
        let pending = vm.session.pendingDeletion
        VStack(spacing: 0) {
            Spacer().frame(height: 64)

            VStack(spacing: 8) {
                Text("这一组看完啦")
                    .font(.title2.weight(.bold))
                Text(summary(pendingCount: pending.count))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .foregroundStyle(.white)
            .padding(.vertical, 20)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(vm.session.items) { item in
                        let marked = vm.session.isMarkedForDeletion(item.id)
                        ThumbnailView(item: item, side: 100)
                            .overlay {
                                if marked {
                                    ZStack {
                                        Color.black.opacity(0.45)
                                        Image(systemName: "trash.fill")
                                            .font(.title3)
                                            .foregroundStyle(.red)
                                    }
                                }
                            }
                            .overlay(alignment: .bottomLeading) {
                                ThumbnailBadges(item: item, isFavorite: vm.session.isFavorite(item.id))
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .onTapGesture { vm.toggleDeletion(item) }
                            .onLongPressGesture { vm.jump(to: item) }
                    }
                }
                .padding(.horizontal, 12)

                Text("点击切换是否删除，长按回去再看一眼。\n删除的内容会移到「最近删除」，30 天内可在照片 App 里恢复。")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(20)
            }

            VStack(spacing: 10) {
                Button {
                    Task { await vm.confirmDeletionAndContinue() }
                } label: {
                    HStack {
                        if vm.isDeleting { ProgressView().tint(.white) }
                        Text(pending.isEmpty ? "下一组" : "删除 \(pending.count) 项，开始下一组")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(pending.isEmpty ? .accentColor : .red)
                .disabled(vm.isDeleting)

                Button("返回上一张") {
                    withAnimation { vm.undo() }
                }
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .disabled(!vm.session.canUndo || vm.isDeleting)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private func summary(pendingCount: Int) -> String {
        let total = vm.session.items.count
        if pendingCount == 0 {
            return "看了 \(total) 张，全部保留"
        }
        return "看了 \(total) 张，标记删除 \(pendingCount) 张"
    }
}

/// 縮圖角落的小標記：影片長度、實況、收藏。
struct ThumbnailBadges: View {
    let item: MediaItem
    var isFavorite = false

    var body: some View {
        HStack(spacing: 3) {
            if isFavorite {
                Image(systemName: "heart.fill").foregroundStyle(.pink)
            }
            if item.kind == .video {
                Text(DurationText.format(item.duration))
            } else if item.isLivePhoto {
                Image(systemName: "livephoto")
            } else if item.isAnimated {
                Text("GIF")
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.7), radius: 2)
        .padding(4)
    }
}
