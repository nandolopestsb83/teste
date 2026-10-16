package com.example.btmesh_app

import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

/**
 * Cada aparelho é ao mesmo tempo:
 *  - peripheral: anuncia o serviço, recebe escritas em TX e envia por notify em RX
 *  - central: escaneia o serviço, conecta, escreve no TX do vizinho e assina o RX dele
 * Toda a lógica de estado roda na thread principal (callbacks fazem main.post).
 */
@SuppressLint("MissingPermission")
class BleMesh(ctx: Context, private val canal: MethodChannel) {
    companion object {
        val SERVICO: UUID = UUID.fromString("6e6b0001-b5a3-f393-e0a9-e50e24dcca9e")
        val TX: UUID = UUID.fromString("6e6b0002-b5a3-f393-e0a9-e50e24dcca9e") // quem conecta escreve aqui
        val RX: UUID = UUID.fromString("6e6b0003-b5a3-f393-e0a9-e50e24dcca9e") // servidor notifica aqui
        val CCCD: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
        const val MTU = 185
        const val MAX_CLIENTES = 4 // limite prático de conexões simultâneas
    }

    private class Fila { val itens = ArrayDeque<ByteArray>(); var ocupado = false }

    private val appCtx = ctx.applicationContext
    private val manager = appCtx.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    private val main = Handler(Looper.getMainLooper())

    private var servidor: BluetoothGattServer? = null
    private var rxServidor: BluetoothGattCharacteristic? = null
    private var scanner: BluetoothLeScanner? = null
    private var anunciante: BluetoothLeAdvertiser? = null

    private val clientes = HashMap<String, BluetoothGatt>()          // eu sou central
    private val txRemotos = HashMap<String, BluetoothGattCharacteristic>()
    private val centrais = HashMap<String, BluetoothDevice>()        // eu sou servidor
    private val conectando = HashSet<String>()
    private val filas = HashMap<String, Fila>()

    // ---------- ciclo de vida ----------

