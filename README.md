# ⚡ Meter Splitter App

An AI-powered Flutter web and mobile application designed to automatically calculate, split, and log sub-meter electricity bills with cloud synchronization.

By leveraging the Google Gemini API, this app eliminates manual data entry by extracting crucial numbers directly from photos of your electric bill and your physical sub-meter.

---

## 📖 The Problem It Solves (Mother Meter vs. Sub-Meter)

In many shared living situations, rental properties, or family compound lots (e.g., Block 6 Lot 39 and Lot 41), there is only one official electric line from the utility provider. This is the **Mother Meter**. 

To track a renter's or secondary unit's usage, a **Sub-Meter** is installed. However, the electric company only sends one combined bill to the Mother Meter. 

**The Challenge:**
1. **Fluctuating Rates:** The cost per Kilowatt-hour (kWh) changes every single month based on the utility company's generation charges. You cannot use a flat, permanent rate to bill the renter.
2. **Manual Math Errors:** Calculating the exact dynamic rate, finding the difference in sub-meter readings, and splitting the final monetary amount is tedious and prone to human error.
3. **Disputes:** Renters want transparency on how their bill was calculated and proof of the previous month's reading.

**The Solution:**
Meter Splitter automates this entirely. It calculates the *exact* floating rate for the current month (`Total Bill ÷ Total kWh`). It then multiplies that exact rate by the renter's consumed electricity (`New Sub-Meter Reading - Locked Previous Reading`). Finally, it subtracts the renter's share from the total bill to show exactly what the Mother Meter owes, saving a permanent, indisputable record to the cloud.

---

## ✨ Key Features

* **🧾 AI Bill Scanning:** Snap a photo of your main electric bill, and Gemini instantly extracts the **Total Amount Due** and **Total KWH Consumed**.
* **📸 AI Meter Scanning:** Take a picture of your sub-meter, and the AI will read and input the current dial reading automatically.
* **🧮 Automated Breakdown:** Instantly calculates the dynamic per-kWh rate and provides a clean, visual breakdown of the amount owed by the mother meter vs. the sub-meter.
* **🔒 Locked Historical Data:** Automatically fetches the previous month's reading from the database and locks it in as the current month's baseline to prevent tampering or typos.
* **📈 Price Trend Indicators:** Visually compares the current month's per-kWh rate to the previous month's rate, showing if electricity prices went up or down.
* **☁️ Cloud Storage:** Securely saves all calculated records and timestamps directly to a Firebase Cloud Firestore database for transparent tracking.
* **📱 Cross-Platform:** Beautifully responsive for the web and fully compilable as a native Android APK.

## 🛠 Tech Stack

* **Framework:** [Flutter](https://flutter.dev/) (Web & Android)
* **Database & Hosting:** [Firebase](https://firebase.google.com/) (Cloud Firestore & Firebase Hosting)
* **AI Engine:** [Google Gemini API](https://aistudio.google.com/) (`gemini-1.5-flash` model)
* **Animations:** `flutter_animate` for smooth, GSAP-style UI transitions

## 🚀 Getting Started (Local Development)

### Prerequisites
* Flutter SDK installed
* Firebase CLI installed and logged in
* A Google AI Studio API Key
* Android Studio (for APK building/emulation)

### Installation

1. **Clone the repository:**
   ```bash
   git clone [https://github.com/ojrtaradel/my-meter-splitter.git](https://github.com/ojrtaradel/my-meter-splitter.git)
   
   cd my-meter-splitter


## Screenshot
<img width="249" height="500" alt="image" src="https://github.com/user-attachments/assets/71f74d6c-ce62-4390-9f15-71a1035efc6d" />
