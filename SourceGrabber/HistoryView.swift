import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var historyStore: HistoryStore
    @Environment(\.dismiss) private var dismiss
    let onSelect: (String) -> Void
    
    var body: some View {
        NavigationView {
            Group {
                if historyStore.records.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("暂无历史记录")
                            .foregroundColor(.secondary)
                    }
                } else {
                    List {
                        ForEach(historyStore.records) { record in
                            Button(action: {
                                onSelect(record.url)
                                dismiss()
                            }) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.title)
                                        .font(.body)
                                        .lineLimit(1)
                                    Text(record.url)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                    Text(record.date, style: .relative)
                                        .font(.caption2)
                                        .foregroundColor(.tertiary)
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
                if !historyStore.records.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        EditButton()
                    }
                }
            }
        }
    }
    
    private func deleteRecord(at offsets: IndexSet) {
        offsets.forEach { index in
            historyStore.removeRecord(historyStore.records[index])
        }
    }
}
