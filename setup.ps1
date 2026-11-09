# Daftar - one-time project setup (Windows / PowerShell).
# Generates the android/ and ios/ folders, adds microphone permissions,
# and downloads packages. Run from the project folder:  .\setup.ps1

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding $false

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Host 'Flutter is not installed or not on PATH. See https://docs.flutter.dev/get-started/install/windows' -ForegroundColor Red
    exit 1
}

flutter create --org org.daftar --project-name daftar --platforms android,ios .
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# flutter create adds a sample test for its counter app; it does not apply here.
if ((Test-Path 'test/widget_test.dart') -and (Select-String -Path 'test/widget_test.dart' -Pattern 'MyApp' -Quiet)) {
    Remove-Item 'test/widget_test.dart'
}

# Android: microphone permission + app name + minSdk 24
$manifest = 'android/app/src/main/AndroidManifest.xml'
$m = [IO.File]::ReadAllText((Resolve-Path $manifest).Path)
if ($m -notmatch 'RECORD_AUDIO') {
    $m = $m -replace '(<manifest[^>]*>)', "`$1`n    <uses-permission android:name=`"android.permission.RECORD_AUDIO`" />"
}
# App name in Arabic, written as XML character references (no encoding issues).
$m = $m -replace 'android:label="daftar"', 'android:label="&#x62F;&#x641;&#x62A;&#x631;"'
[IO.File]::WriteAllText((Resolve-Path $manifest).Path, $m, $utf8)

foreach ($g in @('android/app/build.gradle.kts', 'android/app/build.gradle')) {
    if (Test-Path $g) {
        $t = [IO.File]::ReadAllText((Resolve-Path $g).Path)
        $t = $t -replace 'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 24'
        $t = $t -replace 'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion 24'
        [IO.File]::WriteAllText((Resolve-Path $g).Path, $t, $utf8)
    }
}

# iOS: microphone usage text + display name
$plist = 'ios/Runner/Info.plist'
$pl = [IO.File]::ReadAllText((Resolve-Path $plist).Path)
if ($pl -notmatch 'NSMicrophoneUsageDescription') {
    $add = "`t<key>NSMicrophoneUsageDescription</key>`n`t<string>Daftar records audio alongside your notes.</string>`n</dict>`n</plist>"
    $pl = $pl -replace '</dict>\s*</plist>\s*$', $add
}
$pl = $pl -replace '(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)', '$1&#x62F;&#x641;&#x62A;&#x631;$2'
[IO.File]::WriteAllText((Resolve-Path $plist).Path, $pl, $utf8)

# iOS 14 minimum (required by file_picker)
$pbx = 'ios/Runner.xcodeproj/project.pbxproj'
$t = [IO.File]::ReadAllText((Resolve-Path $pbx).Path)
$t = $t -replace 'IPHONEOS_DEPLOYMENT_TARGET = 1[0-3]\.0;', 'IPHONEOS_DEPLOYMENT_TARGET = 14.0;'
[IO.File]::WriteAllText((Resolve-Path $pbx).Path, $t, $utf8)

flutter pub get
Write-Host ''
Write-Host 'Done. Connect an Android device (or start an emulator) and run:  flutter run' -ForegroundColor Green
