//
//  LoginView.swift
//  HealthSync
//
//  Created by Shusei Yokoi on 2025/11/25.
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var auth: AuthViewModel

    @State private var email = ""
    @State private var password = ""
    @State private var isLoginMode = true

    var body: some View {
        VStack(spacing: 24) {
            Text("HealthSync")
                .font(.largeTitle)
                .bold()

            Picker("", selection: $isLoginMode) {
                Text("Login").tag(true)
                Text("Sign Up").tag(false)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            VStack(spacing: 16) {
                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)

                SecureField("Password", text: $password)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
            }
            .padding(.horizontal)

            if let error = auth.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button(
                action: {
                    if isLoginMode {
                        auth.signIn(email: email, password: password)
                    } else {
                        auth.signUp(email: email, password: password)
                    }
                },
                label: {
                    Text(isLoginMode ? "Login" : "Create Account")
                        .frame(maxWidth: .infinity)
                }
            )
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)

            if auth.isLoading {
                ProgressView()
            }

            Spacer()
        }
    }
}
