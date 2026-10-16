import 'dart:typed_data';

class Recebido {
  Recebido(this.vizinho, this.dados);
  final String vizinho; // ID do aparelho vizinho (no BLE: id do dispositivo)
  final Uint8List dados; // um fragmento
}

/// Interface que o adaptador BLE (flutter_blue_plus / Core Bluetooth /
/// BluetoothGatt) deve implementar. O núcleo não sabe nada de Bluetooth.
abstract class Transporte {
  Stream<Recebido> get recebidos;
  Stream<String> get vizinhoNovo; // disparar ao conectar com um vizinho
  Set<String> get vizinhos; // vizinhos conectados agora
  Future<void> enviar(String vizinho, Uint8List fragmento);
}
