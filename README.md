# ⚡ Meter Splitter App

An AI-powered Flutter web application designed to automatically calculate, split, and log sub-meter electricity bills. 

By leveraging the Google Gemini API, this app eliminates manual data entry by extracting crucial numbers directly from photos of your electric bill and your physical sub-meter.

## ✨ Key Features

* **🧾 AI Bill Scanning:** Snap a photo of your main electric bill, and Gemini instantly extracts the **Total Amount Due** and **Total KWH Consumed**.
* **📸 AI Meter Scanning:** Take a picture of your sub-meter, and the AI will read and input the current dial reading automatically.
* **🧮 Automated Breakdown:** Calculates the exact per-kWh rate and instantly provides a clean, visual breakdown of the amount owed by the mother meter vs. the sub-meter.
* **☁️ Cloud Storage:** Securely saves all calculated records and timestamps directly to a Firebase Cloud Firestore database for easy tracking.
* **📱 PWA Ready:** Beautifully responsive and fully installable as an app on your iPhone or Android home screen.

## 🛠 Tech Stack

* **Framework:** [Flutter](https://flutter.dev/) (Web)
* **Database & Hosting:** [Firebase](https://firebase.google.com/) (Cloud Firestore & Firebase Hosting)
* **AI Engine:** [Google Gemini API](https://aistudio.google.com/) (`gemini-1.5-flash` model)
* **Security:** `flutter_dotenv` for local environment variable protection
* **Animations:** `flutter_animate` for smooth, GSAP-style UI transitions

## 🚀 Getting Started (Local Development)

### Prerequisites
* Flutter SDK installed
* Firebase CLI installed and logged in
* A Google AI Studio API Key

### Installation

1. **Clone the repository:**
   ```bash
   git clone [https://github.com/ojrtaradel/my-meter-splitter.git](https://github.com/ojrtaradel/my-meter-splitter.git)
   cd my-meter-splitter