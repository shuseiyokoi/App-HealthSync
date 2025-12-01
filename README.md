
# 🩺 HealthSync — AI Health Coach Powered by Apple Health, Azure OpenAI & Firebase

**HealthSync** is an iOS app that turns your **Apple Health** data into personalized health coaching using **Azure OpenAI’s GPT-4o**.
You log in, sync HealthKit, chat with an AI coach, and it remembers your goals and past conversations over time.

Behind the scenes, HealthSync uses:

* **SwiftUI + HealthKit** on device
* **Firebase Auth** for login
* A **FastAPI backend** running on **Azure Container Apps**
* **Azure PostgreSQL** to store chat history & summaries
* **Azure OpenAI (GPT-4o)** for the brain

🔗 **TestFlight**: [Join Here](https://testflight.apple.com/join/xBj899wE)
📝 **Full Blog**: [Building AI Health Agent on Notion](https://shuseiyokoi.notion.site/Building-iOS-AI-Health-Agent-App-Using-Azure-OpenAI-SwiftUI-1ecf61fbe85c80e58c42c8df31fafc4f)

<img width="1736" height="780" alt="image (10)" src="https://github.com/user-attachments/assets/249ec739-0668-445e-bf75-b1c0f355cd1d" />


---

## 💡 What It Does

You can ask things like:

> “How active was I last month?”
> “Is my recent weight trend okay?”
> “How can I slowly lose a few kilos without losing muscle?”

HealthSync:

1. Reads your **Apple Health / HealthKit** metrics (with your permission)
2. Builds a structured summary (up to ~18 months)
3. Sends it with your question to a secure backend
4. The backend calls **GPT-4o** with:

   * Your health trends
   * Your recent chat history
   * A persistent summary of your goals & constraints
5. You get a friendly, coach-style answer back in the app

The agent *remembers you* via:

* **Short-term memory** — last few turns of conversation
* **Long-term memory** — summarized “profile” with your goals, constraints, habits & progress stored in Postgres

---

## ⚙️ How It Works

### 📲 iOS App (SwiftUI + HealthKit + Firebase)

* Built with **SwiftUI**
* Uses **HealthKit** to read:

  * Weight, steps, active energy, heart rate, VO₂ max, etc.
* Uses **Firebase Auth** (email/password) for login
* Renders messages in a simple chat UI
* Includes an in-app **Terms & Privacy** screen

On each question, the app:

1. Ensures HealthKit permission is granted
2. Fetches up to 18 months of relevant data
3. Serializes it into JSON
4. Retrieves a Firebase **ID token**
5. Sends a `POST /chat/message` request to the backend with:

   * `health_summary` (JSON string)
   * `question` (user text)
   * `Authorization: Bearer <Firebase ID token>`

### 🧠 Backend (FastAPI + Azure Container Apps)

The backend is a small **FastAPI** app running in a Docker container on **Azure Container Apps**. It:

* Verifies the **Firebase ID token** (Firebase Admin SDK)
* Looks up or creates the user in **Azure PostgreSQL**
* Logs chat turns into `chat_messages`
* Optionally builds / uses **long-term summaries** of the user’s behavior
* Calls **Azure OpenAI GPT-4o** with:

  * A system prompt (doctor + fitness coach persona)
  * The health summary
  * Recent chat context
  * Long-term summary JSON (goals, constraints, habits, progress)

Environment variables (for Container Apps):

* `DATABASE_URL` → Azure Postgres connection string
* `AZURE_OPENAI_API_KEY`
* `FIREBASE_SERVICE_ACCOUNT_JSON` (path inside the container)

### 🗄 Data & Memory (PostgreSQL on Azure)

Core tables:

* **`users`**

  * `id` (UUID)
  * `email`
  * `firebase_uid`
  * `created_at`

* **`chat_messages`**

  * `id` (UUID)
  * `user_id`
  * `question`
  * `answer`
  * `health_summary`
  * `created_at`

* **`chat_summaries`** (long-term memory, optional but planned)

  * `id` (UUID)
  * `user_id`
  * `period_start`
  * `period_end`
  * `summary_json` (goals / constraints / habits / progress / tone / agreements)
  * `created_at`

These summaries let the AI say things like:

> “We’ve been aiming for ~3kg loss over 2–3 months while protecting your muscle mass.”
> “Let’s avoid high-impact running because of your knee pain and focus on walking and strength training instead.”

---

## 🩺 Health Data Used

The app reads and summarizes up to ~18 months of:

* Body Mass (Weight)
* Step Count
* Active Energy Burned
* Heart Rate
* Resting Heart Rate
* Walking Heart Rate Average
* VO₂ Max
* Flights Climbed
* Distance (Walking/Running)

The backend stores **snapshots of these summaries** along with each chat, so it can reconstruct trends and generate meaningful long-term summaries.

Planned future metrics:

* Sleep
* Blood Pressure
* Hydration

---

## 🧠 Prompt Engineering & Memory

On the backend, a typical call to Azure OpenAI looks like:

```python
messages = [
    {
        "role": "system",
        "content": SYSTEM_PROMPT,  # doctor + trainer persona, safety rules, etc.
    },
    {
        "role": "user",
        "content": f"""
Here is this person's recent structured health data from their device
(weights, steps, heart rate, calories, etc.):

{health_summary}

Here are some high-level summaries of previous coaching sessions:
{long_term_summary_json}

Here is a short history of our recent conversation:
{recent_chat_history}

Now answer the user's new question in a friendly, supportive way:

{question}
""",
    },
]
```

The **system prompt** instructs the model to:

* Be a compassionate, professional health assistant
* Act like a mix of **general practitioner + certified trainer**
* Focus on safety, sustainable habits, and realistic plans
* Avoid technical language like “JSON” / “payload” / “data file”
* Explicitly recommend seeing a doctor for anything diagnostic or serious

---

## 🧪 Example Interaction

> **User:** I’ve been walking more lately — is my activity trend improving?
> **AI:** Over the past few weeks your average steps have ticked up compared to your baseline, which is a great sign. You’re not suddenly overdoing it, just nudging your daily movement upward. If you’d like to keep building on this, aim for a consistent step range (for example, 7,500–8,500 on weekdays) and one slightly higher day on the weekend.

---

## 📦 Architecture Overview

| Component          | Tech                                     |
| ------------------ | ---------------------------------------- |
| Frontend           | SwiftUI                                  |
| Health Data        | Apple Health / HealthKit                 |
| Auth               | Firebase Authentication (email/password) |
| Backend API        | FastAPI (Python)                         |
| Container Runtime  | Azure Container Apps                     |
| AI Assistant       | Azure OpenAI GPT-4o                      |
| Database           | Azure Database for PostgreSQL            |
| Container Registry | Azure Container Registry (ACR)           |


---

## 📃 Terms & Privacy (Current Behavior)

* HealthKit data is read locally on your device, then **sent via HTTPS** to the backend.
* The backend stores:

  * your **chat messages**
  * associated **health summaries**
  * and (optionally) **long-term chat summaries** to improve continuity.
* Data is processed using infrastructure providers like **Apple, Firebase, Azure, and OpenAI**.
* Data is **not sold to advertisers**.
* The app is **not** a medical device and does **not** provide diagnoses.
* For any serious symptoms or concerns, you should consult a licensed medical professional.

(There’s an in-app **Terms & Privacy** screen that reflects this.)

---

## 🔭 Roadmap

* 🔁 Better weekly/monthly insight summaries
* 💤 Sleep integration and recovery-oriented coaching
* 📊 Streaks, milestones, and motivational UI
* 💾 Export / delete data options directly from the app
* 🧠 Vector-based retrieval for even richer long-term memory

---

## 📹 Demo

👉 **TestFlight**: [https://testflight.apple.com/join/xBj899wE](https://testflight.apple.com/join/xBj899wE)
*(iPhone only, TestFlight required)*



---

## 👨‍💻 Author

Built by **[Shusei Yokoi](https://github.com/shuseiyokoi)**

📓 Long-form write-up:
[Building iOS AI Health Agent App Using Azure OpenAI & SwiftUI](https://shuseiyokoi.notion.site/Building-iOS-AI-Health-Agent-App-Using-Azure-OpenAI-SwiftUI-1ecf61fbe85c80e58c42c8df31fafc4f)

---

## 📄 License

MIT License

---

**Let your health data talk back — with memory, context, and a coach that actually remembers your story.** 🩺💬
