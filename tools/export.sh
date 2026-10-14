#!/bin/zsh
# export.sh [extra command line args]  -> out/LoG2Coop.apk: Godot's export + the game importer (lib/arm64-v8a/libgodot_export.so),
# aligned and signed with keys/.  PKG=some.other.name exports under another package (a test install beside the real one).
# Set GODOT, ANDROID_SDK and JAVA_HOME for your machine (or edit the defaults below).
B="$(cd "$(dirname "$0")/.." && pwd)"
GODOT=${GODOT:-godot}
ANDROID_SDK=${ANDROID_SDK:-$HOME/Library/Android/sdk}
SDKBT="$ANDROID_SDK/build-tools/36.1.0"
[ -n "$JAVA_HOME" ] && export PATH="$JAVA_HOME/bin:$PATH"
cd "$B/project" || exit 1
find . -name '._*' -delete
cp export_presets.cfg "$B/out/presets_backup.cfg" 2>/dev/null || { mkdir -p "$B/out"; cp export_presets.cfg "$B/out/presets_backup.cfg"; }
sed -i '' "s#^command_line/extra_args=.*#command_line/extra_args=\"$1\"#" export_presets.cfg
sed -i '' "s#^custom_template/release=.*#custom_template/release=\"$B/templates/android_release.apk\"#; s#^custom_template/debug=.*#custom_template/debug=\"$B/templates/android_debug.apk\"#" export_presets.cfg
[ -n "$PKG" ] && sed -i '' "s#^package/unique_name=.*#package/unique_name=\"$PKG\"#; s#^package/name=.*#package/name=\"LoG2 TEST\"#" export_presets.cfg
export PW=$(sed -n 's/^password: //p' "$B/keys/keystore_password.txt")
GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$B/keys/log2coop-release.keystore" GODOT_ANDROID_KEYSTORE_RELEASE_USER=log2coop GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$PW" \
  "$GODOT" --headless --path . --export-release "Android" "$B/out/godot.apk" 2>&1 | grep -E 'ERROR|SCRIPT'
cp "$B/out/presets_backup.cfg" export_presets.cfg && rm -f "$B/out/presets_backup.cfg"
[ -f "$B/out/godot.apk" ] || { echo "export failed"; exit 1; }
# the importer goes in beside the engine
ST=$(mktemp -d); mkdir -p "$ST/lib/arm64-v8a"; cp "$B/importer/android/libgodot_export.so" "$ST/lib/arm64-v8a/"
(cd "$ST" && COPYFILE_DISABLE=1 zip -q -X "$B/out/godot.apk" lib/arm64-v8a/libgodot_export.so)
rm -rf "$ST"
rm -f "$B/out/LoG2Coop.apk" "$B/out/LoG2Coop.apk.idsig"
"$SDKBT/zipalign" -f -p 4 "$B/out/godot.apk" "$B/out/LoG2Coop.apk" && rm -f "$B/out/godot.apk" "$B/out/godot.apk.idsig"
"$SDKBT/apksigner" sign --ks "$B/keys/log2coop-release.keystore" --ks-key-alias log2coop --ks-pass env:PW --key-pass env:PW "$B/out/LoG2Coop.apk" && \
  "$SDKBT/apksigner" verify "$B/out/LoG2Coop.apk" && echo "Signed: $B/out/LoG2Coop.apk"
find "$B/out" -name '._*' -delete
