import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../../../core/network/dio_config.dart';
import '../domain/models/store_stats.dart';
import '../domain/models/top_product.dart';

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  final storage = ref.watch(secureStorageProvider);
  return DashboardRepository(DioConfig.createDio(storage), storage);
});

class DashboardRepository {
  final Dio _dio;
  final FlutterSecureStorage _storage;

  DashboardRepository(this._dio, this._storage);

  Future<StoreStats> fetchStoreStats({bool forceRefresh = false}) async {
    try {
      final now = DateTime.now();
      
      final String monthStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-01";
      final String yearStr = "${now.year}-01-01";
      final String todayStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

      // Query real-time orders for today to bypass any WooCommerce report caching
      final reqTodayOrders = _dio.get('/wp-json/wc/v3/orders', queryParameters: {
        'after': '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}T00:00:00',
        'per_page': 100,
      });

      final reqMonth = _dio.get('/wp-json/wc/v3/reports/sales', queryParameters: {
        'date_min': monthStr,
        'date_max': todayStr,
      });

      final reqYear = _dio.get('/wp-json/wc/v3/reports/sales', queryParameters: {
        'date_min': yearStr,
        'date_max': todayStr,
      });

      final reqVisitors = _dio.get('/wp-json/woopress/v1/stats', options: Options(validateStatus: (_) => true)).catchError((_) => Response(requestOptions: RequestOptions(), data: null, statusCode: 404));

      // Wait for all concurrent requests
      final responses = await Future.wait([reqTodayOrders, reqMonth, reqYear, reqVisitors]);

      // Parse Live Orders Data for Today
      double todayRevenue = 0.0;
      int ordersToday = 0;
      int itemsSold = 0;

      if (responses[0].data != null && responses[0].data is List) {
        final orders = responses[0].data as List;
        for (var order in orders) {
          final status = order['status']?.toString() ?? '';
          // Ignore cancelled/failed/refunded/trash. Count everything else including 'pending' so test orders show up immediately.
          if (!['cancelled', 'failed', 'refunded', 'trash'].contains(status)) {
            todayRevenue += double.tryParse(order['total']?.toString() ?? '0') ?? 0.0;
            ordersToday += 1;
            
            // Calculate items sold
            if (order['line_items'] != null && order['line_items'] is List) {
              for (var item in (order['line_items'] as List)) {
                itemsSold += int.tryParse(item['quantity']?.toString() ?? '0') ?? 0;
              }
            }
          }
        }
      }

      // Parse Native WooCommerce Report Data for Month/Year
      final monthData = (responses[1].data != null && responses[1].data is List && responses[1].data.isNotEmpty) ? responses[1].data[0] : {};
      final yearData = (responses[2].data != null && responses[2].data is List && responses[2].data.isNotEmpty) ? responses[2].data[0] : {};

      final monthlyRevenue = double.tryParse(monthData['total_sales']?.toString() ?? '0') ?? 0.0;
      final yearlyRevenue = double.tryParse(yearData['total_sales']?.toString() ?? '0') ?? 0.0;

      // Parse Visitor Data from custom endpoint (if active)
      int visitorsToday = 0;
      if (responses[3].statusCode == 200 && responses[3].data != null && responses[3].data['status'] == 'success') {
          visitorsToday = int.tryParse(responses[3].data['data']['visitorsToday']?.toString() ?? '0') ?? 0;
      }

      final conversionRate = visitorsToday == 0 ? 0.0 : (ordersToday / visitorsToday) * 100;

      final stats = StoreStats(
        todayRevenue: todayRevenue.toStringAsFixed(2),
        monthlyRevenue: monthlyRevenue.toStringAsFixed(2),
        yearlyRevenue: yearlyRevenue.toStringAsFixed(2),
        ordersToday: ordersToday,
        itemsSold: itemsSold,
        visitorsToday: visitorsToday,
        conversionRate: conversionRate,
      );

      // Persist for optimistic UI
      await _storage.write(
        key: 'optimistic_stats',
        value: jsonEncode({
          'todayRevenue': stats.todayRevenue,
          'monthlyRevenue': stats.monthlyRevenue,
          'yearlyRevenue': stats.yearlyRevenue,
          'ordersToday': stats.ordersToday,
          'itemsSold': stats.itemsSold,
          'visitorsToday': stats.visitorsToday,
          'conversionRate': stats.conversionRate,
        }),
      );

      return stats;

    } catch (e) {
      throw Exception('Failed to fetch live stats: $e');
    }
  }

  Future<List<TopProduct>> fetchTopSellingProducts() async {
    try {
      final now = DateTime.now();
      final thirtyDaysAgo = now.subtract(const Duration(days: 30));
      final String minDateStr = "${thirtyDaysAgo.year}-${thirtyDaysAgo.month.toString().padLeft(2, '0')}-${thirtyDaysAgo.day.toString().padLeft(2, '0')}T00:00:00";

      // 1. Fetch live orders from the last 30 days (up to 100 recent) to bypass report caches
      final ordersRes = await _dio.get('/wp-json/wc/v3/orders', queryParameters: {
        'after': minDateStr,
        'per_page': 100,
      });

      if (ordersRes.data == null || ordersRes.data is! List || (ordersRes.data as List).isEmpty) {
        return [];
      }

      final orders = ordersRes.data as List;
      final Map<int, int> productSales = {};

      for (var order in orders) {
        final status = order['status']?.toString() ?? '';
        // Include pending so test orders immediately show up for users
        if (!['cancelled', 'failed', 'refunded', 'trash'].contains(status)) {
          if (order['line_items'] != null && order['line_items'] is List) {
            for (var item in (order['line_items'] as List)) {
              final productId = int.tryParse(item['product_id']?.toString() ?? '0') ?? 0;
              final qty = int.tryParse(item['quantity']?.toString() ?? '0') ?? 0;
              if (productId > 0 && qty > 0) {
                productSales[productId] = (productSales[productId] ?? 0) + qty;
              }
            }
          }
        }
      }

      if (productSales.isEmpty) return [];

      // Sort products by sales and take top 5
      final sortedEntries = productSales.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final topEntries = sortedEntries.take(5).toList();
      final productIds = topEntries.map((e) => e.key).toList();

      // 2. Fetch Full Product Details for those IDs
      final productsRes = await _dio.get('/wp-json/wc/v3/products', queryParameters: {
        'include': productIds.join(','),
        'per_page': productIds.length,
      });

      if (productsRes.data == null || productsRes.data is! List) {
        return [];
      }

      final productsData = productsRes.data as List;
      final List<TopProduct> topProducts = [];

      for (var product in productsData) {
        final id = product['id'] as int;
        final name = product['name']?.toString() ?? 'Unknown Product';
        final price = product['price']?.toString() ?? '0.00';
        
        String imageUrl = '';
        if (product['images'] != null && (product['images'] as List).isNotEmpty) {
          imageUrl = product['images'][0]['src']?.toString() ?? '';
        }

        topProducts.add(TopProduct(
          id: id,
          name: name,
          price: price,
          imageUrl: imageUrl,
          quantitySold: productSales[id] ?? 0,
        ));
      }

      // Sort by quantity sold just in case the /products endpoint returned them out of order
      topProducts.sort((a, b) => b.quantitySold.compareTo(a.quantitySold));

      return topProducts;
    } catch (e) {
      print('Error fetching top products: $e');
      return [];
    }
  }
}
