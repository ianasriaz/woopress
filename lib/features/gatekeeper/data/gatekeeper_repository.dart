import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../../../../core/storage/secure_storage.dart';

const String KEYGEN_ACCOUNT_ID = 'anasriaz';

enum GatekeeperStatus {
  allowed,
  revoked,
  networkError,
}

final gatekeeperRepositoryProvider = Provider<GatekeeperRepository>((ref) {
  final storage = ref.watch(secureStorageProvider);
  return GatekeeperRepository(storage);
});

class GatekeeperRepository {
  final FlutterSecureStorage _storage;

  GatekeeperRepository(this._storage);

  Future<String?> _getDeviceFingerprint() async {
    final deviceInfo = DeviceInfoPlugin();
    try {
      if (kIsWeb) {
        final webInfo = await deviceInfo.webBrowserInfo;
        return webInfo.vendor! + webInfo.userAgent! + webInfo.hardwareConcurrency.toString();
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return androidInfo.id; // Unique ID for Android
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return iosInfo.identifierForVendor; // Unique ID for iOS
      }
    } catch (e) {
        print("Device fingerprint error: $e");
    }
    return "unknown_device_${DateTime.now().millisecondsSinceEpoch}";
  }

  Future<GatekeeperStatus> verifyLicenseKey(String key) async {
    final dio = Dio();
    final fingerprint = await _getDeviceFingerprint() ?? "unknown_device";
    
    try {
      final response = await dio.post(
        'https://api.keygen.sh/v1/accounts/$KEYGEN_ACCOUNT_ID/licenses/actions/validate-key',
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ),
        data: {
          "meta": {
            "key": key,
            "scope": {
              "fingerprint": fingerprint
            }
          }
        },
      ).timeout(const Duration(seconds: 10));
      
      final meta = response.data['meta'];
      if (meta['valid'] == true) {
        // License is valid, and machine is activated!
        await _storage.write(key: 'license_key', value: key);
        return GatekeeperStatus.allowed;
      } else if (meta['code'] == 'NO_MACHINES' || meta['code'] == 'NO_MACHINE' || meta['code'] == 'FINGERPRINT_SCOPE_MISMATCH') {
        // License is valid, but this machine is not activated yet.
        final licenseId = response.data['data']['id'];
        
        // This will throw if it fails, which will be caught below
        await _activateMachine(key, licenseId, fingerprint);
        
        await _storage.write(key: 'license_key', value: key);
        return GatekeeperStatus.allowed;
      } else {
        // Invalid key, expired, etc.
        throw Exception("Keygen Error: ${meta['detail'] ?? meta['code']}");
      }
    } catch (e) {
      print('Keygen REST Error: $e');
      if (e is DioException) {
          final errorData = e.response?.data;
          print('Keygen API Response: $errorData');
          throw Exception("Keygen API Error: ${e.response?.statusCode} - $errorData");
      }
      throw Exception('Network or Keygen Error: $e');
    }
  }

  Future<bool> _activateMachine(String licenseKey, String licenseId, String fingerprint) async {
    final dio = Dio();
    try {
      final response = await dio.post(
        'https://api.keygen.sh/v1/accounts/$KEYGEN_ACCOUNT_ID/machines',
        options: Options(
          headers: {
            'Authorization': 'License $licenseKey',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ),
        data: {
          "data": {
            "type": "machines",
            "attributes": {
              "fingerprint": fingerprint,
              "platform": kIsWeb ? "Web Browser" : Platform.operatingSystem,
              "name": kIsWeb ? "Web User" : "${Platform.operatingSystem} Device"
            },
            "relationships": {
              "license": {
                "data": { "type": "licenses", "id": licenseId }
              }
            }
          }
        },
      ).timeout(const Duration(seconds: 10));
      
      return response.statusCode == 201 || response.statusCode == 200;
    } catch (e) {
      if (e is DioException) {
          final errorData = e.response?.data;
          throw Exception("Machine Activation Error: ${e.response?.statusCode} - $errorData");
      }
      throw Exception("Machine Activation Error: $e");
    }
  }

  Future<void> deactivateMachine() async {
      final licenseKey = await _storage.read(key: 'license_key');
      if (licenseKey == null) return;
      final fingerprint = await _getDeviceFingerprint();
      if (fingerprint == null) return;

      final dio = Dio();
      try {
        // To deactivate, we must delete the machine by its ID or fingerprint
        // Keygen allows DELETE /v1/accounts/:account/machines/:fingerprint if we provide the right headers,
        // but typically you need the machine ID.
        // For now, we will just try to delete by fingerprint if Keygen supports it, or we leave it.
        // A full implementation would fetch the machine ID first.
      } catch (_) {}
  }

  Future<bool> checkForUpdates(String currentVersion) async {
    // Firebase removed, skip checking for updates
    return false;
  }

  Future<String> getDownloadUrl() async {
    // Firebase removed, return default URL
    return 'https://github.com/ianasriaz/WooFly-Config/releases';
  }
}
