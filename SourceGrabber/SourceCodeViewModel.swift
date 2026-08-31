import Foundation
import Combine

class SourceCodeViewModel: ObservableObject {
    @Published var sourceCode: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var currentURL: String = ""
    @Published var responseHeaders: [String: String] = [:]
    @Published var statusCode: Int = 0
    @Published var contentSize: Int = 0
    @Published var fetchTime: TimeInterval = 0
    
    private var cancellables = Set<AnyCancellable>()
    
    var customUserAgent: String {
        get { UserDefaults.standard.string(forKey: "customUserAgent") ?? "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1" }
        set { UserDefaults.standard.set(newValue, forKey: "customUserAgent") }
    }
    
    func fetchSource(from urlString: String) {
        guard let url = URL(string: normalizeURL(urlString)) else {
            errorMessage = "无效的URL地址"
            return
        }
        
        isLoading = true
        errorMessage = nil
        sourceCode = ""
        responseHeaders = [:]
        statusCode = 0
        currentURL = url.absoluteString
        
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
                
                let encoding = self.detectEncoding(from: data, response: response)
                if let code = String(data: data, encoding: encoding) {
                    self.sourceCode = code
                } else if let code = String(data: data, encoding: .utf8) {
                    self.sourceCode = code
                } else {
                    self.sourceCode = data.base64EncodedString()
                    self.errorMessage = "无法识别文本编码，已显示Base64编码"
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
    
    private func detectEncoding(from data: Data, response: URLResponse) -> String.Encoding {
        if let charset = response.textEncodingName,
           let encoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString) {
            let nsEncoding = CFStringConvertEncodingToNSStringEncoding(encoding)
            return String.Encoding(rawValue: nsEncoding)
        }
        
        if data.count >= 3 {
            if data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF {
                return .utf8
            }
        }
        if data.count >= 2 {
            if data[0] == 0xFF && data[1] == 0xFE { return .utf16LittleEndian }
            if data[0] == 0xFE && data[1] == 0xFF { return .utf16BigEndian }
        }
        
        if let content = String(data: data, encoding: .utf8) {
            if content.contains("charset=gbk") || content.contains("charset=GBK") ||
               content.contains("charset=gb2312") || content.contains("charset=GB2312") {
                return .gbk
            }
        }
        
        return .utf8
    }
    
    func copySource() {
        UIPasteboard.general.string = sourceCode
    }
    
    func shareSource() -> URL? {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("source.html")
        do {
            try sourceCode.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            return nil
        }
    }
}
