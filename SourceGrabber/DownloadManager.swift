import Foundation
import UIKit
import Combine

struct DownloadItem: Identifiable {
    let id = UUID()
    let url: String
    var title: String
    var progress: Double = 0
    var status: DownloadStatus = .waiting
    var localPath: URL?
    var fileSize: Int64 = 0
    var isM3U8: Bool = false
    var totalSegments: Int = 0
    var downloadedSegments: Int = 0
}

enum DownloadStatus: String {
    case waiting = "等待中"
    case downloading = "下载中"
    case completed = "已完成"
    case failed = "失败"
    case paused = "已暂停"
}

class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    @Published var downloads: [DownloadItem] = []
    private var session: URLSession!
    private var tasks: [URLSessionDownloadTask: UUID] = [:]
    private var m3u8Downloads: [UUID: M3U8Downloader] = [:]

    private override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.isDiscretionary = false
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func startDownload(url: String, title: String) {
        let isM3U8 = url.lowercased().contains(".m3u8")

        var item = DownloadItem(url: url, title: title, status: .waiting)
        item.isM3U8 = isM3U8
        downloads.append(item)

        if isM3U8 {
            // m3u8下载
            let downloader = M3U8Downloader(url: url, title: title) { [weak self] progress, status, localPath in
                DispatchQueue.main.async {
                    if let index = self?.downloads.firstIndex(where: { $0.id == item.id }) {
                        self?.downloads[index].progress = progress
                        self?.downloads[index].status = status
                        if let localPath = localPath {
                            self?.downloads[index].localPath = localPath
                        }
                    }
                }
            }
            m3u8Downloads[item.id] = downloader
            downloader.start()
        } else {
            // 普通文件下载
            guard let downloadURL = URL(string: url) else {
                updateItem(id: item.id) { $0.status = .failed }
                return
            }

            var request = URLRequest(url: downloadURL)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

            // 添加Referer
            if let referer = getReferer(for: url) {
                request.setValue(referer, forHTTPHeaderField: "Referer")
            }

            let task = session.downloadTask(with: request)
            tasks[task] = item.id
            task.resume()

            updateItem(id: item.id) { $0.status = .downloading }
        }
    }

    private func getReferer(for url: String) -> String? {
        if url.contains("douyin") || url.contains("douyinvod") || url.contains("douyincdn") {
            return "https://www.douyin.com/"
        } else if url.contains("kuaishou") || url.contains("ksyun") {
            return "https://www.kuaishou.com/"
        } else if url.contains("bilibili") || url.contains("hdslb") {
            return "https://www.bilibili.com/"
        }
        return nil
    }

    func pauseDownload(id: UUID) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }

        if downloads[index].isM3U8 {
            m3u8Downloads[id]?.pause()
        } else {
            guard let task = tasks.first(where: { $0.value == id })?.key else { return }
            task.suspend()
        }
        downloads[index].status = .paused
    }

    func resumeDownload(id: UUID) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }

        if downloads[index].isM3U8 {
            m3u8Downloads[id]?.resume()
        } else {
            guard let task = tasks.first(where: { $0.value == id })?.key else { return }
            task.resume()
        }
        downloads[index].status = .downloading
    }

    func cancelDownload(id: UUID) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }

        if downloads[index].isM3U8 {
            m3u8Downloads[id]?.cancel()
            m3u8Downloads.removeValue(forKey: id)
        } else {
            guard let task = tasks.first(where: { $0.value == id })?.key else { return }
            task.cancel()
            tasks.removeValue(forKey: task)
        }
        downloads.remove(at: index)
    }

    func removeDownload(id: UUID) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        let item = downloads[index]

        if let localPath = item.localPath {
            try? FileManager.default.removeItem(at: localPath)
        }

        if item.isM3U8 {
            m3u8Downloads.removeValue(forKey: id)
        }

        downloads.remove(at: index)
    }

    func shareDownload(id: UUID) {
        guard let index = downloads.firstIndex(where: { $0.id == id }),
              let localPath = downloads[index].localPath else { return }

        let activityVC = UIActivityViewController(activityItems: [localPath], applicationActivities: nil)
        if let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) {
            window.rootViewController?.present(activityVC, animated: true)
        }
    }

    func saveToPhotos(id: UUID) {
        guard let index = downloads.firstIndex(where: { $0.id == id }),
              let localPath = downloads[index].localPath else { return }

        if UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(localPath.path) {
            UISaveVideoAtPathToSavedPhotosAlbum(localPath.path, nil, nil, nil)
        }
    }

    private func updateItem(id: UUID, update: (inout DownloadItem) -> Void) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        update(&downloads[index])
    }

    private func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let downloadsDir = paths[0].appendingPathComponent("Downloads", isDirectory: true)
        if !FileManager.default.fileExists(atPath: downloadsDir.path) {
            try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        }
        return downloadsDir
    }
}

