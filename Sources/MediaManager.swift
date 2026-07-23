import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import CryptoKit

enum MediaType: String, Codable {
    case photo
    case video
}

struct MediaItem: Identifiable, Codable {
    let id: UUID
    let type: MediaType
    let encryptedFileURL: URL
    let dateAdded: Date
    let fileExtension: String

    enum CodingKeys: String, CodingKey {
        case id, type, encryptedFileURL, dateAdded, fileExtension
    }

    init(id: UUID, type: MediaType, encryptedFileURL: URL, dateAdded: Date, fileExtension: String) {
        self.id = id
        self.type = type
        self.encryptedFileURL = encryptedFileURL
        self.dateAdded = dateAdded
        self.fileExtension = fileExtension
    }

    // Custom decoding keeps old vault metadata (saved before this field existed) loadable.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(MediaType.self, forKey: .type)
        encryptedFileURL = try container.decode(URL.self, forKey: .encryptedFileURL)
        dateAdded = try container.decode(Date.self, forKey: .dateAdded)
        fileExtension = try container.decodeIfPresent(String.self, forKey: .fileExtension)
            ?? (type == .video ? "mov" : "jpg")
    }
}

struct FileTransferable: Transferable {
    let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .data) { file in
            SentTransferredFile(file.url)
        } importing: { received in
            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("vault_upload_\(UUID().uuidString).tmp")
            try FileManager.default.copyItem(at: received.file, to: tempURL)
            return FileTransferable(url: tempURL)
        }
    }
}

@MainActor
class MediaManager: ObservableObject {
    @Published var mediaItems: [MediaItem] = []
    private let fileManager = FileManager.default
    
    private var vaultDirectory: URL {
        let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let vaultPath = paths[0].appendingPathComponent("VaultFiles")
        if !fileManager.fileExists(atPath: vaultPath.path) {
            try? fileManager.createDirectory(at: vaultPath, withIntermediateDirectories: true, attributes: nil)
        }
        return vaultPath
    }
    
    init() {
        loadMetadata()
    }
    
    func processPhotosPickerItem(_ pickerItem: PhotosPickerItem, key: SymmetricKey) async {
        do {
            if let file = try await pickerItem.loadTransferable(type: FileTransferable.self) {
                let matchedType = pickerItem.supportedContentTypes.first(where: {
                    $0.conforms(to: .movie) || $0.conforms(to: .video) || $0.conforms(to: .image)
                }) ?? pickerItem.supportedContentTypes.first

                let isVideo = matchedType?.conforms(to: .movie) == true || matchedType?.conforms(to: .video) == true
                let type: MediaType = isVideo ? .video : .photo
                let fileExtension = matchedType?.preferredFilenameExtension ?? (isVideo ? "mov" : "jpg")

                try await importItem(from: file.url, type: type, fileExtension: fileExtension, key: key, originalAssetLocalIdentifier: pickerItem.itemIdentifier)
            }
        } catch {
            print("Failed to process item: \(error)")
            StorageCleaner.shared.purgeTempDirectory()
        }
    }
    
    private func importItem(from url: URL, type: MediaType, fileExtension: String, key: SymmetricKey, originalAssetLocalIdentifier: String?) async throws {
        let id = UUID()
        let encryptedFileURL = vaultDirectory.appendingPathComponent("\(id.uuidString).enc")
        
        try CryptoUtility.encryptFile(inputURL: url, outputURL: encryptedFileURL, key: key)
        
        let item = MediaItem(id: id, type: type, encryptedFileURL: encryptedFileURL, dateAdded: Date(), fileExtension: fileExtension)
        self.mediaItems.append(item)
        self.saveMetadata()
        
        // Cleanup the temporary unencrypted file immediately
        try? fileManager.removeItem(at: url)
        
        // Trigger PhotoKit deletion
        if let localId = originalAssetLocalIdentifier {
            try await deleteFromPhotoLibrary(localIdentifier: localId)
        }
    }
    
    func delete(item: MediaItem) {
        try? fileManager.removeItem(at: item.encryptedFileURL)
        self.mediaItems.removeAll { $0.id == item.id }
        self.saveMetadata()
    }
    
    private func saveMetadata() {
        if let data = try? JSONEncoder().encode(mediaItems) {
            let metaURL = vaultDirectory.appendingPathComponent("metadata.json")
            try? data.write(to: metaURL)
        }
    }
    
    private func loadMetadata() {
        let metaURL = vaultDirectory.appendingPathComponent("metadata.json")
        if let data = try? Data(contentsOf: metaURL),
           let items = try? JSONDecoder().decode([MediaItem].self, from: data) {
            self.mediaItems = items.sorted(by: { $0.dateAdded > $1.dateAdded })
        }
    }
    
    private func deleteFromPhotoLibrary(localIdentifier: String) async throws {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        if let asset = assets.firstObject {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets([asset] as NSArray)
            }
        }
    }
}
