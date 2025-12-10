// lib/models/road_stud_node.dart

class RoadStudNode {
  final String uid;
  final String nodeId;
  final String intersection;
  final String direction;
  final String laneType;
  final String studNumber;

  RoadStudNode({
    required this.uid,
    required this.nodeId,
    required this.intersection,
    required this.direction,
    required this.laneType,
    required this.studNumber,
  });

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'nodeId': nodeId,
        'intersection': intersection,
        'direction': direction,
        'laneType': laneType,
        'studNumber': studNumber,
      };

  factory RoadStudNode.fromJson(Map<String, dynamic> json) => RoadStudNode(
        uid: json['uid'] as String,
        nodeId: json['nodeId'] as String,
        intersection: json['intersection'] as String,
        direction: json['direction'] as String,
        laneType: json['laneType'] as String,
        studNumber: json['studNumber'] as String,
      );
}
