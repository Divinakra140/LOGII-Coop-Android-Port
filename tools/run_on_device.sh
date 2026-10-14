#!/bin/zsh
# installs out/LoG2Coop.apk on the connected device, clears the log, starts it.  PKG= as in export.sh
B="$(cd "$(dirname "$0")/.." && pwd)"
P=${PKG:-com.log2coop.game}
A="${ANDROID_SDK:-$HOME/Library/Android/sdk}/platform-tools/adb"
$A shell am force-stop $P
$A install -r "$B/out/LoG2Coop.apk" 2>&1 | tail -1
$A logcat -c
$A shell monkey -p $P -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
