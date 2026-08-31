import Foundation
import Combine
import UIKit
import WebKit

struct VideoSource: Identifiable, Hashable {
    let id = UUID()
    let url: String
    let type: String
    let quality: String?
    let qualityScore: Int
}

class VideoSourceViewModel: NSObject, ObservableObject, WKNavigationDelegate, WKScriptMessageHandler {
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
    @Published var loadingProgress: Double = 0

    private var cancellables = Set<AnyCancellable>()
    private var webView: WKWebView?
    private var startTime: Date = Date()
    private var foundURLs = Set<String>()
    private var timeoutTimer: Timer?
    private var completionHandler: (() -> Void)?

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
        loadingProgress = 0
        foundURLs.removeAll()
        startTime = Date()

        // 使用WKWebView模式加载页面
        setupWebView()
        loadWebView(url: url)

        // 设置超时
        timeoutTimer?.invalidate()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: false) { [weak self] _ in
            self?.handleTimeout()
        }
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // 添加JS注入，用于提取视频源
        let jsCode = """
        function extractVideoSources() {
            var sources = [];
            var seen = {};

            // 1. 提取video标签的src
            var videos = document.querySelectorAll('video');
            videos.forEach(function(v) {
                if (v.src && !seen[v.src]) { seen[v.src] = 1; sources.push({url: v.src, type: 'video'}); }
                var sources2 = v.querySelectorAll('source');
                sources2.forEach(function(s) {
                    if (s.src && !seen[s.src]) { seen[s.src] = 1; sources.push({url: s.src, type: 'source'}); }
                });
            });

            // 2. 提取所有source标签
            var allSources = document.querySelectorAll('source');
            allSources.forEach(function(s) {
                if (s.src && !seen[s.src]) { seen[s.src] = 1; sources.push({url: s.src, type: 'source'}); }
            });

            // 3. 提取iframe的src
            var iframes = document.querySelectorAll('iframe');
            iframes.forEach(function(f) {
                if (f.src && !seen[f.src]) { seen[f.src] = 1; sources.push({url: f.src, type: 'iframe'}); }
            });

            // 4. 从页面所有脚本中提取视频地址
            var scripts = document.querySelectorAll('script');
            var allText = document.documentElement.innerHTML;
            var patterns = [
                /["']([^"']+\\.m3u8[^"']*)["']/gi,
                /["']([^"']+\\.mp4[^"']*)["']/gi,
                /["']([^"']+\\.flv[^"']*)["']/gi,
                /["']([^"']+\\.ts[^"']*)["']/gi,
                /["']([^"']+\\.mov[^"']*)["']/gi,
                /(?:url|src|videoUrl|playUrl|mediaUrl|play_url|main_url|video_url|m3u8|mp4)\\s*[:=]\\s*["']([^"']+)["']/gi,
                /https?:\\/\\/[^"'\\s<>]+\\.(?:m3u8|mp4|flv|ts|mov|m4v|webm)[^"'\\s<>]*/gi
            ];

            patterns.forEach(function(pattern) {
                var match;
                while ((match = pattern.exec(allText)) !== null) {
                    var url = match[1] || match[0];
                    if (url && !seen[url]) { seen[url] = 1; sources.push({url: url, type: 'js'}); }
                }
            });

            // 5. 提取常见播放器配置
            var playerConfigs = [
                window.player, window.playerConfig, window.playerData,
                window.dplayer, window.dp, window.ckplayer, window.jwplayer,
                window.videoConfig, window.mediaConfig, window.playConfig
            ];
            playerConfigs.forEach(function(cfg) {
                if (cfg) {
                    try {
                        var json = JSON.stringify(cfg);
                        var urlMatch = json.match(/["']?(?:url|src|videoUrl|playUrl|mediaUrl)["']?\\s*[:=]\\s*["']([^"']+)["']/i);
                        if (urlMatch && !seen[urlMatch[1]]) {
                            seen[urlMatch[1]] = 1;
                            sources.push({url: urlMatch[1], type: 'player'});
                        }
                    } catch(e) {}
                }
            });

            // 6. 从meta标签提取
            var metas = document.querySelectorAll('meta');
            metas.forEach(function(m) {
                var content = m.getAttribute('content');
                var property = m.getAttribute('property') || m.getAttribute('name');
                if (content && property && (property.includes('video') || property.includes('media'))) {
                    if (content.match(/\\.(m3u8|mp4|flv|ts|mov)/i) && !seen[content]) {
                        seen[content] = 1;
                        sources.push({url: content, type: 'meta'});
                    }
                }
            });

            return sources;
        }
        window.webkit.messageHandlers.videoSources.postMessage(extractVideoSources());
        """

        let userScript = WKUserScript(source: jsCode, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(userScript)
        config.userContentController.add(self, name: "videoSources")

        webView = WKWebView(frame: .zero, configuration: config)
        webView?.navigationDelegate = self
        webView?.customUserAgent = customUserAgent
        webView?.isHidden = true
    }

    private func loadWebView(url: URL) {
        var request = URLRequest(url: url)
        request.setValue(customUserAgent, forHTTPHeaderField: "User-Agent")
        webView?.load(request)
    }

    // MARK: - WKNavigationDelegate
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadingProgress = 1.0
        pageTitle = webView.title ?? ""

        // 等待一下让JS执行完成，然后提取视频源
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.extractFromWebView()
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
        if message.name == "videoSources" {
            if let sources = message.body as? [[String: String]] {
                processExtractedSources(sources)
            }
        }
    }

    private func extractFromWebView() {
        let jsCode = """
        (function() {
            var sources = [];
            var seen = {};

            // 1. video标签
            var videos = document.querySelectorAll('video');
            videos.forEach(function(v) {
                if (v.src && !seen[v.src]) { seen[v.src] = 1; sources.push({url: v.src, type: 'video'}); }
                var ss = v.querySelectorAll('source');
                ss.forEach(function(s) { if (s.src && !seen[s.src]) { seen[s.src] = 1; sources.push({url: s.src, type: 'source'}); } });
            });

            // 2. 所有source标签
            document.querySelectorAll('source').forEach(function(s) {
                if (s.src && !seen[s.src]) { seen[s.src] = 1; sources.push({url: s.src, type: 'source'}); }
            });

            // 3. iframe
            document.querySelectorAll('iframe').forEach(function(f) {
                if (f.src && !seen[f.src]) { seen[f.src] = 1; sources.push({url: f.src, type: 'iframe'}); }
            });

            // 4. 从HTML中用正则提取
            var html = document.documentElement.innerHTML;
            var patterns = [
                /["']([^"']+\\.m3u8[^"']*)["']/gi,
                /["']([^"']+\\.mp4[^"']*)["']/gi,
                /["']([^"']+\\.flv[^"']*)["']/gi,
                /["']([^"']+\\.ts[^"']*)["']/gi,
                /(?:url|src|videoUrl|playUrl|mediaUrl|play_url|main_url|video_url)\\s*[:=]\\s*["']([^"']+)["']/gi,
                /https?:\\/\\/[^"'\\s<>]+\\.(?:m3u8|mp4|flv|ts|mov|m4v|webm)[^"'\\s<>]*/gi
            ];
            patterns.forEach(function(p) {
                var m;
                while ((m = p.exec(html)) !== null) {
                    var u = m[1] || m[0];
                    if (u && !seen[u]) { seen[u] = 1; sources.push({url: u, type: 'regex'}); }
                }
            });

            return sources;
        })();
        """

        webView?.evaluateJavaScript(jsCode) { [weak self] result, error in
            if let sources = result as? [[String: String]] {
                self?.processExtractedSources(sources)
            } else {
                self?.finishLoading()
            }
        }
    }

    private func processExtractedSources(_ sources: [[String: String]]) {
        for source in sources {
            guard let url = source["url"] else { continue }
            let cleanURL = cleanVideoURL(url)
            let absoluteURL = resolveURL(cleanURL)
            if !foundURLs.contains(absoluteURL) && isValidVideoURL(absoluteURL) {
                foundURLs.insert(absoluteURL)
                let type = source["type"] ?? detectType(from: absoluteURL)
                let quality = extractQuality(from: absoluteURL)
                let score = qualityScore(for: quality)
                let newSource = VideoSource(url: absoluteURL, type: type, quality: quality, qualityScore: score)
                DispatchQueue.main.async {
                    self.videoSources.append(newSource)
                    self.videoSources.sort { $0.qualityScore > $1.qualityScore }
                }
            }
        }
        finishLoading()
    }

    private func finishLoading() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        fetchTime = Date().timeIntervalSince(startTime)
        contentSize = foundURLs.count

        DispatchQueue.main.async {
            self.isLoading = false
            if self.videoSources.isEmpty {
                self.errorMessage = "未在页面中找到有效的视频源地址，该网站可能需要登录或有验证码"
            }
        }

        // 清理webView
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.webView?.stopLoading()
            self.webView = nil
        }
    }

    private func handleTimeout() {
        // 超时后尝试提取已加载的内容
        extractFromWebView()
    }

    private func handleError(_ message: String) {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        DispatchQueue.main.async {
            self.isLoading = false
            self.errorMessage = "加载失败: \(message)"
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
    private func normalizeURL(_ urlString: String) -> String {
        var trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.hasPrefix("http://") && !trimmed.hasPrefix("https://") {
            trimmed = "https://" + trimmed
        }
        return trimmed
    }

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
                          lowercased.contains("player") ||
                          lowercased.contains("play.php") ||
                          lowercased.contains("video.php") ||
                          lowercased.contains("api.php")
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

    private func detectType(from url: String) -> String {
        let lowercased = url.lowercased()
        if lowercased.contains(".m3u8") { return "m3u8" }
        if lowercased.contains(".mp4") { return "mp4" }
        if lowercased.contains(".flv") { return "flv" }
        if lowercased.contains(".ts") { return "ts" }
        if lowercased.contains(".mov") { return "mov" }
        if lowercased.contains("iframe") { return "iframe" }
        return "video"
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
