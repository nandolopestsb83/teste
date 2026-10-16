#!/usr/bin/env bash
# Cria o projeto Android completo em ./app e compila o APK.
# Requer Flutter (stable) e Java 17 instalados. Rode na raiz do repositório.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf app
flutter create --org com.example --platforms android --project-name btmesh_app app

# código do app
cp btmesh_app/lib/*.dart app/lib/
KT=app/android/app/src/main/kotlin/com/example/btmesh_app
mkdir -p "$KT"
cp btmesh_app/android_kotlin/*.kt "$KT"/

# dependências
cd app
flutter pub add btmesh --path ../btmesh
flutter pub add permission_handler cryptography
cd ..

# permissões de Bluetooth no manifesto
python3 - << 'PY'
p = 'app/android/app/src/main/AndroidManifest.xml'
s = open(p).read()
perm = '''<uses-feature android:name="android.hardware.bluetooth_le" android:required="true"/>
    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"/>
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30"/>
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30"/>
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation"/>
    <uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE"/>
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
    '''
if 'BLUETOOTH_SCAN' not in s:
    s = s.replace('<application', perm + '<application', 1)
open(p, 'w').write(s)
PY

# minSdk 23
sed -i 's/minSdk = flutter.minSdkVersion/minSdk = 23/' app/android/app/build.gradle.kts 2>/dev/null || true
sed -i 's/minSdkVersion flutter.minSdkVersion/minSdkVersion 23/' app/android/app/build.gradle 2>/dev/null || true

cd app
flutter build apk --release
echo "APK pronto: app/build/app/outputs/flutter-apk/app-release.apk"
