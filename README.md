<div align="center">
  <img src="assets/images/app_screen_logo.png" width="100" alt="WooPress Logo">
  <h1>WooPress</h1>
  <p><b>A modern, fast, and beautiful iOS & Android app to manage WooCommerce stores on the go.</b></p>
  
  [![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev/)
  [![Dart](https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev/)
  [![Riverpod](https://img.shields.io/badge/Riverpod-000000?style=for-the-badge&logo=dart&logoColor=white)](https://riverpod.dev/)
  [![PHP](https://img.shields.io/badge/PHP-777BB4?style=for-the-badge&logo=php&logoColor=white)](https://php.net/)
</div>

<br>

## 🚀 Overview

**WooPress** is a premium mobile client for WooCommerce store owners. It completely bypasses the need for costly middle-tier servers by connecting securely and directly to the store's native REST API. Built with high-performance Flutter, it features a fluid, heavily-animated dark mode UI that provides a world-class user experience.

This repository contains both the **Flutter Mobile App** and the **Custom PHP WordPress Plugin** used for dispatching real-time Firebase Push Notifications.

---

## ✨ Features

- 🔐 **Direct WooCommerce Authentication:** Connect to any store using the native WooCommerce API Consumer Key and Secret. No middle-man, no central database storing your keys.
- 📊 **Real-time Dashboard:** View sales, orders, and key metrics at a glance.
- 📦 **Inventory Management:** View, edit, and publish new products with complete image upload support.
- 🔔 **Instant Push Notifications:** Custom PHP plugin that listens to WordPress webhooks and uses the Firebase Admin SDK to push real-time alerts to the user's phone for events like "New Order".
- 🛡️ **Software Gatekeeper:** Built-in license verification system to validate beta users.
- 🎨 **Premium UI/UX:** Sharp, modern dark-mode aesthetic with custom haptics, micro-animations, and glassmorphism effects.

---

## 🛠️ Tech Stack

### Mobile App (Frontend)
*   **Framework:** Flutter
*   **Language:** Dart
*   **State Management:** Riverpod
*   **Routing:** GoRouter
*   **Networking:** Dio (HTTP Client)
*   **Storage:** Flutter Secure Storage (AES Encryption)
*   **Cloud Services:** Firebase Cloud Messaging (FCM)

### Web Server (Backend Plugin)
*   **Environment:** WordPress
*   **Language:** PHP
*   **Notifications:** Firebase Admin SDK for PHP

---

## 🏗️ Architecture

WooPress operates on a **decentralized architecture** designed for maximum security and minimum server cost. 

1. **API Communication:** The mobile app stores API keys securely in the device's keychain. It communicates directly with the user's WooCommerce REST API (`/wp-json/wc/v3`).
2. **Push Notifications:** To deliver reliable push notifications without a Node.js middleman, the provided `woopress-connector.php` plugin runs on the user's WordPress server. It hooks into WooCommerce order events and dispatches payloads directly to FCM.

---

## 💻 Getting Started

### Prerequisites
- Flutter SDK (v3.0+)
- Dart SDK
- Xcode (for iOS) & Android Studio (for Android)

### Running the App
1. Clone the repository:
   ```bash
   git clone https://github.com/ianasriaz/woopress.git
   cd woopress
   ```
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Set up Firebase:
   - *Note: For security reasons, the `google-services.json` and `GoogleService-Info.plist` files are excluded from this repository.*
   - You will need to create your own Firebase project and drop your config files into the respective `android/app/` and `ios/Runner/` directories.
4. Run the app:
   ```bash
   flutter run
   ```

### Installing the Backend Plugin
To enable Push Notifications on your store:
1. Zip the `woopress-connector.php` file and the required Firebase Admin SDK JSON.
2. Upload and install the zip as a plugin in your WordPress Admin Dashboard.

---

## 👨‍💻 Author

**Anas Riaz**
- Building the future of mobile eCommerce management.

*(This project was built to demonstrate proficiency in Mobile Architecture, API integrations, and Full-Stack problem solving).*
