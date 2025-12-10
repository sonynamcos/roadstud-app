import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:road_stud_app/ble_scan_debug_page.dart';
import 'models/road_stud_node.dart';
import 'models/road_stud_command.dart';
import 'services/storage/storage_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
  // runApp(const MaterialApp(home: BleScanDebugPage()));
}

/// -------------------- 모델 클래스들 --------------------

/// -------------------- 앱 시작 --------------------

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '탑아이티 도로표지병',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: false),
      home: const MainPage(),
    );
  }
}

/// -------------------- 메인 화면 --------------------

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  final StorageService _storage = StorageService();

  // 🔹 BLE 관련 필드 (향후 실제 컨트롤러용)
  BluetoothDevice? _bleDevice;
  BluetoothCharacteristic? _bleCommandChar;

  // 우리가 약속한 서비스 / 캐릭터리스틱 UUID
  static final Guid _serviceUuid = Guid('12345678-1234-5678-1234-56789abcdef0');
  static final Guid _charUuid = Guid('12345678-1234-5678-1234-56789abcdef1');

  // 🔹 Windows 에뮬에서 광고 이름 (KIM-TOPIT)
  static const String _targetDeviceName = 'KIM-TOPIT';

  String? _lastUid;

  final List<RoadStudNode> _nodes = [];
  RoadStudNode? _currentNode;

  final List<RoadStudCommand> _commands = [];

  String? _statusMessage;

  // 🔹 실시간 로그용 리스트
  final List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _loadStoredData();
  }

  void _log(String msg) {
    final now = DateTime.now();
    final line =
        "${now.hour.toString().padLeft(2, '0')}:"
        "${now.minute.toString().padLeft(2, '0')}:"
        "${now.second.toString().padLeft(2, '0')}  $msg";

    debugPrint(line);

    setState(() {
      _logs.insert(0, line); // 최신 로그를 위에
      if (_logs.length > 100) {
        _logs.removeLast(); // 100줄까지만 유지
      }
      _statusMessage = msg; // 위에 작은 상태 메시지도 같이 갱신
    });
  }

  Future<void> _loadStoredData() async {
    try {
      final loadedNodes = await _storage.loadNodes();
      final loadedCommands = await _storage.loadCommands();

      setState(() {
        _nodes
          ..clear()
          ..addAll(loadedNodes);
        _commands
          ..clear()
          ..addAll(loadedCommands);

        if (_nodes.isNotEmpty) {
          _currentNode = _nodes.first;
          _lastUid = _currentNode!.uid;
          _statusMessage = "저장된 데이터 로드 완료";
        }
      });
    } catch (e) {
      _log("저장된 데이터 로드 실패: $e");
    }
  }

  Future<void> _saveNodes() async {
    try {
      // _nodes 타입이 List면, 안전하게 캐스팅
      await _storage.saveNodes(
        List<RoadStudNode>.from(_nodes as List<dynamic>),
      );
    } catch (e) {
      _log("노드 저장 실패: $e");
    }
  }

  Future<void> _saveCommands() async {
    try {
      await _storage.saveCommands(
        List<RoadStudCommand>.from(_commands as List<dynamic>),
      );
    } catch (e) {
      _log("명령 기록 저장 실패: $e");
    }
  }

  /// -------------------- NFC 태그 읽기 --------------------
  Future<void> _readNfc() async {
    try {
      final availability = await NfcManager.instance.checkAvailability();
      if (availability != NfcAvailability.enabled) {
        setState(() => _statusMessage = "NFC 사용 불가: $availability");
        return;
      }

      await NfcManager.instance.startSession(
        pollingOptions: {
          NfcPollingOption.iso14443,
          NfcPollingOption.iso15693,
          NfcPollingOption.iso18092,
        },
        onDiscovered: (NfcTag tag) async {
          Uint8List? idBytes;

          try {
            if (Platform.isAndroid) {
              final androidTag = NfcTagAndroid.from(tag);
              idBytes = androidTag?.id;
            }
          } catch (e) {
            setState(() => _statusMessage = "NFC 에러: $e");
            await NfcManager.instance.stopSession();
            return;
          }

          final readUid = (idBytes == null)
              ? "UID 읽기 실패"
              : idBytes
                    .map((b) => b.toRadixString(16).padLeft(2, '0'))
                    .join(':')
                    .toUpperCase();

          setState(() {
            _lastUid = readUid;
            _statusMessage = "NFC 태그 읽기 완료";
          });

          await NfcManager.instance.stopSession();
        },
      );
    } catch (e) {
      await NfcManager.instance.stopSession();
      setState(() => _statusMessage = "NFC 에러: $e");
    }
  }

  /// -------------------- 새로운 노드 추가 --------------------
  Future<void> _openNewNodePage() async {
    if (_lastUid == null) {
      setState(() => _statusMessage = "먼저 NFC 태그를 읽어 UID를 가져오세요.");
      return;
    }

    final existingIds = _nodes.map((n) => n.nodeId).toList();

    final newNode = await Navigator.push<RoadStudNode>(
      context,
      MaterialPageRoute(
        builder: (_) => NewNodePage(
          initialUid: _lastUid!,
          existingNodeIds: existingIds,
          originalNode: null,
          isEdit: false,
        ),
      ),
    );

    if (newNode != null) {
      setState(() {
        final idx = _nodes.indexWhere((n) => n.nodeId == newNode.nodeId);
        if (idx >= 0) {
          _nodes[idx] = newNode;
        } else {
          _nodes.add(newNode);
        }
        _currentNode = newNode;
        _statusMessage = "노드가 저장되었습니다.";
      });
      _saveNodes();
    }
  }

  /// -------------------- 저장된 노드 리스트에서 선택 --------------------
  Future<void> _openNodeListPage() async {
    if (_nodes.isEmpty) {
      setState(() => _statusMessage = "저장된 노드가 없습니다.");
      return;
    }

    final selectedNode = await Navigator.push<RoadStudNode>(
      context,
      MaterialPageRoute(builder: (_) => NodeListPage(nodes: _nodes)),
    );

    if (selectedNode != null) {
      setState(() {
        _currentNode = selectedNode;
        _lastUid = selectedNode.uid;
        _statusMessage = "노드를 선택했습니다.";
      });
    }
  }

  /// -------------------- 노드 삭제 --------------------
  Future<void> _deleteCurrentNode() async {
    if (_currentNode == null) {
      setState(() => _statusMessage = "삭제할 노드를 선택하세요.");
      return;
    }

    final node = _currentNode!;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("노드 삭제"),
        content: Text(
          "다음 노드를 삭제하시겠습니까?\n\n"
          "노드 이름: ${node.intersection}\n"
          "Node ID: ${node.nodeId}\n\n"
          "※ 과거 명령 기록은 유지됩니다.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("취소"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("삭제"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _nodes.removeWhere((n) => n.nodeId == node.nodeId);
      if (_nodes.isNotEmpty) {
        _currentNode = _nodes.first;
        _lastUid = _currentNode!.uid;
      } else {
        _currentNode = null;
        _lastUid = null;
      }
      _statusMessage = "노드를 삭제했습니다.";
    });
    _saveNodes();
  }

  /// -------------------- 노드 ID 수정 (UID 검증 후 이동) --------------------
  Future<void> _editCurrentNode() async {
    if (_currentNode == null) {
      setState(() => _statusMessage = "수정할 노드를 먼저 선택하세요.");
      return;
    }

    final node = _currentNode!;
    final existingIds = _nodes.map((n) => n.nodeId).toList();

    final updatedNode = await Navigator.push<RoadStudNode>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            VerifyAndEditPage(node: node, existingNodeIds: existingIds),
      ),
    );

    if (updatedNode != null) {
      setState(() {
        final idx = _nodes.indexWhere((n) => n.nodeId == node.nodeId);
        if (idx >= 0) {
          _nodes[idx] = updatedNode;
        }
        _currentNode = updatedNode;
        _lastUid = updatedNode.uid;
        _statusMessage = "노드 정보가 수정되었습니다.";
      });
      _saveNodes();
    }
  }

  /// -------------------- ★ 전체 노드 브로드캐스트 이벤트 --------------------
  Future<void> _sendEvent(String event) async {
    final now = DateTime.now();
    final total = _nodes.length;

    _log("[$event] 모드 전송 요청 (등록 노드: $total개)");

    // BLE 송신 페이로드 (미래 확장용)
    final payload = {
      "event": event,
      "target": "ALL",
      "total_nodes": total,
      "timestamp": now.toIso8601String(),
    };
    debugPrint("GROUP COMMAND: $payload");

    // 명령 → 코드 테이블
    List<int> _encodeCommand(String event) {
      switch (event) {
        case 'NIGHT':
          return [0x10];
        case 'RAIN':
          return [0x11];
        case 'FOG':
          return [0x12];
        case 'ACCIDENT':
          return [0x13];
      }
      return [0x00];
    }

    // 🔹 1) PC 에뮬로 BLE 명령 전송 (데모용)
    await _sendBleCommandToEmulator(_encodeCommand(event));

    // 🔹 2) 내부 로그/카드 처리
    setState(() {
      _commands.insert(0, RoadStudCommand(event: event, timestamp: now));

      if (_commands.length > 100) {
        _commands.removeRange(100, _commands.length);
      }

      _statusMessage = "전체 노드에 '$event' 모드 적용됨";
    });

    _saveCommands();
  }

  String _eventLabelToCode(String label) {
    switch (label) {
      case '야간':
        return 'NIGHT';
      case '비':
        return 'RAIN';
      case '안개':
        return 'FOG';
      case '사고':
        return 'ACCIDENT';
    }
    return label.toUpperCase();
  }

  /// -------------------- (향후 실제 컨트롤러용) BLE 연결 --------------------
  Future<void> _connectToBleDevice() async {
    try {
      setState(() {
        _statusMessage = "BLE 디바이스 스캔 중...";
      });

      // 혹시 이전 스캔이 돌고 있으면 정지
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}

      BluetoothDevice? foundDevice;

      // 🔥 스캔 결과 listen (stopScan() 할 때까지 계속 들어옴)
      final sub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          final name = r.device.platformName;
          final adv = r.advertisementData;

          debugPrint("[SCAN] name='${name}', local='${adv.localName}'");

          final isMatch =
              name.contains(_targetDeviceName) ||
              adv.localName.contains(_targetDeviceName);

          if (isMatch && foundDevice == null) {
            debugPrint("[SCAN] >>> TARGET FOUND!");
            foundDevice = r.device;
          }
        }
      });

      // 🔥 timeout 없이 스캔 시작
      await FlutterBluePlus.startScan(androidUsesFineLocation: true);

      // 🔥 충분히 길게 기다리기 (5초)
      await Future.delayed(const Duration(seconds: 5));

      // 🔥 스캔 종료
      await FlutterBluePlus.stopScan();
      await sub.cancel();

      // ---------------------------------------------------
      // 스캔 결과 분석
      // ---------------------------------------------------
      final results = FlutterBluePlus.lastScanResults;

      debugPrint("=== SCAN RESULT COUNT: ${results.length} ===");

      if (results.isEmpty) {
        setState(() {
          _statusMessage = "스캔된 장치가 없습니다. (BLE 광고를 확인하세요)";
        });
        return;
      }

      // 로그: 전체 장치 출력
      for (final r in results) {
        final name = r.device.platformName;
        final adv = r.advertisementData;
        debugPrint("[SCAN LIST] name='$name', local='${adv.localName}'");
      }

      // 🔥 target 못 찾았으면, 첫 번째 장치라도 연결해보기
      final target = foundDevice ?? results.first.device;

      setState(() {
        _statusMessage = "디바이스 발견: ${target.platformName} (연결 시도 중...)";
      });

      // ---------------------------------------------------
      // 연결
      // ---------------------------------------------------
      await target.connect(autoConnect: false);

      final services = await target.discoverServices();
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
      }

      if (foundChar == null) {
        setState(() {
          _statusMessage = "캐릭터리스틱을 찾지 못했습니다.";
        });
        return;
      }

      _bleDevice = target;
      _bleCommandChar = foundChar;

      setState(() {
        _statusMessage = "BLE 연결 완료! (향후 실제 컨트롤러와 연동 시 사용 예정)";
      });
    } catch (e) {
      debugPrint("[BLE ERROR] $e");
      setState(() {
        _statusMessage = "BLE 연결 에러: $e";
      });
    }
  }

  // 🔹 BLE 연결 해제
  Future<void> _disconnectBleDevice() async {
    try {
      if (_bleDevice != null) {
        await _bleDevice!.disconnect();
      }
    } catch (_) {}

    setState(() {
      _bleDevice = null;
      _bleCommandChar = null;
      _statusMessage = "BLE 연결 해제됨";
    });
  }

  // ★ 실제 BLE 전송 담당 (향후 실제 컨트롤러용)
  Future<void> _sendBleCommand(String command) async {
    if (_bleDevice == null || _bleCommandChar == null) {
      debugPrint("[BLE] 아직 디바이스/캐릭터리스틱이 준비되지 않았습니다.");
      setState(() {
        _statusMessage = "먼저 BLE 연결 버튼을 눌러 디바이스를 연결하세요.";
      });
      return;
    }

    // 🔹 이벤트명 → 코드 매핑
    List<int> _encodeEvent(String cmd) {
      switch (cmd) {
        case 'NIGHT':
          return [0x10];
        case 'RAIN':
          return [0x11];
        case 'FOG':
          return [0x12];
        case 'ACCIDENT':
          return [0x13];
        default:
          // 혹시 모르는 경우, 그냥 문자열을 UTF-8로 보내기
          return utf8.encode(cmd);
      }
    }

    try {
      final bytes = _encodeEvent(command);

      await _bleCommandChar!.write(bytes, withoutResponse: true);

      debugPrint("[BLE] send command: $command (bytes: $bytes)");
      setState(() {
        _statusMessage = "BLE 전송 완료: $command";
      });
    } catch (e) {
      debugPrint("[BLE] 전송 실패: $e");
      setState(() {
        _statusMessage = "BLE 전송 실패: $e";
      });
    }
  }

  /// -------------------- PC 에뮬용 BLE 전송 (데모용) --------------------
  Future<void> _sendBleCommandToEmulator(List<int> bytes) async {
    _log("에뮬에 명령 전송 시도: $bytes");

    ScanResult? target;

    // 1) 스캔 결과 리스너
    final sub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final name = r.device.platformName;
        final local = r.advertisementData.localName;

        debugPrint("[DEMO BLE SCAN] name='$name', local='$local'");

        if (target == null && (name == "KIM_TOPIT" || local == "KIM_TOPIT")) {
          _log("KIM_TOPIT 발견 (name='$name', local='$local')");
          target = r;
        }
      }
    });

    try {
      _log("BLE 스캔 시작");
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 4),
        androidUsesFineLocation: true,
      );

      await Future.delayed(const Duration(seconds: 4));
      await sub.cancel();

      if (target == null) {
        _log("KIM_TOPIT 를 찾지 못했습니다.");
        return;
      }

      final device = target!.device;
      _log("KIM_TOPIT 에 연결 시도 중...");

      try {
        await device.connect(autoConnect: false);
        _log("연결 성공, 서비스 검색 중...");

        final services = await device.discoverServices();
        BluetoothCharacteristic? cmdChar;

        for (final s in services) {
          if (s.serviceUuid == Guid("12345678-1234-5678-1234-56789abcdef0")) {
            for (final c in s.characteristics) {
              if (c.characteristicUuid ==
                  Guid("12345678-1234-5678-1234-56789abcdef1")) {
                cmdChar = c;
                break;
              }
            }
          }
          if (cmdChar != null) break;
        }

        if (cmdChar == null) {
          _log("에뮬 캐릭터리스틱을 찾지 못했습니다.");
          return;
        }

        _log("캐릭터리스틱 찾음, write 중...");
        await cmdChar.write(bytes, withoutResponse: true);

        _log("BLE 명령 전송 완료! (bytes=$bytes)");
      } catch (e) {
        _log("BLE 전송 실패: $e");
      } finally {
        try {
          await device.disconnect();
          _log("에뮬 디바이스 연결 해제");
        } catch (_) {}
      }
    } catch (e) {
      _log("BLE 처리 중 예외 발생: $e");
    } finally {
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
      try {
        await sub.cancel();
      } catch (_) {}
    }
  }

  /// -------------------- UI --------------------
  @override
  Widget build(BuildContext context) {
    final currentNode = _currentNode;

    return Scaffold(
      appBar: AppBar(
        title: const Text("탑아이티 도로표지병"),
        actions: [
          IconButton(
            icon: const Icon(Icons.bluetooth_searching),
            tooltip: "BLE 테스트",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BleScanDebugPage()),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            /// -------------------- 현재 노드 표시 --------------------
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.blue.shade50,
              ),
              child: currentNode == null
                  ? const Text(
                      "현재 선택된 노드가 없습니다.",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : Text(
                      "노드 이름: ${currentNode.intersection}\n"
                      "방향: ${currentNode.direction} / 차선: ${currentNode.laneType}\n"
                      "표지병 번호: ${currentNode.studNumber}\n"
                      "Node ID: ${currentNode.nodeId}\n"
                      "UID: ${currentNode.uid}",
                      style: const TextStyle(fontSize: 14),
                    ),
            ),
            const SizedBox(height: 12),

            /// -------------------- 노드 입력/리스트 --------------------
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _openNewNodePage,
                    child: const Text("새로운 노드 입력"),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _openNodeListPage,
                    child: const Text("저장된 노드 보기"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            /// -------------------- 수정/삭제 --------------------
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _editCurrentNode,
                    child: const Text("선택된 노드 ID 수정"),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _deleteCurrentNode,
                    child: const Text("선택된 노드 삭제"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            /// -------------------- NFC 읽기 --------------------
            ElevatedButton(onPressed: _readNfc, child: const Text("NFC 태그 읽기")),
            const SizedBox(height: 8),
            Text(
              _lastUid == null ? "UID 없음 (NFC 태그를 읽어주세요)" : "UID: $_lastUid",
              style: const TextStyle(fontSize: 12),
            ),

            const SizedBox(height: 16),

            /// -------------------- 이벤트 버튼 --------------------
            Wrap(
              spacing: 8,
              children: [
                for (final label in ['야간', '비', '안개', '사고'])
                  ElevatedButton(
                    onPressed: () => _sendEvent(_eventLabelToCode(label)),
                    child: Text(label),
                  ),
              ],
            ),

            const SizedBox(height: 12),

            /// -------------------- BLE 연결 (향후 실제 컨트롤러용) --------------------
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _connectToBleDevice,
                    child: Text(
                      _bleDevice == null ? "BLE 연결 (향후용)" : "BLE 재연결",
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _bleDevice == null ? null : _disconnectBleDevice,
                    child: const Text("BLE 연결 해제"),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            /// -------------------- 상태 메시지 (임시 숨김) --------------------
            Visibility(
              visible: false, // ← true 로 바꾸면 다시 나타남
              child: _statusMessage != null
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _statusMessage!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),

            /// -------------------- 실시간 로그 --------------------
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "실시간 로그",
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              height: 140,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _logs.isEmpty
                  ? const Center(
                      child: Text(
                        "아직 로그가 없습니다.",
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      reverse: true, // 최신 로그 위쪽
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          child: Text(
                            _logs[index],
                            style: const TextStyle(fontSize: 11),
                          ),
                        );
                      },
                    ),
            ),

            const SizedBox(height: 12),

            /// -------------------- 최근 명령 카드 (임시 숨김) --------------------
            Visibility(
              visible: false, // ← 여기만 true로 바꾸면 언제든 다시 보이게 가능
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "최근 전송된 정보 (최대 100개)",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  Expanded(
                    child: _commands.isEmpty
                        ? const Center(child: Text("아직 전송된 명령이 없습니다."))
                        : ListView.builder(
                            itemCount: _commands.length,
                            itemBuilder: (context, index) {
                              final cmd = _commands[index];

                              return Card(
                                child: ListTile(
                                  leading: const Icon(
                                    Icons.bolt,
                                    color: Colors.blueAccent,
                                  ),
                                  title: Text(
                                    "${cmd.event} 모드 적용됨",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  subtitle: Text(
                                    "전체 노드: ${_nodes.length}개\n"
                                    "${cmd.timestamp.toLocal()}",
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// -------------------- 새로운 노드 입력 화면 --------------------

class NewNodePage extends StatefulWidget {
  final String initialUid;
  final List<String> existingNodeIds;
  final RoadStudNode? originalNode;
  final bool isEdit;

  const NewNodePage({
    super.key,
    required this.initialUid,
    required this.existingNodeIds,
    required this.originalNode,
    required this.isEdit,
  });

  @override
  State<NewNodePage> createState() => _NewNodePageState();
}

class _NewNodePageState extends State<NewNodePage> {
  final TextEditingController _nodeNameController = TextEditingController();
  final TextEditingController _studNumberController = TextEditingController();

  String _direction = "정방향";
  String _laneType = "황색(중앙선)";
  String? _generatedId;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.isEdit && widget.originalNode != null) {
      final n = widget.originalNode!;
      _nodeNameController.text = n.intersection;
      _studNumberController.text = n.studNumber;
      _direction = n.direction;
      _laneType = n.laneType;
      _generatedId = n.nodeId;
    }
  }

  /// -------------------- ID 생성 --------------------
  void _generateId() {
    final name = _nodeNameController.text.trim();
    final stud = _studNumberController.text.trim();

    if (name.isEmpty || stud.isEmpty) {
      setState(() {
        _errorMessage = "노드 이름과 표지병 번호를 먼저 입력하세요.";
        _generatedId = null;
      });
      return;
    }

    final id = "${name}_${_direction}_${_laneType}_$stud";

    final ids = widget.existingNodeIds;
    final original = widget.originalNode?.nodeId;

    final same = widget.isEdit && id == original;

    if (!same && ids.contains(id)) {
      setState(() {
        _errorMessage = "이미 존재하는 ID입니다.\nID: $id";
        _generatedId = null;
      });
      return;
    }

    setState(() {
      _generatedId = id;
      _errorMessage = null;
    });
  }

  void _save() {
    final nm = _nodeNameController.text.trim();
    final stud = _studNumberController.text.trim();

    if (nm.isEmpty || stud.isEmpty || _generatedId == null) {
      setState(() => _errorMessage = "입력값이 부족합니다.");
      return;
    }

    final node = RoadStudNode(
      uid: widget.initialUid,
      nodeId: _generatedId!,
      intersection: nm,
      direction: _direction,
      laneType: _laneType,
      studNumber: stud,
    );

    Navigator.pop(context, node);
  }

  void _flashIdToTag() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("ID 태그 플래싱 기능은 추후 구현 예정")));
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("취소하시겠습니까?"),
        content: const Text("입력된 값이 모두 삭제됩니다."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("계속"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("취소"),
          ),
        ],
      ),
    );
    if (ok == true) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isEdit ? "노드 정보 수정" : "새로운 노드 입력";

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text("UID: ${widget.initialUid}"),

              const SizedBox(height: 16),
              TextField(
                controller: _nodeNameController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: "노드 이름 (예: 보령교차로)",
                ),
              ),

              const SizedBox(height: 12),
              DropdownButtonFormField(
                value: _direction,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: "방향",
                ),
                items: const [
                  DropdownMenuItem(value: "정방향", child: Text("정방향")),
                  DropdownMenuItem(value: "역방향", child: Text("역방향")),
                ],
                onChanged: (v) => setState(() => _direction = v!),
              ),

              const SizedBox(height: 12),
              DropdownButtonFormField(
                value: _laneType,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: "차선",
                ),
                items: const [
                  DropdownMenuItem(value: "황색(중앙선)", child: Text("황색(중앙선)")),
                  DropdownMenuItem(value: "안쪽 흰색차선", child: Text("안쪽 흰색차선")),
                  DropdownMenuItem(value: "바깥쪽 흰색차선", child: Text("바깥쪽 흰색차선")),
                ],
                onChanged: (v) => setState(() => _laneType = v!),
              ),

              const SizedBox(height: 12),
              TextField(
                controller: _studNumberController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: "표지병 번호 (예: 01)",
                ),
              ),

              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _generateId,
                child: const Text("ID 생성"),
              ),

              if (_generatedId != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    "생성된 ID:\n$_generatedId",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),

              OutlinedButton(
                onPressed: _flashIdToTag,
                child: const Text("노드에 생성된 ID 태그 플래싱하기"),
              ),

              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _save,
                      child: const Text("저장"),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _cancel,
                      child: const Text("취소"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// -------------------- ID 수정 전 UID 재검증 --------------------

class VerifyAndEditPage extends StatefulWidget {
  final RoadStudNode node;
  final List<String> existingNodeIds;

  const VerifyAndEditPage({
    super.key,
    required this.node,
    required this.existingNodeIds,
  });

  @override
  State<VerifyAndEditPage> createState() => _VerifyAndEditPageState();
}

class _VerifyAndEditPageState extends State<VerifyAndEditPage> {
  String? _status;

  Future<void> _startVerify() async {
    setState(() => _status = "NFC 태그를 표지병에 가까이 대주세요...");

    try {
      final availability = await NfcManager.instance.checkAvailability();
      if (availability != NfcAvailability.enabled) {
        setState(() => _status = "NFC 사용 불가: $availability");
        return;
      }

      await NfcManager.instance.startSession(
        pollingOptions: {
          NfcPollingOption.iso14443,
          NfcPollingOption.iso15693,
          NfcPollingOption.iso18092,
        },
        onDiscovered: (tag) async {
          Uint8List? idBytes;

          try {
            final androidTag = NfcTagAndroid.from(tag);
            idBytes = androidTag?.id;
          } catch (_) {}

          final readUid = (idBytes == null)
              ? "UID 읽기 실패"
              : idBytes
                    .map((b) => b.toRadixString(16).padLeft(2, '0'))
                    .join(':')
                    .toUpperCase();

          await NfcManager.instance.stopSession();

          if (readUid != widget.node.uid) {
            setState(() {
              _status =
                  "스캔된 UID가 일치하지 않습니다.\n"
                  "등록된 UID: ${widget.node.uid}\n"
                  "스캔된 UID: $readUid";
            });
            return;
          }

          setState(() => _status = "UID 일치! 수정 화면으로 이동합니다.");

          final updated = await Navigator.push<RoadStudNode>(
            context,
            MaterialPageRoute(
              builder: (_) => NewNodePage(
                initialUid: widget.node.uid,
                existingNodeIds: widget.existingNodeIds,
                originalNode: widget.node,
                isEdit: true,
              ),
            ),
          );

          if (!mounted) return;
          if (updated != null) Navigator.pop(context, updated);
        },
      );
    } catch (e) {
      await NfcManager.instance.stopSession();
      setState(() => _status = "NFC 에러: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;

    return Scaffold(
      appBar: AppBar(title: const Text("ID 수정 - UID 검증")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("노드 이름: ${node.intersection}"),
            Text("Node ID: ${node.nodeId}"),
            Text("UID: ${node.uid}"),

            const SizedBox(height: 16),
            const Text("동일한 표지병인지 검증하기 위해 UID 재스캔이 필요합니다."),
            const SizedBox(height: 16),

            ElevatedButton(
              onPressed: _startVerify,
              child: const Text("NFC 스캔 시작"),
            ),

            const SizedBox(height: 16),
            Text(
              _status ?? "아직 스캔을 시작하지 않았습니다.",
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

/// -------------------- 저장된 노드 목록 --------------------

class NodeListPage extends StatelessWidget {
  final List<RoadStudNode> nodes;

  const NodeListPage({super.key, required this.nodes});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("저장된 노드 목록")),
      body: nodes.isEmpty
          ? const Center(child: Text("저장된 노드가 없습니다."))
          : ListView.builder(
              itemCount: nodes.length,
              itemBuilder: (context, i) {
                final n = nodes[i];
                return Card(
                  child: ListTile(
                    title: Text(
                      "${n.intersection} / ${n.direction} / ${n.laneType}",
                    ),
                    subtitle: Text(
                      "표지병 번호: ${n.studNumber}\n"
                      "Node ID: ${n.nodeId}\n"
                      "UID: ${n.uid}",
                    ),
                    onTap: () => Navigator.pop(context, n),
                  ),
                );
              },
            ),
    );
  }
}
