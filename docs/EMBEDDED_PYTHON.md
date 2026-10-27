# Embedded Python Proof of Concept (M5a) Documentation

## Overview

This document describes the embedded Python proof of concept implemented for Impostor (M5a) using `serious_python`. It details the bundled runtime version, packaging mechanisms, dependency management, Android build requirements, APK size metrics, issues encountered and their resolutions, and current limitations.

---

## 1. Technical Baseline & Documentation Findings

All findings below are drawn directly from the official `serious_python` (version **2.0.0**) documentation, README, CLI tools, and Gradle build scripts:

### Package Version
- `serious_python`: `^2.0.0`
- `serious_python_android`: `2.0.0`
- `serious_python_platform_interface`: `2.0.0`

### Bundled Python Version for Android
From the official documentation:
> *"The plugin can bundle one of several Python releases per build, selected via the `--python-version X.Y` flag of `serious_python:main package` (or the `SERIOUS_PYTHON_VERSION` env var picked up by the Android/Darwin/Linux/Windows plugin build scripts). Defaults to the latest supported version when nothing is specified."*

Supported releases:
| Short Version | CPython Runtime |
|---|---|
| **3.12** | CPython 3.12.13 |
| **3.13** | CPython 3.13.13 |
| **3.14** | CPython 3.14.5 |

For Impostor, **Python 3.12** (`export SERIOUS_PYTHON_VERSION=3.12`) was chosen to match our development environment and ensure maximum package compatibility.

### Packaging Mechanism & CLI Options
From the official documentation:
> *"There is `package` command which takes a directory with Python app as the first argument. The command must be run in Flutter app root directory, where `pubspec.yaml` is located. The path could be either relative or an absolute.*
> *To package Python files for the specific platform:*
> `dart run serious_python:main package app/src -p {platform}`"

Command syntax:
```bash
dart run serious_python:main package <path_to_app_dir> -p Android [options]
```

Key CLI options:
- `-p, --platform` (mandatory): `[iOS, Android, Emscripten, Windows, Linux, Darwin]`
- `--python-version`: `[3.12, 3.13, 3.14]` (defaults to `$SERIOUS_PYTHON_VERSION` or `3.14`)
- `-r, --requirements`: Specifiers passed to `pip` (e.g. `-r websockets==17.3`)
- `-a, --asset`: Output zip path relative to `pubspec.yaml` (default `assets/app.zip`)
- `--exclude`: Comma-separated relative paths to exclude (e.g. tests, build artifacts)
- `--skip-site-packages`: Skip pip installation of site packages
- `--compile-app`: Compile Python application (`.pyc`) before packaging
- `--compile-packages`: Pre-compile dependency packages before packaging
- `--cleanup` / `--cleanup-app` / `--cleanup-packages`: Strip junk files, headers, and docs
- `--verbose`: Enable detailed logs

### Pure-Python Dependencies
From the official documentation:
> *"All 'pure' Python packages are supported. These are packages that implemented in Python only, without native extensions written in C, Rust or other low-level language."*
> *"To package for `iOS` and `Android` platforms developer should set `SERIOUS_PYTHON_SITE_PACKAGES` environment variable with a path to a temp directory for installed app packages. The contents of that directory is embedded into app bundle during app compilation."*

`websockets==17.3` is confirmed to be **pure Python**:
- Wheel distribution tag: `websockets-17.3-py3-none-any.whl`
- Fallback check: When C speedups (`websockets.speedups`) are absent, `websockets` falls back to its 100% pure Python implementation seamlessly.

### Android Requirements (minSdk, ABIs, NDK)
- **`minSdkVersion`**: `21` in plugin build script (recommended `23+` for 64-bit alignment in modern APKs).
- **ABIs**:
  ```groovy
  ndk {
      if (python_version == '3.12') {
          abiFilters 'arm64-v8a', 'armeabi-v7a', 'x86_64'
      } else {
          abiFilters 'arm64-v8a', 'x86_64'
      }
  }
  ```
  `arm64-v8a`, `armeabi-v7a`, `x86_64` are supported for Python 3.12.
- **NDK / Toolchain**:
  The plugin downloads prebuilt CPython Android binaries (`python-android-dart-3.12-<abi>.tar.gz`) from `https://github.com/flet-dev/python-build/releases`. CMake builds the JNI bridge `libpyjni.so` and links against `libpython3.12.so`.

---

## 2. Architecture & Components Built