// MARK: - M3U8下载器
class M3U8Downloader: NSObject, URLSessionDownloadDelegate {
    private let url: String
    private let title: String
    private let progressHandler: (Double, DownloadStatus, URL?) -> Void
    private var session: URLSession!
    private var segments: [String] = []
    private var downloadedSegments: Int = 0
    private var totalSegments: Int = 0
    private var isPaused = false
    private var isCancelled = false
    private var currentTask: URLSessionDownloadTask?
    private var tempDir: URL!

    init(url: String, title: String, progressHandler: @escaping (Double, DownloadStatus, URL?) -> Void) {
        self.url = url
        self.title = title
        self.progressHandler = progressHandler
        super.init()
        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func start() {
        // 创建临时目录
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // 下载m3u8播放列表
        guard let playlistURL = URL(string: url) else {
            progressHandler(0, .failed, nil)
            return
        }

        var request = URLRequest(url: playlistURL)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

        // 添加Referer
        if let referer = getReferer(for: url) {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }

        let task = session.downloadTask(with: request)
        task.resume()
    }

    private func getReferer(for url: String) -> String? {
        if url.contains("douyin") || url.contains("douyinvod") || url.contains("douyincdn") {
            return "https://www.douyin.com/"
        } else if url.contains("kuaishou") || url.contains("ksyun") {
            return "https://www.kuaishou.com/"
        } else if url.contains("bilibili") || url.contains("hdslb") {
            return "https://www.bilibili.com/"
        }
        return nil
    }

    func pause() {
        isPaused = true
        currentTask?.suspend()
    }

    func resume() {
        isPaused = false
        currentTask?.resume()
        downloadNextSegment()
    }

    func cancel() {
        isCancelled = true
        currentTask?.cancel()
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func parseM3U8(_ fileURL: URL) {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            progressHandler(0, .failed, nil)
            return
        }

        let lines = content.components(separatedBy: .newlines)
        var baseURL = url
        if let range = baseURL.range(of: "/", options: .backwards) {
            baseURL = String(baseURL[..<range.upperBound])
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("#") || trimmed.isEmpty {
                continue
            }
            if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                segments.append(trimmed)
            } else {
                segments.append(baseURL + trimmed)
            }
        }

        totalSegments = segments.count
        downloadedSegments = 0

        if segments.isEmpty {
            progressHandler(0, .failed, nil)
            return
        }

        downloadNextSegment()
    }

    private func downloadNextSegment() {
        guard !isCancelled && !isPaused && downloadedSegments < segments.count else {
            if downloadedSegments >= segments.count && totalSegments > 0 {
                mergeSegments()
            }
            return
        }

        let segmentURL = segments[downloadedSegments]
        guard let url = URL(string: segmentURL) else {
            downloadedSegments += 1
            downloadNextSegment()
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

        // 添加Referer
        if let referer = getReferer(for: segmentURL) {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }

        currentTask = session.downloadTask(with: request)
        currentTask?.resume()
    }

    private func mergeSegments() {
        // 清理标题中的特殊字符
        let safeTitle = title.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "*", with: "_")
            .replacingOccurrences(of: "?", with: "_")
            .replacingOccurrences(of: "\"", with: "_")
            .replacingOccurrences(of: "<", with: "_")
            .replacingOccurrences(of: ">", with: "_")
            .replacingOccurrences(of: "|", with: "_")
            .replacingOccurrences(of: "。", with: "")
            .replacingOccurrences(of: "，", with: "")
            .replacingOccurrences(of: "、", with: "")

        let outputURL = getDocumentsDirectory().appendingPathComponent("\(safeTitle).ts")

        // 如果文件已存在，先删除
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        // 创建空文件
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)