    fun iniciar() {
        val a = manager.adapter ?: return
        if (!a.isEnabled) return
        abrirServidor()
        anunciante = a.bluetoothLeAdvertiser
        anunciante?.startAdvertising(
            AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_BALANCED)
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
                .setConnectable(true).setTimeout(0).build(),
            AdvertiseData.Builder().setIncludeDeviceName(false)
                .addServiceUuid(ParcelUuid(SERVICO)).build(),
            advCb
        )
        scanner = a.bluetoothLeScanner
        scanner?.startScan(
            listOf(ScanFilter.Builder().setServiceUuid(ParcelUuid(SERVICO)).build()),
            ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_BALANCED).build(),
            scanCb
        )
    }

    fun parar() {
        scanner?.stopScan(scanCb)
        anunciante?.stopAdvertising(advCb)
        clientes.values.forEach { it.close() }
        servidor?.close()
        clientes.clear(); txRemotos.clear(); centrais.clear(); conectando.clear(); filas.clear()
        servidor = null
    }

    private fun abrirServidor() {
        val srv = manager.openGattServer(appCtx, servidorCb) ?: return
        val servico = BluetoothGattService(SERVICO, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        val tx = BluetoothGattCharacteristic(
            TX,
            BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE,
            BluetoothGattCharacteristic.PERMISSION_WRITE
        )
        val rx = BluetoothGattCharacteristic(
            RX, BluetoothGattCharacteristic.PROPERTY_NOTIFY, BluetoothGattCharacteristic.PERMISSION_READ
        )
        rx.addDescriptor(
            BluetoothGattDescriptor(
                CCCD, BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE
            )
        )
        servico.addCharacteristic(tx)
        servico.addCharacteristic(rx)
        srv.addService(servico)
        servidor = srv
        rxServidor = rx
    }

    // ---------- envio (uma operação GATT por vez, por vizinho) ----------

    fun enviar(addr: String, dados: ByteArray) {
        val f = filas.getOrPut(addr) { Fila() }
        f.itens.addLast(dados)
        if (!f.ocupado) proximo(addr)
    }

    private fun proximo(addr: String) {
        val f = filas[addr] ?: return
        val dados = f.itens.removeFirstOrNull()
        if (dados == null) { f.ocupado = false; return }
        f.ocupado = true
        val gatt = clientes[addr]
        val tx = txRemotos[addr]
        val central = centrais[addr]
        val rx = rxServidor
        @Suppress("DEPRECATION")
        val ok = when {
            gatt != null && tx != null -> {
                tx.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                tx.value = dados
                gatt.writeCharacteristic(tx)
            }
            central != null && rx != null -> {
                rx.value = dados
                servidor?.notifyCharacteristicChanged(central, rx, false) ?: false
            }
            else -> false
        }
        if (!ok) proximo(addr) // falhou: descarta este fragmento e segue
    }

    private fun avisar(metodo: String, addr: String) = canal.invokeMethod(metodo, mapOf("v" to addr))
    private fun dados(addr: String, d: ByteArray) = canal.invokeMethod("dados", mapOf("v" to addr, "d" to d))

    // ---------- anúncio e scan ----------

    private val advCb = object : AdvertiseCallback() {}

    private val scanCb = object : ScanCallback() {
        override fun onScanResult(tipo: Int, r: ScanResult) {
            main.post {
                val addr = r.device.address
                if (clientes.containsKey(addr) || conectando.contains(addr)) return@post
                if (clientes.size + conectando.size >= MAX_CLIENTES) return@post
                conectando.add(addr)
                r.device.connectGatt(appCtx, false, clienteCb, BluetoothDevice.TRANSPORT_LE)
            }
        }
    }

    // ---------- papel de central (eu conectei no vizinho) ----------

    private val clienteCb = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, novo: Int) {
            main.post {
                val addr = g.device.address
                if (novo == BluetoothProfile.STATE_CONNECTED && status == BluetoothGatt.GATT_SUCCESS) {
                    g.requestMtu(MTU)
                } else {
                    g.close()
                    clientes.remove(addr); txRemotos.remove(addr)
                    conectando.remove(addr); filas.remove(addr)
                    avisar("saiu", addr)
                }
            }
        }

        override fun onMtuChanged(g: BluetoothGatt, mtu: Int, status: Int) {
            main.post { g.discoverServices() }
        }

        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
            main.post {
                val s = g.getService(SERVICO)
                val tx = s?.getCharacteristic(TX)
                val rx = s?.getCharacteristic(RX)
                val cccd = rx?.getDescriptor(CCCD)
                if (tx == null || rx == null || cccd == null) { g.disconnect(); return@post }
                txRemotos[g.device.address] = tx
                g.setCharacteristicNotification(rx, true)
                @Suppress("DEPRECATION")
                cccd.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                @Suppress("DEPRECATION")
                g.writeDescriptor(cccd)
            }
        }

        override fun onDescriptorWrite(g: BluetoothGatt, d: BluetoothGattDescriptor, status: Int) {
            main.post {
                val addr = g.device.address
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    clientes[addr] = g
                    conectando.remove(addr)
                    avisar("vizinho", addr)
                } else g.disconnect()
            }
        }

        @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
        override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic) {
            val v = c.value?.copyOf() ?: return
            main.post { dados(g.device.address, v) }
        }

        override fun onCharacteristicWrite(g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int) {
            main.post { proximo(g.device.address) }
        }
    }

    // ---------- papel de servidor (o vizinho conectou em mim) ----------

    private val servidorCb = object : BluetoothGattServerCallback() {
        override fun onConnectionStateChange(d: BluetoothDevice, status: Int, novo: Int) {
            if (novo == BluetoothProfile.STATE_DISCONNECTED) {
                main.post {
                    val a = d.address
                    if (centrais.remove(a) != null) { filas.remove(a); avisar("saiu", a) }
                }
            }
        }

        override fun onDescriptorWriteRequest(
            d: BluetoothDevice, id: Int, desc: BluetoothGattDescriptor,
            prep: Boolean, resp: Boolean, off: Int, value: ByteArray
        ) {
            main.post {
                if (desc.uuid == CCCD && value.isNotEmpty() && value[0].toInt() != 0) {
                    if (centrais.put(d.address, d) == null) avisar("vizinho", d.address)
                }
                if (resp) servidor?.sendResponse(d, id, BluetoothGatt.GATT_SUCCESS, off, value)
            }
        }

        override fun onCharacteristicWriteRequest(
            d: BluetoothDevice, id: Int, c: BluetoothGattCharacteristic,
            prep: Boolean, resp: Boolean, off: Int, value: ByteArray
        ) {
            main.post {
                if (c.uuid == TX) dados(d.address, value)
                if (resp) servidor?.sendResponse(d, id, BluetoothGatt.GATT_SUCCESS, off, value)
            }
        }

        override fun onNotificationSent(d: BluetoothDevice, status: Int) {
            main.post { proximo(d.address) }
        }
    }
}
