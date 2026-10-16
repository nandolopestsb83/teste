import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'crypto.dart';
import 'fragmentacao.dart';
import 'pacote.dart';
import 'transporte.dart';

class Contato {
  Contato(this.nome, this.pubAssinatura, this.pubTroca);
  final String nome;
  final Uint8List pubAssinatura, pubTroca;
}

class Mensagem {
  Mensagem(this.de, this.texto);
  final String de, texto;
}

class _Guardado {
  _Guardado(this.pacote, this.expira);
  final Pacote pacote;
  final DateTime expira;
}

class NoMalha {
  NoMalha(this.eu, this._t, {int mtu = 180}) : _frag = Fragmentador(mtu);

  static const ttlInicial = 6;
  static const validadeVistos = Duration(minutes: 10);
  static const validadeGuardados = Duration(hours: 3);
  static const limitePorMinuto = 20;
  static const maxGuardados = 200;

  final Identidade eu;
  final Transporte _t;
  final Fragmentador _frag;
  final _remontador = Remontador();
  final _rand = Random.secure();

  final contatos = <String, Contato>{}; // hex(id) -> contato
  final _vistos = <String, DateTime>{};
  final _duplicatas = <String, int>{};
  final _guardados = <String, _Guardado>{};
  final _taxa = <String, List<DateTime>>{};
  final _entrada = StreamController<Mensagem>.broadcast();

  Stream<Mensagem> get mensagens => _entrada.stream;
  int get pendentes =>
      _guardados.values.where((g) => g.pacote.tipo == Tipo.mensagem && igual(g.pacote.origem, eu.id)).length;

  Future<void> adicionarContato(String nome, Uint8List pubAss, Uint8List pubTroca) async {
    contatos[hex(await idDe(pubAss))] = Contato(nome, pubAss, pubTroca);
  }

  void iniciar() {
    _t.recebidos.listen((r) {
      final inteiro = _remontador.adicionar(r.vizinho, r.dados);
      if (inteiro != null) _tratar(r.vizinho, inteiro);
    });
    _t.vizinhoNovo.listen(_entregarGuardados);
  }

  Future<void> enviarTexto(Contato c, String texto) async {
    final bytes = Uint8List.fromList(utf8.encode(texto));
    if (bytes.length > 1000) throw ArgumentError('Texto longo demais (máx. 1000 bytes)');
    final payload = await cifrar(bytes, c.pubTroca);
    await _emitir(await _montar(Tipo.mensagem, await idDe(c.pubAssinatura), payload));
  }

  // ---------- recepção ----------

  Future<void> _tratar(String de, Uint8List bytes) async {
    final p = Pacote.desserializar(bytes);
    if (p == null) return;
    _limparExpirados();
    final chave = hex(p.msgId);
    if (_vistos.containsKey(chave)) {
      _duplicatas[chave] = (_duplicatas[chave] ?? 0) + 1;
      return;
    }
    _vistos[chave] = DateTime.now();
    _duplicatas[chave] = 0;
    if (!_dentroDoLimite(hex(p.origem))) return;
    if (!await p.valido()) return; // descarta ANTES de retransmitir

    if (igual(p.destino, eu.id)) {
      await _receberParaMim(p);
    } else if (p.ttl > 1) {
      await _retransmitir(p, de);
    }
  }

  Future<void> _receberParaMim(Pacote p) async {
    if (p.tipo == Tipo.mensagem) {
      final claro = await eu.decifrar(p.payload);
      if (claro == null) return;
      final nome = contatos[hex(p.origem)]?.nome ?? hex(p.origem);
      _entrada.add(Mensagem(nome, utf8.decode(claro, allowMalformed: true)));
      await _emitir(await _montar(Tipo.ack, p.origem, p.msgId));
    } else if (p.tipo == Tipo.ack && p.payload.length == 8) {
      final g = _guardados[hex(p.payload)];
      // só aceita o ACK se vier de quem era o destinatário da mensagem
      if (g != null && igual(g.pacote.destino, p.origem)) _guardados.remove(hex(p.payload));
    }
  }

  Future<void> _retransmitir(Pacote p, String de) async {
    await Future.delayed(Duration(milliseconds: 20 + _rand.nextInt(180))); // jitter
    if ((_duplicatas[hex(p.msgId)] ?? 0) > 0) return; // outro vizinho já retransmitiu
    final copia = p.comTtl(p.ttl - 1);
    _guardar(copia);
    for (final v in _t.vizinhos) {
      if (v != de) await _enviar(v, copia);
    }
  }

  // ---------- envio ----------

  Future<Pacote> _montar(Tipo tipo, Uint8List destino, Uint8List payload) async {
    final msgId = Uint8List.fromList(List.generate(8, (_) => _rand.nextInt(256)));
    final base = Pacote(
        tipo: tipo, msgId: msgId, origem: eu.id, destino: destino, ttl: ttlInicial,
        chavePub: eu.pubAssinatura, assinatura: Uint8List(64), payload: payload);
    final sig = await eu.assinar(base.dadosAssinados());
    return Pacote(
        tipo: tipo, msgId: msgId, origem: eu.id, destino: destino, ttl: ttlInicial,
        chavePub: eu.pubAssinatura, assinatura: sig, payload: payload);
  }

  Future<void> _emitir(Pacote p) async {
    _vistos[hex(p.msgId)] = DateTime.now();
    if (p.tipo == Tipo.mensagem) _guardar(p); // ACKs não precisam ser guardados
    for (final v in _t.vizinhos) {
      await _enviar(v, p);
    }
  }

  Future<void> _enviar(String vizinho, Pacote p) async {
    for (final f in _frag.dividir(p.serializar())) {
      await _t.enviar(vizinho, f);
    }
  }

  // ---------- store-and-forward ----------

  void _guardar(Pacote p) {
    if (_guardados.length >= maxGuardados) _guardados.remove(_guardados.keys.first);
    _guardados[hex(p.msgId)] = _Guardado(p, DateTime.now().add(validadeGuardados));
  }

  Future<void> _entregarGuardados(String vizinho) async {
    final agora = DateTime.now();
    for (final g in _guardados.values.toList()) {
      if (g.expira.isAfter(agora)) await _enviar(vizinho, g.pacote);
    }
  }

  // ---------- manutenção e anti-abuso ----------

  bool _dentroDoLimite(String origem) {
    final agora = DateTime.now();
    final l = _taxa.putIfAbsent(origem, () => []);
    l.removeWhere((t) => agora.difference(t) > const Duration(minutes: 1));
    if (l.length >= limitePorMinuto) return false;
    l.add(agora);
    return true;
  }

  void _limparExpirados() {
    final agora = DateTime.now();
    _vistos.removeWhere((k, t) {
      final vencido = agora.difference(t) > validadeVistos;
      if (vencido) _duplicatas.remove(k);
      return vencido;
    });
    _guardados.removeWhere((_, g) => g.expira.isBefore(agora));
  }
}
