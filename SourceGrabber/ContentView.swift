import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = VideoSourceViewModel()
    @State private var urlInput: String = ""
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var showResponseInfo = false
    @State private var copiedURL: String?
    @State private var showCopiedToast = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // URL 输入栏
                urlInputBar

                // 状态信息栏
                if viewModel.statusCode > 0 {
                    statusBar
                }

                // 内容区域
                contentArea
            }
            .navigationTitle("视频源抓取器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showHistory = true }) {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { showSettings = true }) {
                            Label("设置", systemImage: "gear")
                        }
                        Button(action: { showResponseInfo = true }) {
                            Label("响应信息", systemImage: "info.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(viewModel: viewModel)
            }
            .sheet(isPresented: $showHistory) {
                HistoryView { selectedURL in
                    urlInput = selectedURL
                    viewModel.fetchVideoSources(from: selectedURL)
                }
            }
            .sheet(isPresented: $showResponseInfo) {
                ResponseInfoView(viewModel: viewModel)
            }
            .overlay(
                Group {
                    if showCopiedToast {
                        toastView
                    }
                }
            )
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    // MARK: - URL 输入栏
    private var urlInputBar: some View {
        HStack(spacing: 8) {
            TextField("输入网页URL", text: $urlInput)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .keyboardType(.URL)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .onSubmit {
                    fetchSources()
                }

            Button(action: fetchSources) {
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("抓取")
                        .fontWeight(.semibold)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(urlInput.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isLoading)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    // MARK: - 状态信息栏
    private var statusBar: some View {
        HStack(spacing: 12) {
            statusBadge(text: "\(viewModel.statusCode)", color: viewModel.statusCode == 200 ? .green : .orange)
            Text("\(viewModel.videoSources.count) 个视频源")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text("\(formatSize(viewModel.contentSize)) · \(String(format: "%.2fs", viewModel.fetchTime))")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground))
    }

    private func statusBadge(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color)
            .cornerRadius(4)
    }

    // MARK: - 内容区域
    @ViewBuilder
    private var contentArea: some View {
        if viewModel.isLoading {
            loadingView
        } else if let error = viewModel.errorMessage, viewModel.videoSources.isEmpty {
            errorView(message: error)
        } else if viewModel.videoSources.isEmpty {
            emptyView
        } else {
            videoList
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("正在抓取视频源...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("输入网页URL开始抓取视频源")
                .font(.body)
                .foregroundColor(.secondary)
            Text("支持 m3u8、mp4、flv 等格式")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var videoList: some View {
        List {
            ForEach(viewModel.videoSources) { source in
                videoSourceRow(source: source)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        copySource(source)
                    }
                    .contextMenu {
                        Button(action: { copySource(source) }) {
                            Label("复制地址", systemImage: "doc.on.doc")
                        }
                        Button(action: { shareSource(source) }) {
                            Label("分享", systemImage: "square.and.arrow.up")
                        }
                        Button(action: { openInBrowser(source) }) {
                            Label("在浏览器打开", systemImage: "safari")
                        }
                    }
            }
        }
        .listStyle(PlainListStyle())
        .refreshable {
            if !urlInput.isEmpty {
                viewModel.fetchVideoSources(from: urlInput)
            }
        }
    }

    private func videoSourceRow(source: VideoSource) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // 类型图标
            typeIcon(for: source.type)
                .frame(width: 40, height: 40)
                .background(typeColor(for: source.type).opacity(0.15))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                // 类型标签和画质
                HStack(spacing: 6) {
                    Text(source.type.uppercased())
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(typeColor(for: source.type))
                        .cornerRadius(4)

                    if let quality = source.quality {
                        Text(quality)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }
                }

                // URL
                Text(source.url)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Spacer()

            Image(systemName: "doc.on.doc")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }

    private func typeIcon(for type: String) -> some View {
        let iconName: String
        switch type.lowercased() {
        case "m3u8": iconName = "square.stack.3d.down.right"
        case "mp4": iconName = "film"
        case "flv": iconName = "film.stack"
        default: iconName = "play.rectangle"
        }
        return Image(systemName: iconName)
            .font(.system(size: 20))
            .foregroundColor(typeColor(for: type))
    }

    private func typeColor(for type: String) -> Color {
        switch type.lowercased() {
        case "m3u8": return .purple
        case "mp4": return .blue
        case "flv": return .orange
        default: return .gray
        }
    }

    // MARK: - Toast
    private var toastView: some View {
        VStack {
            Spacer()
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("已复制到剪贴板")
                    .font(.subheadline)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.8))
            .cornerRadius(25)
            .padding(.bottom, 40)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.easeInOut, value: showCopiedToast)
    }

    // MARK: - 方法
    private func fetchSources() {
        hideKeyboard()
        viewModel.fetchVideoSources(from: urlInput)
    }

    private func copySource(_ source: VideoSource) {
        viewModel.copySource(source)
        copiedURL = source.url
        withAnimation {
            showCopiedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopiedToast = false
            }
        }
    }

    private func shareSource(_ source: VideoSource) {
        if let url = URL(string: source.url) {
            let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) {
                window.rootViewController?.present(activityVC, animated: true)
            }
        }
    }

    private func openInBrowser(_ source: VideoSource) {
        if let url = URL(string: source.url) {
            UIApplication.shared.open(url)
        }
    }

    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
