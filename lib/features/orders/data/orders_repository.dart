import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../../../core/network/dio_config.dart';
import '../../../../core/database/database_helper.dart';
import '../domain/models/order_model.dart';

final ordersRepositoryProvider = Provider<OrdersRepository>((ref) {
  final storage = ref.watch(secureStorageProvider);
  return OrdersRepository(DioConfig.createDio(storage), storage);
});

class OrdersRepository {
  final Dio _dio;
  final FlutterSecureStorage _storage;

  OrdersRepository(this._dio, this._storage);

  Future<List<OrderModel>> fetchOrders({int page = 1, String? search, String? status}) async {
    // 1. Fetch from local cache immediately for blazing fast UI
    final cachedData = await DatabaseHelper.instance.getCachedOrders(status: status, search: search);
    List<OrderModel> cachedOrders = cachedData.map((o) => OrderModel.fromJson(o)).toList();

    // 2. Attempt to fetch fresh data from WooCommerce
    try {
      final Map<String, dynamic> params = {
        'page': page, 
        'per_page': 20,
        '_fields': 'id,number,status,total,currency,date_created,billing,shipping,line_items,payment_method,payment_method_title,customer_note,meta_data',
      };
      if (search != null && search.isNotEmpty) params['search'] = search;
      if (status != null && status != 'all') params['status'] = status;
      
      final response = await _dio.get(
        '/wp-json/wc/v3/orders',
        queryParameters: params,
      );

      if (response.statusCode == 200) {
        final List<dynamic> newOrdersJson = response.data;
        
        // Update local cache
        if (page == 1 && (search == null || search.isEmpty)) {
          // If loading fresh list, rebuild cache
          await DatabaseHelper.instance.cacheOrders(newOrdersJson);
        } else {
          // If searching or paging, selectively update cache
          for (var o in newOrdersJson) {
             await DatabaseHelper.instance.updateCachedOrder(o['id'], o as Map<String, dynamic>);
          }
        }
        
        return newOrdersJson.map((o) => OrderModel.fromJson(o as Map<String, dynamic>)).toList();
      }
    } on DioException catch (e) {
      // If network fails (offline, timeout), we swallow the error and gracefully return cached orders
      print('Network offline or error fetching orders: $e');
    }

    // Return whatever we have in the cache
    if (cachedOrders.isEmpty && page == 1) {
       // Only throw if cache is completely empty and we couldn't fetch from network
       throw Exception('No internet connection and no cached data available.');
    }
    
    return cachedOrders;
  }

  Future<void> updateOrderStatus(int orderId, String status, {String? trackingNumber, String? trackingCourier}) async {
    final data = <String, dynamic>{'status': status};
    if (trackingNumber != null || trackingCourier != null) {
      data['meta_data'] = [
        if (trackingNumber != null && trackingNumber.isNotEmpty) {'key': '_tracking_number', 'value': trackingNumber},
        if (trackingCourier != null && trackingCourier.isNotEmpty) {'key': '_tracking_courier', 'value': trackingCourier},
      ];
    }

    // 1. Optimistic Update in Local DB
    final cachedOrder = await DatabaseHelper.instance.getCachedOrder(orderId);
    if (cachedOrder != null) {
      cachedOrder['status'] = status;
      
      // Attempt to optimistically inject meta_data for UI
      if (data.containsKey('meta_data')) {
        List<dynamic> meta = cachedOrder['meta_data'] ?? [];
        for (var newMeta in data['meta_data']) {
          int index = meta.indexWhere((m) => m['key'] == newMeta['key']);
          if (index != -1) {
            meta[index] = newMeta;
          } else {
            meta.add(newMeta);
          }
        }
        cachedOrder['meta_data'] = meta;
      }
      
      await DatabaseHelper.instance.updateCachedOrder(orderId, cachedOrder);
    }

    // 2. Try pushing to server
    try {
      await _dio.put(
        '/wp-json/wc/v3/orders/$orderId',
        data: data,
      );
    } on DioException catch (e) {
      // 3. Offline handling: Queue it!
      print('Network offline, queuing update for order $orderId: $e');
      await DatabaseHelper.instance.enqueueSyncAction(orderId, 'update_status', data);
    }
  }
}
