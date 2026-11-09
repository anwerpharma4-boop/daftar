#!/usr/bin/env bash
# Daftar - one-time project setup (macOS / Linux). Needed on a Mac to build for iPhone/iPad.
# Run from the project folder:  bash setup.sh
set -euo pipefail

command -v flutter >/dev/null || { echo "Flutter is not installed. See https://docs.flutter.dev/get-started/install"; exit 1; }

flutter create --org org.daftar --project-name daftar --platforms android,ios .

# flutter create adds a sample test for its counter app; it does not apply here.
if [ -f test/widget_test.dart ] && grep -q MyApp test/widget_test.dart; then rm test/widget_test.dart; fi

# Android: microphone permission, app name, minSdk 24
M=android/app/src/main/AndroidManifest.xml
grep -q RECORD_AUDIO "$M" || perl -0pi -e 's/(<manifest[^>]*>)/$1\n    <uses-permission android:name="android.permission.RECORD_AUDIO" \/>/' "$M"
perl -pi -e 's/android:label="daftar"/android:label="&#x62F;&#x641;&#x62A;&#x631;"/' "$M"
for G in android/app/build.gradle.kts android/app/build.gradle; do
  [ -f "$G" ] && perl -pi -e 's/minSdk\s*=\s*flutter\.minSdkVersion/minSdk = 24/; s/minSdkVersion\s+flutter\.minSdkVersion/minSdkVersion 24/' "$G"
done

# iOS: microphone usage text + display name
P=ios/Runner/Info.plist
grep -q NSMicrophoneUsageDescription "$P" || perl -0pi -e 's#</dict>\s*</plist>\s*$#\t<key>NSMicrophoneUsageDescription</key>\n\t<string>Daftar records audio alongside your notes.</string>\n</dict>\n</plist>\n#' "$P"
perl -0pi -e 's#(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)#$1&\#x62F;&\#x641;&\#x62A;&\#x631;$2#' "$P"

# iOS 14 minimum (required by file_picker)
perl -pi -e 's/IPHONEOS_DEPLOYMENT_TARGET = 1[0-3]\.0;/IPHONEOS_DEPLOYMENT_TARGET = 14.0;/g' ios/Runner.xcodeproj/project.pbxproj
[ -f ios/Podfile ] && perl -pi -e "s/^#?\s*platform :ios, '[0-9.]+'/platform :ios, '14.0'/" ios/Podfile

flutter pub get
echo "Done. Run: flutter run"
