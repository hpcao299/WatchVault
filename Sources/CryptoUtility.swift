import Foundation
import CryptoKit

enum CryptoError: Error {
    case invalidKey
    case chunkEncryptionFailed
    case chunkDecryptionFailed
    case fileReadError
    case fileWriteError
}

class CryptoUtility {
    // 1MB Chunk size for memory-safe video processing to prevent Jetsam crashes
    static let chunkSize = 1024 * 1024 
    
    /// Chunk Format: [Size (4 bytes UInt32)] + [Nonce (12 bytes)] + [Ciphertext] + [Tag (16 bytes)]
    static func encryptFile(inputURL: URL, outputURL: URL, key: SymmetricKey) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }
        fileManager.createFile(atPath: outputURL.path, contents: nil, attributes: nil)
        
        guard let inputStream = InputStream(url: inputURL),
              let outputHandle = try? FileHandle(forWritingTo: outputURL) else {
            throw CryptoError.fileReadError
        }
        
        inputStream.open()
        defer {
            inputStream.close()
            try? outputHandle.close()
        }
        
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer { buffer.deallocate() }
        
        while inputStream.hasBytesAvailable {
            let bytesRead = inputStream.read(buffer, maxLength: chunkSize)
            if bytesRead < 0 { throw CryptoError.fileReadError }
            if bytesRead == 0 { break }
            
            let chunkData = Data(bytesNoCopy: buffer, count: bytesRead, deallocator: .none)
            let nonce = try AES.GCM.Nonce()
            let sealedBox = try AES.GCM.seal(chunkData, using: key, nonce: nonce)
            
            var size = UInt32(sealedBox.ciphertext.count).bigEndian
            let sizeData = Data(bytes: &size, count: MemoryLayout<UInt32>.size)
            
            outputHandle.write(sizeData)
            outputHandle.write(nonce.withUnsafeBytes { Data($0) })
            outputHandle.write(sealedBox.ciphertext)
            outputHandle.write(sealedBox.tag)
        }
    }
    
    static func decryptFile(inputURL: URL, outputURL: URL, key: SymmetricKey) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }
        fileManager.createFile(atPath: outputURL.path, contents: nil, attributes: nil)
        
        guard let inputHandle = try? FileHandle(forReadingFrom: inputURL),
              let outputHandle = try? FileHandle(forWritingTo: outputURL) else {
            throw CryptoError.fileReadError
        }
        
        defer {
            try? inputHandle.close()
            try? outputHandle.close()
        }
        
        while true {
            let sizeData = inputHandle.readData(ofLength: MemoryLayout<UInt32>.size)
            if sizeData.isEmpty { break } // EOF
            if sizeData.count < 4 { throw CryptoError.chunkDecryptionFailed }
            
            let size = UInt32(bigEndian: sizeData.withUnsafeBytes { $0.load(as: UInt32.self) })
            
            let nonceData = inputHandle.readData(ofLength: 12)
            if nonceData.count < 12 { throw CryptoError.chunkDecryptionFailed }
            let nonce = try AES.GCM.Nonce(data: nonceData)
            
            let ciphertextData = inputHandle.readData(ofLength: Int(size))
            if ciphertextData.count < Int(size) { throw CryptoError.chunkDecryptionFailed }
            
            let tagData = inputHandle.readData(ofLength: 16)
            if tagData.count < 16 { throw CryptoError.chunkDecryptionFailed }
            
            let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertextData, tag: tagData)
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            
            outputHandle.write(decryptedData)
        }
    }
}
