import Foundation
import FirebaseAuth

class AuthViewModel: ObservableObject {
    @Published var user: User?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var handle: AuthStateDidChangeListenerHandle?

    init() {
        self.user = Auth.auth().currentUser
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.user = user
        }
    }

    deinit {
        if let handle = handle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    func signUp(email: String, password: String) {
        errorMessage = nil
        isLoading = true

        Auth.auth().createUser(withEmail: email, password: password) { [weak self] result, error in
            DispatchQueue.main.async {
                self?.isLoading = false

                if let error = error {
                    print("🔥 Firebase signUp error:", error)   // <— log full error
                    self?.errorMessage = error.localizedDescription
                    return
                }

                print("✅ Firebase signUp success:", result?.user.uid ?? "no uid")
                self?.user = result?.user
            }
        }
    }

    func signIn(email: String, password: String) {
        errorMessage = nil
        isLoading = true

        Auth.auth().signIn(withEmail: email, password: password) { [weak self] result, error in
            DispatchQueue.main.async {
                self?.isLoading = false

                if let error = error {
                    print("🔥 Firebase signIn error:", error)
                    self?.errorMessage = error.localizedDescription
                    return
                }

                print("✅ Firebase signIn success:", result?.user.uid ?? "no uid")
                self?.user = result?.user
            }
        }
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
            user = nil
        } catch {
            print("🔥 signOut error:", error)
            errorMessage = error.localizedDescription
        }
    }
}
