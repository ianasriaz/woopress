import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../../gatekeeper/presentation/screens/gatekeeper_screen.dart';
import '../providers/dashboard_controller.dart';
import '../widgets/top_products_widget.dart';
import '../../../inventory/presentation/providers/inventory_controller.dart';
import '../../domain/models/store_stats.dart';
import '../../../inventory/presentation/screens/inventory_screen.dart';
import '../../../orders/presentation/screens/orders_screen.dart' as import_orders;
import '../../../../core/widgets/global_error_view.dart';
import '../../../notifications/data/fcm_service.dart';
import '../../../notifications/presentation/screens/notifications_screen.dart';
import '../../../notifications/presentation/providers/notifications_controller.dart';
import '../../../orders/presentation/providers/orders_controller.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> with WidgetsBindingObserver {
  StoreStats _optimisticStats = StoreStats(
    todayRevenue: "0.00",
    monthlyRevenue: "0.00",
    yearlyRevenue: "0.00",
    ordersToday: 0,
    itemsSold: 0,
    visitorsToday: 0,
    conversionRate: 0.0,
  );
  String? _storeName;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadOptimisticData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAndHealNotifications();
      // Auto-Sync Data silently in the background
      ref.read(dashboardControllerProvider.notifier).refresh();
      ref.read(ordersControllerProvider.notifier).refresh();
      ref.read(notificationsControllerProvider.notifier).refresh();
      ref.read(inventoryControllerProvider.notifier).refresh();
    }
  }

  Future<void> _checkAndHealNotifications() async {
    final storage = ref.read(secureStorageProvider);
    final topic = await storage.read(key: 'last_fcm_topic');
    if (topic == null || topic.startsWith('ERROR')) {
      debugPrint("Auto-Healing: FCM Topic state is $topic. Triggering silent re-sync...");
      await ref.read(fcmServiceProvider).reSyncNotifications();
      if (mounted) setState(() {}); // Trigger a rebuild to update the info dialog if open
    }
  }

  Future<void> _loadOptimisticData() async {
    final storage = ref.read(secureStorageProvider);
    
    // First, try to get the name set during login
    final directName = await storage.read(key: 'store_name');
    if (directName != null && mounted) {
      setState(() => _storeName = directName);
    }

    final savedData = await storage.read(key: 'optimistic_stats');
    if (savedData != null && mounted) {
      try {
        final Map<String, dynamic> json = jsonDecode(savedData);
        setState(() {
          _storeName ??= json['storeName']; // Use cached name only if direct name is missing
          _optimisticStats = StoreStats(
            todayRevenue: json['todayRevenue'] ?? "0.00",
            monthlyRevenue: json['monthlyRevenue'] ?? "0.00",
            yearlyRevenue: json['yearlyRevenue'] ?? "0.00",
            ordersToday: json['ordersToday'] ?? 0,
            itemsSold: json['itemsSold'] ?? 0,
            visitorsToday: json['visitorsToday'] ?? 0,
            conversionRate: (json['conversionRate'] as num?)?.toDouble() ?? 0.0,
          );
        });
      } catch (_) {}
    }
  }

  void _showConnectionInfo() async {
    HapticFeedback.lightImpact();
    final storage = ref.read(secureStorageProvider);
    final baseUrl = await storage.read(key: 'baseUrl');
    final topic = await storage.read(key: 'last_fcm_topic');
    final token = await storage.read(key: 'fcm_token');

    // Live Tracker Verification
    bool trackerActive = false;
    try {
      final dio = Dio();
      final domain = await storage.read(key: 'store_domain');
      if (domain != null) {
        final res = await dio.get('https://$domain/wp-json/woopress/v1/stats').timeout(const Duration(seconds: 3));
        if (res.statusCode == 200) trackerActive = true;
      }
    } catch (_) {
      trackerActive = false;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text("CONNECTION DETAILS", style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w900, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow("STORE URL", baseUrl ?? "Not Found"),
            const SizedBox(height: 16),
            _buildInfoRow("TRACKER STATUS", trackerActive ? "Active (Genuine)" : "Not Found (Paste Script)"),
            const SizedBox(height: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("LIVE CHANNEL", style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3), fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.radio, size: 12, color: topic != null && !topic.startsWith("ERROR") ? const Color(0xFF00FF00) : Colors.redAccent),
                      const SizedBox(width: 8),
                      Text(
                        topic?.toUpperCase() ?? "NOT SUBSCRIBED",
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoRow("DEVICE TOKEN", (token != null) ? "Registered (Active)" : "Missing"),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: () async {
                HapticFeedback.heavyImpact();
                await ref.read(fcmServiceProvider).reSyncNotifications();
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Notification channel re-synced!"), backgroundColor: Color(0xFF34C759)),
                  );
                }
              },
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  color: Theme.of(context).colorScheme.surface,
                ),
                child: Center(
                  child: Text(
                    "RE-SYNC NOTIFICATIONS",
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF34C759).withOpacity(0.1),
                border: Border.all(color: const Color(0xFF34C759).withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.checkCircle, color: const Color(0xFF34C759), size: 16),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      "Your phone is currently synced with the WooPress Connector bridge.",
                      style: TextStyle(color: Color(0xFF34C759), fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("CLOSE", style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5), fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3), fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }

  void _logout() async {
    HapticFeedback.mediumImpact();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text("LOGOUT", style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w900)),
        content: Text("Are you sure you want to log out from this store?", style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text("CANCEL", style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5), fontWeight: FontWeight.w900)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("LOGOUT", style: TextStyle(color: Color(0xFFFF3B30), fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Show a loading dialog while clearing cache
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    try {
      // 1. Clear all key-value pairs in secure storage (Store URL, tokens, stats, etc.)
      final storage = ref.read(secureStorageProvider);
      await storage.deleteAll();

      // 2. Clear network image cache (CachedNetworkImage thumbnails/product photos)
      await DefaultCacheManager().emptyCache();

      // 3. Clear Flutter in-memory image cache
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      // 4. Reset Riverpod states to fresh defaults
      ref.invalidate(dashboardControllerProvider);
      ref.invalidate(ordersControllerProvider);
      ref.invalidate(inventoryControllerProvider);
      ref.invalidate(notificationsControllerProvider);
    } catch (e) {
      debugPrint("Error clearing cache: $e");
    }

    if (mounted) {
      // Pop the loading dialog
      Navigator.of(context).pop();
      
      // Navigate to Gatekeeper screen
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const GatekeeperScreen()),
        (route) => false,
      );
    }
  }

  bool _isRefreshing = false;

  Future<void> _handleManualRefresh() async {
    setState(() => _isRefreshing = true);
    HapticFeedback.mediumImpact();
    ref.invalidate(topProductsCurrentMonthProvider);
    ref.invalidate(topProductsLastMonthProvider);
    await ref.read(dashboardControllerProvider.notifier).refresh();
    if (mounted) setState(() => _isRefreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(dashboardControllerProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/app_screen_logo.png',
              height: 24,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 12),
            const Text(
              'WooPress',
              style: TextStyle(
                color: Color(0xFF000000),
                fontWeight: FontWeight.w900,
                fontSize: 20,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        centerTitle: false,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _isRefreshing 
              ? SizedBox(
                  width: 20, 
                  height: 20, 
                  child: Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary, strokeWidth: 2))
                )
              : IconButton(
                  icon: Icon(LucideIcons.refreshCw, color: Theme.of(context).colorScheme.onSurface, size: 20),
                  onPressed: _handleManualRefresh,
                ),
          ),
          IconButton(
            icon: Icon(LucideIcons.info, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2), size: 20),
            onPressed: _showConnectionInfo,
          ),
          IconButton(
            icon: Icon(LucideIcons.logOut, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2), size: 20),
            onPressed: _logout,
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          RefreshIndicator(
            color: Theme.of(context).colorScheme.primary,
            backgroundColor: Theme.of(context).colorScheme.surface,
            onRefresh: () async {
              HapticFeedback.mediumImpact();
              ref.invalidate(topProductsCurrentMonthProvider);
              ref.invalidate(topProductsLastMonthProvider);
              await ref.read(dashboardControllerProvider.notifier).refresh();
            },
            child: statsAsync.when(
              data: (stats) => _buildDashboardContent(stats, isLoading: false),
              loading: () => _buildDashboardContent(_optimisticStats, isLoading: true),
              error: (e, _) => GlobalErrorView(
                onRetry: () => ref.read(dashboardControllerProvider.notifier).refresh(),
              ),
            ),
          ),
          const import_orders.OrdersScreen(),
          const InventoryScreen(),
          const NotificationsScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Theme.of(context).dividerColor, width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (index) {
            HapticFeedback.lightImpact();
            setState(() => _selectedIndex = index);
          },
          backgroundColor: Theme.of(context).colorScheme.surface,
          selectedItemColor: Theme.of(context).colorScheme.primary,
          unselectedItemColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
          showSelectedLabels: true,
          showUnselectedLabels: true,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 0.5),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 10, letterSpacing: 0.5),
          type: BottomNavigationBarType.fixed,
          items: [
            const BottomNavigationBarItem(icon: Icon(LucideIcons.layoutDashboard, size: 22), label: 'STATS'),
            const BottomNavigationBarItem(icon: Icon(LucideIcons.shoppingBag, size: 22), label: 'ORDERS'),
            const BottomNavigationBarItem(icon: Icon(LucideIcons.package, size: 22), label: 'INVENTORY'),
            BottomNavigationBarItem(
              icon: _buildNotificationIcon(ref),
              label: 'ALERTS',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationIcon(WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsControllerProvider);
    final count = notificationsAsync.value?.where((n) => !n.isRead).length ?? 0;
    
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(LucideIcons.bell, size: 22),
        if (count > 0)
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
              child: Text(
                count > 9 ? '9+' : count.toString(),
                style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDashboardContent(StoreStats stats, {required bool isLoading}) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _storeName?.toUpperCase() ?? "MY STORE",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF34C759).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 4,
                                height: 4,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF34C759),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Text(
                                "LIVE",
                                style: TextStyle(
                                  color: Color(0xFF34C759),
                                  fontSize: 7,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          isLoading && stats.todayRevenue == "0.00"
            ? _buildSkeleton()
            : Column(
                children: [
                  _buildStatCard("TODAY SALES (${DateFormat('EEEE, d MMM').format(DateTime.now()).toUpperCase()})", "Rs. ${stats.todayRevenue}", LucideIcons.shoppingBag, isLarge: true),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          "SALE (${DateFormat('MMMM').format(DateTime.now()).toUpperCase()})", 
                          "Rs. ${stats.monthlyRevenue}", 
                          LucideIcons.calendar,
                          isSmall: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          "SALES (${DateTime.now().year})", 
                          "Rs. ${stats.yearlyRevenue}", 
                          LucideIcons.trendingUp,
                          isSmall: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  _buildSectionHeader("SALES OVERVIEW"),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _buildStatCard("Orders", stats.ordersToday.toString(), LucideIcons.shoppingCart, isSmall: true)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildStatCard("Items Sold", stats.itemsSold.toString(), LucideIcons.layers, isSmall: true)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildSectionHeader("VISITOR ANALYTICS"),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _buildStatCard("Unique Visitors", stats.visitorsToday.toString(), LucideIcons.users, isAccent: true, isSmall: true, showLive: true)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildStatCard("Conv. Rate", "${stats.conversionRate.toStringAsFixed(1)}%", LucideIcons.activity, isAccent: true, isSmall: true)),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
          const SizedBox(height: 16),
          // --- TOP PRODUCTS WIDGETS HERE ---
          TopProductsWidget(
            provider: topProductsCurrentMonthProvider,
            title: "Top 5 Sellers (This Month, ${_getMonthName(DateTime.now())})",
            emptyMessage: "No sales recorded this month.",
          ),
          const SizedBox(height: 24),
          TopProductsWidget(
            provider: topProductsLastMonthProvider,
            title: "Top 5 Sellers (Last Month, ${_getMonthName(DateTime(DateTime.now().year, DateTime.now().month - 1, 1))})",
            emptyMessage: "No sales recorded last month.",
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  String _getMonthName(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[date.month - 1];
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, {bool isAccent = false, bool isSmall = false, bool isLarge = false, bool showLive = false}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isSmall ? 16 : 20,
        vertical: isLarge ? 32 : (isSmall ? 16 : 20),
      ),
      decoration: BoxDecoration(
        color: isLarge ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: isLarge ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label.toUpperCase(),
                      style: TextStyle(
                        color: isLarge ? Theme.of(context).colorScheme.onPrimary.withOpacity(0.5) : Theme.of(context).colorScheme.onSurface.withOpacity(0.3), 
                        fontSize: 9, 
                        fontWeight: FontWeight.w900, 
                        letterSpacing: 1.0
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (showLive) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF34C759).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 3,
                            height: 3,
                            decoration: const BoxDecoration(
                              color: Color(0xFF34C759),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 3),
                          const Text(
                            "TODAY",
                            style: TextStyle(
                              color: Color(0xFF34C759),
                              fontSize: 6,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              Icon(icon, size: 14, color: isLarge ? Theme.of(context).colorScheme.onPrimary : (isAccent ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withOpacity(0.1))),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: isLarge ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurface,
              fontSize: isLarge ? 32 : (isSmall ? 16 : 22),
              fontWeight: FontWeight.w900,
              letterSpacing: -1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeleton() {
    return Column(
      children: [
        _buildSkeletonCard(height: 100),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildSkeletonCard(height: 80)),
            const SizedBox(width: 12),
            Expanded(child: _buildSkeletonCard(height: 80)),
          ],
        ),
        const SizedBox(height: 12),
        _buildSkeletonCard(height: 80),
      ],
    );
  }

  Widget _buildSkeletonCard({required double height}) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Theme.of(context).colorScheme.onSurface.withOpacity(0.03),
                    Colors.transparent,
                  ],
                  stops: const [0.4, 0.5, 0.6],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
