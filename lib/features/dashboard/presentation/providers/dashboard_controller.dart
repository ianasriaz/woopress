import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/dashboard_repository.dart';
import '../../domain/models/store_stats.dart';
import '../../domain/models/top_product.dart';

class DashboardController extends AsyncNotifier<StoreStats> {
  Timer? _refreshTimer;

  @override
  Future<StoreStats> build() async {
    final repo = ref.watch(dashboardRepositoryProvider);
    
    // Set up a periodic background sync (every 5 minutes) as a fail-safe
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      refresh();
    });

    ref.onDispose(() {
      _refreshTimer?.cancel();
    });

    return repo.fetchStoreStats();
  }

  Future<void> refresh() async {
    // We update the state with fresh data using forceRefresh logic
    state = await AsyncValue.guard(() async {
      final repo = ref.read(dashboardRepositoryProvider);
      return repo.fetchStoreStats(forceRefresh: true);
    });
  }
}

final dashboardControllerProvider = AsyncNotifierProvider<DashboardController, StoreStats>(() {
  return DashboardController();
});

final topProductsCurrentMonthProvider = FutureProvider<List<TopProduct>>((ref) async {
  final repo = ref.watch(dashboardRepositoryProvider);
  return repo.fetchTopSellingProducts('month');
});

final topProductsLastMonthProvider = FutureProvider<List<TopProduct>>((ref) async {
  final repo = ref.watch(dashboardRepositoryProvider);
  return repo.fetchTopSellingProducts('last_month');
});
