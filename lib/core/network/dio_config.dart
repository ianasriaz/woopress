import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthInterceptor extends Interceptor {
  final FlutterSecureStorage storage;
  String? _authHeader;
  String? _baseUrl;
  String? _cfId;
  String? _cfSecret;
  bool _isInitialized = false;

  AuthInterceptor(this.storage);

  Future<void> _init() async {
    if (_isInitialized) return;
    final key = await storage.read(key: 'wc_consumer_key');
    final secret = await storage.read(key: 'wc_consumer_secret');
    final domain = await storage.read(key: 'store_domain');
    _cfId = await storage.read(key: 'cf_client_id');
    _cfSecret = await storage.read(key: 'cf_client_secret');
    
    if (key != null && secret != null) {
      _authHeader = 'Basic ${base64Encode(utf8.encode('$key:$secret'))}';
    }
    if (domain != null) {
      String sanitizedDomain = domain.toLowerCase().trim();
      sanitizedDomain = sanitizedDomain.replaceAll('https://', '').replaceAll('http://', '');
      if (sanitizedDomain.endsWith('/')) sanitizedDomain = sanitizedDomain.substring(0, sanitizedDomain.length - 1);
      _baseUrl = 'https://$sanitizedDomain';
    }
    _isInitialized = true;
  }

  void clearCache() {
    _isInitialized = false;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    await _init();
    
    if (_baseUrl != null && (options.baseUrl.isEmpty || options.baseUrl == '')) {
      options.baseUrl = _baseUrl!;
    }
    
    if (_authHeader != null) {
      options.headers['Authorization'] = _authHeader;
    }
    options.headers['Accept'] = 'application/json';
    options.headers['Connection'] = 'keep-alive';
    
    if (_cfId != null && _cfSecret != null) {
      options.headers['CF-Access-Client-Id'] = _cfId;
      options.headers['CF-Access-Client-Secret'] = _cfSecret;
    }
    
    super.onRequest(options, handler);
  }
}

class DioConfig {
  static Dio createDio(FlutterSecureStorage storage) {
    final dio = Dio();
    
    dio.options.connectTimeout = const Duration(seconds: 15);
    dio.options.receiveTimeout = const Duration(seconds: 15);
    dio.options.validateStatus = (status) => status != null && status < 500;
    
    dio.interceptors.add(AuthInterceptor(storage));
    
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (kDebugMode) {
          print('🌐 API REQUEST[${options.method}] => PATH: ${options.path}');
        }
        return handler.next(options);
      },
      onResponse: (response, handler) {
        if (kDebugMode) {
          print('✅ API RESPONSE[${response.statusCode}] => PATH: ${response.requestOptions.path}');
        }
        return handler.next(response);
      },
      onError: (DioException e, handler) async {
        if (kDebugMode) {
          print('❌ API ERROR[${e.response?.statusCode}] => PATH: ${e.requestOptions.path}');
        }
        return handler.next(e);
      },
    ));
    
    return dio;
  }
}
