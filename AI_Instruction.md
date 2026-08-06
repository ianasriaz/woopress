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
- **Release Build Rules (R8/Proguard):** To prevent release APK builds from breaking notifications, custom rules are included in `android/app/proguard-rules.pro` to keep `io.flutter.plugins.firebase.messaging.**` and `com.google.firebase.**`. A `keep.xml` is also added at `android/app/src/main/res/raw/keep.xml` to prevent the `cash_register.mp3` custom sound from being stripped by `isShrinkResources = true`.

### Dashboard Sales Charts (Client-Side Patching)
- **Implementation:** Weekly, Monthly, and Yearly sales charts use `fl_chart`. Data is fetched from WooCommerce's aggregated `/reports/sales` endpoint rather than querying raw orders to prevent server RAM spikes.
- **Client-Side Live Patching:** To keep the chart real-time without constantly pinging the server for updates, the app dynamically injects the `todayRevenue` (from `StoreStats`) into the last data point of the chart on the Flutter side. The server is completely unaware that the chart is updating live.

### Real-Time Offline Stock Deduction
- **Implementation:** Real-time stock drops happen completely on the client side without refreshing the API.
- **How it works:** When a push notification triggers a refresh of the `OrdersController`, it isolates the newly arrived orders and pipes them directly into `InventoryController.processNewOrder()`. The app then mathematically subtracts the ordered items from the local `stockQuantity` state.
- **Zero-Load Low Stock Filter:** The inventory UI includes a `LOW STOCK (N)` filter. To calculate `N` without downloading any products, `InventoryRepository` executes a lightweight HEAD-style request (`per_page=1&_fields=id`) and strictly reads the `X-WP-Total` header.

### Offline Auth & Gatekeeper Resilience
- **Implementation:** The app securely maintains offline access when internet drops.
- **How it works:** On boot, `AuthNotifier` attempts to verify the Keygen license. If the network throws a `DioException` timeout or 500 error, `GatekeeperRepository` traps it and safely returns `GatekeeperStatus.networkError`. Because `hasCredentials()` is true (from secure storage), the app assumes the user is authenticated and correctly routes them directly to the Offline Dashboard. It only revokes access on explicit 4xx HTTP responses.

### Robust Initial Routing & Unified Splash Screen
- **Implementation:** Replaced a distributed splashing approach with a unified `/splash` route and strict state-based routing.
- **How it works:** `GatekeeperScreen` is now strictly an input screen. The app holds the user on the `SplashScreen` while `AuthNotifier.checkExistingCredentials()` executes (including a forced update check and Keygen license validation). Once `checkExistingCredentials()` updates the state (`authenticated`, `needsUpdate`, `needsGatekeeper`, `unauthenticated`), GoRouter redirects the user to the correct screen instantly without UI flickering.

### Premium UI/UX Enforcement (Minimalism & Skeleton Shimmers)
- **Implementation:** UI components are continuously refined to maintain a minimalist, non-colorful aesthetic and buttery experience.
- **Example (Order Status Picker):** Migrated from heavily colored status blocks to a clean monochromatic design with soft borders and `InkWell` ripples. Only highly destructive actions (like "CANCEL ORDER") use distinct vibrant colors (red) to guide the user's attention.
- **Example (Skeleton Loading):** The app uses the `shimmer` package for initial data fetches (e.g., `SkeletonOrderCard`, `DashboardSkeletonView`) rather than `CircularProgressIndicator`. This maintains the UI structure during loading, providing a smoother, perception-of-speed upgrade and avoiding layout jumps.

### Updated Order Notification Content
- **Implementation:** Updated the FCM order notification content formatting across the WordPress connector plugin and Flutter app fallback.
- **Format:** Notifications now follow a concise conversational structure: Title as `🎉 New Order • $currency $total` and Body as `$customer_name just placed a $item_count-item order.` with fallback handling for unnamed customers.

### Push Notification Initialization & Background Handler Audit
- **Implementation:** Re-linked `FCMService.initialize()` in `main.dart` upon app launch so Android 13+ (`POST_NOTIFICATIONS`) runtime permissions are requested immediately after app installation.
- **Background Persistence:** Reintroduced `@pragma('vm:entry-point')` decorated `_firebaseMessagingBackgroundHandler` in `main.dart` to save incoming offline/background notifications directly into `flutter_secure_storage` (`notifications_history_v1`).
- **Channel Synchronization:** Updated `AndroidManifest.xml` default notification channel ID from legacy `sales_alerts_final` to `sales_alerts_v2`, matching both the Flutter local notification channel creation and the WordPress plugin FCM v1 payload. Added automatic topic re-subscription (`reSyncNotifications`) upon successful store authentication in `AuthNotifier`.

### Dual-Mode & Variable Product Atomic Stock Sync Architecture
- **Implementation:** Integrated server-side WooCommerce REST hooks (`woocommerce_rest_insert_product_object` & `woocommerce_rest_insert_product_variation_object`) in `woopress-connector.php` alongside client-side resolution in `inventory_controller.dart`.
- **Atomic Coupling:** Setting `stock_status = outofstock` automatically pairs with `stock_quantity = 0` (or `null` when `manage_stock` is disabled), preventing WooCommerce core data store from auto-reverting items to `instock`.
- **Variable Products:** Variation updates automatically trigger parent variable product recalculation (`WC_Data_Store::load('product-variable')->sync_stock_status($parent_id)`) and purge transients for both child and parent product IDs (`wc_delete_product_transients()`, `clean_post_cache()`).

