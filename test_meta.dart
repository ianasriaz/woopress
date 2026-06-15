import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() async {
  const storage = FlutterSecureStorage();
  final url = await storage.read(key: 'store_url');
  final consumerKey = await storage.read(key: 'consumer_key');
  final consumerSecret = await storage.read(key: 'consumer_secret');

  if (url == null || consumerKey == null || consumerSecret == null) {
    print('No credentials found.');
    return;
  }

  final dio = Dio();
  final basicAuth = 'Basic ' + base64Encode(utf8.encode('$consumerKey:$consumerSecret'));

  try {
    final response = await dio.get(
      '$url/wp-json/wc/v3/orders',
      queryParameters: {'per_page': 10},
      options: Options(headers: {'Authorization': basicAuth}),
    );

    final orders = response.data as List;
    for (var order in orders) {
      print('Order #${order['id']}');
      final metaData = order['meta_data'] as List?;
      if (metaData != null) {
        for (var meta in metaData) {
          final key = meta['key'].toString().toLowerCase();
          if (key.contains('source') || key.contains('utm') || key.contains('refer') || key.contains('origin')) {
            print('  - ${meta['key']}: ${meta['value']}');
          }
        }
      }
      print('---');
    }
  } catch (e) {
    print('Error: $e');
  }
}
