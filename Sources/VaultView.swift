import SwiftUI
import PhotosUI
import CryptoKit
import AVFoundation

struct VaultView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var mediaManager: MediaManager
    
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isImporting = false
    
    let columns = [GridItem(.adaptive(minimum: 100), spacing: 2)]
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if mediaManager.mediaItems.isEmpty {
                    VStack {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("Vault is Empty")
                            .foregroundColor(.gray)
                            .padding()
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(mediaManager.mediaItems) { item in
                                if let key = authManager.derivedKey {
                                    NavigationLink(destination: MediaViewer(item: item, key: key)) {
                                        VaultThumbnailView(item: item, key: key)
                                    }
                                }
                            }
                        }
                    }
                }
                
                if isImporting {
                    Color.black.opacity(0.7).ignoresSafeArea()
                    VStack {
                        ProgressView("Importing & Encrypting...")
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .foregroundColor(.white)
                    }
                }
            }
            .navigationTitle("Watch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    PhotosPicker(selection: $selectedItems, matching: .any(of: [.images, .videos])) {
                        Image(systemName: "plus")
                            .foregroundColor(.white)
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { authManager.lock() }) {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.white)
                    }
                }
            }
            .onChange(of: selectedItems) { newItems in
                guard !newItems.isEmpty, let key = authManager.derivedKey else { return }
                Task {
                    isImporting = true
                    for pickerItem in newItems {
                        await mediaManager.processPhotosPickerItem(pickerItem, key: key)
                    }
                    selectedItems.removeAll()
                    isImporting = false
                }
            }
        }
        .accentColor(.white)
    }
}

struct VaultThumbnailView: View {
    let item: MediaItem
    let key: SymmetricKey
    @State private var image: UIImage?
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.width)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: geo.size.width, height: geo.size.width)
                        .overlay(ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)))
                }
                
                if item.type == .video {
                    Image(systemName: "play.fill")
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear(perform: generateThumbnail)
    }
    
    private func generateThumbnail() {
        DispatchQueue.global(qos: .userInitiated).async {
            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("vault_thumb_\(UUID().uuidString).tmp")
            do {
                try CryptoUtility.decryptFile(inputURL: item.encryptedFileURL, outputURL: tempURL, key: key)
                var thumbnail: UIImage?
                
                if item.type == .photo {
                    if let data = try? Data(contentsOf: tempURL) {
                        thumbnail = UIImage(data: data)
                    }
                } else {
                    let asset = AVURLAsset(url: tempURL)
                    let generator = AVAssetImageGenerator(asset: asset)
                    generator.appliesPreferredTrackTransform = true
                    if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
                        thumbnail = UIImage(cgImage: cgImage)
                    }
                }
                
                try? FileManager.default.removeItem(at: tempURL)
                
                DispatchQueue.main.async {
                    self.image = thumbnail
                }
            } catch {
                try? FileManager.default.removeItem(at: tempURL)
            }
        }
    }
}
