import SwiftUI

struct LockScreenView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var password = ""
    @State private var showError = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 30) {
                Image(systemName: "applewatch")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .foregroundColor(.white)
                
                Text(authManager.isFirstLaunch ? "Setup Watch Vault" : "Watch")
                    .font(.system(size: 28, weight: .light, design: .default))
                    .foregroundColor(.white)
                
                SecureField(authManager.isFirstLaunch ? "Create Password" : "Password", text: $password)
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(10)
                    .foregroundColor(.white)
                    .accentColor(.white)
                    .padding(.horizontal, 40)
                    .onSubmit {
                        submit()
                    }
                
                if showError {
                    Text("Incorrect Password")
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                Button(action: submit) {
                    Text(authManager.isFirstLaunch ? "Set Password" : "Unlock")
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white)
                        .cornerRadius(10)
                }
                .padding(.horizontal, 40)
            }
        }
    }
    
    private func submit() {
        showError = false
        if authManager.isFirstLaunch {
            let success = authManager.setupPassword(password)
            if !success { showError = true }
        } else {
            let success = authManager.authenticate(password)
            if !success { showError = true }
        }
        password = ""
    }
}
