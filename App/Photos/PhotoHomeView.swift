import ShiGuangCore
import SwiftUI

/// 照片分頁首頁：三張扇形疊放的卡片，輕觸開始回顧；左上角切換分類。
struct PhotoHomeView: View {
    @Bindable var review: ReviewModel

    @Environment(AppModel.self) private var model
    @State private var background = Color(white: 0.12)

    var body: some View {
        ZStack {
            LinearGradient(colors: [background, background.opacity(0.55), .black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.6), value: background)

            if review.hasLoaded, review.session.isEmpty {
                EmptyCategoryView(title: review.category.title) { review.reload() }
            } else {
                deck
                    .offset(y: -30)
            }

            VStack(alignment: .leading, spacing: 10) {
                categoryMenu
                if review.didRecycle {
                    recycleBanner
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 6)
        }
        .onAppear { review.loadIfNeeded() }
        .task(id: review.session.current?.id) {
            guard let first = review.session.current else { return }
            background = await ColorExtractor.color(for: first)
        }
        .fullScreenCover(isPresented: $review.isReviewing) {
            PhotoReviewView(review: review)
                .environment(model)
        }
    }

    // MARK: - 扇形卡片

    private var deck: some View {
        let cards = review.session.upcoming(3)
        return Button {
            Haptics.tick()
            review.beginReview()
        } label: {
            ZStack {
                // 後面兩張先畫，前面一張最後畫
                ForEach(Array(cards.enumerated()).reversed(), id: \.element.id) { index, item in
                    DeckCard(item: item, isFront: index == 0)
                        .rotationEffect(.degrees(rotation(for: index)))
                        .offset(x: xOffset(for: index), y: index == 0 ? 20 : -6)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .animation(.spring(duration: 0.4), value: cards.map(\.id))
    }

    private func rotation(for index: Int) -> Double {
        switch index {
        case 1: return -9
        case 2: return 7
        default: return 0
        }
    }

    private func xOffset(for index: Int) -> CGFloat {
        switch index {
        case 1: return -92
        case 2: return 92
        default: return 0
        }
    }

    // MARK: - 分類

    private var categoryMenu: some View {
        Menu {
            ForEach(MediaCategory.photoTabCases) { category in
                Button {
                    model.updateSettings { $0.category = category }
                } label: {
                    if category == review.category {
                        Label(category.title, systemImage: "checkmark")
                    } else {
                        Label(category.title, systemImage: category.systemImage)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                Text(review.category.title)
                    .font(.subheadline.weight(.semibold))
                Text("\(review.session.visibleItems.count - min(review.session.currentIndex, review.session.visibleItems.count))")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.black.opacity(0.7))
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Circle().fill(.white.opacity(0.75)))
            }
            .foregroundStyle(.white)
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .glassBackground(Capsule())
        }
    }

    private var recycleBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
            Text("这个分类都看过啦，正在重温最早看过的内容")
                .font(.footnote)
                .foregroundStyle(.white)
            Spacer(minLength: 4)
            Button("重新开始") { review.resetHistoryAndReload() }
                .font(.footnote.weight(.semibold))
        }
        .padding(12)
        .glassBackground(RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: false)
    }
}

private struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 首頁的單張卡片：白色邊框、圓角、陰影；最前面那張疊上「輕觸開始回顧」。
private struct DeckCard: View {
    let item: MediaItem
    let isFront: Bool

    var body: some View {
        ThumbnailView(item: item, side: 260, aspect: 0.75)
            .frame(width: isFront ? 168 : 150)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white, lineWidth: 3)
            )
            .overlay {
                if isFront {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.tap.fill")
                        Text("轻触开始回顾")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 6)
                }
            }
            .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
    }
}
