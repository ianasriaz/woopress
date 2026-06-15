class ProductModel {
  final int id;
  final String name;
  final String type; // 'simple' or 'variable'
  final String price;
  final String regularPrice;
  final String salePrice;
  final int? stockQuantity;
  final String stockStatus; // 'instock', 'outofstock'
  final bool manageStock;
  final DateTime dateCreated;
  final int totalSales;
  final bool onSale;
  final String? imageUrl;

  ProductModel({
    required this.id,
    required this.name,
    required this.type,
    required this.price,
    required this.regularPrice,
    required this.salePrice,
    this.stockQuantity,
    required this.stockStatus,
    required this.manageStock,
    required this.dateCreated,
    required this.totalSales,
    required this.onSale,
    this.imageUrl,
  });

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    return ProductModel(
      id: json['id'],
      name: json['name'] ?? '',
      type: json['type'] ?? 'simple',
      price: json['price']?.toString() ?? '0',
      regularPrice: json['regular_price']?.toString() ?? '0',
      salePrice: json['sale_price']?.toString() ?? '',
      stockQuantity: json['stock_quantity'] as int?,
      stockStatus: json['stock_status'] ?? 'outofstock',
      manageStock: json['manage_stock'] == true || json['manage_stock']?.toString() == 'yes',
      dateCreated: DateTime.tryParse(json['date_created']?.toString() ?? '') ?? DateTime.now(),
      totalSales: int.tryParse(json['total_sales']?.toString() ?? '0') ?? 0,
      onSale: json['on_sale'] == true,
      imageUrl: (json['images'] != null && (json['images'] as List).isNotEmpty)
          ? json['images'][0]['src']
          : null,
    );
  }

  ProductModel copyWith({
    String? price,
    String? regularPrice,
    String? salePrice,
    int? stockQuantity,
    String? stockStatus,
    bool? manageStock,
    bool? onSale,
  }) {
    return ProductModel(
      id: id,
      name: name,
      type: type,
      price: price ?? this.price,
      regularPrice: regularPrice ?? this.regularPrice,
      salePrice: salePrice ?? this.salePrice,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      stockStatus: stockStatus ?? this.stockStatus,
      manageStock: manageStock ?? this.manageStock,
      dateCreated: this.dateCreated,
      totalSales: this.totalSales,
      onSale: onSale ?? this.onSale,
      imageUrl: imageUrl,
    );
  }
}

class VariationModel {
  final int id;
  final String price;
  final String regularPrice;
  final String salePrice;
  final int? stockQuantity;
  final String stockStatus;
  final bool manageStock;
  final int totalSales;
  final List<String> attributes;

  VariationModel({
    required this.id,
    required this.price,
    required this.regularPrice,
    required this.salePrice,
    this.stockQuantity,
    required this.stockStatus,
    required this.manageStock,
    required this.totalSales,
    required this.attributes,
  });

  factory VariationModel.fromJson(Map<String, dynamic> json) {
    final attrs = (json['attributes'] as List?)?.map((a) => a['option'].toString()).toList() ?? [];
    return VariationModel(
      id: json['id'],
      price: json['price']?.toString() ?? '0',
      regularPrice: json['regular_price']?.toString() ?? '0',
      salePrice: json['sale_price']?.toString() ?? '',
      stockQuantity: json['stock_quantity'] as int?,
      stockStatus: json['stock_status'] ?? 'outofstock',
      manageStock: json['manage_stock'] == true || json['manage_stock']?.toString() == 'yes',
      totalSales: int.tryParse(json['total_sales']?.toString() ?? '0') ?? 0,
      attributes: attrs,
    );
  }
}
