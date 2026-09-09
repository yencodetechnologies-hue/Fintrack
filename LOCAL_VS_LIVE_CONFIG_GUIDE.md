# Local vs. Live Production Configuration Guide

This document serves as the master reference for switching **Fintrack** between **Local Development Mode** and **Live Production Mode**.

---

## 🔄 Quick Mode Switch Matrix

| Setting / File | 🟡 Local Development Mode | 🟢 Live Production Mode |
| :--- | :--- | :--- |
| **Flutter Mobile App Base URL**<br>`lib/config/app_config.dart` | `static const String baseUrl = "http://192.168.100.247:3009";`<br>*(or `http://10.0.2.2:3009` for Android Emulator)* | `static const String baseUrl = "https://fintrack.yencodetechnologies.in";` |
| **Backend MongoDB URI**<br>`backend/.env` | `MONGO_URI=mongodb://localhost:27017/fintrack` | `MONGO_URI=mongodb://mycard:mycard@ac-7tksjgy-shard-00-00.p4cmrso.mongodb.net:27017,ac-7tksjgy-shard-00-01.p4cmrso.mongodb.net:27017,ac-7tksjgy-shard-00-02.p4cmrso.mongodb.net:27017/fintrack?ssl=true&replicaSet=atlas-z05aq3-shard-0&authSource=admin` |
| **Google Redirect URI**<br>`backend/.env` | `GOOGLE_REDIRECT_URI=http://192.168.100.247:3009/api/email/oauth/callback` | `GOOGLE_REDIRECT_URI=https://fintrack.yencodetechnologies.in/api/email/oauth/callback` |
| **Yahoo Redirect URI**<br>`backend/.env` | `YAHOO_REDIRECT_URI=http://192.168.100.247:3009/api/email/oauth/callback` | `YAHOO_REDIRECT_URI=https://fintrack.yencodetechnologies.in/api/email/oauth/callback` |

---

## 🟡 Current Status: LOCAL DEVELOPMENT MODE

### 1. `lib/config/app_config.dart`
```dart
class AppConfig {
  static const String baseUrl = "http://192.168.100.247:3009";
```

### 2. `backend/.env`
```env
MONGO_URI=mongodb://localhost:27017/fintrack
PORT=3009
GOOGLE_REDIRECT_URI=http://192.168.100.247:3009/api/email/oauth/callback
YAHOO_REDIRECT_URI=http://192.168.100.247:3009/api/email/oauth/callback
```

---

## 🟢 How to Switch Back to LIVE Production Mode

To revert to **Live Production Mode**, update the two files as follows:

### Step 1: Update `lib/config/app_config.dart`
```dart
class AppConfig {
  static const String baseUrl = "https://fintrack.yencodetechnologies.in";
```

### Step 2: Update `backend/.env`
```env
MONGO_URI=mongodb://mycard:mycard@ac-7tksjgy-shard-00-00.p4cmrso.mongodb.net:27017,ac-7tksjgy-shard-00-01.p4cmrso.mongodb.net:27017,ac-7tksjgy-shard-00-02.p4cmrso.mongodb.net:27017/fintrack?ssl=true&replicaSet=atlas-z05aq3-shard-0&authSource=admin
GOOGLE_REDIRECT_URI=https://fintrack.yencodetechnologies.in/api/email/oauth/callback
YAHOO_REDIRECT_URI=https://fintrack.yencodetechnologies.in/api/email/oauth/callback
```
