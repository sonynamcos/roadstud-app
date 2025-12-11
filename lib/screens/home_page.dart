import 'package:flutter/material.dart';
import 'package:road_stud_app/ble_scan_debug_page.dart';
import '../models/road_stud_node.dart';
import '../models/road_stud_command.dart';
import '../services/storage/storage_service.dart';
import '../services/ble/ble_manager.dart';
import 'new_node_page.dart';
import 'verify_and_edit_page.dart';
import 'node_list_page.dart';
import '../services/nfc/nfc_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final StorageService _storage = StorageService();
  late BleManager _bleManager;

  final NfcService _nfcService = NfcService();

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
    _bleManager = BleManager(
      log: _log, // 현재 로그 함수 그대로 사용
    );
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
      await _storage.saveNodes(List<RoadStudNode>.from(_nodes));
    } catch (e) {
      _log("노드 저장 실패: $e");
    }
  }

  Future<void> _saveCommands() async {
    try {
      await _storage.saveCommands(List<RoadStudCommand>.from(_commands));
    } catch (e) {
      _log("명령 기록 저장 실패: $e");
    }
  }

  /// -------------------- NFC 태그 읽기 --------------------
  Future<void> _readNfc() async {
    try {
      setState(() {
        _statusMessage = "NFC 태그를 표지병에 가까이 대주세요...";
      });

      final uid = await _nfcService.readUidOnce();

      setState(() {
        _lastUid = uid;
        _statusMessage = "NFC 태그 읽기 완료 (UID: $uid)";
      });
    } catch (e) {
      setState(() {
        _statusMessage = "NFC 에러: $e";
      });
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
      setState(() {
        _statusMessage = "저장된 노드가 없습니다.";
      });
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

  int _eventToModeByte(String event) {
    switch (event) {
      case 'NIGHT':
        return 0x10;
      case 'RAIN':
        return 0x11;
      case 'FOG':
        return 0x12;
      case 'ACCIDENT':
        return 0x13;
    }
    return 0x00;
  }

  /// -------------------- ★ 전체 노드 브로드캐스트 이벤트 --------------------
  Future<void> _sendEvent(String event) async {
    final now = DateTime.now();
    final total = _nodes.length;

    _log("[$event] 모드 전송 요청 (등록 노드: $total개)");

    final payload = {
      "event": event,
      "target": "ALL",
      "total_nodes": total,
      "timestamp": now.toIso8601String(),
    };
    debugPrint("GROUP COMMAND: $payload");

    final modeByte = _eventToModeByte(event);

    try {
      await _bleManager.scanAndConnect();
      await _bleManager.sendMode(modeByte);
      _log("BLE 모드 전송 완료 (event=$event, byte=0x${modeByte.toRadixString(16)})");
    } catch (e) {
      _log("BLE 모드 전송 실패: $e");
    }

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
        _statusMessage = "BLE 스캔 및 연결 시도 중...";
      });

      await _bleManager.scanAndConnect();

      setState(() {
        _statusMessage = "BLE 연결 완료!";
      });
    } catch (e) {
      _log("BLE 연결 실패: $e");
      setState(() {
        _statusMessage = "BLE 연결 실패: $e";
      });
    }
  }

  Future<void> _disconnectBleDevice() async {
    try {
      await _bleManager.disconnect();
    } catch (_) {}

    setState(() {
      _statusMessage = "BLE 연결 해제됨";
    });
  }

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
            // -------------------- 현재 노드 표시 --------------------
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

            // -------------------- 노드 입력/리스트 --------------------
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

            // -------------------- 수정/삭제 --------------------
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

            // -------------------- NFC 읽기 --------------------
            ElevatedButton(onPressed: _readNfc, child: const Text("NFC 태그 읽기")),
            const SizedBox(height: 8),
            Text(
              _lastUid == null ? "UID 없음 (NFC 태그를 읽어주세요)" : "UID: $_lastUid",
              style: const TextStyle(fontSize: 12),
            ),

            const SizedBox(height: 16),

            // -------------------- 이벤트 버튼 --------------------
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

            // -------------------- BLE 연결 (향후 실제 컨트롤러용) --------------------
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _connectToBleDevice,
                    child: Text(_bleManager.isConnected ? "BLE 재연결" : "BLE 연결"),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _bleManager.isConnected
                        ? _disconnectBleDevice
                        : null,
                    child: const Text("BLE 연결 해제"),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // -------------------- 상태 메시지 (임시 숨김) --------------------
            Visibility(
              visible: false,
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

            // -------------------- 실시간 로그 --------------------
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

            // -------------------- 최근 명령 카드 (임시 숨김) --------------------
            Visibility(
              visible: false,
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
