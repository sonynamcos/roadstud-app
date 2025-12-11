// lib/models/road_stud_command.dart

class RoadStudCommand {
  final String event;
  final DateTime timestamp;

  RoadStudCommand({required this.event, required this.timestamp});

  Map<String, dynamic> toJson() => {
    'event': event,
    'timestamp': timestamp.toIso8601String(),
  };

  factory RoadStudCommand.fromJson(Map<String, dynamic> json) =>
      RoadStudCommand(
        event: json['event'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
      );
}
