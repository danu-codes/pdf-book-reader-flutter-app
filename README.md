# Lumina Reader

A high-performance, lightweight offline PDF book reader for Android built with Flutter and SQLite. Designed for zero storage bloat, instant startup, and comfortable long-form reading.

---

## Features

### Library & Storage Management
- **Curated Bookshelf:** Import single or multiple PDFs directly from Android's native system file manager (*Downloads*, *Documents*, SD card, or internal folders) with zero duplicate storage overhead.
- **SQLite Persistence:** Book metadata, reading progress, shelves, and bookmarks are stored in a local SQLite database (`lumina_reader.db`), surviving Android cache clears cleanly.
- **Persistent Cover Thumbnails:** Automatically generates lightweight Page-1 PNG cover previews cached in application support storage.
- **Reading Shelves & Filtering:** Organize books across *All*, *Reading*, *Unread*, *Finished*, and *Bookmarked* tabs with instant search and multi-criteria sorting (*Recently Read*, *Recently Added*, *Title A–Z*, *Progress %*).
- **JSON Backup & Restore:** Export and restore reading progress and bookmarks across devices via JSON backup files.

### Reader Experience
- **Eye-Comfort Themes:** Switch seamlessly between *Day Light*, *Warm Sepia*, and *Dim Night Mode* using hardware-composited overlays with zero scroll lag.
- **Flexible Page Navigation:** Supports continuous vertical scrolling and horizontal page-flip modes, interactive page scrubbing, direct jump-to-page input, and embedded PDF Table of Contents (Chapters) navigation.
- **In-Document Search & Bookmarks:** Full-text PDF search with match highlighting and quick page bookmarking.
- **Reading Comfort Controls:** Configurable screen wake-lock (`wakelock_plus`) and global reader defaults accessible from the navigation sidebar.

---

## Tech Stack

| Layer | Technology |
| :--- | :--- |
| **Framework** | Flutter (Dart, Material 3) |
| **PDF Rendering Engine** | `pdfrx` (PDFium native bindings) |
| **Local Database** | `sqflite` (`lumina_reader.db`) |
| **Preferences & State** | `shared_preferences` |
| **File System & Picker** | `file_picker`, `path_provider`, `path` |
| **Device Utilities** | `wakelock_plus`, `flutter_launcher_icons` |

---

## Project Structure

```text
pdf_book_reader/
├── android/
│   └── app/
│       ├── build.gradle.kts          # R8 minification, resource shrinking & JVM 17 config
│       └── proguard-rules.pro        # Keep rules for Flutter & pdfrx JNI bindings
├── assets/
│   └── app_icon.png                  # Adaptive launcher icon artwork
├── lib/
│   ├── main.dart                     # App entry point & Material 3 light/dark themes
│   ├── models/
│   │   └── book_model.dart           # Book entity, shelf status & JSON serialization
│   ├── screens/
│   │   ├── library_screen.dart       # Bookshelf UI, shelf filters, sort & sidebar drawer
│   │   └── reader_screen.dart        # PDF viewer, themes, TOC drawer, search & scrubber
│   ├── services/
│   │   ├── pdf_scanner_service.dart  # Native file manager import & cover thumbnail generator
│   │   └── storage_service.dart      # SQLite CRUD operations, debounced saves & JSON backup
│   └── widgets/
│       ├── book_card.dart            # Continue Reading hero card & library list tiles
│       └── book_cover_thumbnail.dart # Async Page-1 cover loader
├── deploy_wireless.ps1               # Automated split-APK build & wireless ADB deploy script
└── pubspec.yaml                      # Package dependencies & launcher icon configuration
```

---

## Prerequisites

- **Flutter SDK:** `3.47.x` or newer (Dart `^3.13.7`)
- **Java Development Kit (JDK):** Java 17
- **Android SDK:** Compile/Target SDK configured via Flutter Gradle Plugin
- **Target Device:** Android physical device (`arm64-v8a`) or emulator (`x86_64`)

---

## Getting Started

1. **Clone the repository**
   ```bash
   git clone https://github.com/<your-username>/pdf_book_reader.git
   cd pdf_book_reader
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Generate launcher icons (optional)**
   ```bash
   dart run flutter_launcher_icons
   ```

4. **Run in debug mode**
   ```bash
   flutter run
   ```

---

## Building a Lightweight Release APK

Lumina Reader uses R8 code minification, resource shrinking, and per-ABI splitting to produce a compact ~22–28 MB release APK:

```bash
flutter build apk --release --split-per-abi
```

The generated architecture-specific APKs will be located at:
- **Physical Android Phones (ARM64):** `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
- **Android Emulators (x86_64):** `build/app/outputs/flutter-apk/app-x86_64-release.apk`

### Installing via ADB
```bash
# Over USB debugging
adb -d install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk

# Over Wireless ADB
adb -s <DEVICE_IP>:<PORT> install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```