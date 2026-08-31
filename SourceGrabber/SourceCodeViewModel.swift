import Foundation
import Combine
import UIKit

struct VideoSource: Identifiable, Hashable {
    let id = UUID()
    let url: String
    let type: String
    let quality: String?
    let qualityScore: Int
}

class VideoSourceViewModel: ObservableObject {
    @Published var videoSources: [VideoSource] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var currentURL: String = ""
    @Published var pageTitle: String = ""
    @Published var authorName: String = ""
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
        authorName = ""

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
                self.authorName = self.extractAuthor(from: html, url: url)
                self.videoSources = self.extractVideoSources(from: html, baseURL: url)

                if self.videoSources.isEmpty {
                    self.errorMessage = "未在页面中找到有效的视频源地址"
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

    private func extractAuthor(from html: String, url: URL) -> String {
        // 1. 抖音: 从 <script> 中的 JSON 数据提取 nickname
        if url.host?.contains("douyin") == true || url.host?.contains("iesdouyin") == true {
            if let nickname = extractJSONField(from: html, field: "nickname") {
                return nickname
            }
            if let author = extractJSONField(from: html, field: "author") {
                return author
            }
        }

        // 2. 快手
        if url.host?.contains("kuaishou") == true {
            if let nickname = extractJSONField(from: html, field: "nickname") {
                return nickname
            }
            if let userName = extractJSONField(from: html, field: "user_name") {
                return userName
            }
        }

        // 3. B站
        if url.host?.contains("bilibili") == true {
            if let owner = extractJSONField(from: html, field: "owner") {
                if let name = extractJSONField(from: owner, field: "name") {
                    return name
                }
            }
            if let upName = extractMetaContent(from: html, name: "author") {
                return upName
            }
        }

        // 4. 通用: meta标签
        if let author = extractMetaContent(from: html, name: "author") {
            return author
        }
        if let author = extractMetaContent(from: html, property: "og:article:author") {
            return author
        }
        if let author = extractMetaContent(from: html, name: "keywords") {
            return author
        }

        // 5. 从title中提取（很多平台 title 格式是 "标题 - 作者"）
        let title = extractTitle(from: html)
        if title.contains("-") {
            let parts = title.components(separatedBy: "-")
            if parts.count >= 2 {
                let author = parts.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if author.count > 0 && author.count < 30 {
                    return author
                }
            }
        }

        return ""
    }

    private func extractJSONField(from jsonString: String, field: String) -> String? {
        let pattern = "\"\(field)\"\\s*:\\s*\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsRange = NSRange(jsonString.startIndex..., in: jsonString)
        if let match = regex.firstMatch(in: jsonString, options: [], range: nsRange),
           let range = Range(match.range(at: 1), in: jsonString) {
            return String(jsonString[range])
        }
        return nil
    }

    private func extractMetaContent(from html: String, name: String) -> String? {
        let pattern = "<meta[^>]*name\\s*=\\s*[\"\']\(name)[\"\'][^>]*content\\s*=\\s*[\"\']([^\"\']+)[\"\']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let nsRange = NSRange(html.startIndex..., in: html)
        if let match = regex.firstMatch(in: html, options: [], range: nsRange),
           let range = Range(match.range(at: 1), in: html) {
            return String(html[range])
        }
        return nil
    }

    private func extractMetaContent(from html: String, property: String) -> String? {
        let pattern = "<meta[^>]*property\\s*=\\s*[\"\']\(property)[\"\'][^>]*content\\s*=\\s*[\"\']([^\"\']+)[\"\']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let nsRange = NSRange(html.startIndex..., in: html)
        if let match = regex.firstMatch(in: html, options: [], range: nsRange),
           let range = Range(match.range(at: 1), in: html) {
            return String(html[range])
        }
        return nil
    }

    private func extractVideoSources(from html: String, baseURL: URL) -> [VideoSource] {
        var sources: [VideoSource] = []
        var seenURLs = Set<String>()

        // 先解码HTML实体，避免抓取到被转义的URL
        let decodedHTML = decodeHTMLEntities(html)

        // 1. 提取 m3u8 地址（优先，因为通常是真正的视频源）
        let m3u8Pattern = "[\"']([^\"']+\\.m3u8[^\"']*)[\"']"
        sources.append(contentsOf: extractWithPattern(m3u8Pattern, type: "m3u8", html: decodedHTML, baseURL: baseURL, seen: &seenURLs))

        // 2. 提取 mp4 地址
        let mp4Pattern = "[\"']([^\"']+\\.mp4[^\"']*)[\"']"
        sources.append(contentsOf: extractWithPattern(mp4Pattern, type: "mp4", html: decodedHTML, baseURL: baseURL, seen: &seenURLs))

        // 3. 提取 flv 地址
        let flvPattern = "[\"']([^\"']+\\.flv[^\"']*)[\"']"
        sources.append(contentsOf: extractWithPattern(flvPattern, type: "flv", html: decodedHTML, baseURL: baseURL, seen: &seenURLs))

        // 4. 提取 <video> 标签的 src
        let videoSrcPattern = "<video[^>]*src\\s*=\\s*[\"']([^\"']+)[\"']"
        sources.append(contentsOf: extractWithPattern(videoSrcPattern, type: "video", html: decodedHTML, baseURL: baseURL, seen: &seenURLs))

        // 5. 提取 <source> 标签的 src
        let sourceSrcPattern = "<source[^>]*src\\s*=\\s*[\"']([^\"']+)[\"']"
        sources.append(contentsOf: extractWithPattern(sourceSrcPattern, type: "source", html: decodedHTML, baseURL: baseURL, seen: &seenURLs))

        // 6. 提取常见播放器配置中的视频地址
        let playerUrlPattern = "(?:url|src|videoUrl|playUrl|mediaUrl|play_url|main_url)\\s*[:=]\\s*[\"']([^\"']+)[\"']"
        sources.append(contentsOf: extractWithPattern(playerUrlPattern, type: "player", html: decodedHTML, baseURL: baseURL, seen: &seenURLs))

        // 7. 直接提取完整的URL（带http/https）
        let directURLPattern = "https?://[^\"'\\s<>]+\\.(?:m3u8|mp4|flv|ts|mov|m4v|webm)[^\"'\\s<>]*"
        if let regex = try? NSRegularExpression(pattern: directURLPattern, options: .caseInsensitive) {
            let nsRange = NSRange(decodedHTML.startIndex..., in: decodedHTML)
            regex.enumerateMatches(in: decodedHTML, options: [], range: nsRange) { match, _, _ in
                if let range = match?.range, let swiftRange = Range(range, in: decodedHTML) {
                    let url = String(decodedHTML[swiftRange])
                    let cleanURL = cleanVideoURL(url)
                    if !seenURLs.contains(cleanURL) && isValidVideoURL(cleanURL) {
                        seenURLs.insert(cleanURL)
                        let type = detectType(from: cleanURL)
                        let quality = extractQuality(from: cleanURL)
                        let score = qualityScore(for: quality)
                        sources.append(VideoSource(url: cleanURL, type: type, quality: quality, qualityScore: score))
                    }
                }
            }
        }

        // 按质量排序（高清优先）
        sources.sort { $0.qualityScore > $1.qualityScore }

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
            let cleanURL = cleanVideoURL(rawURL)
            let absoluteURL = resolveURL(cleanURL, baseURL: baseURL)
            if !seen.contains(absoluteURL) && isValidVideoURL(absoluteURL) {
                seen.insert(absoluteURL)
                let quality = extractQuality(from: absoluteURL)
                let score = qualityScore(for: quality)
                sources.append(VideoSource(url: absoluteURL, type: type, quality: quality, qualityScore: score))
            }
        }
        return sources
    }

