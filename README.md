# 🌱 Sera Finans — Personal CFO & Gamified Savings Assistant

**Sera Finans** is a Flutter-based personal finance and hydration tracking application that combines strict daily budget discipline with a procedural, living botanical greenhouse ecosystem.

## ✨ Key Features

* **🌿 Procedural Botanical Greenhouse (`CustomPainter`):** Instead of static progress bars, every **₺100** added to the savings pool procedurally generates new flora—ferns, exotic flowers, bioluminescent mushrooms, a reflective lotus pond, hanging vines, and a glowing underground root network. Exceeding the daily spending limit wilts the leaves, while impulsively draining savings freezes the greenhouse.
* **💼 Personal CFO Calculation Engine:** Automatically locks funds required for unpaid fixed expenses (dormitory, bills, groceries) and divides the remaining net balance across the days left until the user's custom **payday**, calculating a real-time safe daily spending limit.
* **🪙 Smart Round-Up Micro-Savings:** Prompts users to round expenses up to the nearest ten and channels the spare change directly into the botanical savings pool.
* **⚡ One-Tap Recurring Income Templates:** Allows saving regular income sources (scholarships, allowances, salaries) as quick-action chips for instant balance updates.
* **📸 Wish Album (Visual Wishlist):** Stores screenshots of desired items locally on the device. Marking an item as purchased deducts it from the cash balance; abandoning the impulse purchase ("burying it in the garden") rewards the savings pool with 25% of the item's value.
* **💧 CFO Hydration & Dew System:** Tracks daily water intake, visually increasing ambient dew particles and humidity inside the greenhouse, backed by sleep-aware local notifications (`flutter_local_notifications`).
* **💾 Offline-First Local Persistence:** All financial logs, recurring templates, preferences, and wishlist images are persistently stored on-device using `shared_preferences` and `path_provider`.

## 🛠️ Tech Stack

* **Framework:** Flutter & Dart
* **Graphics & Rendering:** Custom procedural 2D rendering via `CustomPainter`
* **Local Storage:** `shared_preferences`, `path_provider`
* **Media & Notifications:** `image_picker`, `flutter_local_notifications`, `timezone`

## 📦 Installation (Android APK)

Download the latest `app-release.apk` directly from the **[Releases](../../releases)** section and install it on your Android device.