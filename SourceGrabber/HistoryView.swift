import SwiftUI

struct HistoryView: View {
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var historyURLs: [String] = []

    var body: some View {
        NavigationView {
            Group {
                if historyURLs.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("暂无历史记录")
                            .foregroundColor(.secondary)
                    }
                } else {
                    List {
                        ForEach(historyURLs, id: \.self) { url in
                            Button(action: {
                                onSelect(url)
                                dismiss()
                            }) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(url)
                                        .font(.body)
                                        .lineLimit(1)
                                        .foregroundColor(.primary)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .onDelete(perform: deleteRecord)
                    }
                }
            }
            .navigationTitle("历史记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
            .onAppear(perform: loadHistory)
        }
    }

    private func loadHistory() {
        historyURLs = UserDefaults.standard.stringArray(forKey: "fetchHistory") ?? []
    }

    private func deleteRecord(at offsets: IndexSet) {
        historyURLs.remove(atOffsets: offsets)
        UserDefaults.standard.set(historyURLs, forKey: "fetchHistory")
    }
}