    private func cleanVideoURL(_ url: String) -> String {
        var clean = url
        // 移除HTML实体
        clean = clean.replacingOccurrences(of: "&amp;", with: "&")
        clean = clean.replacingOccurrences(of: "&quot;", with: "\"")
        clean = clean.replacingOccurrences(of: "&#39;", with: "'")
        clean = clean.replacingOccurrences(of: "&lt;", with: "<")
        clean = clean.replacingOccurrences(of: "&gt;", with: ">")
        // 移除URL编码的引号和尖括号
        clean = clean.replacingOccurrences(of: "%22", with: "")
        clean = clean.replacingOccurrences(of: "%3C", with: "")
        clean = clean.replacingOccurrences(of: "%3E", with: "")
        // 移除尾部的特殊字符
        clean = clean.trimmingCharacters(in: CharacterSet(charactersIn: "\"'<> \t\n\r"))
        return clean
    }

    private func decodeHTMLEntities(_ html: String) -> String {
        var result = html
        result = result.replacingOccurrences(of: "\\u002F", with: "/")
        result = result.replacingOccurrences(of: "\\/", with: "/")
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        return result
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

        // 必须是http或https开头
        if !lowercased.hasPrefix("http://") && !lowercased.hasPrefix("https://") {
            return false
        }

        // 必须包含视频扩展名或视频相关关键词
        let hasVideoExt = lowercased.contains(".m3u8") ||
                          lowercased.contains(".mp4") ||
                          lowercased.contains(".flv") ||
                          lowercased.contains(".ts") ||
                          lowercased.contains(".mov") ||
                          lowercased.contains(".m4v") ||
                          lowercased.contains(".webm")

        if !hasVideoExt {
            return false
        }

        // 过滤掉包含HTML标签的URL
        if url.contains("<") || url.contains(">") {
            return false
        }

        // 过滤掉包含引号的URL（未正确清理的）
        if url.contains("\"") || url.contains("'") {
            return false
        }

        // 过滤掉明显是CSS/JS的URL
        if lowercased.contains(".css") || lowercased.contains(".js") {
            return false
        }

        // 过滤掉图片URL
        if lowercased.contains(".jpg") || lowercased.contains(".jpeg") ||
           lowercased.contains(".png") || lowercased.contains(".gif") ||
           lowercased.contains(".webp") || lowercased.contains(".svg") {
            return false
        }

        // URL长度合理（太短可能是无效的）
        if url.count < 15 {
            return false
        }

        return true
    }

