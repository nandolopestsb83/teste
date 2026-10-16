import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:btmesh/crypto.dart';
import 'package:btmesh/no_malha.dart';
import 'package:btmesh/pacote.dart';
import 'transporte_ble.dart';

void main() => runApp(const MaterialApp(home: Tela()));

/// Tela de teste: mostra seu "cartão de contato", aceita o de outro aparelho e envia texto.
/// As chaves são geradas a cada execução (sem persistência); troque o cartão após reiniciar.
class Tela extends StatefulWidget {
  const Tela({super.key});
  @override
  State<Tela> createState() => _TelaState();
}

class _TelaState extends State<Tela> {
  final _ble = TransporteBle();
  NoMalha? _no;
  Contato? _contato;
  String _cartao = 'iniciando...';
  final _log = <String>[];
  final _colado = TextEditingController();
  final _texto = TextEditingController();

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  void _add(String s) => setState(() => _log.insert(0, s));

  Future<void> _iniciar() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse, // necessário no Android 11 ou inferior
    ].request();
    final eu = await Identidade.gerar();
    final no = NoMalha(eu, _ble, mtu: 150);
    no.mensagens.listen((m) => _add('${m.de}: ${m.texto}'));
    _ble.vizinhoNovo.listen((v) => _add('vizinho conectado: $v'));
    no.iniciar();
    await _ble.iniciar();
    setState(() {
      _no = no;
      _cartao = base64Encode([...eu.pubAssinatura, ...eu.pubTroca]);
    });
  }

  Future<void> _adicionarContato() async {
    try {
      final b = Uint8List.fromList(base64Decode(_colado.text.trim()));
      if (b.length != 64) throw const FormatException('cartão inválido');
      final pubAss = Uint8List.sublistView(b, 0, 32);
      final pubTroca = Uint8List.sublistView(b, 32, 64);
      await _no!.adicionarContato('Contato', pubAss, pubTroca);
      setState(() => _contato = _no!.contatos[hex(await idDe(pubAss))]);
      _add('contato adicionado');
    } catch (e) {
      _add('erro ao adicionar contato: $e');
    }
  }

  Future<void> _enviar() async {
    final c = _contato;
    if (c == null || _texto.text.isEmpty) return;
    await _no!.enviarTexto(c, _texto.text);
    _add('eu: ${_texto.text}');
    _texto.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BT Mesh (teste)')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Seu cartão (envie ao outro aparelho):'),
          Row(children: [
            Expanded(child: Text(_cartao, maxLines: 2, overflow: TextOverflow.ellipsis)),
            IconButton(
                icon: const Icon(Icons.copy),
                onPressed: () => Clipboard.setData(ClipboardData(text: _cartao))),
          ]),
          TextField(
              controller: _colado,
              decoration: const InputDecoration(labelText: 'Cole o cartão do contato')),
          ElevatedButton(onPressed: _adicionarContato, child: const Text('Adicionar contato')),
          TextField(controller: _texto, decoration: const InputDecoration(labelText: 'Mensagem')),
          ElevatedButton(onPressed: _enviar, child: const Text('Enviar')),
          const Divider(),
          Expanded(child: ListView(children: [for (final l in _log) Text(l)])),
        ]),
      ),
    );
  }
}
