//
//  RootView.swift
//  HealthSync
//
//  Created by Shusei Yokoi on 2025/11/25.
//
import SwiftUI

struct RootView: View {
    @EnvironmentObject var auth: AuthViewModel

    var body: some View {
        Group {
            if auth.user != nil {
                MainAppView()
            } else {
                LoginView()
            }
        }
    }
}
