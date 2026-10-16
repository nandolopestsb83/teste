import 'dart:typed_data';
import 'crypto.dart';

enum Tipo {
  mensagem(1),
  ack(2);

  const Tipo(this.codigo);
  final int codigo;
}

String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

bool igual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Layout (bytes):
///  0 versao | 1 tipo | 2-9 msgId | 10-17 origem | 18-25 destino | 26 ttl
///  27-58 chavePub (Ed25519) | 59-122 assinatura | 123-124 tamanho | 125.. payload
/// O TTL NÃO entra na assinatura, pois muda a cada salto.
class Pacote {
  Pacote({
    required this.tipo,
    required this.msgId,
    required this.origem,
    required this.destino,
    required this.ttl,
    required this.chavePub,
    required this.assinatura,
    required this.payload,
  });

  static const versao = 1;
  static const _fixo = 125;
  static const maxPayload = 4000;

  final Tipo tipo;
  final Uint8List msgId, origem, destino, chavePub, assinatura, payload;
  final int ttl;

  Uint8List dadosAssinados() => (BytesBuilder()
        ..addByte(versao)
        ..addByte(tipo.codigo)
        ..add(msgId)
        ..add(origem)
        ..add(destino)
        ..add(chavePub)
        ..add(payload))
      .toBytes();

  Pacote comTtl(int t) => Pacote(
      tipo: tipo, msgId: msgId, origem: origem, destino: destino, ttl: t,
      chavePub: chavePub, assinatura: assinatura, payload: payload);

  /// A chave pública bate com a origem E a assinatura confere?
  Future<bool> valido() async =>
      igual(await idDe(chavePub), origem) &&
      await verificar(chavePub, dadosAssinados(), assinatura);

  Uint8List serializar() => (BytesBuilder()
        ..addByte(versao)
        ..addByte(tipo.codigo)
        ..add(msgId)
        ..add(origem)
        ..add(destino)
        ..addByte(ttl)
        ..add(chavePub)
        ..add(assinatura)
        ..addByte(payload.length >> 8)
        ..addByte(payload.length & 0xFF)
        ..add(payload))
      .toBytes();

  static Pacote? desserializar(Uint8List b) {
    if (b.length < _fixo || b[0] != versao) return null;
    final tipo = Tipo.values.where((t) => t.codigo == b[1]).firstOrNull;
    if (tipo == null) return null;
    final tam = (b[123] << 8) | b[124];
    if (tam > maxPayload || b.length != _fixo + tam) return null;
    return Pacote(
      tipo: tipo,
      msgId: b.sublist(2, 10),
      origem: b.sublist(10, 18),
      destino: b.sublist(18, 26),
      ttl: b[26],
      chavePub: b.sublist(27, 59),
      assinatura: b.sublist(59, 123),
      payload: b.sublist(125),
    );
  }
}
