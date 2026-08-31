import Foundation
import Combine
import UIKit

struct VideoSource: Identifiable, Hashable {
    let id = UUID()
    let url: String
    let type: String
    let quality: String?
}

class VideoSourceViewModel: ObservableObject {
    @Published var videoSources: [VideoSource] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var currentURL: String = ""
    @Published var pageTitle: String = ""
    @Published var responseHeaders: [String: String] = [:]
    @Published var statusCode: Int = 0
    @Published var contentSize: Int = 0
    @Published var fetchTime: TimeInterval = 0

    private var cancellables = Set<AnyCancellable>()

    var customUserAgent: String {
        get { UserDefaults.standard.string(forKey: "customUserAgent") ?? "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1" }
        set { UserDefaults.standard.set(newValue, forKey: "customUserAgent") }
    }

    func fetchVideoSources(from urlString: String) {
        guard let url = URL(string: normalizeURL(urlString)) else {
            errorMessage = "无效的URL地址"
            return
        }

        isLoading = true
        errorMessage = nil
        videoSources = []
        responseHeaders = [:]
        statusCode = 0
        currentURL = url.absoluteString
        pageTitle = ""

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(customUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 30

        let startTime = Date()

        URLSession.shared.dataTaskPublisher(for: request)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                guard let self = self else { return }
                self.isLoading = false
                if case .failure(let error) = completion {
                    self.errorMessage = "请求失败: \(error.localizedDescription)"
                }
            }, receiveValue: { [weak self] data, response in
                guard let self = self else { return }
                self.fetchTime = Date().timeIntervalSince(startTime)
                self.contentSize = data.count

                if let httpResponse = response as? HTTPURLResponse {
                    self.statusCode = httpResponse.statusCode
                    self.responseHeaders = httpResponse.allHeaderFields as? [String: String] ?? [:]
                }

                let html = self.decodeHTML(data: data, response: response)
                self.pageTitle = self.extractTitle(from: html)
                self.videoSources = self.extractVideoSources(from: html, baseURL: url)

                if self.videoSources.isEmpty {
                    self.errorMessage = "未在页面中找到视频源地址"
                }
            })
            .store(in: &cancellables)
    }

    func cancelFetch() {
        cancellables.forEach { $0.cancel() }
        isLoading = false
    }

    private func normalizeURL(_ urlString: String) -> String {
        var trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.hasPrefix("http://") && !trimmed.hasPrefix("https://") {
            trimmed = "https://" + trimmed
        }
        return trimmed
    }

    private func decodeHTML(data: Data, response: URLResponse) -> String {
        if let charset = response.textEncodingName {
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
            if cfEncoding != kCFStringEncodingInvalidId {
                let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
                if let str = String(data: data, encoding: String.Encoding(rawValue: nsEncoding)) {
                    return str
                }
            }
        }
        if let str = String(data: data, encoding: .utf8) {
            return str
        }
        if let str = String(data: data, encoding: .gbk) {
            return str
        }
        let cfEncoding = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        if let str = String(data: data, encoding: String.Encoding(rawValue: cfEncoding)) {
            return str
        }
        return ""
    }

    private func extractTitle(from html: String) -> String {
        guard let range = html.range(of: "<title[^>]*>(.*?)</title>", options: .regularExpression, range: nil, locale: nil) else {
            return ""
        }
        let title = String(html[range])
            .replacingOccurrences(of: "<title[^>]*>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "</title>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title
    }

    private func extractVideoSources(from html: String, baseURL: URL) -> [VideoSource] {
        var sources: [VideoSource] = []
        var seenURLs = Set<String>()

        // 1. 提取 <video> 标签的 src
        let videoSrcPattern = "<video[^>]*src\\s*=\\s*[\"']([^\"']+)[\"']"
        sources.append(contentsOf: extractWithPattern(videoSrcPattern, type: "video", html: html, baseURL: baseURL, seen: &seenURLs))

        // 2. 提取 <source> 标签的 src
        let sourceSrcPattern = "<source[^>]*src\\s*=\\s*[\"']([^\"']+)[\"']"
        sources.append(contentsOf: extractWithPattern(sourceSrcPattern, type: "source", html: html, baseURL: baseURL, seen: &seenURLs))

        // 3. 提取 m3u8 地址
        let m3u8Pattern = "[\"']([^\"']+\\.m3u8[^\"']*)[\"']"
        sources.append(contentsOf: extractWithPattern(m3u8Pattern, type: "m3u8", html: html, baseURL: baseURL, seen: &seenURLs))

        // 4. 提取 mp4 地址
        let mp4Pattern = "[\"']([^\"']+\\.mp4[^\"']*)[\"']"
        sources.append(contentsOf: extractWithPattern(mp4Pattern, type: "mp4", html: html, baseURL: baseURL, seen: &seenURLs))

        // 5. 提取 flv 地址
        let flvPattern = "[\"']([^\"']+\\.flv[^\"']*)[\"']"
        sources.append(contentsOf: extractWithPattern(flvPattern, type: "flv", html: html, baseURL: baseURL, seen: &seenURLs))

        // 6. 提取 m3u8 索引（不带扩展名的常见模式）
        let indexM3u8Pattern = "[\"']([^\"']*index\\.m3u8[^\"']*)[\"']"
        sources.append(contentsOf: extractWithPattern(indexM3u8Pattern, type: "m3u8", html: html, baseURL: baseURL, seen: &seenURLs))

        // 7. 提取常见播放器配置中的视频地址（如 url: 'xxx'）
        let playerUrlPattern = "(?:url|src|videoUrl|playUrl|mediaUrl)\\s*[:=]\\s*[\"']([^\"']+)[\"']"
        sources.append(contentsOf: extractWithPattern(playerUrlPattern, type: "player", html: html, baseURL: baseURL, seen: &seenURLs))

        // 8. 提取 HLS 流媒体地址（.m3u8? 带参数）
        let hlsPattern = "https?://[^\"'\\s]+\\.m3u8[^\"'\\s]*"
        if let regex = try? NSRegularExpression(pattern: hlsPattern, options: .caseInsensitive) {
            let nsRange = NSRange(html.startIndex..., in: html)
            regex.enumerateMatches(in: html, options: [], range: nsRange) { match, _, _ in
                if let range = match?.range, let swiftRange = Range(range, in: html) {
                    let url = String(html[swiftRange])
                    if !seenURLs.contains(url) {
                        seenURLs.insert(url)
                        sources.append(VideoSource(url: url, type: "m3u8", quality: nil))
                    }
                }
            }
        }

        // 9. 提取直接的 mp4 链接
        let directMp4Pattern = "https?://[^\"'\\s]+\\.mp4[^\"'\\s]*"
        if let regex = try? NSRegularExpression(pattern: directMp4Pattern, options: .caseInsensitive) {
            let nsRange = NSRange(html.startIndex..., in: html)
            regex.enumerateMatches(in: html, options: [], range: nsRange) { match, _, _ in
                if let range = match?.range, let swiftRange = Range(range, in: html) {
                    let url = String(html[swiftRange])
                    if !seenURLs.contains(url) {
                        seenURLs.insert(url)
                        sources.append(VideoSource(url: url, type: "mp4", quality: nil))
                    }
                }
            }
        }

        return sources
    }

    private func extractWithPattern(_ pattern: String, type: String, html: String, baseURL: URL, seen: inout Set<String>) -> [VideoSource] {
        var sources: [VideoSource] = []
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return sources
        }

        let nsRange = NSRange(html.startIndex..., in: html)
        regex.enumerateMatches(in: html, options: [], range: nsRange) { match, _, _ in
            guard let match = match, match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: html) else {
                return
            }
            let rawURL = String(html[range])
            let absoluteURL = resolveURL(rawURL, baseURL: baseURL)
            if !seen.contains(absoluteURL) && isValidVideoURL(absoluteURL) {
                seen.insert(absoluteURL)
                let quality = extractQuality(from: rawURL)
                sources.append(VideoSource(url: absoluteURL, type: type, quality: quality))
            }
        }
        return sources
    }

    private func resolveURL(_ rawURL: String, baseURL: URL) -> String {
        if rawURL.hasPrefix("http://") || rawURL.hasPrefix("https://") {
            return rawURL
        }
        if rawURL.hasPrefix("//") {
            return "https:" + rawURL
        }
        if rawURL.hasPrefix("/") {
            if let host = baseURL.host {
                return "\(baseURL.scheme ?? "https")://\(host)\(rawURL)"
            }
            return rawURL
        }
        return baseURL.deletingLastPathComponent().appendingPathComponent(rawURL).absoluteString
    }

    private func isValidVideoURL(_ url: String) -> Bool {
        let lowercased = url.lowercased()
        return lowercased.contains(".m3u8") ||
               lowercased.contains(".mp4") ||
               lowercased.contains(".flv") ||
               lowercased.contains(".ts") ||
               lowercased.contains(".mov") ||
               lowercased.contains(".webm") ||
               lowercased.contains(".m4v") ||
               lowercased.contains("playlist") ||
               lowercased.contains("video")
    }

    private func extractQuality(from url: String) -> String? {
        let lowercased = url.lowercased()
        if lowercased.contains("1080p") || lowercased.contains("1920x1080") { return "1080P" }
        if lowercased.contains("720p") || lowercased.contains("1280x720") { return "720P" }
        if lowercased.contains("480p") || lowercased.contains("854x480") { return "480P" }
        if lowercased.contains("360p") || lowercased.contains("640x360") { return "360P" }
        if lowercased.contains("240p") { return "240P" }
        if lowercased.contains("hd") { return "HD" }
        if lowercased.contains("sd") { return "SD" }
        return nil
    }

    func copySource(_ source: VideoSource) {
        UIPasteboard.general.string = source.url
    }

    func shareSource(_ source: VideoSource) -> URL? {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("video_url.txt")
        do {
            try source.url.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            return nil
        }
    }
}
