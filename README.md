# LOG2II Android Port

Android port of **Legacy of Goku II - Co-op (Godot)** by **Puni Puni**
(YouTube: [@PuniPuni2026](https://www.youtube.com/@PuniPuni2026)), distributed with the developer's permission.
Built for and tested on the Retroid Pocket Flip 2; works on 64-bit ARM Android devices (Android 7+).

**No game data is included.** On first start the app asks for your own *Dragon Ball Z - The Legacy of Goku II (USA)*
.gba (CHOOSE MY ROM) and reads its maps, sprites and sounds on the device (about 30 seconds).

## What the port changes (from the v42 PC release)
- Runs the ROM importer on Android (built with the NDK, shipped as lib/arm64-v8a/libgodot_export.so)
- CHOOSE MY ROM uses Android's file picker
- Game folders (content, mod packs, adventures) unpacked into the app's storage on first start
- Your own music from /storage/emulated/0/Music/LoG2Coop (sounds in .../LoG2Coop/sounds)
- Gamepad navigation in the title menus; Nintendo/Retroid A/B layout by default (OPTIONS - A/B BUTTONS)
- OPTIONS - ON-SCREEN BUTTONS: AUTO / ON / OFF
- Sharp text at any screen size; menu text and controls written for handhelds
- Fixes for Godot 4.7 on Android: an audio crash during fights, slow first start

## Layout
- project/ - the Godot project (Godot 4.7.2; originally made with 4.3)
- data/ - Puni Puni's game folders packed into the APK: content/, modpacks/, adventures/, music/
- importer/source/ - the ROM importer (plain C++17, no other libraries)
- tools/ - make_pack.py (packs data/), export.sh (build + sign), run_on_device.sh (install via adb)

## Building
Needs Godot 4.7.2 with its Android export templates, the Android SDK (build-tools 34), the NDK, and JDK 17.
1. Build the importer for Android:
   aarch64-linux-android24-clang++ -O2 -std=c++17 -fPIE -pie -static-libstdc++ -s -Wl,--hash-style=both -o importer/android/libgodot_export.so importer/source/tools/godot_export.cpp importer/source/src/*.cpp
2. Pack the game folders: python3 tools/make_pack.py data project/bundle/gamedata.pack content modpacks music adventures
3. Put android_release.apk / android_debug.apk from the Godot 4.7.2 export templates in templates/
4. Make your own release keystore in keys/ (keys/log2coop-release.keystore, alias log2coop, password in
   keys/keystore_password.txt as password: ...).
5. Point the scripts at your tools, then build - the signed APK lands in out/LoG2Coop.apk:
   export GODOT=/path/to/godot ANDROID_SDK=/path/to/android-sdk JAVA_HOME=/path/to/jdk-17 then tools/export.sh
