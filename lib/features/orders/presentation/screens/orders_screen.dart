import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../providers/orders_controller.dart';
import '../../domain/models/order_model.dart';
import '../../../inventory/data/inventory_repository.dart';

import '../../../../core/widgets/global_error_view.dart';
import '../../../../core/widgets/empty_state_view.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  final int? openOrderId;
  const OrdersScreen({super.key, this.openOrderId});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  String _selectedStatus = "all";

  final List<Map<String, String>> _statusFilters = [
    {"id": "all", "label": "ALL"},
    {"id": "processing", "label": "PROCESSING"},
    {"id": "on-hold", "label": "ON HOLD"},
    {"id": "completed", "label": "COMPLETED"},
    {"id": "cancelled", "label": "CANCELLED"},
  ];
  bool _didOpenInitialOrder = false;
  bool _isRefreshing = false;

  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    HapticFeedback.mediumImpact();
    await ref.read(ordersControllerProvider.notifier).refresh();
    if (mounted) setState(() => _isRefreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(ordersControllerProvider);

    if (widget.openOrderId != null && !_didOpenInitialOrder) {
      ordersAsync.whenData((state) {
        final order = state.orders.where((o) => o.id == widget.openOrderId).firstOrNull;
        if (order != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_didOpenInitialOrder) {
              _showOrderDetails(context, order);
              setState(() {
                _didOpenInitialOrder = true;
              });
            }
          });
        }
      });
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Orders', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w900)),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        iconTheme: IconThemeData(color: Theme.of(context).colorScheme.onSurface),
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
                  onPressed: _handleRefresh,
                ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildStatusFilters(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _handleRefresh,
              color: Theme.of(context).colorScheme.primary,
              backgroundColor: Theme.of(context).colorScheme.surface,
              child: ordersAsync.when(
                data: (state) {
                  if (state.orders.isEmpty) {
                    return _buildEmptyState(state.orders.isEmpty);
                  }

                  return NotificationListener<ScrollNotification>(
                    onNotification: (scroll) {
                      if (scroll.metrics.pixels >= scroll.metrics.maxScrollExtent - 200) {
                        ref.read(ordersControllerProvider.notifier).loadMore();
                      }
                      return false;
                    },
                    child: ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: state.orders.length + (state.isLoadingMore ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        if (index == state.orders.length) {
                          return Center(child: Padding(padding: const EdgeInsets.all(16.0), child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)));
                        }
                        final order = state.orders[index];
                        return GestureDetector(
                          onTap: () => _showOrderDetails(context, order),
                          child: _OrderCard(order: order),
                        );
                      },
                    ),
                  );
                },
                loading: () => Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
                error: (e, _) => GlobalErrorView(
                  onRetry: () => ref.read(ordersControllerProvider.notifier).refresh(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: TextField(
          controller: _searchController,
          onChanged: (val) {
            setState(() => _searchQuery = val);
            ref.read(ordersControllerProvider.notifier).onSearch(val);
          },
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: "Search name or ID...",
            hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2), fontSize: 13),
            prefixIcon: Icon(LucideIcons.search, size: 16, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3)),
            suffixIcon: _searchQuery.isNotEmpty 
              ? IconButton(
                  icon: Icon(LucideIcons.x, size: 14, color: Theme.of(context).colorScheme.onSurface),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = "");
                    ref.read(ordersControllerProvider.notifier).onSearch("");
                  },
                )
              : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusFilters() {
    final state = ref.watch(ordersControllerProvider).value;
    final currentStatus = state?.status ?? 'all';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        height: 30, // Reduced height for professional look
        margin: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: _statusFilters.map((filter) {
            final isSelected = currentStatus == filter['id'];
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() => _selectedStatus = filter['id']!);
                  ref.read(ordersControllerProvider.notifier).onFilter(filter['id']!);
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(color: Theme.of(context).dividerColor), // Fixed border
                  ),
                  child: Center(
                    child: Text(
                      filter['label']!,
                      style: TextStyle(
                        color: isSelected ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                        fontSize: 7.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isTotalEmpty) {
    final isFiltering = _searchQuery.isNotEmpty || _selectedStatus != "all";
    return EmptyStateView(
      icon: isFiltering ? LucideIcons.searchX : LucideIcons.shoppingBag,
      title: isFiltering ? "No orders found" : "No orders yet",
      subtitle: isFiltering 
        ? "We couldn't find any orders matching your criteria. Try changing your search or status filter."
        : "You haven't received any orders yet. Once orders start coming in, they'll appear here.",
      actionLabel: isFiltering ? "CLEAR FILTERS" : null,
      onAction: isFiltering ? () {
        setState(() {
          _searchQuery = "";
          _selectedStatus = "all";
          _searchController.clear();
        });
        ref.read(ordersControllerProvider.notifier).onSearch("");
        ref.read(ordersControllerProvider.notifier).onFilter("all");
      } : null,
    );
  }

  void _showOrderDetails(BuildContext context, OrderModel order) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _OrderDetailsSheet(order: order),
    );
  }
}