    private func detectType(from url: String) -> String {
        let lowercased = url.lowercased()
        if lowercased.contains(".m3u8") { return "m3u8" }
        if lowercased.contains(".mp4") { return "mp4" }
        if lowercased.contains(".flv") { return "flv" }
        if lowercased.contains(".ts") { return "ts" }
        if lowercased.contains(".mov") { return "mov" }
        if lowercased.contains(".m4v") { return "m4v" }
        if lowercased.contains(".webm") { return "webm" }
        return "video"
    }

    private func extractQuality(from url: String) -> String? {
        let lowercased = url.lowercased()
        if lowercased.contains("1080p") || lowercased.contains("1920x1080") || lowercased.contains("_1080") { return "1080P" }
        if lowercased.contains("720p") || lowercased.contains("1280x720") || lowercased.contains("_720") { return "720P" }
        if lowercased.contains("480p") || lowercased.contains("854x480") || lowercased.contains("_480") { return "480P" }
        if lowercased.contains("360p") || lowercased.contains("640x360") || lowercased.contains("_360") { return "360P" }
        if lowercased.contains("240p") || lowercased.contains("_240") { return "240P" }
        if lowercased.contains("hd") || lowercased.contains("_hd") { return "HD" }
        if lowercased.contains("sd") || lowercased.contains("_sd") { return "SD" }
        if lowercased.contains("ld") || lowercased.contains("_ld") { return "LD" }
        return nil
    }

    private func qualityScore(for quality: String?) -> Int {
        guard let quality = quality?.lowercased() else { return 0 }
        if quality.contains("1080") { return 100 }
        if quality.contains("720") { return 80 }
        if quality.contains("hd") { return 70 }
        if quality.contains("480") { return 60 }
        if quality.contains("sd") { return 50 }
        if quality.contains("360") { return 40 }
        if quality.contains("ld") { return 30 }
        if quality.contains("240") { return 20 }
        return 0
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
