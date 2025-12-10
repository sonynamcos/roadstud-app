// lib/services/ble/ble_manager.dart

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// 로그 출력용 콜백 타입
typedef LogCallback = void Function(String);

/// 스마트 도로표지병용 BLE 매니저
///
/// - 스캔
/// - 디바이스 연결
/// - 캐릭터리스틱 찾기
/// - 모드 전송(야간/비/안개/사고 등)
class BleManager {
  final FlutterBluePlus _ble = FlutterBluePlus.instance;
  final LogCallback log;

  /// 스캔 시 찾을 디바이스 이름 (PC 에뮬레이터 이름 등)
  final String targetDeviceName;

  /// 서비스 / 캐릭터리스틱 UUID
  final Guid serviceUuid;
  final Guid txCharacteristicUuid;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _txChar;
  StreamSubscription<ScanResult>? _scanSub;

  BleManager({
    required this.log,
    required this.targetDeviceName,
    required this.serviceUuid,
    required this.txCharacteristicUuid,
  });

  BluetoothDevice? get device => _device;
  bool get isConnected => _device != null && _txChar != null;

  /// -------------------- 스캔/연결 --------------------

  /// 타겟 디바이스를 찾아 자동 연결
  Future<void> scanAndConnect({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    log("BLE: 스캔 시작 (target: $targetDeviceName)");

    // 이미 연결되어 있으면 재시도 안 함
    if (isConnected) {
      log("BLE: 이미 연결된 상태입니다.");
      return;
    }

    // 이전 스캔 정리
    await _scanSub?.cancel();

    final completer = Completer<void>();

    _scanSub = _ble.scanResults.listen((results) async {
      for (final r in results) {
        final name = r
            .device
            .platformName; // flutter_blue_plus v1.x (이전 이름: r.device.name)
        if (name == targetDeviceName) {
          log("BLE: 타겟 디바이스 발견 → $name, RSSI=${r.rssi}");

          await _ble.stopScan();
          await _scanSub?.cancel();
          _scanSub = null;

          try {
            await _connectToDevice(r.device);
            completer.complete();
          } catch (e) {
            log("BLE: 디바이스 연결 실패: $e");
            if (!completer.isCompleted) {
              completer.completeError(e);
            }
          }

          break;
        }
      }
    });

    await _ble.startScan(timeout: timeout);
    log("BLE: 스캔 명령 전송됨");

    // 타임아웃 처리
    return completer.future.timeout(
      timeout + const Duration(seconds: 1),
      onTimeout: () async {
        log("BLE: 타임아웃 – 디바이스를 찾지 못했습니다.");
        await _ble.stopScan();
        await _scanSub?.cancel();
        _scanSub = null;
      },
    );
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    log("BLE: 디바이스 연결 시도: ${device.platformName}");

    _device = device;

    await device.connect(autoConnect: false);
    log("BLE: 연결 완료");

    // 서비스 검색
    final services = await device.discoverServices();
    log("BLE: 서비스 ${services.length}개 발견");

    BluetoothCharacteristic? foundChar;

    for (final s in services) {
      if (s.serviceUuid == serviceUuid) {
        for (final c in s.characteristics) {
          if (c.characteristicUuid == txCharacteristicUuid) {
            foundChar = c;
            break;
          }
        }
      }
      if (foundChar != null) break;
    }

    if (foundChar == null) {
      log("BLE: TX 캐릭터리스틱을 찾지 못했습니다.");
      await device.disconnect();
      _device = null;
      throw Exception("TX characteristic not found");
    }

    _txChar = foundChar;
    log("BLE: TX 캐릭터리스틱 바인딩 완료");
  }

  /// 연결 해제
  Future<void> disconnect() async {
    if (_device != null) {
      log("BLE: 연결 해제 시도");
      try {
        await _device!.disconnect();
      } catch (_) {}
    }
    _device = null;
    _txChar = null;
  }

  /// -------------------- 명령 전송 --------------------

  /// 단일 바이트 모드 명령 전송 (ex: 0x10 = 야간, 0x11 = 비, ...)
  Future<void> sendMode(int modeByte) async {
    if (!isConnected) {
      log("BLE: sendMode 호출 – 아직 디바이스에 연결되지 않았습니다.");
      throw Exception("Device not connected");
    }

    final data = Uint8List.fromList([modeByte & 0xFF]);

    try {
      await _txChar!.write(data, withoutResponse: true);
      log("BLE: 모드 전송 완료 (0x${modeByte.toRadixString(16).padLeft(2, '0')})");
    } catch (e) {
      log("BLE: 모드 전송 실패: $e");
      rethrow;
    }
  }

  /// 안전한 정리
  Future<void> dispose() async {
    await _scanSub?.cancel();
    _scanSub = null;
    await disconnect();
  }
}
