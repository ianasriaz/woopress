class OrderModel {
  final int id;
  final String status;
  final String total;
  final String currency;
  final String dateCreated;
  final String customerNote;
  final String paymentMethodTitle;
  final String orderSource;
  final BillingAddress billing;
  final ShippingAddress shipping;
  final List<OrderItem> items;

  OrderModel({
    required this.id,
    required this.status,
    required this.total,
    required this.currency,
    required this.dateCreated,
    required this.customerNote,
    required this.paymentMethodTitle,
    required this.orderSource,
    required this.billing,
    required this.shipping,
    required this.items,
  });

  OrderModel copyWith({
    int? id,
    String? status,
    String? total,
    String? currency,
    String? dateCreated,
    String? customerNote,
    String? paymentMethodTitle,
    String? orderSource,
    BillingAddress? billing,
    ShippingAddress? shipping,
    List<OrderItem>? items,
  }) {
    return OrderModel(
      id: id ?? this.id,
      status: status ?? this.status,
      total: total ?? this.total,
      currency: currency ?? this.currency,
      dateCreated: dateCreated ?? this.dateCreated,
      customerNote: customerNote ?? this.customerNote,
      paymentMethodTitle: paymentMethodTitle ?? this.paymentMethodTitle,
      orderSource: orderSource ?? this.orderSource,
      billing: billing ?? this.billing,
      shipping: shipping ?? this.shipping,
      items: items ?? this.items,
    );
  }

  String get customerName => "${billing.firstName} ${billing.lastName}";

  String get displayAddress {
    if (shipping.fullAddress.isNotEmpty) return shipping.fullAddress;
    return billing.fullAddress;
  }

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    String parsedSource = 'Unknown';
    if (json['meta_data'] != null && json['meta_data'] is List) {
      String? origin;
      String? utmSource;
      String? sourceType;
      String? referrer;

      for (var meta in json['meta_data']) {
        final key = meta['key']?.toString().toLowerCase() ?? '';
        final value = meta['value']?.toString() ?? '';
        if (value.isEmpty) continue;

        if (key == '_wc_order_attribution_origin') {
          origin = value;
        } else if (key == 'utm_source' || key.endsWith('_utm_source') || key == 'source') {
          utmSource = value;
        } else if (key.endsWith('source_type') || key.endsWith('traffic_source')) {
          sourceType = value;
        } else if (key == 'referrer' || key == 'http_referer' || key.contains('_referrer') || key.endsWith('_ref')) {
          referrer = value.toLowerCase();
        }
      }

      if (origin != null && origin.isNotEmpty) {
        parsedSource = origin;
      } else if (utmSource != null && utmSource.isNotEmpty && utmSource.toLowerCase() != '(direct)') {
        String lower = utmSource.toLowerCase();
        if (lower == 'ig' || lower == 'instagram') parsedSource = 'Instagram';
        else if (lower == 'fb' || lower == 'facebook') parsedSource = 'Facebook';
        else if (lower == 'google') parsedSource = 'Google';
        else if (lower == 'tiktok') parsedSource = 'TikTok';
        else if (lower == 'youtube') parsedSource = 'YouTube';
        else parsedSource = utmSource;
      } else if (sourceType == 'typein' || sourceType == 'direct' || sourceType == 'admin') {
        parsedSource = sourceType == 'admin' ? 'Admin' : 'Direct';
      } else if (referrer != null && referrer.isNotEmpty) {
        if (referrer.contains('google.')) {
          parsedSource = 'Google';
        } else if (referrer.contains('facebook.com') || referrer.contains('fb.com') || referrer.contains('fb.me')) {
          parsedSource = 'Facebook';
        } else if (referrer.contains('instagram.com')) {
          parsedSource = 'Instagram';
        } else if (referrer.contains('tiktok.com')) {
          parsedSource = 'TikTok';
        } else if (referrer.contains('youtube.com') || referrer.contains('youtu.be')) {
          parsedSource = 'YouTube';
        } else if (referrer.contains('pinterest.com')) {
          parsedSource = 'Pinterest';
        } else if (referrer.contains('bing.com')) {
          parsedSource = 'Bing';
        } else if (referrer.contains('yahoo.com')) {
          parsedSource = 'Yahoo';
        } else {
          try {
            Uri uri = Uri.parse(referrer);
            String host = uri.host;
            if (host.startsWith('www.')) host = host.substring(4);
            if (host.isNotEmpty) {
              List<String> parts = host.split('.');
              if (parts.isNotEmpty) {
                parsedSource = parts[0];
              }
            }
          } catch (_) {
            parsedSource = sourceType == 'organic' ? 'Organic' : 'Referral';
          }
        }
      } else if (sourceType != null && sourceType.isNotEmpty) {
        if (sourceType == 'organic') {
          parsedSource = 'Organic';
        } else if (sourceType == 'referral') {
          parsedSource = 'Referral';
        } else {
          parsedSource = sourceType;
        }
      }
    }

    // Capitalize first letter for display
    if (parsedSource.isNotEmpty && parsedSource != 'Unknown') {
      parsedSource = parsedSource[0].toUpperCase() + parsedSource.substring(1);
    } else {
      parsedSource = 'Unknown';
    }

    return OrderModel(
      id: json['id'],
      status: json['status'] ?? 'pending',
      total: json['total'] ?? '0.00',
      currency: json['currency'] ?? 'RS',
      dateCreated: json['date_created'] ?? '',
      customerNote: json['customer_note'] ?? '',
      paymentMethodTitle: (json['payment_method_title'] != null && json['payment_method_title'].toString().isNotEmpty)
          ? json['payment_method_title']
          : (json['payment_method']?.toString().toUpperCase() ?? 'N/A'),
      orderSource: parsedSource,
      billing: BillingAddress.fromJson(json['billing'] ?? {}),
      shipping: ShippingAddress.fromJson(json['shipping'] ?? {}),
      items: (json['line_items'] as List)
          .map((i) => OrderItem.fromJson(i))
          .toList(),
    );
  }
}

