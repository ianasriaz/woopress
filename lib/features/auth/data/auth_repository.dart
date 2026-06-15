import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';
import '../../../../main.dart';
import '../../gatekeeper/presentation/screens/gatekeeper_screen.dart';
import '../../dashboard/presentation/providers/dashboard_controller.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../notifications/data/fcm_service.dart';
import '../../gatekeeper/data/gatekeeper_repository.dart';
import 'dart:async';
import 'package:firebase_database/firebase_database.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final storage = ref.watch(secureStorageProvider);
  return AuthRepository(storage, Dio());
});

class AuthRepository {
  final FlutterSecureStorage _storage;
  final Dio _dio;

  AuthRepository(this._storage, this._dio) {
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 10);
  }

  Future<bool> verifyAndSaveKeys(String key, String secret) async {
    final domain = await _storage.read(key: 'store_domain');
    if (domain == null) return false;

    // Read Cloudflare tokens (if saved by Gatekeeper)
    final cfId = await _storage.read(key: 'cf_client_id');
    final cfSecret = await _storage.read(key: 'cf_client_secret');

    // Sanitize domain to prevent https://https://
    String sanitizedDomain = domain.toLowerCase().trim();
    sanitizedDomain = sanitizedDomain.replaceAll('https://', '').replaceAll('http://', '');
    if (sanitizedDomain.endsWith('/')) sanitizedDomain = sanitizedDomain.substring(0, sanitizedDomain.length - 1);

    final baseUrl = 'https://$sanitizedDomain';
    final authHeader = 'Basic ${base64Encode(utf8.encode('$key:$secret'))}';
    
    final Map<String, String> headers = {
      'Authorization': authHeader,
      'Connection': 'keep-alive',
    };

    if (cfId != null && cfSecret != null && cfId.isNotEmpty && cfSecret.isNotEmpty) {
      headers['CF-Access-Client-Id'] = cfId;
      headers['CF-Access-Client-Secret'] = cfSecret;
    }

    try {
      // 1. Strictly validate keys against a protected WooCommerce endpoint
      final authResponse = await _dio.get(
        '$baseUrl/wp-json/wc/v3/orders?per_page=1',
        options: Options(
          headers: headers,
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      // If the protected endpoint rejects the keys, fail instantly
      if (authResponse.statusCode != 200) {
        return false;
      }

      // 2. Fetch public store metadata for the UI
      final storeResponse = await _dio.get(
        '$baseUrl/wp-json',
        options: Options(
          headers: headers,
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (storeResponse.statusCode == 200) {
        final storeName = storeResponse.data['name'] ?? domain;
        final storeUrl = storeResponse.data['url'] ?? baseUrl;

        // Save everything
        await _storage.write(key: 'baseUrl', value: baseUrl);
        await _storage.write(key: 'store_name', value: storeName);
        await _storage.write(key: 'wc_consumer_key', value: key);
        await _storage.write(key: 'wc_consumer_secret', value: secret);
        
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> hasCredentials() async {
    final key = await _storage.read(key: 'wc_consumer_key');
    final secret = await _storage.read(key: 'wc_consumer_secret');
    return key != null && secret != null && key.isNotEmpty && secret.isNotEmpty;
  }
}

enum AuthState { uninitialized, needsGatekeeper, unauthenticated, authenticated, loading, error }

class AuthNotifier extends Notifier<AuthState> {
  StreamSubscription? _gatekeeperSub;

  @override
  AuthState build() {
    ref.onDispose(() {
      _gatekeeperSub?.cancel();
    });
    
    // Auto-initialize on boot
    Future.microtask(() => checkExistingCredentials());
    
    return AuthState.uninitialized;
  }

  // Removed Firebase _setupGatekeeperListener

  Future<void> checkExistingCredentials() async {
    state = AuthState.loading;
    final repo = ref.read(authRepositoryProvider);
    final hasCreds = await repo.hasCredentials();
    
    if (hasCreds) {
      final licenseKey = await repo._storage.read(key: 'license_key');
      if (licenseKey != null) {
        // Verify Keygen License on boot
        final status = await ref.read(gatekeeperRepositoryProvider).verifyLicenseKey(licenseKey);
        if (status == GatekeeperStatus.revoked) {
          await logout();
          return;
        }
        state = AuthState.authenticated;
      } else {
        state = AuthState.needsGatekeeper;
      }
    } else {
      // No credentials. Do we have a license key?
      final licenseKey = await repo._storage.read(key: 'license_key');
      if (licenseKey != null) {
        state = AuthState.unauthenticated; // Has license, needs WooCommerce keys
      } else {
        state = AuthState.needsGatekeeper; // No license, needs to enter license
      }
    }
  }

  void markGatekeeperPassed() {
    state = AuthState.unauthenticated;
  }

  Future<bool> authenticate(String url, String key, String secret) async {
    state = AuthState.loading;
    final repo = ref.read(authRepositoryProvider);

    try {
      // Sanitize domain
      String sanitizedDomain = url.toLowerCase().trim();
      sanitizedDomain = sanitizedDomain.replaceAll('https://', '').replaceAll('http://', '');
      if (sanitizedDomain.endsWith('/')) sanitizedDomain = sanitizedDomain.substring(0, sanitizedDomain.length - 1);

      // Save the domain so verifyAndSaveKeys can use it
      await repo._storage.write(key: 'store_domain', value: sanitizedDomain);
      await repo._storage.write(key: 'baseUrl', value: sanitizedDomain); // Fallback for older code

      final isValid = await repo.verifyAndSaveKeys(key, secret);
      
      if (isValid) {
        final finalDomain = await repo._storage.read(key: 'baseUrl');
        if (finalDomain != null) {
          try {
            await ref.read(fcmServiceProvider).subscribeToStore(finalDomain);
          } catch (e) {
            print("Failed to subscribe to FCM on this platform: $e");
          }
        }

        ref.read(dashboardControllerProvider.notifier).refresh();
        state = AuthState.authenticated;
        return true;
      } else {
        state = AuthState.error;
        return false;
      }
    } catch (e) {
      print("Authentication error: $e");
      state = AuthState.error;
      return false;
    }
  }

  Future<void> logout() async {
    _gatekeeperSub?.cancel();
    final repo = ref.read(authRepositoryProvider);
    // Deactivate machine before wiping storage
    await ref.read(gatekeeperRepositoryProvider).deactivateMachine();
    await repo._storage.deleteAll();
    state = AuthState.needsGatekeeper;
  }
}

final authNotifierProvider = NotifierProvider<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});
