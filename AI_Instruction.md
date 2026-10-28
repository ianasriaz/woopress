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
- **Monochrome Badge System (Zero Clashing Colors):** All UTM / Order Source badges (`SourceBadge` in `orders_screen.dart`) have been stripped of RGB brand colors (Facebook blue, Instagram pink, Google red) and unified into neutral greyscale tags (`onSurface` opacity variations).
- **Dynamic Active Status Button & Badge Styling (Shipped & Soft-Red Cancelled):** The order action button and status chips dynamically represent the active status state:
  - **Completed / Shipped:** When an order is completed, the status badge and action button turn vibrant green (`Color(0xFF34C759)`) with `"SHIPPED"` text and a check icon (`LucideIcons.checkCircle`), making fulfilled orders instantly noticeable during scanning.
  - **Cancelled:** When an order is cancelled, both the status badge and button adopt an elegant, non-alarming soft red aesthetic (`Color(0xFFFF3B30).withValues(alpha: 0.12)` background, `0.3` alpha soft red border, and `Color(0xFFFF3B30)` text with `LucideIcons.xCircle` icon).
  - **Other Statuses:** Pending, Processing, and On Hold remain in clean monochromatic neutral styles.
- **Executive SaaS Geometry:** Upgraded `_OrderCard` geometry to a modern 12px rounded profile (`BorderRadius.circular(12)`) with subtle surface contrast borders and consistent 8px radius action tiles for Phone, WhatsApp, and Status updates.
- **Universal Timezone-Aware Today's Sales Calculation:** In `dashboard_repository.dart`, querying today's live orders is now anchored to UTC (`startOfTodayUtc = DateTime(now.year, now.month, now.day).toUtc()`) while each order's `date_created_gmt` is parsed as UTC and converted to the device's local timezone (`.toLocal()`). Orders are strictly validated against `now.year`, `now.month`, and `now.day`, preventing orders created yesterday from bleeding into today's sales across any worldwide timezone.

### WooPress Platform Consolidation (Phase 1: Conventions & Ownership)
- **Implementation:** Established a single-ownership model to stop app-integration features from being duplicated across the app, the Connector plugin, and the two client themes (KTF, 3Clothing).
- **Canonical doc:** `PLATFORM.md` in the WooPress Connector plugin repository defines the ownership matrix, frozen endpoint/field contracts, and a "where does this code go?" decision tree.
- **Boundary:** The **plugin** owns FCM push, visitor stats (`/wp-json/woopress/v1/stats`), health + `wc/v3/woopress-dashboard`, SMTP config, custom emails, stock sync/cache purge, `woopress_update_count`, and attribution meta. The **themes** own storefront rendering only. The **app** owns UI/offline cache and depends only on WooCommerce REST + plugin endpoints.
- **Dependency rule:** All data still flows `API/Cache -> Repository -> Riverpod Controller -> UI`; defensively handle a missing `woopress_update_count` (model default `1`).

### WooPress Platform Consolidation (Phase 2: Connector Feature Parity)
- **Implementation:** Moved the remaining app-integration features into the WooPress Connector plugin (v2.1.0), so the app no longer depends on any client theme for them.
- **`woopress_update_count`:** The plugin now registers `woopress_update_count` as a REST field on `product` and `product_variation` (backed by `_woopress_update_count`, incremented on REST updates, initialised to `1` on create). The inventory screen's modification counters are now server-authoritative; the app's default of `1` remains a safe fallback.
- **Atomic stock sync:** Setting a managed product to `outofstock` also zeroes its quantity (prevents WooCommerce reverting to `instock`); variation status bubbles to the parent variable product (`sync_stock_status`); product/variation caches are purged on every mutation.
- **Emergency SMTP fallback & order attribution:** Both now live in the plugin. Attribution is written to `_wc_order_attribution_*` / `_custom_order_source`, which `OrderModel.fromJson` reads for the `SourceBadge`.

### WooPress Platform Consolidation (Phase 3 & 4: Themes Retired, App Aligned)
- **Phase 3 (client themes):** KTF and 3Clothing no longer own platform features. Both visitor trackers and their dead `woofly/*` endpoints were removed, and the theme-side SMTP, order-attribution, cache-invalidation, and emergency-mail callbacks now short-circuit when the connector plugin's functions are present (`function_exists('woopress_connector_*')`). Behaviour is unchanged until the plugin's v2.1.0 code executes, so there is no outage window.
- **Phase 4 (this app):** `woopress_update_count` needed no change — it is already requested in `_fields` and parsed with a `1` fallback (`product_model.dart`), and the plugin now returns real values (unknown `_fields` entries are simply omitted when the plugin is absent, so older stores are unaffected). The connection-details dialog (`dashboard_screen.dart` → `_showConnectionInfo`) now probes the plugin's public `/wp-json/woopress/v1/health` instead of `/stats` and displays the deployed connector version (e.g. `Active (v2.1.0)`), making rollouts verifiable from inside the app.
- **Deliberately NOT adopted:** `wc/v3/woopress-dashboard` is *not* used for dashboard stats. Its "today" window is computed in UTC (`gmdate`) server-side, whereas this app anchors daily revenue to the device's local calendar day (the universal timezone fix above). Adopting it would regress those numbers, so the client-side `/reports/sales` + live-orders path stays authoritative.