class OrderItem {
  final int id;
  final String name;
  final int quantity;
  final String total;
  final int productId;
  final int variationId;
  final String sku;
  final List<dynamic> metaData;
  String? image;

  OrderItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.total,
    required this.productId,
    required this.variationId,
    required this.sku,
    required this.metaData,
    this.image,
  });

  String get variationInfo {
    if (metaData.isEmpty) return "";
    return metaData
        .where((m) => !m['key'].toString().startsWith('_'))
        .map((m) => "${m['display_key']}: ${m['display_value']}")
        .join(" | ");
  }

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      id: json['id'],
      name: json['name'] ?? '',
      quantity: json['quantity'] ?? 0,
      total: json['total'] ?? '0.00',
      productId: json['product_id'] ?? 0,
      variationId: json['variation_id'] ?? 0,
      sku: json['sku'] ?? '',
      metaData: json['meta_data'] ?? [],
      image: json['image'] is Map ? json['image']['src'] : (json['image_url'] ?? json['product_image']), 
    );
  }
}

class BillingAddress {
  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  final String address1;
  final String address2;
  final String city;
  final String state;
  final String postcode;
  final String country;

  BillingAddress({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.address1,
    required this.address2,
    required this.city,
    required this.state,
    required this.postcode,
    required this.country,
  });

  String get fullAddress {
    if (address1.isEmpty && city.isEmpty) return "";
    List<String> parts = [];
    if (address1.isNotEmpty) parts.add(address1);
    if (address2.isNotEmpty) parts.add(address2);
    if (city.isNotEmpty) parts.add(city);
    if (state.isNotEmpty) parts.add(state);
    if (postcode.isNotEmpty) parts.add(postcode);
    return parts.join(", ");
  }

  factory BillingAddress.fromJson(Map<String, dynamic> json) {
    return BillingAddress(
      firstName: json['first_name'] ?? '',
      lastName: json['last_name'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'] ?? '',
      address1: json['address_1'] ?? '',
      address2: json['address_2'] ?? '',
      city: json['city'] ?? '',
      state: json['state'] ?? '',
      postcode: json['postcode'] ?? '',
      country: json['country'] ?? '',
    );
  }
}

class ShippingAddress {
  final String firstName;
  final String lastName;
  final String address1;
  final String address2;
  final String city;
  final String state;
  final String postcode;
  final String country;

  ShippingAddress({
    required this.firstName,
    required this.lastName,
    required this.address1,
    required this.address2,
    required this.city,
    required this.state,
    required this.postcode,
    required this.country,
  });

  String get fullAddress {
    if (address1.isEmpty && city.isEmpty) return "";
    List<String> parts = [];
    if (address1.isNotEmpty) parts.add(address1);
    if (address2.isNotEmpty) parts.add(address2);
    if (city.isNotEmpty) parts.add(city);
    if (state.isNotEmpty) parts.add(state);
    if (postcode.isNotEmpty) parts.add(postcode);
    return parts.join(", ");
  }

  factory ShippingAddress.fromJson(Map<String, dynamic> json) {
    return ShippingAddress(
      firstName: json['first_name'] ?? '',
      lastName: json['last_name'] ?? '',
      address1: json['address_1'] ?? '',
      address2: json['address_2'] ?? '',
      city: json['city'] ?? '',
      state: json['state'] ?? '',
      postcode: json['postcode'] ?? '',
      country: json['country'] ?? '',
    );
  }
}
