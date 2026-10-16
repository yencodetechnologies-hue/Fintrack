# Backend Route Configuration & Reversion Guide

This document records the backend route configuration for the Fintrack Flutter app and provides quick copy-paste snippets to switch between **Local Testing** and **Live Production**.

---

## 📍 Target File
**[lib/config/app_config.dart](file:///e:/Yencode/Fintrack/lib/config/app_config.dart)** (Line 7)

---

## ⚙️ API Environment Selection

```dart
class AppConfig {
  static const String baseUrl = String.fromEnvironment(
    "FINTRACK_API_BASE_URL",
    defaultValue: "https://fintrack.yencodetechnologies.in",
  );
```

---

## 🔄 Quick Reversion Snippets

### 1. Use the Live Production Environment 🚀
Production is the default; no additional setting is required.

```dart
class AppConfig {
  static const String baseUrl = String.fromEnvironment(
    "FINTRACK_API_BASE_URL",
    defaultValue: "https://fintrack.yencodetechnologies.in",
  );
```

---

### 2. Local Testing Options 💻

| Environment | `baseUrl` Setting |
| :--- | :--- |
| **Android Emulator (Local Backend)** | `flutter run --dart-define=FINTRACK_API_BASE_URL=http://10.0.2.2:3009` |
| **iOS Simulator / Web / Windows Desktop** | `flutter run --dart-define=FINTRACK_API_BASE_URL=http://localhost:3009` |
| **Physical Phone (via Local Wi-Fi)** | `flutter run --dart-define=FINTRACK_API_BASE_URL=http://<YOUR_LOCAL_IP>:3009` |
| **Live Production** | Default: `https://fintrack.yencodetechnologies.in` |

---

## 🛠️ Local Server Command
To start your local Node.js backend on port `3009`:

```bash
cd backend
npm start
# or node index.js / nodemon
```