class _OrderDetailsSheet extends StatelessWidget {
  final OrderModel order;
  const _OrderDetailsSheet({required this.order});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Order #${order.id}",
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 24, fontWeight: FontWeight.w900),
              ),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Theme.of(context).dividerColor.withOpacity(0.1), shape: BoxShape.circle),
                  child: Icon(LucideIcons.x, color: Theme.of(context).colorScheme.onSurface, size: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader(context, "CUSTOMER INFO"),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                      border: Border.all(color: Theme.of(context).dividerColor),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        _buildCustomerTableRow(context, "NAME", order.customerName),
                        if (order.billing.phone.isNotEmpty) ...[
                          Divider(color: Theme.of(context).dividerColor.withOpacity(0.5), height: 1),
                          _buildCustomerTableRow(context, "PHONE", order.billing.phone, onTap: () => launchUrl(Uri.parse("tel:${order.billing.phone}"))),
                        ],
                        if (order.billing.email.isNotEmpty) ...[
                          Divider(color: Theme.of(context).dividerColor.withOpacity(0.5), height: 1),
                          _buildCustomerTableRow(context, "EMAIL", order.billing.email, onTap: () => launchUrl(Uri.parse("mailto:${order.billing.email}"))),
                        ],
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                  _buildSectionHeader(context, "ORDER ADDRESS"),
                  _buildAddressTile(context, order.displayAddress),

                  const SizedBox(height: 32),
                  _buildSectionHeader(context, "ITEMS"),
                  const SizedBox(height: 12),
                  ...order.items.map((item) => _buildItemCard(context, item)),

                  const SizedBox(height: 32),
                  if (order.customerNote.isNotEmpty) ...[
                    _buildSectionHeader(context, "CUSTOMER NOTE"),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.1),
                        border: Border.all(color: Colors.amber.withOpacity(0.5)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(LucideIcons.alertCircle, color: Colors.amber, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              order.customerNote,
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13, fontWeight: FontWeight.w700, fontStyle: FontStyle.italic),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],

                  _buildSectionHeader(context, "SUMMARY"),
                  _buildSummaryRow(context, "Payment", order.paymentMethodTitle),
                  _buildSummaryRow(context, "Source", SourceBadge(source: order.orderSource)),
                  _buildSummaryRow(context, "Subtotal", "Rs. ${order.total}"),
                  Divider(color: Theme.of(context).dividerColor, height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("TOTAL", style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 18, fontWeight: FontWeight.w900)),
                      Text(
                        "Rs. ${order.total}",
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -1.0),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5),
      ),
    );
  }

  Widget _buildCustomerTableRow(BuildContext context, String label, String value, {VoidCallback? onTap}) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 60,
            child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
          ),
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              child: Text(
                value, 
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface, 
                  fontSize: 14, 
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          IconButton(
            icon: Icon(LucideIcons.copy, size: 16, color: Theme.of(context).colorScheme.primary),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label copied')));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAddressTile(BuildContext context, String address) {
    return Container(
      padding: const EdgeInsets.all(16),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              address,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8), fontSize: 14, height: 1.5, fontWeight: FontWeight.w500),
            ),
          ),
          IconButton(
            icon: Icon(LucideIcons.copy, size: 18, color: Theme.of(context).colorScheme.primary),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: address));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Address copied to clipboard')));
            },
            tooltip: 'Copy Address',
          ),
        ],
      ),
    );
  }

  Widget _buildItemCard(BuildContext context, OrderItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.1)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _OrderItemImage(item: item),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.w800)),
                if (item.variationAttributes.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: item.variationAttributes.map((attr) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.2)),
                        ),
                        child: Text(
                          "${attr['key']}: ${attr['value']}",
                          style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 11, fontWeight: FontWeight.w800),
                        ),
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                      child: Text("${item.quantity}x", style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w900, fontSize: 11)),
                    ),
                    const SizedBox(width: 8),
                    if (item.sku.isNotEmpty)
                      Text("SKU: ${item.sku}", style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4), fontSize: 10, fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text("Rs. ${item.total}", style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.w900)),
              if (item.quantity > 1 && item.price.isNotEmpty && item.price != '0.00')
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text("Rs. ${item.price} each", style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5), fontSize: 10, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(BuildContext context, String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3), fontSize: 13, fontWeight: FontWeight.w600)),
          if (value is Widget) value else Text(value.toString(), style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7), fontSize: 13, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _OrderItemImage extends ConsumerStatefulWidget {
  final OrderItem item;
  const _OrderItemImage({required this.item});

  @override
  ConsumerState<_OrderItemImage> createState() => _OrderItemImageState();
}

