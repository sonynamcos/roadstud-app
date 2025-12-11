import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';

typedef NfcStatusCallback = void Function(String message);

/// NFC 관련 기능을 전담하는 서비스
class NfcService {
  /// NFC 태그를 스캔해서 UID를 문자열로 반환
  ///
  /// - 성공: "AA:BB:CC:DD:..." 형태의 UID 문자열
  /// - 실패 또는 NFC 불가: null
  Future<String?> readUid({required NfcStatusCallback onStatus}) async {
    try {
      final availability = await NfcManager.instance.checkAvailability();
      if (availability != NfcAvailability.enabled) {
        onStatus("NFC 사용 불가: $availability");
        return null;
      }

      onStatus("NFC 스캔을 시작합니다. 태그를 가까이 대주세요.");

      final completer = Completer<String?>();

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
              onStatus("UID 읽기 실패");
              if (!completer.isCompleted) {
                completer.complete(null);
              }
            } else {
              final uid = idBytes
                  .map((b) => b.toRadixString(16).padLeft(2, '0'))
                  .join(':')
                  .toUpperCase();
              onStatus("NFC 태그 읽기 완료");
              if (!completer.isCompleted) {
                completer.complete(uid);
              }
            }
          } catch (e) {
            onStatus("NFC 에러: $e");
            if (!completer.isCompleted) {
              completer.complete(null);
            }
          } finally {
            try {
              await NfcManager.instance.stopSession();
            } catch (_) {}
          }
        },
      );

      // UID 결과 대기 (에러 난 경우도 null)
      final uid = await completer.future;
      return uid;
    } catch (e) {
      onStatus("NFC 에러: $e");
      try {
        // 여기도 errorMessage 없이 호출
        await NfcManager.instance.stopSession();
      } catch (_) {}
      return null;
    }
  }
}
