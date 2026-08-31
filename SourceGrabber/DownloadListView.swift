import SwiftUI

struct DownloadListView: View {
    @StateObject private var downloadManager = DownloadManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Group {
                if downloadManager.downloads.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("暂无下载任务")
                            .foregroundColor(.secondary)
                        Text("在视频源列表中点下载按钮开始下载")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    List {
                        ForEach(downloadManager.downloads) { item in
                            downloadRow(item: item)
                        }
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("下载管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func downloadRow(item: DownloadItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: statusIcon(for: item.status))
                    .foregroundColor(statusColor(for: item.status))
                Text(item.title)
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer()
                Text(item.status.rawValue)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if item.status == .downloading {
                ProgressView(value: item.progress)
                    .progressViewStyle(LinearProgressViewStyle())
                HStack {
                    Text("\(Int(item.progress * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    if item.fileSize > 0 {
                        Text(formatSize(item.fileSize))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            HStack(spacing: 12) {
                if item.status == .downloading {
                    Button(action: { downloadManager.pauseDownload(id: item.id) }) {
                        Label("暂停", systemImage: "pause")
                    }
                    .font(.caption)
                }

                if item.status == .paused {
                    Button(action: { downloadManager.resumeDownload(id: item.id) }) {
                        Label("继续", systemImage: "play")
                    }
                    .font(.caption)
                }

                if item.status == .completed {
                    Button(action: { downloadManager.shareDownload(id: item.id) }) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                    .font(.caption)

                    Button(action: { downloadManager.saveToPhotos(id: item.id) }) {
                        Label("保存到相册", systemImage: "photo")
                    }
                    .font(.caption)
                }

                Spacer()

                Button(role: .destructive, action: {
                    if item.status == .downloading || item.status == .paused {
                        downloadManager.cancelDownload(id: item.id)
                    } else {
                        downloadManager.removeDownload(id: item.id)
                    }
                }) {
                    Label("删除", systemImage: "trash")
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 8)
    }

    private func statusIcon(for status: DownloadStatus) -> String {
        switch status {
        case .waiting: return "clock"
        case .downloading: return "arrow.down.circle"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .paused: return "pause.circle"
        }
    }

    private func statusColor(for status: DownloadStatus) -> Color {
        switch status {
        case .waiting: return .gray
        case .downloading: return .blue
        case .completed: return .green
        case .failed: return .red
        case .paused: return .orange
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        if bytes < 1024 * 1024 * 1024 { return String(format: "%.1f MB", Double(bytes) / (1024 * 1024)) }
        return String(format: "%.1f GB", Double(bytes) / (1024 * 1024 * 1024))
    }
}
