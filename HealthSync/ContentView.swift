import SwiftUI
import HealthKit

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
    
    private var healthStore = HKHealthStore()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 15) {
                VStack(spacing: 5) {
                    Text("AI Health Agent")
                        .font(.headline)
                    NavigationLink(destination: LegalView()) {
                        Text("Terms & Privacy")
                            .font(.footnote)
                            .foregroundColor(.blue)
                    }
                }
                .padding(.top)
                
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
                
                HStack(spacing: 10) {
                    TextField("Ask AI about your health...", text: $inputText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
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
        
        isSending = true
        messages.append(ChatMessage(text: inputText, isUser: true))
        
        fetchHealthSummary { structuredSummary in
            let userPrompt = """
            Patient Health Data (JSON):
            \(structuredSummary)

            Question:
            \(inputText)
            """
            
            sendToAzureOpenAIChat(userPrompt: userPrompt) { response in
                DispatchQueue.main.async {
                    messages.append(ChatMessage(text: response, isUser: false))
                    inputText = ""
                    isSending = false
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
    
    private func sendToAzureOpenAIChat(userPrompt: String, completion: @escaping (String) -> Void) {
        guard let url = URL(string: "OpenAI-URL-HERE") else {
            completion("Invalid Azure URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("YOUR-API-KEY", forHTTPHeaderField: "api-key")

        let body: [String: Any] = [
            "messages": [
                [
                    "role": "system",
                    "content": "You are a compassionate, professional health assistant combining the expertise of a certified fitness trainer and a general practitioner doctor. Your goal is to help users understand their health trends and provide safe, realistic, and personalized advice based on their body data, such as weight history, step count, heart rate, and calorie activity levels. You speak in a friendly, supportive, and encouraging tone. You always prioritize the user's safety, long-term well-being, and sustainable habit-building. The system already knows the user's health data — the frontend application automatically sends structured health data (e.g., from Apple Health). Do not mention technical terms like \"JSON\", \"data file\", or \"based on what you sent\". Instead, speak naturally, as if you're familiar with the user's recent health and lifestyle habits."
                ],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": 0.7
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
                completion("No data returned from Azure.")
                return
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let content = message["content"] as? String {
                completion(content)
            } else {
                let rawResponse = String(data: data, encoding: .utf8) ?? "Unreadable content"
                print("🧾 Raw Azure Response: \(rawResponse)")
                completion("Azure returned no usable response.")
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

struct LegalView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                Text("Terms of Use")
                    .font(.title2)
                    .bold()

                Text("""
                By using the AI Health Agent app, you agree to the following terms:

                • The app is provided “as is” without warranties of any kind.
                • The developer and distributor of this app are not responsible for any direct or indirect damages, losses, or liabilities resulting from use of the app, including but not limited to health decisions made based on its outputs.
                • The app does not provide medical diagnoses or treatment. For any health concerns, please consult a licensed medical professional.
                • You use this app at your own risk.
                """)

                Text("Privacy Policy")
                    .font(.title2)
                    .bold()

                Text("""
                • This app accesses your HealthKit data on your device (e.g., weight, steps, heart rate) only with your explicit permission.
                • No health data is stored or saved by the developer or app backend.
                • Your health data is sent directly to OpenAI’s API to generate responses. The developer has no access or control over how OpenAI processes this information.
                • The developer and distributor are not liable for any misuse, loss, or exposure of data during this process.

                If you do not agree to these terms, please discontinue use of the app.
                """)
            }
            .padding()
        }
        .navigationTitle("Terms & Privacy")
    }
}
