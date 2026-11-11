# Kid Town phone app (Android)

This fork builds the Luanti phone client as a **local-network app** for the
Kid Town server:

- **Installed from a local file.** The installable artifact is a debug APK
  signed with the standard Android debug key. Copy it to the phone over USB
  (or any local file transfer) and tap it. No Play Store account and no
  internet connection are needed to install it.
- **Uses the connected Wi-Fi, never mobile data.** `LocalNetwork.java` binds
  the whole app process to the Wi-Fi network currently connected. This works
  when that Wi-Fi has no internet access, which is how the town is meant to
  run. If Wi-Fi disappears, the app does not silently fall back to cellular.
- **Only talks to the local network.** The native build sets
  `LOCAL_NETWORK_ONLY`, which refuses any server address that is not a
  private IPv4 address (10/8, 172.16/12, 192.168/16, 127/8, 169.254/16), an
  IPv6 loopback/link-local/ULA address, or an IPv4-mapped private address.
  A public address or a hostname that resolves outside the LAN is rejected.
- **No internet screens.** On Android the public server list, ContentDB and
  the update checker are disabled at the default-settings level, and the
  Content tab is hidden. The Join Game tab keeps the address/port fields and
  the Login button, with a short "home Wi-Fi only" explanation.
- **Find town.** The Join Game tab's **Find town** button sends one ordinary
  Luanti handshake to the LAN broadcast address on the game port. The town PC
  answers with its own address, which the app fills in; the child never has to
  type an IP address.

## Install on a phone

1. Get the `KidTown-phone-debug-apks` artifact from the **phone-apk** GitHub
   Actions run, or build it locally (below). The workflow builds the
   `app-arm64-v8a-debug.apk` that modern phones need; the full `android`
   workflow still uploads every ABI.
2. If the phone already has the store version of Luanti installed, uninstall
   it first: Android will not install a debug-signed APK over the store's
   release signature. (The town world is on the PC, so nothing is lost.)
3. Connect the phone to the home Wi-Fi.
4. Copy the APK to the phone with a USB cable (or a local file share) and
   open it in the phone's Files app.
5. Allow "install unknown apps" for the Files app when Android asks.
6. Open the installed app, choose **Join Game**, and tap **Find town**. It
   fills in the address and port of the town PC on the same Wi-Fi. If it cannot
   find the town, check that the PC is running the town, that Play access is
   **Home Network**, and that the phone is on the same Wi-Fi; the address can
   still be entered by hand from the Parent Area's **Join / app** page.
7. Log in with the account a grown-up made for the child.

The app is intentionally **not** published to a store and does not need an
account, a download, or an update check over the internet.

## Build locally

Prerequisites: JDK 17 or newer, the Android SDK with platform/build-tools 36,
NDK `30.0.16248370`, CMake, and `gettext` (`msgfmt`). Android Studio can
install the SDK, NDK and CMake; set `ANDROID_HOME`/`ANDROID_SDK_ROOT` or add a
`android/local.properties` file.

```bash
cd android
./gradlew assembleDebug -PphoneAbi=arm64-v8a
# -> app/build/outputs/apk/debug/app-arm64-v8a-debug.apk
```

Omit `-PphoneAbi=arm64-v8a` to build all four ABIs.

For a smaller build you can limit ABI splits to the phone's architecture, for
example `arm64-v8a`:

```bash
./gradlew assembleDebug -Pandroid.injected.build.abi=arm64-v8a
```

The existing `assembleRelease` targets still produce the normal upstream
unsigned release APKs/AAB; the local installable APKs are the debug builds.
Because ABI splits are enabled, `assembleDebug` writes one APK per CPU
architecture rather than a single `app-debug.apk`.

## What changed from upstream

| File | Change |
| --- | --- |
| `android/app/src/main/AndroidManifest.xml` | `ACCESS_NETWORK_STATE` so the app can bind to Wi-Fi. |
| `android/.../LocalNetwork.java` | Binds the process to the connected Wi-Fi network and watches for changes. Never falls back to mobile data. |
| `android/.../MainActivity.java`, `GameActivity.java` | Start the Wi-Fi binding before native code and before the game starts. |
| `android/native/build.gradle` | Builds with `-DLOCAL_NETWORK_ONLY=1`. |
| `CMakeLists.txt` | Adds the `LOCAL_NETWORK_ONLY` compile definition. |
| `src/network/address.{h,cpp}` | Adds `Address::isLocalNetwork()` and `isBroadcast()`, and makes name resolution choose/reject based on it. |
| `src/network/socket.cpp` | Refuses any UDP send to a non-local address, except the one LAN discovery broadcast. |
| `src/script/lua_api/l_mainmenu.{h,cpp}` | Adds `core.find_lan_server()`: one LAN handshake reveals the town PC's address. |
| `src/defaultsettings.cpp` | Android defaults disable `serverlist_url`, `contentdb_url` and update indicators. |
| `builtin/mainmenu/init.lua` | Hides the Content tab when no ContentDB URL is configured. |
| `builtin/mainmenu/tab_online.lua` | Shows a simple address/port/name/password join pane with **Find town** instead of the public server list. |
| `.github/workflows/android.yml` | Builds and uploads the signed `KidTown-phone-debug-apks` artifact for local installation. |
| `.github/workflows/phone-apk.yml` | Fast debug-only build for the arm64 phone APK, separate from the store release build. |
