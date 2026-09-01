import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = VideoSourceViewModel()
    @StateObject private var downloadManager = DownloadManager.shared
    @State private var urlInput: String = ""
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var showResponseInfo = false
    @State private var showDownloads = false
    @State private var showPlayer = false
    @State private var selectedVideo: VideoSource?
    @State private var showCopiedToast = false
    @State private var showExportSheet = false
    @State private var showDownloadDialog = false
    @State private var downloadTitle = ""
    @State private var selectedDownloadSource: VideoSource?
    @State private var downloadSources: [VideoSource] = []

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                urlInputBar
                statusBar
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
                        Button(action: { showDownloads = true }) {
                            Label("下载管理", systemImage: "arrow.down.circle")
                        }
                        Button(action: { showResponseInfo = true }) {
                            Label("响应信息", systemImage: "info.circle")
                        }
                        Button(action: { showSettings = true }) {
                            Label("设置", systemImage: "gear")
                        }
                        Button(action: { exportSources() }) {
                            Label("导出视频源", systemImage: "square.and.arrow.up")
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
            .sheet(isPresented: $showDownloads) {
                DownloadListView()
            }
            .fullScreenCover(isPresented: $showPlayer) {
                if let video = selectedVideo {
                    VideoPlayerWrapper(videoURL: video.url, title: video.quality ?? "视频播放")
                }
            }
            .overlay(
                Group {
                    if showCopiedToast {
                        toastView
                    }
                }
            )
            .sheet(isPresented: $showDownloadDialog) {
                downloadDialog
            }
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
        VStack(alignment: .leading, spacing: 4) {
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

            if !viewModel.pageTitle.isEmpty || !viewModel.authorName.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    if !viewModel.pageTitle.isEmpty {
                        Text(viewModel.pageTitle)
                            .font(.caption)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }
                    if !viewModel.authorName.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "person.circle")
                                .font(.caption2)
                                .foregroundColor(.blue)
                            Text(viewModel.authorName)
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                    }
                }
                .padding(.top, 2)
            }
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
            Text("支持 m3u8、mp4、flv、直播源等")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var videoList: some View {
        List {
            ForEach(viewModel.videoSources) { source in
                videoSourceRow(source: source)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                typeIcon(for: source.type)
                    .frame(width: 40, height: 40)
                    .background(typeColor(for: source.type).opacity(0.15))
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 4) {
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

                    Text(source.url)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer()
            }

            HStack(spacing: 8) {
                Button(action: {
                    selectedVideo = source
                    showPlayer = true
                }) {
                    Label("播放", systemImage: "play.circle")
                }
                .font(.caption)
                .buttonStyle(.bordered)

                Button(action: {
                    showDownloadDialog(for: source)
                }) {
                    Label("下载", systemImage: "arrow.down.circle")
                }
                .font(.caption)
                .buttonStyle(.bordered)

                Button(action: {
                    copySource(source)
                }) {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .font(.caption)
                .buttonStyle(.bordered)

                Spacer()

                Menu {
                    Button(action: {
                        if let url = URL(string: source.url) {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        Label("浏览器打开", systemImage: "safari")
                    }
                    Button(action: {
                        let activityVC = UIActivityViewController(activityItems: [source.url], applicationActivities: nil)
                        if let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) {
                            window.rootViewController?.present(activityVC, animated: true)
                        }
                    }) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func typeIcon(for type: String) -> some View {
        let iconName: String
        switch type.lowercased() {
        case "m3u8": iconName = "square.stack.3d.down.right"
        case "mp4": iconName = "film"
        case "flv": iconName = "film.stack"
        case "直播", "live": iconName = "dot.radiowaves.left.and.right"
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
        case "直播", "live": return .red
        default: return .gray
        }
    }

    // MARK: - 下载对话框
    private var downloadDialog: some View {
        NavigationView {
            Form {
                Section(header: Text("文件标题")) {
                    TextField("输入文件标题", text: $downloadTitle)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                if downloadSources.count > 1 {
                    Section(header: Text("选择清晰度")) {
                        ForEach(downloadSources) { source in
                            Button(action: {
                                selectedDownloadSource = source
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
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
                                        Text(source.url)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    if selectedDownloadSource?.id == source.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                            .foregroundColor(.primary)
                        }
                    }
                }

                Section {
                    Button(action: confirmDownload) {
                        HStack {
                            Spacer()
                            Label("开始下载", systemImage: "arrow.down.circle.fill")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                        }
                    }
                    .disabled(downloadTitle.isEmpty || selectedDownloadSource == nil)
                }
            }
            .navigationTitle("下载设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        showDownloadDialog = false
                    }
                }
            }
        }
    }

    private func showDownloadDialog(for source: VideoSource) {
        // 收集同类型的所有源作为清晰度选项
        let sameTypeSources = viewModel.videoSources.filter { $0.type == source.type }
        downloadSources = sameTypeSources.isEmpty ? [source] : sameTypeSources
        selectedDownloadSource = source
        downloadTitle = "视频_\(source.type)_\(source.quality ?? "默认")"
        showDownloadDialog = true
    }

    private func confirmDownload() {
        guard let source = selectedDownloadSource else { return }
        downloadManager.startDownload(url: source.url, title: downloadTitle)
        showDownloadDialog = false
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
        withAnimation {
            showCopiedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopiedToast = false
            }
        }
    }

    private func exportSources() {
        guard !viewModel.videoSources.isEmpty else { return }

        var exportText = "视频源抓取结果\n"
        exportText += "网址: \(viewModel.currentURL)\n"
        exportText += "标题: \(viewModel.pageTitle)\n"
        exportText += "时间: \(Date())\n"
        exportText += "共 \(viewModel.videoSources.count) 个视频源\n\n"
        exportText += String(repeating: "=", count: 50) + "\n\n"

        for (index, source) in viewModel.videoSources.enumerated() {
            exportText += "【\(index + 1)】类型: \(source.type.uppercased())"
            if let quality = source.quality {
                exportText += " | 画质: \(quality)"
            }
            exportText += "\n\(source.url)\n\n"
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("视频源列表.txt")
        do {
            try exportText.write(to: tempURL, atomically: true, encoding: .utf8)
            let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
            if let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) {
                window.rootViewController?.present(activityVC, animated: true)
            }
        } catch {
            print("导出失败: \(error)")
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
