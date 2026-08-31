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

    private func loadVideo() {
        guard let url = URL(string: videoURL) else {
            errorMessage = "无效的视频地址"
            isLoading = false
            return
        }

        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)

        playerItem.addObserver(self, forKeyPath: "status", options: [.new, .initial], context: nil)

        NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: playerItem, queue: .main) { _ in
            errorMessage = "视频播放失败，可能格式不支持或地址已失效"
            isLoading = false
        }
    }
}

struct VideoPlayerView_Previews: PreviewProvider {
    static var previews: some View {
        VideoPlayerView(videoURL: "https://example.com/video.mp4", title: "测试视频")
    }
}
