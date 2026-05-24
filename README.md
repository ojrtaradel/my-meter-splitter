# ⚡ Meter Splitter [v1.5.0]

A professional-grade full-stack solution for managing and splitting shared electricity bills. Designed for efficient tracking, automated breakdown calculations, and visual consumption analytics.

By leveraging the Google Gemini API, this app eliminates manual data entry by extracting crucial numbers directly from photos of your electric bill and your physical sub-meter.

---

## 📖 The Problem It Solves (Mother Meter vs. Sub-Meter)

In many shared living situations, rental properties, or family compound lots (e.g., Rosie B6 L39 and Marilyn B6 L41), there is only one official electric line from the utility provider. This is the **Mother Meter**. 

To track a renter's or secondary unit's usage, a **Sub-Meter** is installed. However, the electric company only sends one combined bill to the Mother Meter. 

**The Challenge:**
1. **Fluctuating Rates:** The cost per Kilowatt-hour (kWh) changes every single month based on the utility company's generation charges. You cannot use a flat, permanent rate to bill the renter.
2. **Manual Math Errors:** Calculating the exact dynamic rate, finding the difference in sub-meter readings, and splitting the final monetary amount is tedious and prone to human error.
3. **Disputes:** Renters want transparency on how their bill was calculated and proof of the previous month's reading.

**The Solution:**
Meter Splitter automates this entirely. It calculates the *exact* floating rate for the current month (`Total Bill ÷ Total kWh`). It then multiplies that exact rate by the renter's consumed electricity (`New Sub-Meter Reading - Locked Previous Reading`). Finally, it subtracts the renter's share from the total bill to show exactly what the Mother Meter owes, saving a permanent, indisputable record to the cloud.

---

## 📸 App Screenshots

<p align="center">
  <img src="https://github.com/user-attachments/assets/ac794ca9-0d0a-4f1c-91ac-7ff2102e8276" width="30%" alt="Main Dashboard Input Screen">&nbsp; &nbsp; &nbsp; &nbsp;
  <img src="https://github.com/user-attachments/assets/39a95319-e047-4568-807e-446de6c81191" width="30%" alt="Computation Results Screen">&nbsp; &nbsp; &nbsp; &nbsp;
  <img src="https://github.com/user-attachments/assets/2b12e048-e2cf-413e-9830-892d879a280c" width="30%" alt="Analytics Screen">&nbsp; &nbsp; &nbsp; &nbsp;
  <img src="https://github.com/user-attachments/assets/ac859d9e-b4c6-4ef8-a218-262bf0e6f898" width="30%" alt="Billing History Screen">&nbsp; &nbsp; &nbsp; &nbsp;
</p>

---

## 🚀 Key Features

* **Smart Calculation:** Automates the split between a "Mother Meter" and "Sub-meter" based on your input parameters.
* **Billing History & Auditing:** Secure storage of all past bills.
    * Image-based audit trail: Upload photos of your original bill and meter readings.
    * **Payment Tracking:** "Mark as Paid" workflow with date logging and receipt photo capture.
* **Advanced Analytics:**
    * Dual-chart visualization (Consumption in kWh & Amount in ₱).
    * **Trend Analysis:** Interactive Red Trend Line overlay to track the trajectory of your monthly expenses and consumption.
    * Permanent data labeling for at-a-glance monitoring.
* **Administrative Control:** * PIN-protected deletion to prevent accidental removal of records.
    * Automatic receipt and photo cleanup upon record deletion.

## 🛠 Tech Stack

* **Frontend:** Flutter (Full-stack Web/Mobile)
* **Backend:** Firebase (Cloud Firestore & Firebase Storage)
* **Visualization:** `fl_chart` with custom Trend Line overlays
* **Animations:** `flutter_animate` for smooth, GSAP-style UI transitions and 3D effects.

## 📋 Latest Version Updates (v1.5.0)

* **Trend Line Integration:** Added a smooth, red visual trend line to Analytics charts to show bill trajectory.
* **Visual Enhancements:** Increased legibility of analytics data labels (Bold, outline shadow).
* **Workflow Improvement:** Moved "Mark as Paid" button directly to the billing history card for easier access.
* **Audit Expansion:** Receipts are now fully integrated into the Audit Photos row as the third thumbnail.

## 🚀 Deployment Instructions

### For Development
1. Clone the repository.
2. Ensure you have the latest Flutter SDK installed.
3. Run `flutter pub get` to install dependencies.
4. Run the app: `flutter run -d chrome --dart-define=GEMINI_API_KEY=YOUR_KEY`

### For Production
1. Build the web project:
   ```bash
   flutter build web --dart-define=GEMINI_API_KEY=YOUR_KEY

2. Deploy to Firebase:
   ```bash
   firebase deploy --only hosting
