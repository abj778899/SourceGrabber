import Foundation
import Combine
import UIKit
import WebKit
import AVFoundation

struct VideoSource: Identifiable, Hashable {
    let id = UUID()
    let url: String
    let type: String
    let quality: String?
    let qualityScore: Int
    var isValid: Bool = true
    var fileSize: Int64 = 0
}

class VideoSourceViewModel: NSObject, ObservableObject, WKNavigationDelegate, WKScriptMessageHandler {
    @Published var videoSources: [VideoSource] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var currentURL: String = ""
    @Published var pageTitle: String = ""
    @Published var authorName: String = ""
    @Published var statusCode: Int = 0
    @Published var fetchTime: TimeInterval = 0
    @Published var loadingProgress: Double = 0
    @Published var foundCount: Int = 0
    @Published var validCount: Int = 0

    private var webView: WKWebView?
    private var startTime: Date = Date()
    private var foundURLs = Set<String>()
    private var timeoutTimer: Timer?
    private var verifyQueue = DispatchQueue(label: "com.sourcegrabber.verify", attributes: .concurrent)
    private var verifyGroup = DispatchGroup()

    var customUserAgent: String {
        get { UserDefaults.standard.string(forKey: "customUserAgent") ?? "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1" }
        set { UserDefaults.standard.set(newValue, forKey: "customUserAgent") }
    }

