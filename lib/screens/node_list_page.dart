import 'package:flutter/material.dart';
import '../models/road_stud_node.dart';

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
