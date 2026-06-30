# AI_Instruction: WooExpress Architecture & Memory Log

**IMPORTANT FOR ALL AI AGENTS:** 
This file is the single source of truth for the WooExpress Flutter application. You MUST read this file before making architectural changes or implementing major new features to prevent duplicate logic, maintain consistency, and understand why specific implementations exist.

## 1. Project Overview & Tech Stack
- **Framework:** Flutter (Mobile + Web fallback for debugging)
- **State Management:** Riverpod (`flutter_riverpod`)
- **Networking:** Dio (`dio`)
- **Local Storage / Offline Support:** SQLite (`sqflite`), Secure Storage (`flutter_secure_storage`)
- **Routing:** GoRouter (`go_router`)
- **Push Notifications:** Firebase Cloud Messaging (`firebase_messaging`)
- **UI & Aesthetics:** `flex_color_scheme` (dynamic dark mode), Lucide Icons (`lucide_icons`)

## 2. Architecture Pattern (Feature-First Clean Architecture)
The `lib` directory is strictly organized by **features**. Every feature (e.g., `orders`, `dashboard`, `auth`, `inventory`) must contain three subdirectories:
1. `data/`: Contains Repositories (Dio network calls, Local cache fetching).
2. `domain/`: Contains Models (Dart data classes like `order_model.dart`).
3. `presentation/`: Contains Screens, Widgets, and Riverpod Controllers (`providers/`).

Do **NOT** put network logic inside UI files. All data must flow: `API/Cache -> Repository -> Riverpod Controller -> UI Screen`.

## 3. Core Implemented Features & Tracking Logic

### Offline-First Architecture (Orders & Dashboard)
- **Implementation:** The app is built to survive airplane mode. We use a local SQLite database (`lib/core/database/database_helper.dart`).
- **How it works (Optimistic UI):**
  1. Repositories immediately return `cached_orders` or `optimistic_stats` from SQLite.
  2. Background Dio request fires.
  3. If successful, SQLite cache is overwritten and UI updates.
  4. If offline (DioException), the app gracefully swallows the error and relies entirely on the SQLite cache.
- **Background Sync Queue:** If a user makes a mutation (e.g., updating an order status) while offline, it is saved to the `sync_queue` table in SQLite. The `SyncService` (`lib/core/network/sync_service.dart`) listens to `connectivity_plus`. The moment internet is restored, it processes the queue silently.
- **Web Bypass:** `sqflite` crashes on Chrome. The `DatabaseHelper` explicitly checks `kIsWeb` and falls back to an in-memory `List` to allow for smooth browser debugging.

### WhatsApp Integration & Number Parsing
- **Implementation:** When launching WhatsApp to contact a customer from the Orders tab, the parsing logic happens **entirely on the Flutter side**.
- **Reasoning:** The companion WordPress site (KTF theme) allows users to input any phone number format (03XX, 3XX, +923XX) to maximize checkout conversions. The Flutter app is responsible for standardizing it to the exact WhatsApp API requirement. DO NOT try to push phone number validation back to the WordPress backend.

### Push Notifications
- **Implementation:** Uses FCM. Notifications are caught in `main.dart` via `_firebaseMessagingBackgroundHandler`. 
- **Storage:** Because we lack a central backend server to store notification history, notifications are saved locally as a JSON list inside `flutter_secure_storage` (`notifications_history_v1`) so the user can view a historical feed.

## 4. Instructions for Future AI Agents
1. **Never Duplicate Offline Logic:** If you need to make a new feature work offline, extend `database_helper.dart` and `sync_service.dart`. Do not create a new database engine.
2. **Web Compatibility:** Always remember this app is tested via `flutter run -d chrome`. Any new native packages (hardware, cameras, DBs) must check `if (kIsWeb)` to avoid crashing the debugging session.
3. **Log Your Changes:** If you implement a major new feature, you MUST append a new bullet point to the `Core Implemented Features` section in this document.
