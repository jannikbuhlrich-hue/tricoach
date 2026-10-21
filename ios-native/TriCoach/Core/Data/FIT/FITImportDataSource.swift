import Foundation

/// Importiert .fit-Dateien (z. B. aus Garmin Connect → Aktivität → „Original exportieren“
/// oder direkt per USB von der Forerunner 265: GARMIN/Activity/*.fit).
/// Liefert als einzige lokale Quelle SWOLF pro Bahn und volle Laufdynamik.
struct FITImportDataSource: TrainingDataSource {
    let kind: DataSourceKind = .fitFile

    static var folder: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("FIT", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Kopiert vom Nutzer gewählte Dateien in den App-Ordner.
    static func importFiles(_ urls: [URL]) throws -> Int {
        var count = 0
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let target = folder.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.copyItem(at: url, to: target)
            count += 1
        }
        return count
    }

    func fetchActivities(from: Date, to: Date) async throws -> [Activity] {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "fit" }
            .compactMap { url -> Activity? in
                guard let data = try? Data(contentsOf: url),
                      let messages = try? FITDecoder.decode(data) else { return nil }
                return FITActivityMapper.activity(from: messages, fileID: url.deletingPathExtension().lastPathComponent)
            }
            .filter { $0.startDate >= from && $0.startDate <= to }
    }

    func fetchWellness(from: Date, to: Date) async throws -> [DailyWellness] { [] }
}
