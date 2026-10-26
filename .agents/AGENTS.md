# Documentation Rule

Every time a new feature or update is shipped, you MUST clearly describe it in the `AI_Instruction.md` file in the root of the project for future reference.
Specifically, append the details to the `3. Core Implemented Features & Tracking Logic` section of the `AI_Instruction.md` file. This ensures all future AI agents have an up-to-date log of the app's capabilities and architecture.

# Development Priorities Rule

For every update and feature you implement, your primary priorities MUST be:
1. **Minimum Server Load**: Avoid unnecessary API calls. Rely heavily on local caching (SQLite).
2. **Robust Data Fetching**: Gracefully handle offline states and errors using the optimistic UI pattern and sync queue.
3. **Instant UI Updates**: Ensure stock and dashboard data updates instantly on the client side before waiting for server confirmation.
4. **Clean Architecture**: Strictly adhere to the Feature-First Clean Architecture structure (data, domain, presentation).
5. **Optimized App Experience**: Prioritize fluid animations, haptic feedback, and a premium UI/UX.

# Platform Rules Rule

This app is one layer of the WooPress platform. The **WooPress Connector plugin** is the integration layer and owns all app-facing server behavior (FCM push, visitor stats, health/dashboard endpoints, SMTP, custom emails, stock sync, `woopress_update_count`, attribution). The canonical ownership doc (`PLATFORM.md`) lives in the Connector plugin repository.

1. **Never depend on client-theme code.** The app talks only to the store's WooCommerce REST API and the plugin's `woopress/v1` endpoints.
2. **Never assume a connector feature exists** — read endpoints/fields defensively and keep safe fallbacks (e.g. `woopress_update_count` defaults to `1`).
3. **Endpoint/field contracts are frozen** unless `PLATFORM.md` is updated in the same change.
