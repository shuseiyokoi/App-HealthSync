import SwiftUI
import HealthKit
import FirebaseAuth


struct ChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
}

struct ContentView: View {
    @State private var weight: Double? = nil
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isSending = false
    @State private var healthAuthorized = false
    @FocusState private var isTextFieldFocused: Bool
    
    private var healthStore = HKHealthStore()
    
    var body: some View {
        VStack(spacing: 15) {

            // 🔹 Chat messages – full height except bottom input
            ScrollView {
                LazyVStack {
                    ForEach(messages) { message in
                        HStack {
                            if message.isUser { Spacer() }
                            Text(.init(cleanMarkdownTitles(message.text)))
                                .padding()
                                .background(message.isUser ? Color.blue : Color.gray.opacity(0.2))
                                .cornerRadius(10)
                                .foregroundColor(message.isUser ? .white : .primary)
                                .multilineTextAlignment(.leading)
                            if !message.isUser { Spacer() }
                        }
                        .padding(.horizontal)
                    }
                }
            }

            // 🔹 Input row
            HStack(spacing: 10) {
                TextField("Ask AI about your health...", text: $inputText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .focused($isTextFieldFocused)

                Button("Ask AI") {
                    guard !isSending, !inputText.isEmpty else { return }
                    askAI()
                }
                .disabled(isSending)

                if isSending {
                    ProgressView()
                        .frame(width: 20, height: 20)
                }
            }
            .padding()
        }
        .padding([.leading, .trailing])
        .onAppear {
            authorizeAndFetchIfNeeded()
        }
    }



    
    private func authorizeAndFetchIfNeeded() {
        let typesToRead: Set = [
            HKObjectType.quantityType(forIdentifier: .bodyMass)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!
        ]
        healthStore.requestAuthorization(toShare: nil, read: typesToRead) { success, _ in
            DispatchQueue.main.async {
                healthAuthorized = success
                if success {
                    readWeight()
                } else {
                    print("❌ HealthKit not authorized")
                }
            }
        }
    }
    
    private func readWeight() {
        guard let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: weightType, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, results, _ in
            if let result = results?.first as? HKQuantitySample {
                let kg = result.quantity.doubleValue(for: .gramUnit(with: .kilo))
                DispatchQueue.main.async {
                    self.weight = (kg > 0 && kg.isFinite) ? kg : nil
                }
            }
        }
        healthStore.execute(query)
    }
    
    private func askAI() {
        guard healthAuthorized else {
            authorizeAndFetchIfNeeded()
            return
        }
        
        let userInput = inputText
        inputText = ""
        isTextFieldFocused = false
        
        isSending = true
        messages.append(ChatMessage(text: userInput, isUser: true))
        
        fetchHealthSummary { structuredSummary in
            sendToBackend(healthSummary: structuredSummary, question: userInput) { response in
                DispatchQueue.main.async {
                    self.messages.append(ChatMessage(text: response, isUser: false))
                    self.isSending = false
                }
            }
        }
    }
    
    private func fetchHealthSummary(completion: @escaping (String) -> Void) {
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .month, value: -18, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date(), options: [])
        
        let healthDataTypes: [(HKQuantityTypeIdentifier, String, (HKQuantity) -> Double)] = [
            (.bodyMass, "weights", { $0.doubleValue(for: .gramUnit(with: .kilo)) }),
            (.stepCount, "steps", { $0.doubleValue(for: .count()) }),
            (.activeEnergyBurned, "activeEnergy", { $0.doubleValue(for: .kilocalorie()) }),
            (.heartRate, "heartRates", { $0.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) }),
            (.restingHeartRate, "restingHeartRates", { $0.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) }),
            (.walkingHeartRateAverage, "walkingHeartRates", { $0.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) }),
            (.vo2Max, "vo2Max", {
                $0.doubleValue(for: HKUnit.liter().unitDivided(by: .minute()).unitDivided(by: .gramUnit(with: .kilo)))
            }),
            (.flightsClimbed, "flightsClimbed", { $0.doubleValue(for: .count()) }),
            (.distanceWalkingRunning, "distanceWalkingRunning", { $0.doubleValue(for: .meter()) })
        ]
        
        var resultsDict: [String: [[String: Any]]] = [:]
        var dailyCalories: [String: Double] = [:]
        let group = DispatchGroup()
        
        for (identifier, key, unitConverter) in healthDataTypes {
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
                resultsDict[key] = []
                continue
            }
            
            group.enter()
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 550, sortDescriptors: [sort]) { _, samples, _ in
                var dataPoints: [[String: Any]] = []
                if let quantitySamples = samples as? [HKQuantitySample] {
                    for sample in quantitySamples {
                        let value = unitConverter(sample.quantity)
                        guard value.isFinite, value > 0 else { continue }
                        let timestamp = ISO8601DateFormatter().string(from: sample.endDate)
                        dataPoints.append(["value": value, "timestamp": timestamp])
                        if identifier == .activeEnergyBurned {
                            let day = DateFormatter.localizedString(from: sample.endDate, dateStyle: .short, timeStyle: .none)
                            dailyCalories[day, default: 0] += value
                        }
                    }
                }
                resultsDict[key] = dataPoints
                group.leave()
            }
            healthStore.execute(query)
        }
        
        group.notify(queue: .main) {
            resultsDict["dailyCaloriesEstimate"] = dailyCalories.map { ["date": $0.key, "calories": $0.value] }
            if let jsonData = try? JSONSerialization.data(withJSONObject: resultsDict, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                completion(jsonString)
            } else {
                completion("{\"error\": \"Failed to serialize health data\"}")
            }
        }
    }
    
    private func sendToBackend(healthSummary: String, question: String, completion: @escaping (String) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion("You need to log in before using the AI.")
            return
        }
        
        user.getIDToken { idToken, error in
            if let error = error {
                completion("Failed to get ID token: \(error.localizedDescription)")
                return
            }
            
            guard let idToken = idToken else {
                completion("No ID token available.")
                return
            }
            
            // For simulator talking to your Mac:
            let urlString = "YOUR-API-KEY"
            guard let url = URL(string: urlString) else {
                completion("Backend URL is invalid.")
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
            
            let body: [String: Any] = [
                "health_summary": healthSummary,
                "question": question
            ]
            
            guard let data = try? JSONSerialization.data(withJSONObject: body) else {
                completion("Failed to encode request.")
                return
            }
            
            request.httpBody = data
            
            URLSession.shared.dataTask(with: request) { data, _, error in
                if let error = error {
                    completion("Network error: \(error.localizedDescription)")
                    return
                }
                
                guard let data = data else {
                    completion("No data returned from backend.")
                    return
                }
                
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let reply = json["reply"] as? String {
                    completion(reply)
                } else {
                    let raw = String(data: data, encoding: .utf8) ?? "Unreadable response"
                    print("🧾 Raw backend response:", raw)
                    completion("Backend returned no usable reply.")
                }
            }.resume()
        }
    }
    
    
    func cleanMarkdownTitles(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: .newlines)
        return lines.map {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("#") ?
            $0.replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression) :
            $0
        }.joined(separator: "\n")
    }
}