    func fetchVideoSources(from urlString: String) {
        let normalized = normalizeShareURL(urlString)
        guard let url = URL(string: normalized) else {
            errorMessage = "无效的URL地址"
            return
        }

        isLoading = true
        errorMessage = nil
        videoSources = []
        statusCode = 0
        currentURL = normalized
        pageTitle = ""
        authorName = ""
        loadingProgress = 0
        foundCount = 0
        validCount = 0
        foundURLs.removeAll()
        startTime = Date()

        setupWebView()
        loadWebView(url: url)

        timeoutTimer?.invalidate()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            self?.handleTimeout()
        }
    }

    private func normalizeShareURL(_ url: String) -> String {
        var trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        // 提取分享文本中的URL
        if let range = trimmed.range(of: "https?://[^\\s]+", options: .regularExpression) {
            trimmed = String(trimmed[range])
        }
        if !trimmed.hasPrefix("http://") && !trimmed.hasPrefix("https://") {
            trimmed = "https://" + trimmed
        }
        return trimmed
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // 核心：注入JS拦截所有网络请求（猫爪原理）
        let interceptJS = """
        (function() {
            var videoPatterns = [/\\.m3u8/i, /\\.mp4/i, /\\.flv/i, /\\.ts/i, /\\.mov/i, /\\.m4v/i, /\\.webm/i, /\\.aac/i, /\\.mp3/i, /m3u8/i, /mp4/i, /flv/i, /video/i, /play/i, /stream/i, /live/i, /media/i];
            var sentURLs = {};

            function isVideoURL(url) {
                if (!url || url.length < 10) return false;
                if (url.indexOf('data:') === 0) return false;
                if (url.indexOf('blob:') === 0) return false;
                for (var i = 0; i < videoPatterns.length; i++) {
                    if (videoPatterns[i].test(url)) return true;
                }
                return false;
            }

            function sendURL(url, type) {
                if (!url || sentURLs[url]) return;
                if (!isVideoURL(url)) return;
                sentURLs[url] = 1;
                try {
                    window.webkit.messageHandlers.videoInterceptor.postMessage({url: url, type: type || 'network'});
                } catch(e) {}
            }

            // 拦截 XMLHttpRequest
            var origOpen = XMLHttpRequest.prototype.open;
            var origSend = XMLHttpRequest.prototype.send;
            XMLHttpRequest.prototype.open = function(method, url) {
                this._url = url;
                return origOpen.apply(this, arguments);
            };
            XMLHttpRequest.prototype.send = function() {
                if (this._url) sendURL(this._url, 'xhr');
                return origSend.apply(this, arguments);
            };

            // 拦截 fetch
            var origFetch = window.fetch;
            if (origFetch) {
                window.fetch = function(input, init) {
                    var url = typeof input === 'string' ? input : (input && input.url);
                    if (url) sendURL(url, 'fetch');
                    return origFetch.apply(this, arguments);
                };
            }

            // 拦截 video/audio 标签的 src
            function checkMediaElements() {
                var videos = document.querySelectorAll('video, audio');
                videos.forEach(function(v) {
                    if (v.src) sendURL(v.src, 'media');
                    var sources = v.querySelectorAll('source');
                    sources.forEach(function(s) {
                        if (s.src) sendURL(s.src, 'source');
                    });
                });
            }

            // 定期检查新创建的media元素
            setInterval(checkMediaElements, 1000);
            setTimeout(checkMediaElements, 500);

            // 监听DOM变化
            var observer = new MutationObserver(function(mutations) {
                checkMediaElements();
            });
            observer.observe(document.documentElement, {childList: true, subtree: true});

            // 从页面HTML中提取
            function extractFromHTML() {
                var html = document.documentElement.innerHTML;
                var patterns = [
                    /["']([^"']+\\.m3u8[^"']*)["']/gi,
                    /["']([^"']+\\.mp4[^"']*)["']/gi,
                    /["']([^"']+\\.flv[^"']*)["']/gi,
                    /["']([^"']+\\.ts[^"']*)["']/gi,
                    /(?:url|src|videoUrl|playUrl|mediaUrl|play_url|main_url|video_url|m3u8|mp4|flv)\\s*[:=]\\s*["']([^"']+)["']/gi,
                    /https?:\\/\\/[^"'\\s<>]+\\.(?:m3u8|mp4|flv|ts|mov|m4v|webm)[^"'\\s<>]*/gi
                ];
                patterns.forEach(function(pattern) {
                    var match;
                    while ((match = pattern.exec(html)) !== null) {
                        var url = match[1] || match[0];
                        sendURL(url, 'html');
                    }
                });
            }
            setTimeout(extractFromHTML, 2000);
            setTimeout(extractFromHTML, 5000);
        })();
        """

        let userScript = WKUserScript(source: interceptJS, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        config.userContentController.addUserScript(userScript)
        config.userContentController.add(self, name: "videoInterceptor")

        webView = WKWebView(frame: .zero, configuration: config)
        webView?.navigationDelegate = self
        webView?.customUserAgent = customUserAgent
        webView?.isHidden = true
    }

    private func loadWebView(url: URL) {
        var request = URLRequest(url: url)
        request.setValue(customUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        webView?.load(request)
    }

    // MARK: - WKNavigationDelegate
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadingProgress = 1.0
        pageTitle = webView.title ?? ""
        statusCode = 200

        // 提取作者信息
        extractAuthorInfo()

        // 页面加载完成后，再等几秒让视频请求都发出来
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.startVerification()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleError(error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleError(error.localizedDescription)
    }

    // MARK: - WKScriptMessageHandler
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "videoInterceptor" {
            if let dict = message.body as? [String: String], let url = dict["url"] {
                addFoundURL(url, type: dict["type"] ?? "network")
            }
        }
    }

    private func addFoundURL(_ rawURL: String, type: String) {
        let cleanURL = cleanVideoURL(rawURL)
        let absoluteURL = resolveURL(cleanURL)

        guard !foundURLs.contains(absoluteURL) else { return }
        guard isValidVideoURL(absoluteURL) else { return }

        foundURLs.insert(absoluteURL)
        foundCount = foundURLs.count

        let quality = extractQuality(from: absoluteURL)
        let score = qualityScore(for: quality)
        let source = VideoSource(url: absoluteURL, type: type, quality: quality, qualityScore: score)

        DispatchQueue.main.async {
            self.videoSources.append(source)
            self.videoSources.sort { $0.qualityScore > $1.qualityScore }
        }
    }

    private func extractAuthorInfo() {
        let js = """
        (function() {
            var author = '';
            var metaAuthor = document.querySelector('meta[name="author"]');
            if (metaAuthor) author = metaAuthor.getAttribute('content') || '';
            if (!author) {
                var ogAuthor = document.querySelector('meta[property="og:article:author"]');
                if (ogAuthor) author = ogAuthor.getAttribute('content') || '';
            }
            if (!author && document.title) {
                var parts = document.title.split(/[-_|]/);
                if (parts.length > 1) {
                    var last = parts[parts.length - 1].trim();
                    if (last.length > 0 && last.length < 30) author = last;
                }
            }
            return author;
        })();
        """
        webView?.evaluateJavaScript(js) { [weak self] result, _ in
            if let author = result as? String, !author.isEmpty {
                DispatchQueue.main.async {
                    self?.authorName = author
                }
            }
        }
    }

    private func startVerification() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil

        guard !foundURLs.isEmpty else {
            finishLoading()
            return
        }

        let urlsToVerify = Array(foundURLs)
        var validSources: [VideoSource] = []
        let lock = NSLock()

        for url in urlsToVerify {
            verifyGroup.enter()
            verifyQueue.async {
                self.verifyURL(url) { isValid, fileSize in
                    lock.lock()
                    if isValid {
                        let quality = self.extractQuality(from: url)
                        let score = self.qualityScore(for: quality)
                        let source = VideoSource(url: url, type: "verified", quality: quality, qualityScore: score, isValid: true, fileSize: fileSize)
                        validSources.append(source)
                        DispatchQueue.main.async {
                            self.validCount = validSources.count
                        }
                    }
                    lock.unlock()
                    self.verifyGroup.leave()
                }
            }
        }

        verifyGroup.notify(queue: .main) {
            validSources.sort { $0.qualityScore > $1.qualityScore }
            self.videoSources = validSources
            self.finishLoading()
        }
    }

    private func verifyURL(_ urlString: String, completion: @escaping (Bool, Int64) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(false, 0)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue(customUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        // 对m3u8用GET，因为有些服务器不支持HEAD
        if urlString.lowercased().contains(".m3u8") {
            request.httpMethod = "GET"
        }

        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                completion(false, 0)
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(false, 0)
                return
            }
            let statusCode = httpResponse.statusCode
            let contentType = httpResponse.allHeaderFields["Content-Type"] as? String ?? ""
            let contentLength = Int64(httpResponse.allHeaderFields["Content-Length"] as? String ?? "0") ?? 0

            let isValid = (statusCode == 200 || statusCode == 206) &&
                          (contentType.contains("video") ||
                           contentType.contains("audio") ||
                           contentType.contains("mpegurl") ||
                           contentType.contains("octet-stream") ||
                           contentType.contains("mp4") ||
                           contentType.contains("x-mpegURL") ||
                           urlString.lowercased().contains(".m3u8") ||
                           urlString.lowercased().contains(".mp4") ||
                           urlString.lowercased().contains(".flv"))

            completion(isValid, contentLength)
        }
        task.resume()
    }

    private func handleTimeout() {
        startVerification()
    }

    private func handleError(_ message: String) {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        DispatchQueue.main.async {
            self.isLoading = false
            self.errorMessage = "加载失败: \(message)"
        }
    }

    private func finishLoading() {
        fetchTime = Date().timeIntervalSince(startTime)
        DispatchQueue.main.async {
            self.isLoading = false
            if self.videoSources.isEmpty {
                self.errorMessage = "未找到可播放的视频源，该网站可能需要登录或有验证码保护"
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.webView?.stopLoading()
            self.webView = nil
        }
    }

    func cancelFetch() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        webView?.stopLoading()
        webView = nil
        isLoading = false
    }

    // MARK: - 工具方法
    private func cleanVideoURL(_ url: String) -> String {
        var clean = url
        clean = clean.replacingOccurrences(of: "\\u002F", with: "/")
        clean = clean.replacingOccurrences(of: "\\/", with: "/")
        clean = clean.replacingOccurrences(of: "&amp;", with: "&")
        clean = clean.replacingOccurrences(of: "&quot;", with: "\"")
        clean = clean.replacingOccurrences(of: "&#39;", with: "'")
        clean = clean.trimmingCharacters(in: CharacterSet(charactersIn: "\"'<> \t\n\r"))
        return clean
    }

    private func resolveURL(_ rawURL: String) -> String {
        if rawURL.hasPrefix("http://") || rawURL.hasPrefix("https://") {
            return rawURL
        }
        if rawURL.hasPrefix("//") {
            return "https:" + rawURL
        }
        if let baseURL = URL(string: currentURL) {
            if rawURL.hasPrefix("/") {
                if let host = baseURL.host {
                    return "\(baseURL.scheme ?? "https")://\(host)\(rawURL)"
                }
            }
            return baseURL.deletingLastPathComponent().appendingPathComponent(rawURL).absoluteString
        }
        return rawURL
    }

    private func isValidVideoURL(_ url: String) -> Bool {
        let lowercased = url.lowercased()
        if !lowercased.hasPrefix("http://") && !lowercased.hasPrefix("https://") {
            return false
        }
        let hasVideoExt = lowercased.contains(".m3u8") ||
                          lowercased.contains(".mp4") ||
                          lowercased.contains(".flv") ||
                          lowercased.contains(".ts") ||
                          lowercased.contains(".mov") ||
                          lowercased.contains(".m4v") ||
                          lowercased.contains(".webm") ||
                          lowercased.contains(".aac") ||
                          lowercased.contains(".mp3") ||
                          lowercased.contains("player") ||
                          lowercased.contains("play.php") ||
                          lowercased.contains("video.php") ||
                          lowercased.contains("api.php") ||
                          lowercased.contains("stream") ||
                          lowercased.contains("live")
        if !hasVideoExt {
            return false
        }
        if url.contains("<") || url.contains(">") {
            return false
        }
        if url.contains("\"") || url.contains("'") {
            return false
        }
        if lowercased.contains(".css") || lowercased.contains(".js") {
            return false
        }
        if lowercased.contains(".jpg") || lowercased.contains(".jpeg") ||
           lowercased.contains(".png") || lowercased.contains(".gif") ||
           lowercased.contains(".webp") || lowercased.contains(".svg") {
            return false
        }
        if url.count < 15 {
            return false
        }
        return true
    }

    private func extractQuality(from url: String) -> String? {
        let lowercased = url.lowercased()
        if lowercased.contains("1080p") || lowercased.contains("1920x1080") || lowercased.contains("_1080") { return "1080P" }
        if lowercased.contains("720p") || lowercased.contains("1280x720") || lowercased.contains("_720") { return "720P" }
        if lowercased.contains("480p") || lowercased.contains("854x480") || lowercased.contains("_480") { return "480P" }
        if lowercased.contains("360p") || lowercased.contains("640x360") || lowercased.contains("_360") { return "360P" }
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
        return 0
    }

    func copySource(_ source: VideoSource) {
        UIPasteboard.general.string = source.url
    }

    func formatFileSize(_ bytes: Int64) -> String {
        if bytes <= 0 { return "未知" }
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        if bytes < 1024 * 1024 * 1024 { return String(format: "%.1f MB", Double(bytes) / (1024 * 1024)) }
        return String(format: "%.2f GB", Double(bytes) / (1024 * 1024 * 1024))
    }
}
