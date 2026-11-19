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
    // First successful send delivers the full 18-month history so the backend
    // can build its long-term memory; afterwards only a recent window is sent.
    @AppStorage("hasCompletedInitialHealthSync") private var hasCompletedInitialSync = false
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
        let quantityIdentifiers: [HKQuantityTypeIdentifier] = [
            .bodyMass, .stepCount, .activeEnergyBurned, .basalEnergyBurned,
            .heartRate, .restingHeartRate, .walkingHeartRateAverage, .vo2Max,
            .flightsClimbed, .distanceWalkingRunning, .appleExerciseTime, .walkingSpeed
        ]
        var typesToRead: Set<HKObjectType> = [HKObjectType.workoutType()]
        for identifier in quantityIdentifiers {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) {
                typesToRead.insert(type)
            }
        }
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
        
        let isInitialSync = !hasCompletedInitialSync
        fetchHealthSummary(fullHistory: isInitialSync) { structuredSummary in
            sendToBackend(healthSummary: structuredSummary, question: userInput) { response, success in
                DispatchQueue.main.async {
                    if success && isInitialSync {
                        self.hasCompletedInitialSync = true
                    }
                    self.messages.append(ChatMessage(text: response, isUser: false))
                    self.isSending = false
                }
            }
        }
    }
    
    /// Builds the health payload as one aggregated value per interval per metric.
    /// `fullHistory: true` covers 18 months at weekly granularity (initial sync);
    /// `false` covers the last 30 days at daily granularity. Aggregation keeps
    /// the payload within the backend LLM's token limit — raw samples do not fit.
    private func fetchHealthSummary(fullHistory: Bool, completion: @escaping (String) -> Void) {
        let calendar = Calendar.current
        let now = Date()
        let monthsBack = fullHistory ? -18 : -1
        let intervalDays = fullHistory ? 7 : 1
        let startDate = calendar.startOfDay(for: calendar.date(byAdding: .month, value: monthsBack, to: now) ?? now)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: now, options: [])

        // (identifier, JSON key, daily aggregation, unit)
        let metrics: [(HKQuantityTypeIdentifier, String, HKStatisticsOptions, HKUnit)] = [
            (.bodyMass, "weightKg", .discreteAverage, .gramUnit(with: .kilo)),
            (.stepCount, "steps", .cumulativeSum, .count()),
            (.activeEnergyBurned, "activeEnergyKcal", .cumulativeSum, .kilocalorie()),
            (.basalEnergyBurned, "basalEnergyKcal", .cumulativeSum, .kilocalorie()),
            (.heartRate, "avgHeartRateBpm", .discreteAverage, HKUnit.count().unitDivided(by: .minute())),
            (.restingHeartRate, "restingHeartRateBpm", .discreteAverage, HKUnit.count().unitDivided(by: .minute())),
            (.walkingHeartRateAverage, "walkingHeartRateBpm", .discreteAverage, HKUnit.count().unitDivided(by: .minute())),
            (.vo2Max, "vo2Max", .discreteAverage, HKUnit.liter().unitDivided(by: .minute()).unitDivided(by: .gramUnit(with: .kilo))),
            (.flightsClimbed, "flightsClimbed", .cumulativeSum, .count()),
            (.distanceWalkingRunning, "distanceWalkingRunningKm", .cumulativeSum, .meterUnit(with: .kilo)),
            (.appleExerciseTime, "exerciseMinutes", .cumulativeSum, .minute()),
            (.walkingSpeed, "walkingSpeedKmh", .discreteAverage, HKUnit.meterUnit(with: .kilo).unitDivided(by: .hour()))
        ]

        var resultsDict: [String: Any] = [:]
        let group = DispatchGroup()
        // Query handlers fire on background threads; serialize dictionary writes
        let resultsQueue = DispatchQueue(label: "com.healthsync.healthResults")

        for (identifier, key, options, unit) in metrics {
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { continue }

            group.enter()
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: options,
                anchorDate: startDate,
                intervalComponents: DateComponents(day: intervalDays)
            )
            query.initialResultsHandler = { _, collection, _ in
                let dayFormatter = DateFormatter()
                dayFormatter.dateFormat = "yyyy-MM-dd"
                var dataPoints: [[String: Any]] = []
                collection?.enumerateStatistics(from: startDate, to: now) { stats, _ in
                    let quantity = options == .cumulativeSum ? stats.sumQuantity() : stats.averageQuantity()
                    guard let quantity = quantity else { return }
                    let value = quantity.doubleValue(for: unit)
                    guard value.isFinite, value > 0 else { return }
                    dataPoints.append([
                        "date": dayFormatter.string(from: stats.startDate),
                        "value": (value * 100).rounded() / 100
                    ])
                }
                resultsQueue.sync { resultsDict[key] = dataPoints }
                group.leave()
            }
            healthStore.execute(query)
        }

        group.enter()
        let workoutSort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let workoutLimit = fullHistory ? 200 : 50
        let workoutQuery = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: workoutLimit, sortDescriptors: [workoutSort]) { _, samples, _ in
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "yyyy-MM-dd"
            var workoutPoints: [[String: Any]] = []
            if let workouts = samples as? [HKWorkout] {
                for workout in workouts {
                    var point: [String: Any] = [
                        "type": workout.workoutActivityType.displayName,
                        "durationMinutes": (workout.duration / 60).rounded(),
                        "date": dayFormatter.string(from: workout.endDate)
                    ]
                    if let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
                       let calories = workout.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie()) {
                        point["calories"] = calories.rounded()
                    }
                    workoutPoints.append(point)
                }
            }
            resultsQueue.sync { resultsDict["workouts"] = workoutPoints }
            group.leave()
        }
        healthStore.execute(workoutQuery)

        group.notify(queue: .main) {
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "yyyy-MM-dd"
            resultsDict["dataRange"] = [
                "from": dayFormatter.string(from: startDate),
                "to": dayFormatter.string(from: now),
                "granularity": fullHistory
                    ? "one aggregated value per week (sums for counts, averages for rates); date marks the start of the week"
                    : "one aggregated value per day (sums for counts, averages for rates)"
            ]
            if let jsonData = try? JSONSerialization.data(withJSONObject: resultsDict),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                completion(jsonString)
            } else {
                completion("{\"error\": \"Failed to serialize health data\"}")
            }
        }
    }
    
    private func sendToBackend(healthSummary: String, question: String, completion: @escaping (String, Bool) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion("You need to log in before using the AI.", false)
            return
        }

        user.getIDToken { idToken, error in
            if let error = error {
                completion("Failed to get ID token: \(error.localizedDescription)", false)
                return
            }

            guard let idToken = idToken else {
                completion("No ID token available.", false)
                return
            }
            
            // For simulator talking to your Mac:
            let urlString = "YOUR-BACKEND-URL/chat/message"
            guard let url = URL(string: urlString) else {
                completion("Backend URL is invalid.", false)
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
                completion("Failed to encode request.", false)
                return
            }

            request.httpBody = data

            URLSession.shared.dataTask(with: request) { data, _, error in
                if let error = error {
                    completion("Network error: \(error.localizedDescription)", false)
                    return
                }

                guard let data = data else {
                    completion("No data returned from backend.", false)
                    return
                }

                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let reply = json["reply"] as? String {
                    completion(reply, true)
                } else {
                    let raw = String(data: data, encoding: .utf8) ?? "Unreadable response"
                    print("🧾 Raw backend response:", raw)
                    completion("Backend returned no usable reply.", false)
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

extension HKWorkoutActivityType {
    var displayName: String {
        switch self {
        case .running: return "running"
        case .walking: return "walking"
        case .cycling: return "cycling"
        case .swimming: return "swimming"
        case .hiking: return "hiking"
        case .yoga: return "yoga"
        case .pilates: return "pilates"
        case .functionalStrengthTraining, .traditionalStrengthTraining: return "strengthTraining"
        case .highIntensityIntervalTraining: return "hiit"
        case .coreTraining: return "coreTraining"
        case .elliptical: return "elliptical"
        case .rowing: return "rowing"
        case .stairClimbing: return "stairClimbing"
        case .crossTraining: return "crossTraining"
        case .dance, .socialDance, .cardioDance: return "dance"
        case .tennis: return "tennis"
        case .basketball: return "basketball"
        case .soccer: return "soccer"
        case .golf: return "golf"
        default: return "other"
        }
    }
}
