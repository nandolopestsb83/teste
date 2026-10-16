import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:btmesh/transporte.dart';

/// Liga o núcleo (btmesh) ao plugin Kotlin via MethodChannel.
class TransporteBle implements Transporte {
  TransporteBle() {
    _canal.setMethodCallHandler(_aoReceber);
  }

  final _canal = const MethodChannel('btmesh/ble');
  final _rec = StreamController<Recebido>.broadcast();
  final _novo = StreamController<String>.broadcast();
  final _vizinhos = <String>{};

  Future<void> iniciar() => _canal.invokeMethod('iniciar');
  Future<void> parar() => _canal.invokeMethod('parar');

  Future<dynamic> _aoReceber(MethodCall c) async {
    final a = Map<String, dynamic>.from(c.arguments as Map);
    final v = a['v'] as String;
    switch (c.method) {
      case 'dados':
        _rec.add(Recebido(v, a['d'] as Uint8List));
      case 'vizinho':
        _vizinhos.add(v);
        _novo.add(v);
      case 'saiu':
        _vizinhos.remove(v);
    }
  }

  @override
  Stream<Recebido> get recebidos => _rec.stream;
  @override
  Stream<String> get vizinhoNovo => _novo.stream;
  @override
  Set<String> get vizinhos => {..._vizinhos}; // cópia: o núcleo itera com await

  @override
  Future<void> enviar(String vizinho, Uint8List fragmento) =>
      _canal.invokeMethod('enviar', {'v': vizinho, 'd': fragmento});
}
