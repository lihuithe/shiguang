import Photos
import ShiGuangCore
import SwiftUI

@main
struct ShiGuangApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Color.accentColor)
        }
    }
}

struct RootView: View {
    let model: AppModel

    @State private var photos: ReviewModel
    @State private var videos: ReviewModel
    @State private var tab: AppTab = .photos
    @State private var didPrune = false
    @Environment(\.scenePhase) private var scenePhase

    init(model: AppModel) {
        self.model = model
        _photos = State(initialValue: ReviewModel(kind: .photos, model: model))
        _videos = State(initialValue: ReviewModel(kind: .videos, model: model))
    }

    var body: some View {
        Group {
            if model.canBrowse {
                MainTabView(tab: $tab, photos: photos, videos: videos)
                    .task {
                        if !didPrune {
                            didPrune = true
                            model.pruneHistory()
                        }
                    }
            } else {
                PermissionView()
            }
        }
        .onChange(of: model.libraryVersion) {
            photos.libraryDidChange()
            videos.libraryDidChange()
        }
        .onChange(of: model.settings.demoMode) {
            photos.reload()
            videos.reload()
        }
        .onChange(of: model.settings.category) {
            photos.reload()
        }
        .onChange(of: model.canBrowse) { _, canBrowse in
            if canBrowse {
                photos.reload()
                videos.reload()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                model.refreshAuthorization()
            case .background, .inactive:
                model.saveNow()
            @unknown default:
                break
            }
        }
    }
}

/// 系統原生 TabView：用 Xcode 26 編譯、在 iOS 26 上自動呈現液態玻璃 Tab 列。
/// 各分頁的內容都停在 Tab 列上方（抖音式），Tab 列底下是黑色背景。
/// 照片的全螢幕瀏覽由 PhotoHomeView 以 fullScreenCover 呈現，會蓋住 Tab 列。
struct MainTabView: View {
    @Binding var tab: AppTab
    let photos: ReviewModel
    let videos: ReviewModel

    var body: some View {
        TabView(selection: $tab) {
            Tab("照片", systemImage: "photo.on.rectangle", value: AppTab.photos) {
                PhotoHomeView(review: photos)
            }
            Tab("视频", systemImage: "play.rectangle.fill", value: AppTab.videos) {
                VideoFeedView(review: videos)
            }
            Tab("统计", systemImage: "person.fill", value: AppTab.stats) {
                StatsView {
                    photos.reload()
                    videos.reload()
                }
            }
        }
        .onChange(of: tab) {
            Haptics.tick()
        }
        .background(Color.black.ignoresSafeArea())
    }
}

/// 尚未取得相簿權限時的引導頁。
struct PermissionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "photo.stack")
                .font(.system(size: 72))
                .foregroundStyle(Color.accentColor)
            VStack(spacing: 10) {
                Text("拾光")
                    .font(.largeTitle.weight(.bold))
                Text("像刷短视频一样回顾照片\n看到废片，顺手一删")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.8))
            }
            VStack(alignment: .leading, spacing: 12) {
                PermissionPoint(icon: "shuffle", text: "每次随机抽一组，像开盲盒")
                PermissionPoint(icon: "hand.draw", text: "左右滑动翻看，点删除顺手清理")
                PermissionPoint(icon: "lock.shield", text: "不需要登录，不上传，不收集任何数据")
            }
            .padding(.top, 8)
            Spacer()

            if model.authorization == .denied || model.authorization == .restricted {
                Text("你之前拒绝了相册访问，请在系统设置中允许拾光访问照片。")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Text("打开系统设置").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    Task { await model.requestLibraryAccess() }
                } label: {
                    Text("允许访问相册").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
            }

            Button("先用演示模式看看") {
                model.updateSettings { $0.demoMode = true }
            }
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white)
        .padding(28)
        .background(Color.black.ignoresSafeArea())
    }
}

private struct PermissionPoint: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 28)
                .foregroundStyle(Color.accentColor)
            Text(text)
        }
        .font(.body)
    }
}
