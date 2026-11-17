#!/usr/bin/env bash
# Build the W200 "now playing" launcher APK without the Android SDK:
#   javac against the Apache-2.0 android-4.1.1.4.jar from Maven Central, d8 (r8 jar) to dex,
#   hand-written binary AndroidManifest.xml, v1 (JAR) signature with SHA-1 (Android 4.2 needs it).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
B=~/w200-build/launcher
T=~/w200-build/tools
mkdir -p "$B" && cd "$B"
AJ=$T/android-4.1.1.4.jar
if [ ! -f "$AJ" ]; then
  curl -sSfL -o "$AJ" https://repo1.maven.org/maven2/com/google/android/android/4.1.1.4/android-4.1.1.4.jar
  echo "android.jar bytes: $(stat -c %s "$AJ")"
fi
# org.json is part of Android but not of that jar: compile against Android's org.json sources, repackaged
JJ=$T/android-json-0.0.20131108.vaadin1.jar
if [ ! -f "$JJ" ]; then
  curl -sSfL -o "$JJ" https://repo1.maven.org/maven2/com/vaadin/external/google/android-json/0.0.20131108.vaadin1/android-json-0.0.20131108.vaadin1.jar
  echo "android-json bytes: $(stat -c %s "$JJ")"
fi
rm -rf classes dex apk && mkdir -p classes dex apk
javac -nowarn --release 8 -cp "$AJ:$JJ" -d classes $(find "$W/launcher/src" -name '*.java')
[ -f classes/com/w200/nowplaying/NowPlaying.class ] || { echo "javac failed"; exit 1; }
# only our classes go into the dex; android.* / org.json come from the phone
java -cp "$T/r8-8.5.35.jar" com.android.tools.r8.D8 --release --min-api 16 --lib "$AJ" --classpath "$JJ" --output dex $(find classes -name '*.class')
python3 "$W/launcher/make_manifest.py" apk/AndroidManifest.xml
cp dex/classes.dex apk/
rm -f unsigned.apk && (cd apk && zip -q -X ../unsigned.apk AndroidManifest.xml classes.dex)
# signing key (kept in the build dir; reusing it lets `adb install -r` update the app)
if [ ! -f w200-key.pem ]; then
  openssl req -x509 -newkey rsa:2048 -sha1 -nodes -days 10000 -subj "/CN=W200 Launcher" \
    -keyout w200-key.pem -out w200-cert.pem 2>/dev/null
fi
python3 "$W/launcher/sign_apk.py" unsigned.apk W200NowPlaying.apk w200-key.pem w200-cert.pem
cp W200NowPlaying.apk "$W/out/W200NowPlaying.apk"
ls -l "$W/out/W200NowPlaying.apk"
unzip -l "$W/out/W200NowPlaying.apk" | tail -n +4 | head -6
