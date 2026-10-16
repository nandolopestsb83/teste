// Simulação: A --- B --- C. A só enxerga B; C só enxerga B.
// Testa criptografia, fragmentação, salto, ACK e store-and-forward.
import 'dart:async';
import 'dart:typed_data';
import 'package:btmesh/no_malha.dart';
import 'package:btmesh/transporte.dart';

class RedeSim {
  final nos = <String, TransporteSim>{};
  final _adj = <String, Set<String>>{};

  TransporteSim criar(String nome) => nos[nome] = TransporteSim(nome, this);

  void ligar(String a, String b) {
    _adj.putIfAbsent(a, () => {}).add(b);
    _adj.putIfAbsent(b, () => {}).add(a);
    nos[a]!._novo.add(b);
    nos[b]!._novo.add(a);
  }
}

class TransporteSim implements Transporte {
  TransporteSim(this.nome, this.rede);
  final String nome;
  final RedeSim rede;
  final _rec = StreamController<Recebido>.broadcast();
  final _novo = StreamController<String>.broadcast();

  @override
  Stream<Recebido> get recebidos => _rec.stream;
  @override
  Stream<String> get vizinhoNovo => _novo.stream;
  @override
  Set<String> get vizinhos => rede._adj[nome] ?? {};
  @override
  Future<void> enviar(String vizinho, Uint8List fragmento) async {
    await Future.delayed(const Duration(milliseconds: 5));
    rede.nos[vizinho]?._rec.add(Recebido(nome, fragmento));
  }
}

Future<void> main() async {
  final rede = RedeSim();
  final ids = {for (final n in ['A', 'B', 'C']) n: await Identidade.gerar()};
  // MTU pequeno (100) para forçar fragmentação
  final nos = {
    for (final e in ids.entries) e.key: NoMalha(e.value, rede.criar(e.key), mtu: 100)..iniciar()
  };

  // A e C trocam chaves (na vida real: QR code, pessoalmente)
  await nos['A']!.adicionarContato('C', ids['C']!.pubAssinatura, ids['C']!.pubTroca);
  await nos['C']!.adicionarContato('A', ids['A']!.pubAssinatura, ids['A']!.pubTroca);

  nos['C']!.mensagens.listen((m) => print('C recebeu de ${m.de}: "${m.texto}"'));

  rede.ligar('A', 'B'); // C ainda está fora de alcance
  final paraC = nos['A']!.contatos.values.first;
  await nos['A']!.enviarTexto(paraC, 'Olá, C! Esta mensagem saltou por B.');
  await Future.delayed(const Duration(seconds: 1));
  print('Pendentes em A (sem ACK): ${nos['A']!.pendentes}');

  print('--- C entra no alcance de B ---');
  rede.ligar('B', 'C');
  await Future.delayed(const Duration(seconds: 2));
  print('Pendentes em A após ACK: ${nos['A']!.pendentes}');
}