class _OrderItemImageState extends ConsumerState<_OrderItemImage> {
  String? _imageUrl;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _imageUrl = widget.item.image;
    if (_imageUrl == null) {
      _fetchImage();
    }
  }

  Future<void> _fetchImage() async {
    if (widget.item.productId == 0) return;
    setState(() => _loading = true);
    try {
      final url = await ref.read(inventoryRepositoryProvider).getProductThumbnail(
        widget.item.productId,
        variationId: widget.item.variationId > 0 ? widget.item.variationId : null,
      );
      if (mounted) {
        setState(() {
          _imageUrl = url;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (_imageUrl != null) {
          _showFullImage(context, _imageUrl!);
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 50,
          height: 50,
          color: Theme.of(context).dividerColor.withOpacity(0.1),
          child: _imageUrl != null
              ? CachedNetworkImage(
                  imageUrl: _imageUrl!,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Center(child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.primary))),
                  errorWidget: (context, url, error) => Icon(LucideIcons.image, size: 20, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1)),
                )
              : _loading
                  ? Center(child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.primary)))
                  : Icon(LucideIcons.image, size: 20, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1)),
        ),
      ),
    );
  }

  void _showFullImage(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(color: Colors.black.withOpacity(0.9)),
              ),
            ),
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.contain,
                  placeholder: (context, url) => const Center(child: CircularProgressIndicator(color: Colors.white)),
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(LucideIcons.x, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderCard extends ConsumerWidget {
  final OrderModel order;
  const _OrderCard({required this.order});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  "#${order.id}",
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SourceBadge(source: order.orderSource, isSmall: true),
                  const SizedBox(width: 8),
                  _StatusChip(status: order.status),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            order.customerName,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16, fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(LucideIcons.calendar, size: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4)),
              const SizedBox(width: 4),
              Text(
                _formatDate(order.dateCreated),
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4), fontSize: 11, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 12),
              Icon(LucideIcons.clock, size: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4)),
              const SizedBox(width: 4),
              Text(
                _formatTime(order.dateCreated),
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4), fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "${order.items.length} items • ${order.total} ${order.currency}",
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5), fontSize: 13, fontWeight: FontWeight.w600),
          ),
          if (order.trackingNumber.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.1)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.package, size: 14, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      order.trackingCourier.isNotEmpty ? "${order.trackingCourier}: ${order.trackingNumber}" : "Tracking: ${order.trackingNumber}",
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    icon: Icon(LucideIcons.copy, size: 14, color: Theme.of(context).colorScheme.primary),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: order.trackingNumber));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tracking number copied')));
                    },
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    final isUpdating = ref.watch(ordersControllerProvider).value?.updatingOrderIds.contains(order.id) ?? false;
                    if (!isUpdating) _showStatusPicker(context, ref, order);
                  },
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: order.status == 'completed' ? const Color(0xFF34C759) : Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ref.watch(ordersControllerProvider).value?.updatingOrderIds.contains(order.id) ?? false
                          ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Row(
                              children: [
                                Icon(
                                  order.status == 'completed' ? LucideIcons.checkCircle : LucideIcons.edit3, 
                                  color: Colors.white, 
                                  size: 16
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  order.status == 'completed' ? "SHIPPED" : "UPDATE STATUS",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ],
                            ),
                      ],
                    ),
                  ),
                ),
              ),
              if (order.billing.phone.isNotEmpty) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => launchUrl(Uri.parse("tel:${order.billing.phone}")),
                  child: Container(
                    height: 48,
                    width: 48,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.3)),
                    ),
                    child: Center(
                      child: Icon(LucideIcons.phone, size: 20, color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _launchWhatsApp(order.billing.phone, order.id.toString(), order.customerName),
                  child: Container(
                    height: 48,
                    width: 48,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF25D366).withOpacity(0.3)),
                    ),
                    child: Center(
                      child: const FaIcon(FontAwesomeIcons.whatsapp, size: 20, color: Color(0xFF25D366)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _showStatusPicker(BuildContext context, WidgetRef ref, OrderModel order) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "UPDATE ORDER STATUS",
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1.0),
              ),
              const SizedBox(height: 24),
              _buildStatusOption(context, ref, order.id, "pending", "PENDING", LucideIcons.clock, const Color(0xFFFF9500)),
              _buildStatusOption(context, ref, order.id, "processing", "PROCESSING", LucideIcons.loader, const Color(0xFF007AFF)),
              _buildStatusOption(context, ref, order.id, "on-hold", "ON HOLD", LucideIcons.pauseCircle, const Color(0xFFFFCC00)),
              _buildStatusOption(context, ref, order.id, "completed", "COMPLETED", LucideIcons.checkCircle, const Color(0xFF34C759)),
              Divider(color: Theme.of(context).dividerColor, height: 32),
              _buildStatusOption(context, ref, order.id, "cancelled", "CANCEL ORDER", LucideIcons.xCircle, const Color(0xFFFF3B30), isDanger: true),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusOption(
    BuildContext context, 
    WidgetRef ref, 
    int orderId, 
    String slug, 
    String label, 
    IconData icon, 
    Color color, 
    {bool isDanger = false}
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () {
          Navigator.pop(context);
          if (isDanger) {
            _confirmCancel(context, ref, orderId);
          } else if (slug == 'completed') {
            _showTrackingDialog(context, ref, orderId);
          } else {
            ref.read(ordersControllerProvider.notifier).updateStatus(orderId, slug);
          }
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.1)),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 16),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Icon(LucideIcons.chevronRight, color: color.withOpacity(0.3), size: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmCancel(BuildContext context, WidgetRef ref, int orderId) {
    HapticFeedback.vibrate();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text("CANCEL ORDER", style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w900)),
        content: Text("Are you sure you want to cancel this order? This cannot be undone.", style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("NO", style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5), fontWeight: FontWeight.w900)),
          ),
          TextButton(
            onPressed: () {
              ref.read(ordersControllerProvider.notifier).updateStatus(orderId, 'cancelled');
              Navigator.pop(ctx);
            },
            child: const Text("YES, CANCEL", style: TextStyle(color: Color(0xFFFF3B30), fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  void _showTrackingDialog(BuildContext context, WidgetRef ref, int orderId) {
    String trackingNumber = '';
    String selectedCourier = 'TCS';
    String customCourier = '';
    final couriers = ['TCS', 'Fastex', 'Leopards', 'Postex', 'M&P', 'Other'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "COMPLETE ORDER",
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1.0),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Optionally provide tracking details before completing.",
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5), fontSize: 12),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      onChanged: (v) => trackingNumber = v,
                      decoration: InputDecoration(
                        labelText: "Tracking Number (Optional)",
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: selectedCourier,
                      decoration: InputDecoration(
                        labelText: "Courier",
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                      ),
                      items: couriers.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => selectedCourier = v);
                      },
                    ),
                    if (selectedCourier == 'Other') ...[
                      const SizedBox(height: 16),
                      TextField(
                        onChanged: (v) => customCourier = v,
                        decoration: InputDecoration(
                          labelText: "Specify Courier Name",
                          border: const OutlineInputBorder(),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Theme.of(context).colorScheme.onPrimary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          ref.read(ordersControllerProvider.notifier).updateStatus(
                            orderId, 
                            'completed',
                            trackingNumber: trackingNumber.trim(),
                            trackingCourier: selectedCourier == 'Other' ? customCourier.trim() : selectedCourier,
                          );
                        },
                        child: const Text("MARK AS COMPLETED", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.0)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        );
      },
    );
  }

  String _formatDate(String iso) {
    try {
      final date = DateTime.parse(iso);
      final months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
      return "${months[date.month - 1]} ${date.day.toString().padLeft(2, '0')}, ${date.year}";
    } catch (_) {
      return iso;
    }
  }

  String _formatTime(String iso) {
    try {
      final date = DateTime.parse(iso);
      final hour = date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
      final ampm = date.hour >= 12 ? "PM" : "AM";
      return "${hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} $ampm";
    } catch (_) {
      return "";
    }
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case 'completed': color = const Color(0xFF34C759); break;
      case 'processing': color = const Color(0xFF007AFF); break;
      case 'pending': color = const Color(0xFFFF9500); break;
      case 'on-hold': color = const Color(0xFFFFCC00); break;
      case 'cancelled': color = const Color(0xFFFF3B30); break;
      default: color = Colors.white24;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5),
      ),
    );
  }
}

