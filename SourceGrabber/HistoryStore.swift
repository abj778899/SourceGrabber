import Foundation
import SwiftUI

class HistoryStore: ObservableObject {
    @Published var records: [HistoryRecord] = []
    
    private let saveKey = "SourceGrabberHistory"
    
    init() {
        load()
    }
    
    func addRecord(url: String, title: String?) {
        let record = HistoryRecord(url: url, title: title ?? url, date: Date())
        if let index = records.firstIndex(where: { $0.url == url }) {
            records.remove(at: index)
        }
        records.insert(record, at: 0)
        if records.count > 100 {
            records = Array(records.prefix(100))
        }
        save()
    }
    
    func removeRecord(_ record: HistoryRecord) {
        records.removeAll { $0.id == record.id }
        save()
    }
    
    func clearAll() {
        records.removeAll()
        save()
    }
    
    private func save() {
        if let encoded = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }
    
    private func load() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([HistoryRecord].self, from: data) {
            records = decoded
        }
    }
}

struct HistoryRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let url: String
    let title: String
    let date: Date
    
    init(url: String, title: String, date: Date) {
        self.id = UUID()
        self.url = url
        self.title = title
        self.date = date
    }
}