### 1. Repeatable Packaging Script (`scripts/package_python.sh`)
Automates:
1. Staging `engine/` and `server/` (including `server/embedded_entry.py`) without `.pyc` junk.
2. Setting `SERIOUS_PYTHON_VERSION=3.12` and `SERIOUS_PYTHON_SITE_PACKAGES=$APP_DIR/build/site-packages`.
3. Executing `dart run serious_python:main package` with `-p Android --python-version 3.12 -a assets/app.zip -r websockets==17.3`.
4. Outputting `app/assets/app.zip` (32 KB compressed).

### 2. Python Embedded Supervisor Entrypoint (`server/embedded_entry.py`)
- Configured as a long-lived supervisor running a single `asyncio` event loop.
- Exposes a loopback-only control channel strictly bound to `127.0.0.1` (port `8766` by default or configured via `EMBEDDED_CONTROL_PORT`). Never exposed to external network interfaces.
- Authenticated via a random cryptographically secure token passed by Dart via `EMBEDDED_CONTROL_TOKEN`. Rejects any unauthenticated or incorrect command with `ERROR: Unauthorized`.
- Accepts command line strings:
  - `START [port]`: Starts `GameServer` on `0.0.0.0:port` (default 8765).
  - `STOP`: Gracefully broadcasts `room_closed` to all clients, terminates websockets, cancels ticker and room tasks, clears the room registry hash table, and releases the listening socket. Idempotent.
  - `STATUS`: Returns JSON payload with `{running: bool, port: int?, rooms: int, connections: int}`.
  - `QUIT`: Stops any active server and shuts down supervisor loop.
- Survives client and connection errors without crashing the host process.

### 3. Debug Screen (`app/lib/screens/embedded_server_debug_screen.dart`)
- Accessible from `HomeScreen` by **long-pressing the "IMPOSTOR" title**.
- Queries device Wi-Fi IP address via `network_info_plus` (with interface fallback).
- Displays live supervisor and game server status (Running / Stopped, port, rooms, connections).
- "Start Embedded Server" button triggers supervisor startup and sends `START`.
- "Stop Server" sends `STOP` to the supervisor, releasing port 8765 and closing all active connections immediately.

---

## 3. Test Suite Validation (Python 3.12 & Flutter)

Running under the exact bundled Python version (**Python 3.12.15**) via `uv`:
```bash
uv run --python 3.12 pytest tests/ -v
```
**Results:**
- Total tests: **54**
- Passed: **54**
- Failed: **0**
- Duration: **0.68s**

Flutter test suite:
```bash
flutter test
```
**Results:**
- Total tests: **28**
- Passed: **28**
- Failed: **0**

---

## 4. APK Build Metrics

| Metric | Debug APK (`app-debug.apk`) | Release APK (`app-release.apk`) |
|---|---|---|
| **File Size** | **115 MB** | **55.6 MB** |
| **Asset Archive (`app.zip`)** | 32 KB | 32 KB |
| **Site Packages** | `websockets==17.3` (pure Python) | `websockets==17.3` (pure Python) |
| **ABIs Bundled** | `arm64-v8a`, `armeabi-v7a`, `x86_64` | `arm64-v8a`, `armeabi-v7a`, `x86_64` |

*Note: In production with split-per-ABI (`flutter build apk --split-per-abi`), the release APK for `arm64-v8a` is estimated at approximately **18–22 MB**.*

---

## 5. Problems Hit & How They Were Resolved

### Issue 1: `SERIOUS_PYTHON_SITE_PACKAGES` environment variable missing
- **Symptom:** Gradle build aborted with:
  `A problem occurred evaluating project ':serious_python_android'. > SERIOUS_PYTHON_SITE_PACKAGES environment variable is not set.`
- **Cause:** `serious_python_android/android/build.gradle` line 100 explicitly checks `System.getenv('SERIOUS_PYTHON_SITE_PACKAGES')`.
- **Fix:** Added `export SERIOUS_PYTHON_SITE_PACKAGES="$APP_DIR/build/site-packages"` and ensured directory exists with sub-folders for each ABI before invoking `flutter build` or `flutter run`.

### Issue 2: `android.bundle.enableUncompressedNativeLibs` removed in AGP 8.1
- **Symptom:** Gradle threw:
  `The option 'android.bundle.enableUncompressedNativeLibs' is deprecated. It was removed in version 8.1 of the Android Gradle plugin.`
- **Cause:** Deprecated property recommended in older `serious_python` docs.
- **Fix:** Removed the flag from `android/gradle.properties`.

### Issue 3: `compileSdkVersion 31` incompatibility with AndroidX dependencies
- **Symptom:** AGP error:
  `Dependency 'androidx.core:core:1.13.1' requires libraries and applications that depend on it to compile against version 34 or later of the Android APIs. :serious_python_android is currently compiled against android-31.`
