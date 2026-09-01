import SwiftUI
import AVKit
import AVFoundation

struct VideoPlayerView: UIViewControllerRepresentable {
    let videoURL: String
    let title: String

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let playerVC = AVPlayerViewController()
        playerVC.title = title

        guard let url = URL(string: videoURL) else {
            return playerVC
        }

        // 添加请求头，解决防盗链
        var headers: [String: String] = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        ]
        if let referer = getReferer(for: videoURL) {
            headers["Referer"] = referer
        }

        let assetOptions = ["AVURLAssetHTTPHeaderFieldsKey": headers]
        let asset = AVURLAsset(url: url, options: assetOptions)
        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)

        playerVC.player = player
        playerVC.allowsPictureInPicturePlayback = true
        playerVC.showsPlaybackControls = true
        playerVC.entersFullScreenWhenPlaybackBegins = true
        playerVC.exitsFullScreenWhenPlaybackEnds = false

        // 自动播放
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            player.play()
        }

        return playerVC
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}

    private func getReferer(for url: String) -> String? {
        if url.contains("douyin") || url.contains("douyinvod") || url.contains("douyincdn") {
            return "https://www.douyin.com/"
        } else if url.contains("kuaishou") || url.contains("ksyun") {
            return "https://www.kuaishou.com/"
        } else if url.contains("bilibili") || url.contains("hdslb") {
            return "https://www.bilibili.com/"
        } else if url.contains("weibo") || url.contains("sinaimg") {
            return "https://weibo.com/"
        } else if url.contains("xiaohongshu") || url.contains("xhscdn") {
            return "https://www.xiaohongshu.com/"
        }
        return nil
    }
}

// 包装成可关闭的视图
struct VideoPlayerWrapper: View {
    let videoURL: String
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                VideoPlayerView(videoURL: videoURL, title: title)
                    .edgesIgnoringSafeArea(.all)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
}
