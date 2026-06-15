import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:image/image.dart' as img_lib;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../../../core/network/dio_config.dart';
import '../domain/models/product_model.dart';

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  final storage = ref.watch(secureStorageProvider);
  return InventoryRepository(DioConfig.createDio(storage), storage);
});

class InventoryRepository {
  final Dio _dio;
  final FlutterSecureStorage _storage;

  InventoryRepository(this._dio, this._storage);

  Future<List<ProductModel>> fetchProducts({int page = 1, String? search, String? stockStatus}) async {
    final params = {
      'page': page,
      'per_page': 20,
      'status': 'publish',
      '_fields': 'id,name,type,price,regular_price,sale_price,on_sale,stock_quantity,stock_status,manage_stock,date_created,total_sales,images',
    };
    if (search != null && search.isNotEmpty) params['search'] = search;
    if (stockStatus != null && stockStatus != 'all') params['stock_status'] = stockStatus;

    final response = await _dio.get('/wp-json/wc/v3/products', queryParameters: params);

    if (response.statusCode == 200) {
      final List data = response.data;
      return data.map((json) => ProductModel.fromJson(json)).toList();
    }
    throw Exception('Failed to fetch products');
  }

  Future<List<VariationModel>> fetchVariations(int productId) async {
    final response = await _dio.get(
      '/wp-json/wc/v3/products/$productId/variations',
      queryParameters: {'_fields': 'id,price,regular_price,sale_price,stock_quantity,stock_status,manage_stock,total_sales,attributes'},
    );

    if (response.statusCode == 200) {
      final List data = response.data;
      return data.map((json) => VariationModel.fromJson(json)).toList();
    }
    throw Exception('Failed to fetch variations');
  }

  Future<void> updateProduct(int id, Map<String, dynamic> data) async {
    final response = await _dio.put('/wp-json/wc/v3/products/$id', data: data);
    if (response.statusCode != 200) {
      throw Exception('Failed to update product');
    }
  }

  Future<void> updateVariation(int productId, int variationId, Map<String, dynamic> data) async {
    final response = await _dio.put('/wp-json/wc/v3/products/$productId/variations/$variationId', data: data);
    if (response.statusCode != 200) {
      throw Exception('Failed to update variation');
    }
  }

  Future<String?> getProductThumbnail(int productId, {int? variationId}) async {
    try {
      final endpoint = variationId != null && variationId > 0
          ? '/wp-json/wc/v3/products/$productId/variations/$variationId'
          : '/wp-json/wc/v3/products/$productId';
      
      final response = await _dio.get(endpoint, queryParameters: {'_fields': 'images'});
      
      if (response.statusCode == 200) {
        final images = response.data['images'] as List?;
        if (images != null && images.isNotEmpty) {
          return images.first['src'] as String?;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<List<Map<String, dynamic>>> fetchCategories() async {
    final response = await _dio.get('/wp-json/wc/v3/products/categories', queryParameters: {'per_page': 100});
    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(response.data);
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> fetchGlobalAttributes() async {
    final response = await _dio.get('/wp-json/wc/v3/products/attributes');
    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(response.data);
    }
    return [];
  }

  Future<List<String>> fetchAttributeTerms(int attributeId) async {
    final response = await _dio.get('/wp-json/wc/v3/products/attributes/$attributeId/terms', queryParameters: {'per_page': 100});
    if (response.statusCode == 200) {
      final List data = response.data;
      return data.map((t) => t['name'].toString()).toList();
    }
    return [];
  }

  Future<Uint8List> _processImageForUpload(Uint8List originalBytes) async {
    try {
      // Decode the image
      img_lib.Image? image = img_lib.decodeImage(originalBytes);
      if (image == null) return originalBytes;

      // Smart Resize: Max 1600px width or height
      if (image.width > 1600 || image.height > 1600) {
        if (image.width > image.height) {
          image = img_lib.copyResize(image, width: 1600);
        } else {
          image = img_lib.copyResize(image, height: 1600);
        }
      }

      // Encode to JPEG (Quality 80) - Guaranteed to compile and work globally
      return Uint8List.fromList(img_lib.encodeJpg(image, quality: 80));
    } catch (e) {
      // If optimization fails, fallback to original bytes
      return originalBytes;
    }
  }

  Future<int> uploadImage(Uint8List bytes, String fileName) async {
    
    // Step 1: Optimize and Convert to WebP
    final optimizedBytes = await _processImageForUpload(bytes);
    
    // Step 2: Ensure filename is .jpg (matching our optimized encoder)
    String finalFileName = fileName;
    if (finalFileName.contains('.')) {
      finalFileName = '${finalFileName.split('.').first}_optimized.jpg';
    } else {
      finalFileName = '${finalFileName}_optimized.jpg';
    }
    
    const contentType = 'image/jpeg';

    try {
      final response = await _dio.post(
        '/wp-json/wp/v2/media',
        data: Stream.fromIterable([optimizedBytes]), 
        queryParameters: {
          'status': 'publish',
          'title': finalFileName,
        },
        options: Options(
          headers: {
            'Content-Type': contentType,
            'Content-Disposition': 'attachment; filename="$finalFileName"',
          },
        ),
      );
      
      if (response.statusCode == 201) {
        return response.data['id'];
      }
      
      // Detailed error from server if available
      final serverMsg = response.data is Map ? response.data['message'] : 'Status ${response.statusCode}';
      throw Exception('Upload Failed: $serverMsg');
    } on DioException catch (e) {
      final msg = e.response?.data is Map ? e.response?.data['message'] : e.message;
      throw Exception('Server Error: $msg');
    }
  }

  String _getContentType(String fileName) {
    final path = fileName.toLowerCase();
    if (path.endsWith('.png')) return 'image/png';
    if (path.endsWith('.gif')) return 'image/gif';
    if (path.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<int> createProduct(Map<String, dynamic> data) async {
    final response = await _dio.post(
      '/wp-json/wc/v3/products',
      data: data,
    );

    if (response.statusCode == 201) {
      return response.data['id'];
    }
    throw Exception('Failed to create product');
  }

  Future<void> createVariation(int productId, Map<String, dynamic> data) async {
    await _dio.post(
      '/wp-json/wc/v3/products/$productId/variations',
      data: data,
    );
  }
}