        guard let handle = try? FileHandle(forWritingTo: outputURL) else {
            progressHandler(0, .failed, nil)
            return
        }

        // 依次写入所有ts分片
        for i in 0..<totalSegments {
            let segmentFile = tempDir.appendingPathComponent("segment_\(i).ts")
            if let data = try? Data(contentsOf: segmentFile) {
                handle.write(data)
            }
        }

        handle.closeFile()

        // 清理临时文件
        try? FileManager.default.removeItem(at: tempDir)

        progressHandler(1.0, .completed, outputURL)
    }

    private func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let downloadsDir = paths[0].appendingPathComponent("Downloads", isDirectory: true)
        if !FileManager.default.fileExists(atPath: downloadsDir.path) {
            try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        }
        return downloadsDir
    }

    // MARK: - URLSessionDownloadDelegate
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if segments.isEmpty {
            // 这是m3u8播放列表
            parseM3U8(location)
        } else {
            // 这是ts分片
            let segmentFile = tempDir.appendingPathComponent("segment_\(downloadedSegments).ts")
            try? FileManager.default.moveItem(at: location, to: segmentFile)
            downloadedSegments += 1

            let progress = Double(downloadedSegments) / Double(totalSegments)
            progressHandler(progress, .downloading, nil)

            downloadNextSegment()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        // 对于ts分片，进度已经通过分片数量计算
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error != nil && !isCancelled {
            if segments.isEmpty {
                progressHandler(0, .failed, nil)
            } else {
                // 跳过失败的分片
                downloadedSegments += 1
                downloadNextSegment()
            }
        }
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let itemID = tasks[downloadTask],
              let itemIndex = downloads.firstIndex(where: { $0.id == itemID }) else { return }

        let item = downloads[itemIndex]
        let fileExtension = downloadTask.originalRequest?.url?.pathExtension ?? "mp4"
        let safeTitle = item.title.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "*", with: "_")
            .replacingOccurrences(of: "?", with: "_")
            .replacingOccurrences(of: "\"", with: "_")
            .replacingOccurrences(of: "<", with: "_")
            .replacingOccurrences(of: ">", with: "_")
            .replacingOccurrences(of: "|", with: "_")
        let fileName = "\(safeTitle).\(fileExtension)"
        let destinationURL = getDocumentsDirectory().appendingPathComponent(fileName)

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: location, to: destinationURL)

            DispatchQueue.main.async {
                self.updateItem(id: itemID) { item in
                    item.status = .completed
                    item.localPath = destinationURL
                    item.progress = 1.0
                }
                self.tasks.removeValue(forKey: downloadTask)
            }
        } catch {
            DispatchQueue.main.async {
                self.updateItem(id: itemID) { item in
                    item.status = .failed
                }
                self.tasks.removeValue(forKey: downloadTask)
            }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let itemID = tasks[downloadTask] else { return }

        let progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0

        DispatchQueue.main.async {
            self.updateItem(id: itemID) { item in
                item.progress = progress
                item.fileSize = totalBytesExpectedToWrite
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let downloadTask = task as? URLSessionDownloadTask,
              let itemID = tasks[downloadTask],
              error != nil else { return }

        DispatchQueue.main.async {
            self.updateItem(id: itemID) { item in
                item.status = .failed
            }
            self.tasks.removeValue(forKey: downloadTask)
        }
    }
}