- **Cause:** Upstream `serious_python_android-2.0.0` specifies `compileSdkVersion 31`, whereas modern Flutter and AndroidX require API 34+.
- **Fix:** Updated `compileSdkVersion` to `34` in `serious_python_android` build configuration.

### Issue 4: `android:extractNativeLibs="true"` deprecated in AGP 8+
- **Symptom:** Build failed in `:app:packageDebug`:
  `android:extractNativeLibs is set to "true" in AndroidManifest.xml. Avoid setting android:extractNativeLibs="true" explicitly in AndroidManifest.xml, and instead set android.packagingOptions.jniLibs.useLegacyPackaging to true in the build script.`
- **Cause:** Android Gradle Plugin 8.0+ strictly enforces DSL packaging options over manifest attributes.
- **Fix:** Removed `android:extractNativeLibs="true"` from `AndroidManifest.xml` and added `packaging.jniLibs.useLegacyPackaging = true` in `app/android/app/build.gradle.kts`.

---

## 6. Milestone 5b: Real Create Room Flow & Architecture

Milestone 5b transitions the embedded Python server from a standalone debug utility to an integrated, seamless in-app hosting experience for local multiplayer gaming over Wi-Fi or mobile hotspot.

### Host Lifecycle & Supervisor Process Model

1. **CPython Process Constraints & The Supervisor Solution:**
   - As observed in `serious_python_android`, `SeriousPython.terminate()` is an empty stub (`{ // nothing to do }`). CPython initializes native state globally (`Py_Initialize()`) and cannot safely finalize or re-initialize inside an existing Android process.
   - Furthermore, `serious_python` chains run invocations through `_pythonRunQueue`. If a Python script runs an infinite loop or waits on a signal without exiting, future `SeriousPython.run(...)` calls hang indefinitely.
   - To resolve this cleanly, Python runs a **single long-lived supervisor** (`server/embedded_entry.py`) launched at most once per app process.
   - The supervisor exposes an authenticated control channel strictly bound to `127.0.0.1:8766`. External devices cannot reach or manipulate this control port.

2. **Control Protocol & Port Management:**
   - When the host starts (`HostService.ensureServerRunning()`):
     - If the supervisor process has not been launched, Dart generates a 256-bit cryptographically secure random token (`_controlToken = ...`) and passes it in `environmentVariables: {'EMBEDDED_CONTROL_TOKEN': _controlToken}` to `SeriousPython.run(...)`.
     - Dart connects via loopback TCP socket to `127.0.0.1:8766` and sends `AUTH <token>\nSTART 8765\n`.
     - The supervisor instantiates `GameServer`, begins listening on `0.0.0.0:8765`, and starts the engine ticker task.
     - Dart verifies readiness by polling the game port (`8765`) until it responds.
   - When the host leaves a room, dismisses the foreground notification, or taps "Stop" on the debug screen:
     - Dart connects to `127.0.0.1:8766` and issues `AUTH <token>\nSTOP\n`.
     - The supervisor executes full graceful teardown:
       - Broadcasts `room_closed` (`{"type": "room_closed", "data": {"reason": "Host closed room. Server stopped."}}`) to all connected websockets.
       - Closes all active client websockets with code `1000`.
       - Cancels the background ticker task and per-connection tasks.
       - Clears the custom `ChainedHashTable` room registry (`room_registry.clear()`) and room locks.
       - Closes the listening server socket (`server.close()` + `server.wait_closed()`), releasing port `8765`.
     - Dart polls `127.0.0.1:8765` to verify the port is completely closed before completing `stopServer()`.
     - `STOP` is idempotent: calling it multiple times when already stopped returns `OK: Stopped` safely.
     - Subsequent `START` commands cleanly spin up a fresh `GameServer` instance on the same port without restarting the app.

3. **Lifecycle Hooks & Last-Resort Fallback:**
   - Dart registers a `WidgetsBindingObserver` to monitor `AppLifecycleState.detached`. On app termination, Dart sends `STOP` best-effort.
   - The foreground task handler (`ImpostorHostTaskHandler.onDestroy()`) triggers `HostService.stopServer()` when the foreground service is stopped or the notification is swiped away.
   - **Emergency Fallback:** If `STOP` times out or the control channel fails to respond during shutdown, `HostService` triggers `_lastResortFallback()`: terminates the foreground task and kills the process (`exit(1)`), guaranteeing that the server can never run silently or leak listening ports in the background.

### Host IP Detection & Hotspot Fallback

