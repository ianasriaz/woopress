import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/inventory_repository.dart';
import '../../domain/models/product_model.dart';

class InventoryState {
  final List<ProductModel> products;
  final int page;
  final bool hasMore;
  final String? search;
  final String? stockStatus;

  InventoryState({
    required this.products,
    required this.page,
    required this.hasMore,
    this.search,
    this.stockStatus = 'all',
  });

  InventoryState copyWith({
    List<ProductModel>? products,
    int? page,
    bool? hasMore,
    String? search,
    String? stockStatus,
  }) {
    return InventoryState(
      products: products ?? this.products,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      search: search ?? this.search,
      stockStatus: stockStatus ?? this.stockStatus,
    );
  }
}

class InventoryController extends AsyncNotifier<InventoryState> {
  Timer? _searchTimer;
  @override
  Future<InventoryState> build() async {
    final repo = ref.watch(inventoryRepositoryProvider);
    final initialProducts = await repo.fetchProducts(page: 1);
    return InventoryState(
      products: initialProducts,
      page: 1,
      hasMore: initialProducts.length == 20,
    );
  }

  Future<void> loadMore() async {
    if (state.isLoading || state.hasError) return;
    
    final currentState = state.value;
    if (currentState == null || !currentState.hasMore) return;

    final repo = ref.read(inventoryRepositoryProvider);
    final nextPage = currentState.page + 1;

    try {
      final newProducts = await repo.fetchProducts(
        page: nextPage,
        search: currentState.search,
        stockStatus: currentState.stockStatus,
      );
      state = AsyncValue.data(
        currentState.copyWith(
          products: [...currentState.products, ...newProducts],
          page: nextPage,
          hasMore: newProducts.length == 20,
        ),
      );
    } catch (e) {
      // Fail silently to preserve list
    }
  }

  Future<void> onSearch(String query) async {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 500), () async {
      final currentState = state.value;
      if (currentState == null) return;

      state = const AsyncValue.loading();
      final repo = ref.read(inventoryRepositoryProvider);

      try {
        final products = await repo.fetchProducts(page: 1, search: query, stockStatus: currentState.stockStatus);
        state = AsyncValue.data(InventoryState(
          products: products,
          page: 1,
          hasMore: products.length == 20,
          search: query,
          stockStatus: currentState.stockStatus,
        ));
      } catch (e) {
        state = AsyncValue.error(e, StackTrace.current);
      }
    });
  }

  Future<void> onFilter(String status) async {
    final currentState = state.value;
    if (currentState == null) return;

    state = const AsyncValue.loading();
    final repo = ref.read(inventoryRepositoryProvider);

    try {
      final products = await repo.fetchProducts(page: 1, search: currentState.search, stockStatus: status);
      state = AsyncValue.data(InventoryState(
        products: products,
        page: 1,
        hasMore: products.length == 20,
        search: currentState.search,
        stockStatus: status,
      ));
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }

  Future<void> updateSimpleProductOptimistic(int id, String newRegularPrice, String newSalePrice, {int? newStock, String? newStatus, required bool manageStock}) async {
    final currentState = state.value;
    if (currentState == null) return;

    final resolvedStatus = manageStock ? (newStock! > 0 ? 'instock' : 'outofstock') : newStatus!;
    final repo = ref.read(inventoryRepositoryProvider);

    // 1. Instant Optimistic UI
    final updatedProducts = currentState.products.map<ProductModel>((p) {
      if (p.id == id) {
        return p.copyWith(
          price: newSalePrice.isNotEmpty ? newSalePrice : newRegularPrice,
          regularPrice: newRegularPrice,
          salePrice: newSalePrice,
          stockQuantity: manageStock ? newStock : null,
          stockStatus: resolvedStatus,
          manageStock: manageStock,
        );
      }
      return p;
    }).toList();

    state = AsyncValue.data(currentState.copyWith(products: updatedProducts));

    try {
      // 2. Atomic Payload Construction
      final Map<String, dynamic> updateData = {
        'regular_price': newRegularPrice,
        'sale_price': newSalePrice,
        'manage_stock': manageStock,
        'stock_status': resolvedStatus,
      };
      
      if (manageStock) {
        updateData['stock_quantity'] = newStock;
      } else {
        updateData['stock_quantity'] = null; // Important: Clear quantity if not managing stock
      }

      // 3. Execution & Verification
      await repo.updateProduct(id, updateData);
      
      // 4. Instant Heartbeat Refresh
      await Future.delayed(const Duration(milliseconds: 300));
      await refresh(); 
    } catch (e) {
      ref.invalidateSelf();
      rethrow;
    }
  }

  Future<void> triggerVariationUpdate(int productId, int variationId, String newRegularPrice, String newSalePrice, {int? newStock, String? newStatus, required bool manageStock}) async {
    final resolvedStatus = manageStock ? (newStock! > 0 ? 'instock' : 'outofstock') : newStatus!;
    final repo = ref.read(inventoryRepositoryProvider);
    try {
      // Atomic Payload for Variations
      final Map<String, dynamic> updateData = {
        'regular_price': newRegularPrice,
        'sale_price': newSalePrice,
        'manage_stock': manageStock,
        'stock_status': resolvedStatus,
      };
      
      if (manageStock) {
        updateData['stock_quantity'] = newStock;
      } else {
        updateData['stock_quantity'] = null;
      }

      await repo.updateVariation(productId, variationId, updateData);
      
      await Future.delayed(const Duration(milliseconds: 300));
      // Invalidate the variations list for this specific product to clear the cache
      ref.invalidate(productVariationsProvider(productId));
      ref.invalidateSelf(); 
    } catch (e) {
      rethrow;
    }
  }

  Future<void> refresh() async {
    final currentState = state.value;
    state = await AsyncValue.guard(() async {
      final repo = ref.read(inventoryRepositoryProvider);
      final products = await repo.fetchProducts(
        page: 1, 
        search: currentState?.search, 
        stockStatus: currentState?.stockStatus
      );
      return (currentState ?? InventoryState(products: [], page: 1, hasMore: false)).copyWith(
        products: products,
        page: 1,
        hasMore: products.length == 20,
      );
    });
  }
}

final inventoryControllerProvider = AsyncNotifierProvider<InventoryController, InventoryState>(() {
  return InventoryController();
});

final productVariationsProvider = FutureProvider.family<List<VariationModel>, int>((ref, productId) async {
  final repo = ref.watch(inventoryRepositoryProvider);
  return repo.fetchVariations(productId);
});
