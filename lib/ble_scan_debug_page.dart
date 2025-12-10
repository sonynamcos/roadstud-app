import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleScanDebugPage extends StatefulWidget {
  const BleScanDebugPage({super.key});

  @override
  State<BleScanDebugPage> createState() => _BleScanDebugPageState();
}

class _BleScanDebugPageState extends State<BleScanDebugPage> {
  final Map<String, ScanResult> _devices = {};
  StreamSubscription<List<ScanResult>>? _scanSub;
  bool _isScanning = false;

  // 우리가 약속한 서비스 / 캐릭터리스틱 UUID
  // 🔹 실제 네가 Windows 에뮬에서 사용한 UUID로 바꿔 넣어야 함
  static const String targetServiceUuid =
      '12345678-1234-5678-1234-56789abcdef0';
  static const String targetCharUuid = '12345678-1234-5678-1234-56789abcdef1';

  String _statusText = '디바이스를 탭해서 연결 테스트';

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> _connectAndTest(ScanResult r) async {
    final device = r.device;

    setState(() {
      _statusText = '연결 시도 중: ${device.name} (${device.id.id})';
    });

    debugPrint('=== CONNECT TO ${device.id.id} ===');

    try {
      if (device.isConnected) {
        debugPrint('Already connected');
      } else {
        await device.connect(autoConnect: false);
        debugPrint('Connected!');
      }

      setState(() {
        _statusText = '서비스 검색 중...';
      });

      final services = await device.discoverServices();
      BluetoothCharacteristic? targetChar;

      for (final s in services) {
        debugPrint('SERVICE: ${s.uuid}');

        if (s.uuid.toString().toLowerCase() ==
            targetServiceUuid.toLowerCase()) {
          debugPrint('>> TARGET SERVICE FOUND');

          for (final c in s.characteristics) {
            debugPrint('  CHAR: ${c.uuid}');

            if (c.uuid.toString().toLowerCase() ==
                targetCharUuid.toLowerCase()) {
              debugPrint('>> TARGET CHARACTERISTIC FOUND');
              targetChar = c;
            }
          }
        }
      }

      if (targetChar == null) {
        debugPrint('!!! Target characteristic not found');
        setState(() {
          _statusText = '타겟 캐릭터리스틱을 찾지 못했습니다.';
        });
        return;
      }

      final command = <int>[0x01, 0x02, 0x03];
      await targetChar.write(command, withoutResponse: true);
      debugPrint('>>> WRITE SENT: ${_bytesToHex(command)}');

      setState(() {
        _statusText = '명령 전송 완료: ${_bytesToHex(command)}';
      });
    } catch (e, st) {
      debugPrint('### CONNECT/WRITE ERROR: $e');
      debugPrint(st.toString());

      setState(() {
        _statusText = '에러 발생: $e';
      });
    }
  }

  Future<void> _startScan() async {
    if (_isScanning) return;

    setState(() {
      _devices.clear();
      _isScanning = true;
    });

    debugPrint('=== BLE SCAN START ===');

    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final id = r.device.id.id;

        if (!_devices.containsKey(id)) {
          _devices[id] = r;

          debugPrint('----- BLE DEVICE FOUND -----');
          debugPrint('ID: ${r.device.id.id}');
          debugPrint('NAME: ${r.device.name}');
          debugPrint('RSSI: ${r.rssi}');

          final adv = r.advertisementData;
          debugPrint('LOCAL NAME: ${adv.localName}');
          debugPrint('SERVICE UUIDS: ${adv.serviceUuids}');
          debugPrint('-----------------------------');
        }
      }

      setState(() {});
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 10),
        androidUsesFineLocation: true, // 위치 권한 사용
      );
    } catch (e, st) {
      debugPrint('### SCAN ERROR: $e');
      debugPrint(st.toString());
    }

    debugPrint('=== BLE SCAN END ===');

    setState(() {
      _isScanning = false;
    });
  }

  String _formatMfrData(Map<int, List<int>> data) {
    if (data.isEmpty) return '{}';
    return data.entries
        .map((e) => '${e.key.toRadixString(16)}: ${_bytesToHex(e.value)}')
        .join(', ');
  }

  String _formatServiceData(Map<Guid, List<int>> data) {
    if (data.isEmpty) return '{}';
    return data.entries
        .map((e) => '${e.key.toString()}: ${_bytesToHex(e.value)}')
        .join(', ');
  }

  String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final deviceList = _devices.values.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Scan Debug'),
        actions: [
          IconButton(
            onPressed: _startScan,
            icon: Icon(_isScanning ? Icons.sync : Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isScanning) const LinearProgressIndicator(),
          Expanded(
            child: ListView.builder(
              itemCount: deviceList.length,
              itemBuilder: (context, index) {
                final r = deviceList[index];
                final adv = r.advertisementData;

                return ListTile(
                  title: Text(
                    r.device.name.isNotEmpty ? r.device.name : '(no name)',
                  ),
                  subtitle: Text(
                    'ID: ${r.device.id.id}\n'
                    'RSSI: ${r.rssi}\n'
                    'LocalName: ${adv.localName}\n'
                    'ServiceUUIDs: ${adv.serviceUuids}',
                  ),
                  isThreeLine: true,
                  // 🔹 여기 추가
                  onTap: () {
                    debugPrint('TAP: ${r.device.id.id} (${r.device.name})');

                    // 🔹 탭 피드백: 스낵바 + 상태 텍스트 업데이트
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '연결 테스트: ${r.device.name.isNotEmpty ? r.device.name : r.device.id.id}',
                        ),
                        duration: const Duration(seconds: 1),
                      ),
                    );

                    _connectAndTest(r);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
