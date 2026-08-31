import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: VideoSourceViewModel
    @State private var userAgent: String = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("请求设置")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("User-Agent")
                            .font(.headline)
                        TextEditor(text: $userAgent)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(minHeight: 80)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                    }
                    
                    Button("恢复默认 User-Agent") {
                        userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
                    }
                    
                    Button("使用桌面端 User-Agent") {
                        userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
                    }
                }
                
                Section(header: Text("关于")) {
                    HStack {
                        Text("应用名称")
                        Spacer()
                        Text("源码抓取器")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("功能")
                        Spacer()
                        Text("网页HTML源码抓取")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        viewModel.customUserAgent = userAgent
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                userAgent = viewModel.customUserAgent
            }
        }
    }
}
