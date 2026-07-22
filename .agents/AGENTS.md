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
