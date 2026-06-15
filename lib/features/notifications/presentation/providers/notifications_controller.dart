import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../domain/models/notification_model.dart';

class NotificationsController extends AsyncNotifier<List<NotificationModel>> {
  static const _storageKey = 'notifications_history_v1';
  static const _maxNotifications = 50;

  @override
  Future<List<NotificationModel>> build() async {
    return _loadFromStorage();
  }

  Future<List<NotificationModel>> _loadFromStorage() async {
    final storage = ref.read(secureStorageProvider);
    final data = await storage.read(key: _storageKey);
    if (data == null) return [];
    try {
      final List decoded = jsonDecode(data);
      return decoded.map((e) => NotificationModel.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveToStorage(List<NotificationModel> list) async {
    final storage = ref.read(secureStorageProvider);
    await storage.write(key: _storageKey, value: jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  Future<void> addNotification(NotificationModel notification) async {
    final currentList = state.value ?? await _loadFromStorage();
    // Check if ID already exists
    if (currentList.any((n) => n.id == notification.id)) return;
    
    final updatedList = [notification, ...currentList];
    if (updatedList.length > _maxNotifications) {
      updatedList.removeLast();
    }
    await _saveToStorage(updatedList);
    state = AsyncValue.data(updatedList);
  }

  Future<void> markAsRead(String id) async {
    final currentList = state.value ?? [];
    final updatedList = currentList.map((n) {
      if (n.id == id) return n.copyWith(isRead: true);
      return n;
    }).toList();
    await _saveToStorage(updatedList);
    state = AsyncValue.data(updatedList);
  }

  Future<void> deleteNotification(String id) async {
    final currentList = state.value ?? [];
    final updatedList = currentList.where((n) => n.id != id).toList();
    await _saveToStorage(updatedList);
    state = AsyncValue.data(updatedList);
  }

  Future<void> clearAll() async {
    await _saveToStorage([]);
    state = const AsyncValue.data([]);
  }

  Future<void> refresh() async {
    final list = await _loadFromStorage();
    state = AsyncValue.data(list);
  }
}

final notificationsControllerProvider = AsyncNotifierProvider<NotificationsController, List<NotificationModel>>(() {
  return NotificationsController();
});