On Android, `network_info_plus.getWifiIP()` queries `WifiManager.getConnectionInfo()`. When the host device enables a **Mobile Hotspot** instead of connecting to an external Wi-Fi router, `getWifiIP()` returns `null` because the Wi-Fi client is disabled.

`NetworkIpHelper` implements a robust multi-tiered resolution:
1. Try `network_info_plus.getWifiIP()`.
2. Fallback to enumerating network interfaces via `NetworkInterface.list()`.
3. Filter all IPv4 non-loopback addresses against standard RFC 1918 private address ranges:
   - `10.0.0.0/8`
   - `172.16.0.0/12` (`172.16.x.x` – `172.31.x.x`)
   - `192.168.0.0/16`
4. Prioritize interfaces whose names match known Wi-Fi / Hotspot adapters (`wlan`, `ap`, `wifi`, `softap`).
5. If no valid private IPv4 address is detected, the UI prompts the host to connect to Wi-Fi or enable their portable hotspot.

### QR Code & Join Protocol

- **QR Payload Format:** `QrPayload` encodes a clean JSON structure:
  ```json
  {
    "host": "192.168.43.1",
    "port": 8765,
    "code": "XKCD"
  }
  ```
  The parser also supports fallback URIs (`impostor://join?host=...&port=...&code=...`) and compact text (`192.168.43.1:8765#XKCD`).
- **Host Lobby:** Displays the room code, the full WebSocket address (`ws://<IP>:<PORT>`), a high-contrast QR code (`qr_flutter`), and copyable manual entry fields.
- **Client Scanner:** Uses `mobile_scanner` with a custom viewfinder overlay and torch toggle. If camera permissions are denied, the user is gracefully guided to the manual entry form. Upon scanning a valid payload, the address and room code are automatically populated, and the client auto-joins the room.

### Stability, Foreground Service & Android Permissions

To prevent the Android OS from killing or throttling the socket server when the screen dims or another app is briefly opened, the host activates:
1. **`wakelock_plus`**: Holds `PARTIAL_WAKE_LOCK` while the room is active.
2. **`flutter_foreground_task`**: Spawns an ongoing foreground notification:
   - Title: `Impostor server running`
   - Body: `Hosting room for nearby players`

#### Foreground Service Type Selection Rationale (`specialUse`)
Android 14+ (API level 34) requires applications declaring `<service android:name="...ForegroundService">` to specify an explicit `android:foregroundServiceType`.
- Standard types evaluated:
  - `dataSync`: Strictly intended for client synchronization with remote cloud storage or download managers. Google Play policies prohibit using `dataSync` for socket servers.
  - `connectedDevice`: Requires interacting with external physical peripherals (Bluetooth, USB companion devices).
  - `mediaPlayback` / `location`: Inapplicable.
- **Choice: `specialUse`**
  - Android provides `specialUse` specifically for legitimate use cases that require continuous foreground execution but do not fall into predefined categories.
  - Manifest declaration:
    ```xml
    <service
        android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
        android:foregroundServiceType="specialUse"
        android:exported="false">
        <property
            android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
            android:value="Local multiplayer game server hosting WebSocket connections for nearby players" />
    </service>
    ```

#### Target Manifest Permissions
- `android.permission.INTERNET`: Socket communications on `0.0.0.0:8765`.
- `android.permission.ACCESS_NETWORK_STATE` & `ACCESS_WIFI_STATE`: Network interface and hotspot IP discovery.
- `android.permission.WAKE_LOCK`: CPU wake lock during game hosting.
- `android.permission.FOREGROUND_SERVICE` & `FOREGROUND_SERVICE_SPECIAL_USE`: Android 14+ foreground service.
- `android.permission.POST_NOTIFICATIONS`: Runtime notification permission for Android 13+ (API 33+).
- `android.permission.CAMERA`: QR scanner integration.

---

## 7. Known Limitations & Operating Considerations

1. **Aggressive Vendor Battery Optimizations (OEM "Task Killers"):**
   - Certain Android skins (e.g. Xiaomi MIUI/HyperOS, Samsung OneUI, Huawei EMUI) employ aggressive out-of-spec power management that may kill background tasks or suspend network sockets if the host app remains in the background for extended periods.
   - *Mitigation:* While `flutter_foreground_task` and `wakelock_plus` provide standard Android protection, hosts on heavily skinned devices should disable "Battery Optimization" for Impostor in system settings if hosting long tournament sessions.
