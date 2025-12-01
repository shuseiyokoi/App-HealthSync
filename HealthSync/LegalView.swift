//
//  LegalView.swift
//  HealthSync
//
//  Created by Shusei Yokoi on 2025/12/01.
//

import SwiftUI

struct LegalView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                Text("Terms of Use")
                    .font(.title2)
                    .bold()
                
                Text("""
            By using the HealthSync AI Health Agent app, you agree to the following terms:
            
            • The app is provided “as is” without warranties of any kind.
            • The developer and distributor of this app are not responsible for any direct or indirect damages, losses, or liabilities resulting from use of the app, including but not limited to health decisions made based on its outputs.
            • The app does not provide medical diagnoses or treatment. For any health concerns, please consult a licensed medical professional.
            • All information and suggestions from the AI are for general wellness and educational purposes only.
            • You use this app at your own risk.
            """)
                
                Text("Privacy Policy")
                    .font(.title2)
                    .bold()
                
                Text("""
            • This app accesses your HealthKit data on your device (e.g., weight, steps, heart rate, activity) only with your explicit permission.
            • A structured summary of your HealthKit data and your chat messages are sent securely (via HTTPS) to the app’s backend server in order to generate AI responses.
            • The backend stores your chat history and associated health summaries in a secure database to:
              – provide short-term and long-term conversation memory,
              – help the AI give more consistent and personalized guidance over time,
              – and allow the developer to monitor, debug, and improve the service.
            • Your data is processed using third-party infrastructure services (such as Apple, Firebase, Azure, and OpenAI) that help run the app. These providers may temporarily process your data as part of delivering their services, but they are not authorized to use it for their own advertising.
            • Your data is **not** sold to advertisers.
            • Even though reasonable technical and organizational measures are used to protect your data, no system can be guaranteed 100% secure.
            • If you wish to stop using the app, you can delete the app from your device. If you would like your stored data to be deleted from the backend, please contact the developer and request data deletion.
            
            If you do not agree to these terms, please discontinue use of the app.
            """)
            }
            .padding()
        }
        .navigationTitle("Terms & Privacy")
    }
}
