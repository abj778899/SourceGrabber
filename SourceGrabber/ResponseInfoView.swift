import SwiftUI

struct ResponseInfoView: View {
    @ObservedObject var viewModel: VideoSourceViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("基本信息")) {
                    infoRow(title: "状态码", value: "\(viewModel.statusCode) \(statusDescription)")
                    infoRow(title: "请求URL", value: viewModel.currentURL)
                    infoRow(title: "页面标题", value: viewModel.pageTitle)
                    infoRow(title: "视频源数量", value: "\(viewModel.videoSources.count) 个")
                    infoRow(title: "内容大小", value: formattedSize)
                    infoRow(title: "耗时", value: String(format: "%.2f 秒", viewModel.fetchTime))
                }

                Section(header: Text("响应头 (\(viewModel.responseHeaders.count) 项)")) {
                    ForEach(Array(viewModel.responseHeaders.keys.sorted()), id: \.self) { key in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(key)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                            Text(viewModel.responseHeaders[key] ?? "")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("响应信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var statusDescription: String {
        switch viewModel.statusCode {
        case 200: return "OK"
        case 301: return "Moved Permanently"
        case 302: return "Found"
        case 304: return "Not Modified"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        default: return ""
        }
    }

    private var formattedSize: String {
        let bytes = viewModel.contentSize
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.2f KB", Double(bytes) / 1024) }
        return String(format: "%.2f MB", Double(bytes) / (1024 * 1024))
    }

    private func infoRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }
}
