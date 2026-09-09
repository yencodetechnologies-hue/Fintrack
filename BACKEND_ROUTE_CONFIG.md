# Backend Route Configuration & Reversion Guide

This document records the backend route configuration for the Fintrack Flutter app and provides quick copy-paste snippets to switch between **Local Testing** and **Live Production**.

---

## 📍 Target File
**[lib/config/app_config.dart](file:///e:/Yencode/Fintrack/lib/config/app_config.dart)** (Line 7)

---

## ⚙️ Current Active Environment: LOCAL TESTING

```dart
class AppConfig {
  // Local Testing Endpoint (Port 3009)
  // Android Emulator: http://10.0.2.2:3009 | iOS Simulator/Desktop: http://localhost:3009
  // Production Endpoint: https://fintrack.yencodetechnologies.in
  static const String baseUrl = "http://10.0.2.2:3009";
```

---

## 🔄 Quick Reversion Snippets

### 1. Revert to Live Production Environment 🚀
To switch the app back to the live production server, edit `lib/config/app_config.dart`:

```dart
class AppConfig {
  // Live Production Endpoint
  static const String baseUrl = "https://fintrack.yencodetechnologies.in";
```

---

### 2. Local Testing Options 💻

| Environment | `baseUrl` Setting |
| :--- | :--- |
| **Android Emulator (Local Backend)** | `static const String baseUrl = "http://10.0.2.2:3009";` |
| **iOS Simulator / Web / Windows Desktop** | `static const String baseUrl = "http://localhost:3009";` |
| **Physical Phone (via Local Wi-Fi)** | `static const String baseUrl = "http://<YOUR_LOCAL_IP>:3009";` |
| **Live Production** | `static const String baseUrl = "https://fintrack.yencodetechnologies.in";` |

---

## 🛠️ Local Server Command
To start your local Node.js backend on port `3009`:

```bash
cd backend
npm start
# or node index.js / nodemon
```
