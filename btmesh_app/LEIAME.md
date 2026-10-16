# Como montar o app de teste (Android)

Estrutura esperada (as duas pastas lado a lado):
```
btmesh/          <- núcleo Dart (já entregue)
btmesh_app/      <- app Flutter (criado no passo 1)
```

## 1. Criar o projeto
```
flutter create --org com.example --platforms android btmesh_app
```
Copie os arquivos desta pasta para dentro dele:
- `lib/main.dart` e `lib/transporte_ble.dart` -> `btmesh_app/lib/` (substitui o main.dart)
- `android_kotlin/BleMesh.kt` e `MainActivity.kt` -> `btmesh_app/android/app/src/main/kotlin/com/example/btmesh_app/` (substitui o MainActivity.kt)

## 2. pubspec.yaml do app (em `dependencies:`)
```yaml
  btmesh:
    path: ../btmesh
  permission_handler: ^11.3.0
  cryptography: ^2.7.0
```

## 3. android/app/build.gradle(.kts)
Defina `minSdk = 23` (ou `minSdkVersion 23`) e `compileSdk` 34 ou superior.

## 4. AndroidManifest.xml (dentro de `<manifest>`, antes de `<application>`)
```xml
<uses-feature android:name="android.hardware.bluetooth_le" android:required="true"/>
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"/>
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30"/>
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation"/>
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE"/>
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
```

## 5. Rodar
```
cd btmesh_app && flutter pub get && flutter run
```
Instale em 3 celulares físicos (A, B, C).

## Teste de salto
1. Em cada aparelho, copie o "cartão". A e C trocam cartões (colam o do outro e tocam em "Adicionar contato"). B não precisa de contatos: só retransmite.
2. Posicione A e C fora do alcance um do outro, com B no meio. Confirme nos logs que A e C mostram "vizinho conectado" só com B.
3. Envie de A para C. Deve chegar via B.
4. Teste store-and-forward: afaste C, envie de A, depois aproxime C.

## Limitações conhecidas
- Sem serviço em primeiro plano: o Android pausa o BLE com o app em segundo plano. Mantenha a tela ligada nos testes.
- O mesmo vizinho pode aparecer duas vezes (uma como central e outra como servidor). A deduplicação do núcleo absorve isso, mas gasta banda.
- Chaves não persistem: ao reabrir o app, troque os cartões de novo.
- Sem duty cycle no scan: o consumo de bateria é alto.
- Se o vizinho negociar MTU menor que 185, os fragmentos de 150 bytes ainda cabem em aparelhos modernos, mas aparelhos muito antigos podem falhar.