### Icon Package Migration: `lucide_icons` → `lucide_icons_flutter` (2026-10-25)
- **Why:** `lucide_icons` (last release 0.257.0, June 2023) declares `class LucideIconData extends IconData`, and `IconData` became a **final class in Flutter 3.44 / Dart 3.12**. The package is abandoned, so there is no version to upgrade to and the app could not be compiled on current Flutter stable.
- **Fix:** Replaced it with the maintained fork **`lucide_icons_flutter: ^4.0.1`** in `pubspec.yaml`, and updated the import in the 10 files that reference it. The fork keeps the same `LucideIcons` class and ships all 52 icons this app uses (verified name-by-name).
- **Toolchain:** Flutter 3.47.8 (stable) / Dart 3.13.7. Do **not** work around this by pinning Flutter below 3.44 — the fork removes that constraint.
- **Verification:** `flutter analyze` → 0 errors; `flutter build web --release` → built successfully (Lucide font tree-shaken 930 KB → 17.9 KB).
- **Note:** running `flutter pub get` under Flutter 3.47 also added an `analyzer.exclude` block to `analysis_options.yaml` (build/ and platform dirs) and refreshed `pubspec.lock` transitive versions; both are toolchain-driven, not hand edits.

### Cancelled-Order Email + Cancellation Reason (plugin 2.2.0)
- **Plugin side:** `includes/emails/class-wc-custom-cancelled-email.php` sends a quiet customer email when an order becomes `cancelled` (hook: `woocommerce_order_status_changed`). It carries no tracking, totals or address, and renders `_woopress_cancel_reason` when present. A `_woopress_cancelled_email_sent` meta (written via `save_meta_data()`, so no order re-save) guarantees one send per order.
- **App side:** the cancel confirmation dialog now takes an optional **Reason** (`orders_screen.dart` → `_confirmCancel`), which flows through `OrdersController.updateStatus(..., cancelReason:)` into `OrdersRepository.updateOrderStatus()`, where it is appended to the same `PUT /wp-json/wc/v3/orders/{id}` payload as `_woopress_cancel_reason`. Because the offline queue stores the whole payload, a cancel made offline keeps its reason when it syncs.
- **Order status colours (current):** Completed → solid green `#34C759` "SHIPPED"; Cancelled → solid red `#FF3B30` "CANCELLED" with an x-circle icon (the chip uses a red tint, 0.15 fill / 0.4 border); On hold → soft butter yellow (`#FFF6DA` fill, `#EBD9A6` border, `#8A6A00` text/icon) — deliberately not a sharp yellow. Pending and Processing stay monochrome.

### Release APK Signing & Android Toolchain (2026-10)
- Android SDK installed via cmdline-tools at `C:\Android\Sdk` (platform-tools, platforms;android-36, build-tools 36.0.0; licences accepted). `flutter config --android-sdk` points there. JDK 21 (`C:\Program Files\Java\jdk-21`) is the toolchain's Java.
- `android/app/google-services.json` was **regenerated from the Firebase options hardcoded in `main.dart`** (gitignored, not committed). If Firebase console values ever change, re-download the real file or regenerate the same way.
- **Release signing:** new keystore `android/app/woopress-release-key.jks` (alias `woopress`, RSA-2048, 10,000-day validity, DN `CN=WooPress`), referenced by `android/key.properties` at the `android/` root. Both files are gitignored (`key.properties`, `**/*.jks`) — the keystore password exists **only** in that local file; it is deliberately not in any repo. Losing the keystore or password means clients can never update the app in place again — both must be backed up outside this machine.
- Released certificate fingerprint (SHA-256): `d85e9cd303ecebf0e81aded46698141e82bfd00e94ba254e0818b1988fbdc638`.
- **Build commands:** `flutter build apk --release` → single fat APK (~61 MB, all ABIs); `flutter build apk --release --split-per-abi` → one small APK per CPU architecture (~25–35 MB each); `flutter build appbundle --release` → AAB for Play Store. Debug builds (`--debug`) are ~167 MB and debug-signed — never ship them.
- **One-time migration:** every device running an older, differently-signed install must **uninstall first** before installing this release key (Android rejects signature changes). After that, all future builds signed from this keystore update in place.

## 4. Instructions for Future AI Agents
1. **Never Duplicate Offline Logic:** If you need to make a new feature work offline, extend `database_helper.dart` and `sync_service.dart`. Do not create a new database engine.
2. **Web Compatibility:** Always remember this app is tested via `flutter run -d chrome`. Any new native packages (hardware, cameras, DBs) must check `if (kIsWeb)` to avoid crashing the debugging session.
3. **Log Your Changes:** If you implement a major new feature, you MUST append a new bullet point to the `Core Implemented Features` section in this document.
