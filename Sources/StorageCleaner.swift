import Foundation

class StorageCleaner {
    static let shared = StorageCleaner()
    private let fileManager = FileManager.default
    
    private init() {}
    
    func purgeTempDirectory() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        do {
            let contents = try fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            for file in contents {
                if file.lastPathComponent.hasPrefix("vault_") || file.pathExtension == "tmp" {
                    try? fileManager.removeItem(at: file)
                }
            }
        } catch {
            print("Failed to purge temp directory: \(error)")
        }
    }
}
