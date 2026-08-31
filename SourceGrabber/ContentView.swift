import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = SourceCodeViewModel()
    @EnvironmentObject var historyStore: HistoryStore
    @State private var urlInput: String = ""
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var searchText = ""
    @State private var showSearchBar = false
    @State private var showResponseInfo = false
    @FocusState private var isURLFieldFocused: Bool
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                urlInputBar
                if viewModel.isLoading {
                    loadingView
                } else if let error = viewModel.errorMessage, viewModel.sourceCode.isEmpty {
                    errorView(error)
                } else if !viewModel.sourceCode.isEmpty {
                    sourceCodeArea
                } else {
                    emptyStateView
                }
            }
            .navigationTitle("源码抓取器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if !viewModel.sourceCode.isEmpty {
                        Button(action: { showResponseInfo.toggle() }) {
                            Image(systemName: "info.circle")
                        }
                        Button(action: { showSearchBar.toggle() }) {
                            Image(systemName: "magnifyingglass")
                        }
                        Button(action: viewModel.copySource) {
                            Image(systemName: "doc.on.doc")
                        }
                        Button(action: shareSource) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    Button(action: { showHistory.toggle() }) {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    Button(action: { showSettings.toggle() }) {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(viewModel: viewModel)
            }
            .sheet(isPresented: $showHistory) {
                HistoryView { selectedURL in
                    urlInput = selectedURL
                    fetchSource()
                }
                .environmentObject(historyStore)
            }
            .sheet(isPresented: $showResponseInfo) {
                ResponseInfoView(viewModel: viewModel)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    private var urlInputBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .foregroundColor(.secondary)
                TextField("输入网址，例如 example.com", text: $urlInput)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .focused($isURLFieldFocused)
                    .onSubmit(fetchSource)
                if viewModel.isLoading {
                    Button(action: viewModel.cancelFetch) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                    }
                } else if !urlInput.isEmpty {
                    Button(action: { urlInput = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
                Button(action: fetchSource) {
                    Text("抓取")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.systemGray6))
            
            if showSearchBar && !viewModel.sourceCode.isEmpty {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("搜索源码", text: $searchText)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    if !searchText.isEmpty {
                        Text("\(searchOccurrences) 处匹配")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray5))
            }
        }
    }
    
    private var searchOccurrences: Int {
        guard !searchText.isEmpty else { return 0 }
        return viewModel.sourceCode.lowercased().components(separatedBy: searchText.lowercased()).count - 1
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("正在抓取源码...")
                .foregroundColor(.secondary)
            Text(viewModel.currentURL)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
            Button("重试") {
                fetchSource()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 60))
                .foregroundColor(.blue.opacity(0.6))
            Text("输入网址开始抓取")
                .font(.title2)
                .fontWeight(.medium)
            Text("支持查看网页HTML源码、响应头、状态码\n可搜索、复制、导出源码文件")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var sourceCodeArea: some View {
        ScrollView {
            if searchText.isEmpty {
                Text(viewModel.sourceCode)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .textSelection(.enabled)
            } else {
                highlightedSourceCode
            }
        }
        .background(Color(.systemBackground))
    }
    
    private var highlightedSourceCode: some View {
        let attributed = highlightSearchResults(in: viewModel.sourceCode, searchText: searchText)
        return Text(attributed)
            .font(.system(size: 11, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .textSelection(.enabled)
    }
    
    private func highlightSearchResults(in text: String, searchText: String) -> AttributedString {
        var attributed = AttributedString(text)
        let lowercasedText = text.lowercased()
        let lowercasedSearch = searchText.lowercased()
        var searchRange = lowercasedText.startIndex..<lowercasedText.endIndex
        
        while let range = lowercasedText.range(of: lowercasedSearch, range: searchRange) {
            if let attributedRange = Range(range, in: attributed) {
                attributed[attributedRange].backgroundColor = .yellow
                attributed[attributedRange].foregroundColor = .black
            }
            searchRange = range.upperBound..<lowercasedText.endIndex
        }
        return attributed
    }
    
    private func fetchSource() {
        isURLFieldFocused = false
        guard !urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        viewModel.fetchSource(from: urlInput)
        historyStore.addRecord(url: urlInput, title: nil)
    }
    
    private func shareSource() {
        guard let fileURL = viewModel.shareSource() else { return }
        let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}
