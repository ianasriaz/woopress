import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:woo_press/features/dashboard/presentation/providers/dashboard_controller.dart';
import '../../data/orders_repository.dart';
import '../../domain/models/order_model.dart';

class OrdersState {
  final List<OrderModel> orders;
  final bool hasMore;
  final int page;
  final bool isLoadingMore;
  final String? search;
  final String? status;
  final Set<int> updatingOrderIds;

  OrdersState({
    required this.orders,
    required this.hasMore,
    required this.page,
    this.isLoadingMore = false,
    this.search,
    this.status = 'all',
    this.updatingOrderIds = const {},
  });

  OrdersState copyWith({
    List<OrderModel>? orders,
    bool? hasMore,
    int? page,
    bool? isLoadingMore,
    String? search,
    String? status,
    Set<int>? updatingOrderIds,
  }) {
    return OrdersState(
      orders: orders ?? this.orders,
      hasMore: hasMore ?? this.hasMore,
      page: page ?? this.page,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      search: search ?? this.search,
      status: status ?? this.status,
      updatingOrderIds: updatingOrderIds ?? this.updatingOrderIds,
    );
  }
}

class OrdersController extends AsyncNotifier<OrdersState> {
  Timer? _searchTimer;

  @override
  Future<OrdersState> build() async {
    final repo = ref.watch(ordersRepositoryProvider);
    final initialOrders = await repo.fetchOrders(page: 1);
    return OrdersState(
      orders: initialOrders,
      page: 1,
      hasMore: initialOrders.length == 20,
    );
  }

  Future<void> onSearch(String query) async {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 500), () async {
      final current = state.value;
      state = const AsyncValue.loading();
      final repo = ref.read(ordersRepositoryProvider);

      try {
        final products = await repo.fetchOrders(page: 1, search: query, status: current?.status);
        state = AsyncValue.data(OrdersState(
          orders: products,
          page: 1,
          hasMore: products.length == 20,
          search: query,
          status: current?.status,
        ));
      } catch (e) {
        state = AsyncValue.error(e, StackTrace.current);
      }
    });
  }

  Future<void> onFilter(String status) async {
    final current = state.value;
    state = const AsyncValue.loading();
    final repo = ref.read(ordersRepositoryProvider);

    try {
      final products = await repo.fetchOrders(page: 1, search: current?.search, status: status);
      state = AsyncValue.data(OrdersState(
        orders: products,
        page: 1,
        hasMore: products.length == 20,
        search: current?.search,
        status: status,
      ));
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || !state.hasValue) return;
    
    final current = state.value!;
    if (!current.hasMore || current.isLoadingMore) return;

    state = AsyncValue.data(current.copyWith(isLoadingMore: true));

    final repo = ref.read(ordersRepositoryProvider);
    final nextPage = current.page + 1;

    try {
      final newOrders = await repo.fetchOrders(page: nextPage, search: current.search, status: current.status);
      state = AsyncValue.data(current.copyWith(
        orders: [...current.orders, ...newOrders],
        page: nextPage,
        hasMore: newOrders.length == 20,
        isLoadingMore: false,
      ));
    } catch (e) {
      state = AsyncValue.data(current.copyWith(isLoadingMore: false));
    }
  }

  Future<void> updateStatus(int orderId, String status, {String? trackingNumber, String? trackingCourier}) async {
    final current = state.value;
    if (current == null) return;

    // Start Updating State
    final newUpdating = Set<int>.from(current.updatingOrderIds)..add(orderId);
    state = AsyncValue.data(current.copyWith(updatingOrderIds: newUpdating));

    try {
      final repo = ref.read(ordersRepositoryProvider);
      await repo.updateOrderStatus(orderId, status, trackingNumber: trackingNumber, trackingCourier: trackingCourier);
      
      // Auto-refresh dashboard after status change to update sales stats instantly
      ref.read(dashboardControllerProvider.notifier).refresh();
      
      // Slight delay for server sync stability
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Remove from updating and trigger refresh for final state sync
      final finalCurrent = state.value ?? current;
      final finalUpdating = Set<int>.from(finalCurrent.updatingOrderIds)..remove(orderId);
      state = AsyncValue.data(finalCurrent.copyWith(updatingOrderIds: finalUpdating));
      
      // Actually refresh the list to get fresh server data
      await refresh();
    } catch (e) {
      // Remove from updating and revert
      final finalCurrent = state.value ?? current;
      final finalUpdating = Set<int>.from(finalCurrent.updatingOrderIds)..remove(orderId);
      state = AsyncValue.data(finalCurrent.copyWith(updatingOrderIds: finalUpdating));
      ref.invalidateSelf();
    }
  }

  Future<void> refresh() async {
    final current = state.value;
    state = await AsyncValue.guard(() async {
      final repo = ref.read(ordersRepositoryProvider);
      final freshOrders = await repo.fetchOrders(page: 1, search: current?.search, status: current?.status);
      return OrdersState(
        orders: freshOrders,
        page: 1,
        hasMore: freshOrders.length == 20,
        search: current?.search,
        status: current?.status,
      );
    });
  }
}

final ordersControllerProvider = AsyncNotifierProvider<OrdersController, OrdersState>(() {
  return OrdersController();
});