void _launchWhatsApp(String phone, String orderId, String name) async {
  // Remove all non-digit characters
  String sanitizedPhone = phone.replaceAll(RegExp(r'\D'), '');
  if (sanitizedPhone.isEmpty) return;
  
  // Handle leading '00' (often used instead of '+')
  if (sanitizedPhone.startsWith('00')) {
    sanitizedPhone = sanitizedPhone.substring(2);
  }
  
  // If it starts with '920', it's a common double-prefix error where a user typed '+92' followed by the local '03xx...'
  // e.g., '+9203001234567' -> '9203001234567' -> should be '923001234567'
  if (sanitizedPhone.startsWith('920') && sanitizedPhone.length == 13) {
    sanitizedPhone = '92${sanitizedPhone.substring(3)}';
  }
  
  // Handle local Pakistani mobile or landline numbers:
  // - Starts with '0' followed by digits (e.g. '03001234567' -> '923001234567')
  // - Starts with '3' with length 10 (e.g. '3001234567' -> '923001234567')
  if (sanitizedPhone.startsWith('0') && sanitizedPhone.length == 11) {
    sanitizedPhone = '92${sanitizedPhone.substring(1)}';
  } else if (sanitizedPhone.startsWith('3') && sanitizedPhone.length == 10) {
    sanitizedPhone = '92$sanitizedPhone';
  }

  final message = "Hello $name, this is regarding your order #$orderId.";
  final url = "https://wa.me/$sanitizedPhone?text=${Uri.encodeComponent(message)}";
  
  if (await canLaunchUrl(Uri.parse(url))) {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}

class SourceBadge extends StatelessWidget {
  final String source;
  final bool isSmall;

  const SourceBadge({super.key, required this.source, this.isSmall = false});

  @override
  Widget build(BuildContext context) {
    dynamic icon;
    bool isFa = false;
    Color color;

    String lower = source.toLowerCase();
    if (lower == 'facebook') {
      icon = FontAwesomeIcons.facebook;
      isFa = true;
      color = const Color(0xFF1877F2);
    } else if (lower == 'instagram') {
      icon = FontAwesomeIcons.instagram;
      isFa = true;
      color = const Color(0xFFE1306C);
    } else if (lower == 'google') {
      icon = FontAwesomeIcons.google;
      isFa = true;
      color = const Color(0xFFDB4437);
    } else if (lower == 'tiktok') {
      icon = FontAwesomeIcons.tiktok;
      isFa = true;
      color = Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black;
    } else if (lower == 'youtube') {
      icon = FontAwesomeIcons.youtube;
      isFa = true;
      color = const Color(0xFFFF0000);
    } else if (lower == 'pinterest') {
      icon = FontAwesomeIcons.pinterest;
      isFa = true;
      color = const Color(0xFFE60023);
    } else if (lower == 'twitter' || lower == 'x') {
      icon = FontAwesomeIcons.xTwitter;
      isFa = true;
      color = Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black;
    } else if (lower == 'bing' || lower == 'yahoo' || lower == 'organic') {
      icon = LucideIcons.search;
      color = Theme.of(context).colorScheme.primary;
    } else if (lower == 'direct' || lower == 'typein' || lower == 'admin') {
      icon = LucideIcons.mousePointerClick;
      color = Theme.of(context).colorScheme.primary;
    } else {
      icon = LucideIcons.link;
      color = Theme.of(context).colorScheme.onSurface.withOpacity(0.5);
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: isSmall ? 8 : 10, vertical: isSmall ? 4 : 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(isSmall ? 4 : 6),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            if (isFa)
              FaIcon(icon, size: isSmall ? 10 : 14, color: color)
            else
              Icon(icon, size: isSmall ? 10 : 14, color: color),
            SizedBox(width: isSmall ? 4 : 8),
          ],
          Flexible(
            child: Text(
              source,
              style: TextStyle(
                color: color, 
                fontSize: isSmall ? 10 : 13, 
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
