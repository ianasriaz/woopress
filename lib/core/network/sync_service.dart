import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/database_helper.dart';
import 'dio_config.dart';
import '../storage/secure_storage.dart';

final syncServiceProvider = Provider<SyncService>((ref) {
  final storage = ref.watch(secureStorageProvider);
  return SyncService(DioConfig.createDio(storage));
});

class SyncService {
  final Dio _dio;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isSyncing = false;

  SyncService(this._dio);

  void startListening() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (results.contains(ConnectivityResult.mobile) || results.contains(ConnectivityResult.wifi)) {
        _syncPendingActions();
      }
    });
    // Attempt sync immediately on startup
    _syncPendingActions();
  }

  void stopListening() {
    _connectivitySubscription?.cancel();
  }

  Future<void> _syncPendingActions() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final pendingActions = await DatabaseHelper.instance.getPendingSyncActions();
      if (pendingActions.isEmpty) {
        _isSyncing = false;
        return;
      }

      print('Starting sync of ${pendingActions.length} pending actions...');

      for (var action in pendingActions) {
        int id = action['id'];
        int orderId = action['order_id'];
        String actionType = action['action_type'];
        Map<String, dynamic> payload = jsonDecode(action['payload']);

        try {
          if (actionType == 'update_status') {
            await _dio.put('/wp-json/wc/v3/orders/$orderId', data: payload);
          }
          // If successful, remove from queue
          await DatabaseHelper.instance.removeSyncAction(id);
          print('Successfully synced action ID: $id');
        } on DioException catch (e) {
          // If network failed during sync, abort this sync run and try again later
          print('Network failed during sync for ID: $id. Aborting sync run.');
          break;
        } catch (e) {
           print('Fatal error syncing ID $id: $e');
        }
      }
    } finally {
      _isSyncing = false;
    }
  }
}
