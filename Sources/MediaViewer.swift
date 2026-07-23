import SwiftUI
import CryptoKit
import AVKit

struct MediaViewer: View {
    let item: MediaItem
    let key: SymmetricKey
    @EnvironmentObject var mediaManager: MediaManager
    @Environment(\.presentationMode) var presentationMode
    
    @State private var decryptedURL: URL?
    @State private var loadError: Error?
    @State private var uiImage: UIImage?
    @State private var player: AVPlayer?
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let error = loadError {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text("Decryption Failed")
                        .foregroundColor(.white)
                        .padding()
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            } else if item.type == .photo {
                if let uiImage = uiImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
            } else {
                if let player = player {
                    VideoPlayer(player: player)
                        .onAppear { player.play() }
                        .onDisappear { player.pause() }
                } else {
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showDeleteConfirmation = true }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
            }
        }
        .alert(isPresented: $showDeleteConfirmation) {
            Alert(
                title: Text("Delete from Vault?"),
                message: Text("This will permanently erase the item from your secure storage."),
                primaryButton: .destructive(Text("Delete")) {
                    deleteItem()
                },
                secondaryButton: .cancel()
            )
        }
        .onAppear(perform: decryptAndLoad)
        .onDisappear(perform: cleanup)
    }
    
    private func decryptAndLoad() {
        DispatchQueue.global(qos: .userInitiated).async {
            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("vault_decrypted_\(UUID().uuidString)")
                .appendingPathExtension(item.fileExtension)
            do {
                try CryptoUtility.decryptFile(inputURL: item.encryptedFileURL, outputURL: tempURL, key: key)
                DispatchQueue.main.async {
                    self.decryptedURL = tempURL
                    if item.type == .photo {
                        if let data = try? Data(contentsOf: tempURL) {
                            self.uiImage = UIImage(data: data)
                        } else {
                            self.loadError = CryptoError.fileReadError
                        }
                    } else {
                        self.player = AVPlayer(url: tempURL)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.loadError = error
                }
            }
        }
    }
    
    private func deleteItem() {
        mediaManager.delete(item: item)
        presentationMode.wrappedValue.dismiss()
    }
    
    private func cleanup() {
        player?.pause()
        player = nil
        uiImage = nil
        
        if let url = decryptedURL {
            try? FileManager.default.removeItem(at: url)
        }
        StorageCleaner.shared.purgeTempDirectory()
    }
}
