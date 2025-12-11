import 'package:flutter/material.dart';
import '../models/road_stud_node.dart';

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
