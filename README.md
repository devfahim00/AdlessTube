# AdlessTube

**An ad-free YouTube client for Android — built with Flutter.**

AdlessTube is a privacy-friendly, open-source YouTube front-end that lets you browse, search, watch, and download videos without ads, trackers, or interruptions. It uses [NewPipeExtractor](https://github.com/TeamNewPipe/NewPipeExtractor) under the hood to resolve video streams directly, so nothing is proxied through a third-party server.

[![Platform](https://img.shields.io/badge/platform-Android-3DDC84?logo=android&logoColor=white)](https://www.android.com)
[![Framework](https://img.shields.io/badge/framework-Flutter-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![License](https://img.shields.io/badge/license-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![GitHub release](https://img.shields.io/github/v/release/devfahim00/AdlessTube?color=red&label=latest)](https://github.com/devfahim00/AdlessTube/releases/latest)
[![GitHub stars](https://img.shields.io/github/stars/devfahim00/AdlessTube?style=social)](https://github.com/devfahim00/AdlessTube/stargazers)
[![GitHub issues](https://img.shields.io/github/issues/devfahim00/AdlessTube)](https://github.com/devfahim00/AdlessTube/issues)
[![Telegram](https://img.shields.io/badge/Telegram-Join-229ED9?logo=telegram&logoColor=white)](https://t.me/projectredfox)

---

## 📥 Download

Grab the latest APK from the Releases page:

### ➡️ [**Download Latest APK**](https://github.com/devfahim00/AdlessTube/releases/latest)

> Requires **Android 6.0 (Marshmallow)** or newer.

---

## 🎯 Purpose

The goal of AdlessTube is simple: **watch YouTube the way you want to.**

* 🚫 **No ads.** Ever. Not before, during, or after a video.
* 🕵️ **No tracking.** No analytics, no telemetry, no profiling.
* 📴 **Offline playback.** Download videos and music to watch or listen later.
* 🎨 **Clean, familiar UI.** Feels like the YouTube app, minus the clutter.
* 🔓 **Open source.** Fully transparent, community-driven, and free forever.

It's built for people who want an uninterrupted viewing experience on their own terms.

---

## ✨ Features

### 📺 YouTube
* Personalized home feed built from your watch history, subscriptions, saved videos, and search history.
* Endless scroll with an interleaved recommendation engine — no two refreshes look the same.
* Full video player with quality selection, playback speed (0.25x – 2x), double-tap to seek, and gesture controls.
* **Dubbed audio support** — switch between original and dubbed language tracks on the fly.
* Picture-in-Picture (PiP) mode on Android.
* Floating mini player that keeps videos playing while you browse.

### 🎵 Music
* Dedicated music player with background playback and media notification controls.
* Like songs, build a favorites queue, and start an endless **radio** of similar tracks.
* Autoplay related songs when the queue ends.
* Full music search with live suggestions.

### 🎬 Shorts
* Vertical, full-screen short video feed.
* Preloads the next short ahead of your swipe for instant playback.
* Personalised from your subscriptions and regional trends.

### ⬇️ Downloads
* Download **video + audio**, **video only**, or **audio only**.
* **Parallel segmented downloads** for significantly faster speeds.
* Live progress with pause, resume, and cancel.
* Download music directly from the music player.

### 📚 Library
* Watch history, subscriptions, saved videos, and downloads — all in one place.
* Fully searchable and organized by tab.

### 🎨 General
* **Region selection** (20+ countries) for localized trending and music feeds.
* **Service toggles** — enable or disable YouTube, Shorts, or Music independently.
* Light / Dark / System theme.
* Default video quality preference.
* Search history with live YouTube-suggested queries.
* Beautiful shimmer skeleton loaders throughout the app.
* In-app update checker powered by GitHub Releases.

---

## 🛠️ How It Works

AdlessTube doesn't use YouTube's official API. Instead, it relies on **NewPipeExtractor**, an open-source Java library that extracts video metadata and stream URLs directly from YouTube's public pages.

```
┌──────────────────────────────────────────────────────────┐
│                      AdlessTube App                      │
│                                                          │
│  ┌────────────┐  ┌────────────┐  ┌────────────────────┐  │
│  │  Home Feed │  │   Music    │  │      Shorts        │  │
│  └─────┬──────┘  └─────┬──────┘  └─────────┬──────────┘  │
│        │               │                    │            │
│        └───────────────┼────────────────────┘            │
│                        ▼                                 │
│            ┌───────────────────────┐                     │
│            │   NewPipeService      │                     │
│            │  (caching + parsing)  │                     │
│            └───────────┬───────────┘                     │
└────────────────────────┼─────────────────────────────────┘
                         ▼
              ┌───────────────────────┐
              │   newpipeextractor    │
              │   (Dart FFI bridge)   │
              └───────────┬───────────┘
                          ▼
                  ┌───────────────┐
                  │   YouTube     │
                  └───────────────┘
```

### Key Components

| Layer | Responsibility |
|-------|---------------|
| **`newpipe_service.dart`** | Wraps `newpipeextractor_dart`. Handles search, trending, channels, related videos, and stream resolution. Includes a shared in-memory cache (15 min TTL for streams, 30 min for related videos) so navigating back and forth is instant. |
| **`recommendation_service.dart`** | Builds the personalized home feed using weighted lottery selection across multiple source types — subscribed channels, related videos from recent watches, topic keywords, saved videos, and regional trending. |
| **`video_playback_service.dart`** | App-wide video player powered by `media_kit`. Handles quality switching, audio track selection, playback state persistence, and mini player lifecycle. |
| **`music_playback_service.dart`** | Background music player using `audio_service` + `just_audio`. Provides Android media notification controls and queue management. |
| **`download_service.dart`** | Segmented parallel downloader with live progress. Pre-allocates the target file and writes each segment via a positioned `RandomAccessFile` handle — typically 3–5× faster than a single connection. |
| **`storage_service.dart`** | Hive-based local persistence for history, subscriptions, liked songs, saved videos, downloads, settings, search history, and feed impression memory. |

---

## 🔨 Building from Source

### Prerequisites

* **Flutter SDK** `3.24.0` or newer — [install guide](https://docs.flutter.dev/get-started/install)
* **Android SDK** with API level 21+ (Android 5.0 Lollipop minimum)
* **Java JDK** `17` or newer
* A physical Android device or emulator

Verify your setup:

```bash
flutter doctor
```

### Steps

1. **Clone the repository**
   ```bash
   git clone https://github.com/devfahim00/AdlessTube.git
   cd AdlessTube
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Build the debug APK** (for testing)
   ```bash
   flutter build apk --debug
   ```

4. **Build the release APK**
   ```bash
   flutter build apk --release
   ```

   The output APK will be at:
   ```
   build/app/outputs/flutter-apk/app-release.apk
   ```

5. **Build split APKs per ABI** (smaller downloads)
   ```bash
   flutter build apk --split-per-abi --release
   ```

   Outputs:
   ```
   build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
   build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
   build/app/outputs/flutter-apk/app-x86_64-release.apk
   ```

### Running on a Device

```bash
flutter run
```

To select a specific device:

```bash
flutter devices
flutter run -d <device-id>
```

### Release Signing (optional)

To sign your own release builds, create `android/key.properties`:

```properties
storePassword=<your-password>
keyPassword=<your-password>
keyAlias=<your-key-alias>
storeFile=<path-to-your-keystore>
```

Then reference it in `android/app/build.gradle.kts` under `signingConfigs`.

---

## 📲 Installation

### Method 1 — Install the Pre-built APK (Recommended)

1. Go to the [**Releases page**](https://github.com/devfahim00/AdlessTube/releases/latest).
2. Download the latest `app-release.apk` (or the ABI-specific variant for your device).
3. On your Android device, enable **Install unknown apps** for your browser or file manager:
   * *Settings → Apps → Special access → Install unknown apps*
4. Open the downloaded APK and tap **Install**.
5. Launch AdlessTube, pick your region and services, and you're ready to go.

### Method 2 — Build & Install from Source

```bash
# Connect your device via USB with USB debugging enabled
flutter install --release
```

Or manually install a built APK:

```bash
adb install build/app/outputs/flutter-apk/app-release.apk
```

### First Launch

1. **Select your region** — this determines trending and music feeds.
2. **Choose services** — enable YouTube, Shorts, and/or Music.
3. **Start browsing** — the home feed personalizes as you watch, search, and subscribe.

You can change region and services anytime from **Menu → Region** and **Menu → Services**.

---

## 🧱 Project Structure

```
lib/
├── main.dart                      # App entry point, provider setup
├── models.dart                    # Data models (VideoItem, DownloadItem, etc.)
├── storage_service.dart           # Hive-based local persistence
├── newpipe_service.dart           # YouTube extraction + caching
├── recommendation_service.dart    # Home feed recommendation engine
├── video_playback_service.dart    # App-wide video player
├── music_playback_service.dart    # Background music player
├── download_service.dart          # Segmented parallel downloader
├── suggestion_service.dart        # Search-as-you-type suggestions
├── update_service.dart            # GitHub Releases update checker
├── region_service.dart            # Supported regions list
├── widgets.dart                   # Shared UI components + skeletons
├── service_select_screen.dart     # First-launch service picker
├── region_select_screen.dart      # First-launch region picker
└── screens/
    ├── main_shell.dart            # Bottom nav + mini player
    ├── home_screen.dart           # Personalized YouTube feed
    ├── music_screen.dart          # Music discovery feed
    ├── shorts_screen.dart         # Vertical shorts feed
    ├── library_screen.dart        # History / Subs / Saved / Downloads
    ├── search_screen.dart         # YouTube search
    ├── music_search_screen.dart   # Music search
    ├── player_screen.dart         # Video player
    ├── music_player_screen.dart   # Now Playing screen
    ├── video_controls.dart        # Custom player controls
    ├── channel_screen.dart        # Channel browse
    ├── downloads_screen.dart      # Downloads manager
    ├── menu_screen.dart           # Menu / settings hub
    ├── settings_screen.dart       # App settings
    └── region_change_screen.dart  # Region switcher
```

---

## 🧰 Tech Stack

| Package | Purpose |
|---------|---------|
| [`newpipeextractor_dart`](https://pub.dev/packages/newpipeextractor_dart) | YouTube metadata & stream extraction |
| [`media_kit`](https://pub.dev/packages/media_kit) | Video playback engine (mpv-based) |
| [`just_audio`](https://pub.dev/packages/just_audio) | Music playback |
| [`audio_service`](https://pub.dev/packages/audio_service) | Background audio + media notifications |
| [`provider`](https://pub.dev/packages/provider) | State management |
| [`hive_flutter`](https://pub.dev/packages/hive_flutter) | Local key-value storage |
| [`cached_network_image`](https://pub.dev/packages/cached_network_image) | Thumbnail caching |
| [`android_pip`](https://pub.dev/packages/android_pip) | Picture-in-Picture support |
| [`share_plus`](https://pub.dev/packages/share_plus) | Share sheet integration |
| [`url_launcher`](https://pub.dev/packages/url_launcher) | External link handling |
| [`package_info_plus`](https://pub.dev/packages/package_info_plus) | App version info |

---

## 🤝 Contributing

Contributions are welcome and appreciated!

1. Fork the repository.
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Commit your changes: `git commit -m "Add my feature"`
4. Push to the branch: `git push origin feature/my-feature`
5. Open a Pull Request.

### Guidelines

* Follow the existing code style and keep widgets/service boundaries clean.
* Run `flutter analyze` before submitting — no new warnings.
* Add comments for non-obvious logic.
* Test on a real device when possible.

Found a bug or have a feature idea? [Open an issue](https://github.com/devfahim00/AdlessTube/issues).

---

## ⚠️ Disclaimer

AdlessTube is an **unofficial** YouTube client and is **not affiliated with, endorsed by, or sponsored by YouTube or Google LLC**.

* All video content is fetched directly from YouTube's public infrastructure.
* This app does not host, store, or redistribute any copyrighted material.
* Users are responsible for complying with YouTube's Terms of Service in their region.
* The app is provided as-is for personal, educational, and research purposes.

If you enjoy the content you watch, please support the creators directly.

---

## 📄 License

This project is licensed under the **GNU General Public License v3.0**.

You may copy, distribute, and modify this software under the terms of the GPLv3. See the [LICENSE](LICENSE) file in this repository for the full text, or read it online at <https://www.gnu.org/licenses/gpl-3.0.html>.

```
Copyright (C) 2026 devfahim00

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
```

---

## 💬 Community

* **Telegram:** [t.me/projectredfox](https://t.me/projectredfox)
* **Issues:** [GitHub Issues](https://github.com/devfahim00/AdlessTube/issues)
* **Releases:** [GitHub Releases](https://github.com/devfahim00/AdlessTube/releases)

---

<div align="center">

**⭐ If you find this project useful, please consider giving it a star! ⭐**

Made with ❤️ by [devfahim00](https://github.com/devfahim00)

</div>
