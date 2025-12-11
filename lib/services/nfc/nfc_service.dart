// lib/services/nfc/nfc_service.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';

class NfcService {
  /// NFC 사용 가능 여부 단순 체크
  Future<NfcAvailability> checkAvailability() {
    return NfcManager.instance.checkAvailability();
  }

  /// 한 번 태그 스캔해서 UID를 문자열로 반환
  ///
  /// - 성공: "AA:BB:CC:DD:EE:FF" 형태의 UID 리턴
  /// - 실패: Exception throw
  Future<String> readUidOnce() async {
    final availability = await checkAvailability();
    if (availability != NfcAvailability.enabled) {
      throw Exception("NFC 사용 불가: $availability");
    }

    final completer = Completer<String>();

    try {
      await NfcManager.instance.startSession(
        pollingOptions: {
          NfcPollingOption.iso14443,
          NfcPollingOption.iso15693,
          NfcPollingOption.iso18092,
        },
        onDiscovered: (NfcTag tag) async {
          try {
            Uint8List? idBytes;

            if (Platform.isAndroid) {
              final androidTag = NfcTagAndroid.from(tag);
              idBytes = androidTag?.id;
            }

            if (idBytes == null) {
              throw Exception("UID 읽기 실패");
            }

            final uid = idBytes
                .map((b) => b.toRadixString(16).padLeft(2, '0'))
                .join(':')
                .toUpperCase();

            await NfcManager.instance.stopSession();
            if (!completer.isCompleted) {
              completer.complete(uid);
            }
          } catch (e) {
            await NfcManager.instance.stopSession(errorMessage: "$e");
            if (!completer.isCompleted) {
              completer.completeError(e);
            }
          }
        },
      );
    } catch (e) {
      // startSession 자체가 실패한 경우
      try {
        await NfcManager.instance.stopSession();
      } catch (_) {}
      if (!completer.isCompleted) {
        completer.completeError(e);
      }
    }

    return completer.future;
  }
}