### Inventory Timestamps & Sleek Professional Card UI (Activity Log Removed)
- **Activity Log Deprecation & Lightweight Timestamps:** To eliminate UI complexity and avoid unnecessary database/log querying, the separate Activity Log feature (`lib/features/activity_log`) has been completely removed. Instead, stock tracking and update times are displayed directly inside the Inventory screen on each product item.
- **Data & Domain Layer Integration (With Update Counter):** `ProductModel` and `VariationModel` parse both `date_modified` and an integer `woopress_update_count` directly from the WooCommerce REST API (`_fields` includes `woopress_update_count`). In `woopress-connector.php`, updates increment custom metadata `_woopress_update_count` and expose it via a zero-database-read REST field get_callback. When price or stock mutations occur on mobile in `InventoryController.updateSimpleProductOptimistic()`, both `dateModified` and `updateCount` are updated instantly on the client side without waiting for server confirmation.
- **Sleek Minimalist Card UI/UX:** Completely redesigned `_buildProductCard` in `inventory_screen.dart` to embody modern minimalist principles: rounded 12px card boundaries, subtle surface contrast, refined badge pills for `IN STOCK` / `SALE`, and a dedicated 2-line timestamp footer separating Added and Last Updated timestamps formatted clearly via `_formatCompactTimestamp` along with total modification count in parentheses (e.g., `Today, 02:15 PM (3)` or `15m ago (12)`).
- **Responsive 50/50 AppBar Title Badge:** To maximize vertical list real estate and provide a live executive pulse, the catalog status indicator is embedded directly inside `AppBar.title` using a responsive 50/50 `Expanded(flex: 1)` split opposite the screen title. It is presented as an aligned right-hand pill badge displaying a refresh symbol and the newest catalog modification timestamp.
- **Full-Stack WebP Master Overwrite & Zero-Load Optimization System:** In `inventory_repository.dart`, `_processImageForUpload()` runs asynchronously within a dedicated background Dart Isolate (`Isolate.run()`), guaranteeing zero UI lag or freezing during daily inventory additions. Images exceeding 1600px are smart-resized and compressed in pure Dart into lightweight optimized JPEGs at 80% quality (~150KB), slashing upload network payload by over 90% without risking native NDK build incompatibility. Server hook converts to `.webp` in <30ms and deletes original master files. Upon every successful image upload in `add_product_screen.dart`, the app fires a haptic impact and presents an instant floating success banner (`✨ Image optimized to WebP & uploaded successfully!`).

### Monochrome Order Cards Polish & Dynamic Active Status Labels
- **Monochrome Badge System (Zero Clashing Colors):** All UTM / Order Source badges (`SourceBadge` in `orders_screen.dart`) have been stripped of RGB brand colors (Facebook blue, Instagram pink, Google red) and unified into neutral greyscale tags (`onSurface` opacity variations). Similarly, all non-shipped order status chips are styled in clean neutral greyscale to prevent visual color fatigue.
- **Selective Neon Green Shipped Accent:** Completed/shipped order badges and action buttons intentionally retain a sharp neon green accent (`Color(0xFF34C759)`) with `"SHIPPED"` text so fulfilled orders immediately pop out during high-speed visual scanning.
- **Dynamic Active Status Button Labels:** Instead of displaying a generic `"UPDATE STATUS"` string on order cards, the action button dynamically reflects the currently active order status (e.g., `"PROCESSING"`, `"PENDING"`, `"ON HOLD"`, `"CANCELLED"` or `"SHIPPED"`). When a status is updated via Optimistic UI, the button text instantly transforms to display the newly selected state.
- **Executive SaaS Geometry:** Upgraded `_OrderCard` geometry to a modern 12px rounded profile (`BorderRadius.circular(12)`) with subtle surface contrast borders and consistent 8px radius action tiles for Phone, WhatsApp, and Status updates.
- **Universal Update Counter & Inline Source UI Refinements:** Resolved update counts remaining at 1 by replacing obsolete empty state diff checks in `woopress-connector.php` with direct REST insert (`woocommerce_rest_insert_product_object` & variation counterpart) and update action hooking with request deduplication guards (`$GLOBALS['woopress_counted_ID']`). Variation updates now also properly increment the parent product's counter. In `inventory_screen.dart`, the catalog update indicator in the AppBar was streamlined to plain icon+text (removing box decoration badge), and the sale badge was colored matching green (`0xFF34C759`) with `"ON SALE"` text. In `orders_screen.dart`, UTM source displays inline alongside Date and Time (`_InlineSource`) without a badge container, while Call and WhatsApp buttons feature light backgrounds with black and green icon/borders respectively.

## 4. Instructions for Future AI Agents
1. **Never Duplicate Offline Logic:** If you need to make a new feature work offline, extend `database_helper.dart` and `sync_service.dart`. Do not create a new database engine.
2. **Web Compatibility:** Always remember this app is tested via `flutter run -d chrome`. Any new native packages (hardware, cameras, DBs) must check `if (kIsWeb)` to avoid crashing the debugging session.
3. **Log Your Changes:** If you implement a major new feature, you MUST append a new bullet point to the `Core Implemented Features` section in this document.
