import Foundation
import UIKit
import Combine

struct DownloadItem: Identifiable {
    let id = UUID()
    let url: String
    let title: String
    var progress: Double = 0
    var status: DownloadStatus = .waiting
    var localPath: URL?
    var fileSize: Int64 = 0
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

    private override init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: "com.sourcegrabber.downloads")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func startDownload(url: String, title: String) {
        guard let downloadURL = URL(string: url) else { return }

        let item = DownloadItem(url: url, title: title, status: .waiting)
        downloads.append(item)

        let task = session.downloadTask(with: downloadURL)
        tasks[task] = item.id
        task.resume()

        updateItem(id: item.id) { item in
            item.status = .downloading
        }
    }

    func pauseDownload(id: UUID) {
        guard let index = downloads.firstIndex(where: { $0.id == id }),
              let task = tasks.first(where: { $0.value == id })?.key else { return }

        task.suspend()
        downloads[index].status = .paused
    }

    func resumeDownload(id: UUID) {
        guard let index = downloads.firstIndex(where: { $0.id == id }),
              let task = tasks.first(where: { $0.value == id })?.key else { return }

        task.resume()
        downloads[index].status = .downloading
    }

    func cancelDownload(id: UUID) {
        guard let index = downloads.firstIndex(where: { $0.id == id }),
              let task = tasks.first(where: { $0.value == id })?.key else { return }

        task.cancel()
        tasks.removeValue(forKey: task)
        downloads.remove(at: index)
    }

    func removeDownload(id: UUID) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        let item = downloads[index]

        if let localPath = item.localPath {
            try? FileManager.default.removeItem(at: localPath)
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

extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let itemID = tasks[downloadTask] else { return }

        let fileName = downloadTask.originalRequest?.url?.lastPathComponent ?? "video.mp4"
        let safeFileName = fileName.replacingOccurrences(of: "/", with: "_")
        let destinationURL = getDocumentsDirectory().appendingPathComponent(safeFileName)

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
