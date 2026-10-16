package com.example.btmesh_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var ble: BleMesh? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val canal = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "btmesh/ble")
        val b = BleMesh(this, canal)
        ble = b
        canal.setMethodCallHandler { call, result ->
            when (call.method) {
                "iniciar" -> { b.iniciar(); result.success(null) }
                "parar" -> { b.parar(); result.success(null) }
                "enviar" -> {
                    b.enviar(call.argument<String>("v")!!, call.argument<ByteArray>("d")!!)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        ble?.parar()
        super.onDestroy()
    }
}
