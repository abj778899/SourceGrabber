import SwiftUI
import AVKit
import AVFoundation

struct VideoPlayerView: View {
    let videoURL: String
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)

                if let player = player {
                    VideoPlayer(player: player)
                        .edgesIgnoringSafeArea(.all)
                        .onAppear {
                            player.play()
                        }
                } else if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        Text("正在加载视频...")
                            .foregroundColor(.white)
                    }
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(.orange)
                        Text(error)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button("用浏览器打开") {
                            if let url = URL(string: videoURL) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .foregroundColor(.blue)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") {
                        player?.pause()
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        if let url = URL(string: videoURL) {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        Image(systemName: "safari")
                    }
                    .foregroundColor(.white)
                }
            }
            .onAppear(perform: loadVideo)
            .onDisappear {
                player?.pause()
            }
        }
    }

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
        } else if url.contains("youtube") || url.contains("googlevideo") {
            return "https://www.youtube.com/"
        } else if url.contains("twitch") || url.contains("ttvnw") {
            return "https://www.twitch.tv/"
        }
        return nil
    }

    private func loadVideo() {
        guard let url = URL(string: videoURL) else {
            errorMessage = "无效的视频地址"
            isLoading = false
            return
        }

        var headers: [String: String] = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"
        ]

        if let referer = getReferer(for: videoURL) {
            headers["Referer"] = referer
        }

        let assetOptions = ["AVURLAssetHTTPHeaderFieldsKey": headers]
        let asset = AVURLAsset(url: url, options: assetOptions)

        let playerItem = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: playerItem)
        isLoading = false

        NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: playerItem, queue: .main) { _ in
            errorMessage = "视频播放失败，可能格式不支持或地址已失效，可尝试用浏览器打开"
            isLoading = false
        }

        NotificationCenter.default.addObserver(forName: .AVPlayerItemNewErrorLogEntry, object: playerItem, queue: .main) { _ in
            if let errorLog = playerItem.errorLog(), let lastEvent = errorLog.events.last {
                DispatchQueue.main.async {
                    errorMessage = "播放错误: \(lastEvent.errorComment ?? "未知错误")\n可尝试用浏览器打开"
                    isLoading = false
                }
            }
        }
    }
}

struct VideoPlayerView_Previews: PreviewProvider {
    static var previews: some View {
        VideoPlayerView(videoURL: "https://example.com/video.mp4", title: "测试视频")
    }
}
