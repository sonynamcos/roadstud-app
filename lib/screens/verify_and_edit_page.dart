import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';

import '../models/road_stud_node.dart';
import 'new_node_page.dart';

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
            if (Platform.isAndroid) {
              final androidTag = NfcTagAndroid.from(tag);
              idBytes = androidTag?.id;
            }
          } catch (e) {
            setState(() => _status = "NFC 에러: $e");
            await NfcManager.instance.stopSession();
            return;
          }

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
          if (updated != null) {
            Navigator.pop(context, updated);
          }
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
