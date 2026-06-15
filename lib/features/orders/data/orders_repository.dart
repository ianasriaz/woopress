import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../../../core/network/dio_config.dart';
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
      return (response.data as List).map((o) => OrderModel.fromJson(o)).toList();
    }
    throw Exception('Failed to fetch orders');
  }

  Future<void> updateOrderStatus(int orderId, String status, {String? trackingNumber, String? trackingCourier}) async {
    final data = <String, dynamic>{'status': status};
    if (trackingNumber != null || trackingCourier != null) {
      data['meta_data'] = [
        if (trackingNumber != null && trackingNumber.isNotEmpty) {'key': '_tracking_number', 'value': trackingNumber},
        if (trackingCourier != null && trackingCourier.isNotEmpty) {'key': '_tracking_courier', 'value': trackingCourier},
      ];
    }
    await _dio.put(
      '/wp-json/wc/v3/orders/$orderId',
      data: data,
    );
  }
}
