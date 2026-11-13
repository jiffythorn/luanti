# Kid Town phone app (Android)

This fork builds the Luanti phone client as a **local-network app** for the
Kid Town server:

- **Installed from a local file.** The installable artifact is a debug APK
  signed with the stable KidTown debug key stored in
  `android/kidtown-debug.p12` (a debug-only key; never use it for a release).
  Copy it to the phone over USB (or any local file transfer) and tap it. No
  Play Store account and no internet connection are needed to install it.
  Because the key is stable, a newer build can install over the previous one.
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
- **Find towns.** The Join Game tab's **Find towns** button sends an ordinary
  Luanti handshake to the LAN broadcast address on the game port. If the
  router drops `255.255.255.255`, it also tries each active interface's subnet
  broadcast (for example `192.168.1.255`). The town PC answers with its own
  address. The app then reads that PC's `/towns.txt` directory and shows a
  picker, so one PC can offer several worlds on different ports. The child
  chooses a town and logs in; without a directory it falls back to the one
  server that answered. The directory request is made only to the private
  address that answered discovery; a public address is never fetched and no
  public directory is involved. The town PC can put one town first as the
  default and can hide the rest; the phone simply shows the list it receives.
- **Parent settings lock.** The Join Game screen has a **Parent settings**
  button. The first visit lets a grown-up create a password (at least four
  characters); later visits need that password before the allowed-town list or
  the address and port can be changed. The child sees the address and port as
  read-only labels and can only choose from the towns the parent checked with
  check marks. The checked names and ports are saved on this phone, so a later
  rename on the PC does not change the name a locked child sees; the parent
  must unlock and save again to accept a new name or town. The phone list is a
  per-phone subset of what the town PC publishes. The Parent Area's **Phone
  towns** page still controls which towns are published at all.
- **Parent recovery.** When the parent password is created, the app shows a
  one-time recovery code. Write it down and keep it private. The code is
  stored only as a hash on the phone and is shown only on that screen. The
  parent settings page has **Change password**, which requires the current
  password and issues a fresh recovery code. If the password is forgotten,
  tap **Forgot password?** on the locked parent screen, enter the saved
  recovery code, and choose a new password; the app then shows a fresh code.
  A phone built with an older version can add a recovery code from the parent
  settings page with **Create recovery code** while the old password is still
  known. Without a saved recovery code, a forgotten password cannot be
  recovered without clearing the app's data.

## Install on a phone

1. Get the `KidTown-phone-debug-apks` artifact from the **phone-apk** GitHub
   Actions run, or build it locally (below). The workflow builds the
   `app-arm64-v8a-debug.apk` that modern phones need; the full `android`
   workflow still uploads every ABI.
2. If the phone already has the store version of Luanti installed, uninstall
   it first: Android will not install a debug-signed APK over the store's
   release signature. (The town world is on the PC, so nothing is lost.)
   Builds made before the stable key was introduced may also need one final
   uninstall; after that, newer KidTown builds use the same key and can update
   in place.
3. Connect the phone to the home Wi-Fi.
4. Copy the APK to the phone with a USB cable (or a local file share) and
   open it in the phone's Files app.
5. Allow "install unknown apps" for the Files app when Android asks.
6. Open the installed app, choose **Join Game**, and tap **Find towns**. Choose
   the town from the list; the address and port are filled in for you. If it
   cannot find a town, check that the PC is running the town, that Play access
   is **Home Network**, and that the phone is on the same Wi-Fi; the address
   can still be entered by hand from the Parent Area's **Join / app** page.
7. Log in with the account a grown-up made for the child.

The app is intentionally **not** published to a store and does not need an
account, a download, or an update check over the internet.

## Updates from the town PC
The app checks `http://<town-pc>:8791/update.json` when it starts, using the
address already saved by **Find towns** (it also tries the next few fallback
ports if 8791 is busy). The town PC's `phoneapp.py` serves that manifest and
the APK from the same writable `share/` folder. If the manifest has a higher
`versionCode`, the app downloads the APK, verifies its SHA-256 and signing
certificate, and opens Android's installer. Android always asks the person to
confirm the update; the app cannot install it silently. Allow KidTown to
install apps when Android asks.

The update file must have a higher `versionBuild` in `android/build.gradle`
and be signed with the same `android/kidtown-debug.p12` key. The manifest is
generated from the APK's own binary manifest, so the version shown by the LAN
server is the version in the file being served.

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
| `src/script/lua_api/l_mainmenu.{h,cpp}` | Adds `core.find_lan_server()`: one LAN handshake reveals the town PC's address; tries limited broadcast, then subnet broadcasts. |
| `src/network/address.{h,cpp}` | Adds local-interface subnet-broadcast discovery for routers that drop `255.255.255.255`. |
| `src/defaultsettings.cpp` | Android defaults disable `serverlist_url`, `contentdb_url` and update indicators. |
| `builtin/mainmenu/init.lua` | Hides the Content tab when no ContentDB URL is configured. |
| `builtin/mainmenu/tab_online.lua` | Shows a simple address/port/name/password join pane with **Find towns**, a LAN town picker, and the password-protected parent town checklist. |
| `.github/workflows/android.yml` | Builds and uploads the signed `KidTown-phone-debug-apks` artifact for local installation. |
| `.github/workflows/phone-apk.yml` | Fast debug-only build for the arm64 phone APK, separate from the store release build. |
| `android/app/src/main/java/.../PhoneUpdater.java` | Checks the LAN manifest, verifies the APK, and opens Android's installer. |
| `android/app/build.gradle` | Uses the stable `kidtown-debug.p12` key for debug builds. |
