// lib/services/storage/storage_service.dart

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:road_stud_app/models/road_stud_node.dart';
import 'package:road_stud_app/models/road_stud_command.dart';

class StorageService {
  static const String _nodesKey = 'nodes';
  static const String _commandsKey = 'commands';

  /// 노드 리스트 로드
  Future<List<RoadStudNode>> loadNodes() async {
    final prefs = await SharedPreferences.getInstance();
    final nodeStrings = prefs.getStringList(_nodesKey) ?? [];

    return nodeStrings
        .map(
          (s) => RoadStudNode.fromJson(jsonDecode(s) as Map<String, dynamic>),
        )
        .toList();
  }

  /// 노드 리스트 저장
  Future<void> saveNodes(List<RoadStudNode> nodes) async {
    final prefs = await SharedPreferences.getInstance();
    final data = nodes.map((n) => jsonEncode(n.toJson())).toList();
    await prefs.setStringList(_nodesKey, data);
  }

  /// 명령 기록 로드
  Future<List<RoadStudCommand>> loadCommands() async {
    final prefs = await SharedPreferences.getInstance();
    final cmdStrings = prefs.getStringList(_commandsKey) ?? [];

    return cmdStrings
        .map(
          (s) =>
              RoadStudCommand.fromJson(jsonDecode(s) as Map<String, dynamic>),
        )
        .toList();
  }

  /// 명령 기록 저장
  Future<void> saveCommands(List<RoadStudCommand> commands) async {
    final prefs = await SharedPreferences.getInstance();
    final data = commands.map((c) => jsonEncode(c.toJson())).toList();
    await prefs.setStringList(_commandsKey, data);
  }
}
