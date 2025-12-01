//
//  MainAppView.swift
//  HealthSync
//
//  Created by Shusei Yokoi on 2025/11/25.
//

import SwiftUI

struct MainAppView: View {
    @EnvironmentObject var auth: AuthViewModel

    var body: some View {
        NavigationStack {
            ContentView()
                .navigationTitle("HealthSync")
                .toolbar {
                    // LEFT: Terms & Privacy
                    ToolbarItem(placement: .navigationBarLeading) {
                        NavigationLink(destination: LegalView()) {
                            Text("Terms & Privacy")
                                .font(.footnote)
                        }
                    }

                    // RIGHT: Logout
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Logout") {
                            auth.signOut()
                        }
                    }
                }
        }
    }
}

