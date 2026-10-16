import 'dart:math';
import 'dart:typed_data';

/// Camada de enlace: divide um pacote em pedaços que cabem no MTU do BLE.
/// Cabeçalho de cada fragmento: idTransferencia(2) | indice(1) | total(1)
class Fragmentador {
  Fragmentador(this.mtu);
  final int mtu;
  int _proximo = 0;

  List<Uint8List> dividir(Uint8List dados) {
    final tam = mtu - 4;
    final total = (dados.length + tam - 1) ~/ tam;
    if (total > 255) throw ArgumentError('Pacote grande demais');
    final id = _proximo++ & 0xFFFF;
    return [
      for (var i = 0; i < total; i++)
        Uint8List.fromList([
          id >> 8, id & 0xFF, i, total,
          ...dados.sublist(i * tam, min(dados.length, (i + 1) * tam)),
        ])
    ];
  }
}

class Remontador {
  final _parciais = <String, List<Uint8List?>>{};

  /// Devolve o pacote completo quando o último fragmento chega.
  Uint8List? adicionar(String vizinho, Uint8List f) {
    if (f.length < 5) return null;
    final idx = f[2], total = f[3];
    if (total == 0 || idx >= total) return null;
    final chave = '$vizinho:${f[0]}:${f[1]}';
    if (_parciais.length > 64 && !_parciais.containsKey(chave)) {
      _parciais.remove(_parciais.keys.first); // evita crescer sem limite
    }
    final partes = _parciais.putIfAbsent(chave, () => List.filled(total, null));
    if (partes.length != total) return null;
    partes[idx] = f.sublist(4);
    if (partes.any((p) => p == null)) return null;
    _parciais.remove(chave);
    return Uint8List.fromList([for (final p in partes) ...p!]);
  }
}
