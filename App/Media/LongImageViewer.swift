import Photos
import ShiGuangCore
import SwiftUI

/// 長圖（例如長截圖）以寬度撐滿、上下捲動的方式瀏覽。
struct LongImageViewer: View {
    let item: MediaItem

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView(.vertical) {
                    if DemoLibrary.isDemoID(item.id) {
                        DemoCardView(item: item)
                            .frame(height: proxy.size.width * 2.5)
                    } else if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: proxy.size.width)
                    } else {
                        ProgressView()
                            .tint(.white)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                }
                .task(id: item.id) {
                    await load(width: proxy.size.width)
                }
            }
            .background(Color.black)
            .navigationTitle("长图")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func load(width: CGFloat) async {
        guard !DemoLibrary.isDemoID(item.id), let asset = fetchAsset(item.id), asset.pixelWidth > 0 else { return }
        let scale = UIScreen.main.scale
        let targetWidth = min(width * scale, CGFloat(asset.pixelWidth))
        let ratio = CGFloat(asset.pixelHeight) / CGFloat(asset.pixelWidth)
        let bag = RequestBag()
        bag.add(MediaLoader.shared.requestImage(
            for: asset,
            targetSize: CGSize(width: targetWidth, height: targetWidth * ratio)
        ) { result, _ in
            if let result { image = result }
        })
        await MediaLoader.shared.hold(bag)
    }
}
