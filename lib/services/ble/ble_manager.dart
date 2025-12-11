// lib/services/ble/ble_manager.dart

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

typedef LogCallback = void Function(String);

/// 스마트 도로표지병용 BLE 매니저
///
/// - 스캔
/// - 디바이스 연결
/// - 캐릭터리스틱 찾기
/// - 단일 바이트 모드 전송 (0x10 ~ 0x13)
class BleManager {
  BleManager({required this.log});

  final LogCallback log;

  // 🔹 Windows PC 에뮬에서 광고되는 이름
  static const String _targetDeviceName = 'KIM_TOPIT';

  // 🔹 우리가 약속한 서비스 / 캐릭터리스틱 UUID
  static final Guid _serviceUuid = Guid('12345678-1234-5678-1234-56789abcdef0');
  static final Guid _charUuid = Guid('12345678-1234-5678-1234-56789abcdef1');

  BluetoothDevice? _device;
  BluetoothCharacteristic? _txChar;
  StreamSubscription? _scanSub;

  BluetoothDevice? get device => _device;
  bool get isConnected => _device != null && _txChar != null;

  /// -------------------- 스캔/연결 --------------------

  /// 타겟 디바이스를 찾아 자동 연결
  Future<void> scanAndConnect({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    log("BLE: 스캔 시작 (target: $_targetDeviceName)");

    // 이미 연결되어 있으면 재시도 안 함
    if (isConnected) {
      log("BLE: 이미 연결된 상태입니다.");
      return;
    }

    // 이전 스캔 정리
    await _scanSub?.cancel();
    _scanSub = null;

    final completer = Completer<void>();

    _scanSub = FlutterBluePlus.scanResults.listen((results) async {
      for (final r in results) {
        final name = r.device.platformName;
        if (name == _targetDeviceName) {
          log("BLE: 타겟 디바이스 발견 → $name, RSSI=${r.rssi}");

          await FlutterBluePlus.stopScan();
          await _scanSub?.cancel();
          _scanSub = null;

          try {
            await _connectToDevice(r.device);
            if (!completer.isCompleted) {
              completer.complete();
            }
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

    await FlutterBluePlus.startScan(
      timeout: timeout,
      androidUsesFineLocation: true,
    );
    log("BLE: 스캔 명령 전송됨");

    // 타임아웃 처리
    return completer.future.timeout(
      timeout + const Duration(seconds: 1),
      onTimeout: () async {
        log("BLE: 타임아웃 – 디바이스를 찾지 못했습니다.");
        try {
          await FlutterBluePlus.stopScan();
        } catch (_) {}
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
      if (s.serviceUuid == _serviceUuid) {
        for (final c in s.characteristics) {
          if (c.characteristicUuid == _charUuid) {
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

    final data = Uint8List.fromList(<int>[modeByte & 0xFF]);

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