2. **Wi-Fi Client Isolation (AP Isolation):**
   - Public networks (universities, corporate guest Wi-Fi, hotels, cafes) commonly enable AP isolation on their routers. Under AP isolation, devices connected to the same Wi-Fi SSID cannot send TCP/UDP packets directly to one another.
   - *Mitigation:* When playing in public environments, the host should turn on their phone's **Personal Hotspot**, and other players should connect to the host's hotspot.
3. **OS Process Termination Under Low Memory:**
   - If the host phone experiences extreme memory pressure, Android may terminate the host process. If this occurs, the Python thread is terminated with the process and all players will experience a disconnect.
   - *Mitigation:* The Python server memory footprint is minimal (~25 MB total including CPython runtime and site-packages). Avoid running heavy background tasks (e.g. 3D games, video rendering) on the host phone while hosting.

---

## 8. Milestone 5b Acceptance Test Procedure (3 Physical Devices)

This test validates standalone phone-to-phone gameplay with **zero laptop or external server dependencies**.

### Equipment Required
- **Phone A (Host):** Android device running the Impostor APK.
- **Phone B (Joiner 1):** Android device running Impostor (joins via camera QR scan).
- **Phone C (Joiner 2):** Android device running Impostor (joins via manual IP + code entry).
- **Environment:** All 3 phones connected to the same Wi-Fi network, **OR** Phone B & C connected to Phone A's Portable Hotspot (laptop completely turned off).

### Step-by-Step Test Execution

#### Step 1: Host Preparation
1. Ensure the laptop is switched off or disconnected from the network.
2. On **Phone A**, ensure Wi-Fi is connected or Portable Hotspot is turned ON.
3. Launch **Impostor**. Enter player name (e.g., `Alice`).
4. Tap **Play on Wi-Fi**. Notice the network status bar displays the device's local IP (e.g., `192.168.43.1` or `192.168.1.100`).
5. Tap **Create Room**.
   - *Expected:* "Starting embedded Python server..." loading spinner appears briefly (~0.5s), the persistent notification `"Impostor server running"` appears in the Android notification drawer, and the app transitions to the **Lobby Screen**.
   - *Expected:* The lobby displays the 4-letter Room Code, the full address `ws://<Host-IP>:8765`, a high-contrast QR code, and `Alice (Host)` in the player list.

#### Step 2: Joiner 1 via QR Code
1. On **Phone B**, launch Impostor. Enter player name (e.g., `Bob`).
2. Tap **Play on Wi-Fi**, then tap **Join Room**.
3. Tap **Scan QR Code**.
   - *Expected:* Camera permission dialog appears (if first time). Grant permission.
   - Point Phone B's camera at Phone A's screen showing the QR code.
   - *Expected:* Phone B automatically reads the QR code, fills the server address and room code, and connects.
   - *Expected:* Phone A and Phone B both display `Bob` in their player lists.

#### Step 3: Joiner 2 via Manual Typing
1. On **Phone C**, launch Impostor. Enter player name (e.g., `Charlie`).
2. Tap **Play on Wi-Fi**, then tap **Join Room**.
3. Look at the manual join info displayed on Phone A's screen below the QR code (e.g., Server: `192.168.43.1:8765`, Room Code: `ABCD`).
4. Enter the address `192.168.43.1:8765` and Room Code in the input fields, then tap **Join Room**.
   - *Expected:* Phone C connects immediately. All three phones now display `Alice (Host)`, `Bob`, and `Charlie`.
   - *Expected:* On Phone A, the **Start Game** button becomes active (requires 3+ players).

#### Step 4: Full Game Playthrough
1. On **Phone A**, tap **Start Game**.
2. **Role Reveal Phase:** All 3 phones reveal their roles (e.g., 2 Crewmates see the secret word and category; 1 Impostor sees the category and "IMPOSTOR"). All tap "I Understand".
3. **Clue Phase:** In player order, each player submits their one-word clue. Clues appear in real-time across all 3 screens.
4. **Discussion & Voting Phase:** A timer runs. Players discuss, then vote for who they believe is the Impostor.
5. **Results Screen:** The votes are tallied, the Impostor is revealed, and the winner is announced.

#### Step 5: Lifecycle & Room Closure Verification
1. On **Phone A** (Host), leave the room or tap Back to return to Home.
   - *Expected:* Phone B and Phone C receive a `"Room Closed: The host left the room"` dialog and return to Home.
   - *Expected:* On Phone A, the foreground service notification `"Impostor server running"` dismisses and the wakelock releases.
2. On **Phone A**, tap **Play on Wi-Fi** -> **Create Room** a second time.
   - *Expected:* The room creates instantly without re-initializing the Python process (reusing the already running server singleton).
