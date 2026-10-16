import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

final _ed = Ed25519();
final _x25519 = X25519();
final _aead = Chacha20.poly1305Aead();
final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

/// ID de 8 bytes derivado da chave pública de assinatura.
Future<Uint8List> idDe(List<int> chavePub) async =>
    Uint8List.fromList((await Sha256().hash(chavePub)).bytes.sublist(0, 8));

Future<bool> verificar(List<int> chavePub, List<int> dados, List<int> assinatura) =>
    _ed.verify(dados,
        signature: Signature(assinatura,
            publicKey: SimplePublicKey(chavePub, type: KeyPairType.ed25519)));

Future<SecretKey> _chaveSessao(SimpleKeyPair par, List<int> remota, List<int> sal) async {
  final segredo = await _x25519.sharedSecretKey(
      keyPair: par,
      remotePublicKey: SimplePublicKey(remota, type: KeyPairType.x25519));
  return _hkdf.deriveKey(
      secretKey: segredo, nonce: sal, info: utf8.encode('btmesh-v1'));
}

/// Cifra para o destinatário (chave efêmera X25519 + ChaCha20-Poly1305).
/// Formato: chave_efemera(32) | nonce(12) | texto_cifrado | mac(16)
Future<Uint8List> cifrar(Uint8List texto, Uint8List pubTrocaDestino) async {
  final efemera = await _x25519.newKeyPair();
  final efPub = (await efemera.extractPublicKey()).bytes;
  final chave = await _chaveSessao(efemera, pubTrocaDestino, efPub);
  final caixa = await _aead.encrypt(texto, secretKey: chave);
  return Uint8List.fromList([...efPub, ...caixa.concatenation()]);
}

class Identidade {
  Identidade._(this._assinatura, this._troca, this.pubAssinatura, this.pubTroca, this.id);
  final SimpleKeyPair _assinatura, _troca;
  final Uint8List pubAssinatura, pubTroca, id;

  static Future<Identidade> gerar() async {
    final a = await _ed.newKeyPair();
    final t = await _x25519.newKeyPair();
    final pa = Uint8List.fromList((await a.extractPublicKey()).bytes);
    final pt = Uint8List.fromList((await t.extractPublicKey()).bytes);
    return Identidade._(a, t, pa, pt, await idDe(pa));
  }

  Future<Uint8List> assinar(List<int> dados) async =>
      Uint8List.fromList((await _ed.sign(dados, keyPair: _assinatura)).bytes);

  /// Retorna null se não for para este aparelho ou se estiver adulterado.
  Future<Uint8List?> decifrar(Uint8List blob) async {
    try {
      final efPub = blob.sublist(0, 32);
      final chave = await _chaveSessao(_troca, efPub, efPub);
      final caixa = SecretBox.fromConcatenation(blob.sublist(32),
          nonceLength: 12, macLength: 16);
      return Uint8List.fromList(await _aead.decrypt(caixa, secretKey: chave));
    } catch (_) {
      return null;
    }
  }
}
