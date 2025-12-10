class RoadStudTag {
  final String uid;        // NFC 태그 UID
  final String nodeId;     // 부여한 Node ID
  final String event;      // RAIN / ACCIDENT / NIGHT 등
  final DateTime timestamp;

  final String intersection; // 교차로 이름 (보령교차로, 웅천교차로 등)
  final String direction;    // 정방향 / 역방향
  final String laneType;     // 황색(중앙선), 안쪽 흰색차선, 바깥쪽 흰색차선
  final String studNumber;   // 표지병 번호 (예: 01, 02...)

  RoadStudTag({
    required this.uid,
    required this.nodeId,
    required this.event,
    required this.timestamp,
    required this.intersection,
    required this.direction,
    required this.laneType,
    required this.studNumber,
  });

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'nodeId': nodeId,
        'event': event,
        'timestamp': timestamp.toIso8601String(),
        'intersection': intersection,
        'direction': direction,
        'laneType': laneType,
        'studNumber': studNumber,
      };
}
