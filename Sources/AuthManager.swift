import Foundation
import CryptoKit
import SwiftUI

class AuthManager: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var isFirstLaunch: Bool = false
    
    // In-memory derived key for encryption/decryption, cleared when app is locked
    private(set) var derivedKey: SymmetricKey?
    
    init() {
        checkFirstLaunch()
    }
    
    private func checkFirstLaunch() {
        if KeychainManager.shared.load() == nil {
            isFirstLaunch = true
        } else {
            isFirstLaunch = false
        }
    }
    
    func setupPassword(_ pass: String) -> Bool {
        guard !pass.isEmpty else { return false }
        let passData = Data(pass.utf8)
        let hashed = SHA256.hash(data: passData)
        let hashData = Data(hashed)
        
        if KeychainManager.shared.save(password: hashData) {
            isFirstLaunch = false
            deriveKey(from: pass)
            isAuthenticated = true
            return true
        }
        return false
    }
    
    func authenticate(_ pass: String) -> Bool {
        guard !pass.isEmpty else { return false }
        let passData = Data(pass.utf8)
        let hashed = SHA256.hash(data: passData)
        let hashData = Data(hashed)
        
        if let storedHash = KeychainManager.shared.load(), storedHash == hashData {
            deriveKey(from: pass)
            isAuthenticated = true
            return true
        }
        return false
    }
    
    func lock() {
        isAuthenticated = false
        // Purge key from memory
        derivedKey = nil
        // Trigger storage cleaner immediately
        StorageCleaner.shared.purgeTempDirectory()
    }
    
    private func deriveKey(from pass: String) {
        // Derive a 256-bit key using HKDF
        let salt = "WatchVaultSalt".data(using: .utf8)!
        let inputKeyMaterial = SymmetricKey(data: Data(pass.utf8))
        derivedKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: inputKeyMaterial, salt: salt, info: Data(), outputByteCount: 32)
    }
}
