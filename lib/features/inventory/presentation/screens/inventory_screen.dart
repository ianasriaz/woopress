import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import '../providers/inventory_controller.dart';
import '../../domain/models/product_model.dart';

import '../../../../core/widgets/global_error_view.dart';
import '../../../../core/widgets/empty_state_view.dart';
import '../../../../core/utils/error_popup.dart';
import 'add_product_screen.dart';

class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inventoryAsync = ref.watch(inventoryControllerProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Inventory', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w900)),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        iconTheme: IconThemeData(color: Theme.of(context).colorScheme.onSurface),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(110),
          child: Padding(
            padding: const EdgeInsets.only(left: 20, right: 20, bottom: 16),
            child: Column(
              children: [
                _buildSearchBar(context, ref),
                const SizedBox(height: 12),
                _buildFilterChips(context, ref),
              ],
            ),
          ),
        ),
      ),
      body: inventoryAsync.when(
        data: (state) {
          if (state.products.isEmpty) {
            final isFiltering = (state.search != null && state.search!.isNotEmpty) || state.stockStatus != 'all';
            return EmptyStateView(
              icon: isFiltering ? LucideIcons.searchX : LucideIcons.package2,
              title: isFiltering ? "No matches found" : "Empty Inventory",
              subtitle: isFiltering 
                ? "Try adjusting your search or filters to find what you're looking for."
                : "Your store's inventory is empty. Start by adding your first product.",
              actionLabel: isFiltering ? "CLEAR FILTERS" : "CREATE PRODUCT",
              onAction: () {
                if (isFiltering) {
                  ref.read(inventoryControllerProvider.notifier).onSearch("");
                } else {
                  _showAddProductChoice(context);
                }
              },
            );
          }
          return NotificationListener<ScrollNotification>(
            onNotification: (ScrollNotification scrollInfo) {
              if (scrollInfo.metrics.pixels >= scrollInfo.metrics.maxScrollExtent - 200) {
                ref.read(inventoryControllerProvider.notifier).loadMore();
              }
              return false;
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: state.products.length + (state.hasMore ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                if (index == state.products.length) {
                  return _buildShimmerItem(context);
                }
                final product = state.products[index];
                return _buildProductCard(context, ref, product);
              },
            ),
          );
        },
        loading: () => ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: 6,
          separatorBuilder: (_, __) => const SizedBox(height: 16),
          itemBuilder: (context, __) => _buildShimmerItem(context),
        ),
        error: (e, _) => GlobalErrorView(
          onRetry: () => ref.refresh(inventoryControllerProvider),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          HapticFeedback.heavyImpact();
          _showAddProductChoice(context);
        },
        backgroundColor: const Color(0xFF34C759),
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Icon(LucideIcons.plus, color: Theme.of(context).colorScheme.onSurface, size: 28),
      ),
    );
  }

  void _showAddProductChoice(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(0), topRight: Radius.circular(0)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "CREATE NEW PRODUCT",
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5),
            ),
            const SizedBox(height: 24),
            _choiceCard(
              context,
              "SIMPLE PRODUCT",
              "Standard item with one price.",
              LucideIcons.package,
              () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AddProductScreen(isVariable: false)),
                );
              },
            ),
            const SizedBox(height: 12),
            _choiceCard(
              context,
              "VARIABLE PRODUCT",
              "Sizes, colors, or multiple prices.",
              LucideIcons.layers,
              () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AddProductScreen(isVariable: true)),
                );
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _choiceCard(BuildContext context, String title, String subtitle, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary),
              child: Icon(icon, color: Theme.of(context).colorScheme.onPrimary, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4), fontSize: 11, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, color: Theme.of(context).colorScheme.onSurface, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildProductCard(BuildContext context, WidgetRef ref, ProductModel product) {
    final inStock = product.stockStatus == 'instock';
    
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _showQuickEditSheet(context, ref, product);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(color: Theme.of(context).dividerColor, width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
              ),
              child: product.imageUrl != null 
                  ? CachedNetworkImage(
                      imageUrl: product.imageUrl!,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Shimmer.fromColors(
                        baseColor: Theme.of(context).colorScheme.surfaceVariant,
                        highlightColor: Theme.of(context).dividerColor,
                        child: Container(color: Theme.of(context).colorScheme.onSurface),
                      ),
                      errorWidget: (context, url, error) => Icon(LucideIcons.image, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1)),
                    )
                  : Icon(LucideIcons.image, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: inStock ? const Color(0xFF34C759).withOpacity(0.1) : const Color(0xFFFF3B30).withOpacity(0.1),
                          border: Border.all(color: inStock ? const Color(0xFF34C759).withOpacity(0.5) : const Color(0xFFFF3B30).withOpacity(0.5)),
                        ),
                        child: Text(
                          inStock ? 'IN STOCK' : 'OUT OF STOCK',
                          style: TextStyle(
                            color: inStock ? const Color(0xFF34C759) : const Color(0xFFFF3B30),
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (product.onSale) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFCC00).withOpacity(0.1),
                            border: Border.all(color: const Color(0xFFFFCC00).withOpacity(0.5)),
                          ),
                          child: Text(
                            'SALE',
                            style: TextStyle(
                              color: Color(0xFFFFCC00),
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 10),
                      Text(
                        product.stockQuantity != null ? '${product.stockQuantity} UNITS' : '-',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        DateFormat('MMM dd, yyyy • hh:mm a').format(product.dateCreated),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '🛍️ ${product.totalSales} SOLD',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Rs. ${product.price}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  product.type.toUpperCase(),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context, WidgetRef ref) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: TextField(
        onChanged: (val) {
          // In a real app, we'd debounce this. For now, we refresh on submit or small delay
          ref.read(inventoryControllerProvider.notifier).onSearch(val);
        },
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
        decoration: InputDecoration(
          hintText: "SEARCH PRODUCTS...",
          hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2), fontSize: 12, fontWeight: FontWeight.w800),
          prefixIcon: Icon(LucideIcons.search, size: 16, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }



  Widget _buildFilterChips(BuildContext context, WidgetRef ref) {
    final state = ref.watch(inventoryControllerProvider).value;
    final currentFilter = state?.stockStatus ?? 'all';

    final filters = [
      {"label": "ALL", "value": "all"},
      {"label": "IN STOCK", "value": "instock"},
      {"label": "OUT OF STOCK", "value": "outofstock"},
    ];

    return Container(
      height: 30, // Reduced height for professional look
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: filters.map((f) {
          final active = currentFilter == f['value'];
          return Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                ref.read(inventoryControllerProvider.notifier).onFilter(f['value']!);
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: active ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: Theme.of(context).dividerColor), // Fixed border
                ),
                child: Center(
                  child: Text(
                    f['label']!,
                    style: TextStyle(
                      color: active ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
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
    );
  }



  Widget _buildShimmerItem(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Theme.of(context).colorScheme.surface,
      highlightColor: Theme.of(context).dividerColor,
      child: Container(
        height: 96,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }

  void _showQuickEditSheet(BuildContext context, WidgetRef ref, ProductModel product) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return QuickEditSheet(product: product);
      },
    );
  }
}

class QuickEditSheet extends ConsumerStatefulWidget {
  final ProductModel product;
  const QuickEditSheet({super.key, required this.product});

  @override
  ConsumerState<QuickEditSheet> createState() => _QuickEditSheetState();
}

class _QuickEditSheetState extends ConsumerState<QuickEditSheet> {
  late TextEditingController _priceController;
  late TextEditingController _salePriceController;
  late TextEditingController _stockController;
  late String _selectedStatus;
  late bool _manageStock;
  VariationModel? _selectedVariation;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _priceController = TextEditingController(text: widget.product.regularPrice);
    _salePriceController = TextEditingController(text: widget.product.salePrice);
    _stockController = TextEditingController(text: widget.product.stockQuantity?.toString() ?? '0');
    _selectedStatus = widget.product.stockStatus;
    _manageStock = widget.product.manageStock;
  }

  @override
  void dispose() {
    _priceController.dispose();
    _salePriceController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  void _saveChanges() async {
    if (_isSaving) return;
    
    HapticFeedback.vibrate();
    setState(() => _isSaving = true);
    
    final regularPrice = _priceController.text;
    final salePrice = _salePriceController.text;
    final stock = int.tryParse(_stockController.text) ?? 0;

    try {
      if (widget.product.type == 'simple') {
        await ref.read(inventoryControllerProvider.notifier).updateSimpleProductOptimistic(
          widget.product.id, 
          regularPrice, 
          salePrice,
          newStock: _manageStock ? stock : null,
          newStatus: _manageStock ? null : _selectedStatus,
          manageStock: _manageStock,
        );
      } else if (widget.product.type == 'variable' && _selectedVariation != null) {
        await ref.read(inventoryControllerProvider.notifier).triggerVariationUpdate(
          widget.product.id, 
          _selectedVariation!.id, 
          regularPrice, 
          salePrice,
          newStock: _manageStock ? stock : null,
          newStatus: _manageStock ? null : _selectedStatus,
          manageStock: _manageStock,
        );
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('CHANGES SAVED SUCCESSFULLY', style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontWeight: FontWeight.w900, fontSize: 10)),
            backgroundColor: Theme.of(context).colorScheme.onSurface,
            duration: Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(20),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ErrorPopup.show(
          context, 
          title: "UPDATE FAILED", 
          message: e.toString().split(':').last.trim(),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.only(left: 24, right: 24, top: 32, bottom: bottomInset + 32),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor, width: 2)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    widget.product.name,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 18, fontWeight: FontWeight.w900, height: 1.1),
                  ),
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(LucideIcons.x, color: Theme.of(context).colorScheme.onSurface, size: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            if (widget.product.type == 'variable') ...[
              Text("SELECT VARIATION", style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.24), fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
              const SizedBox(height: 12),
              _buildVariationsList(),
              const SizedBox(height: 24),
            ],
            if (widget.product.type == 'simple' || _selectedVariation != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("REGULAR PRICE", style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.24), fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                        const SizedBox(height: 8),
                        _buildNumericInput(_priceController),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("SALE PRICE", style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.24), fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                        const SizedBox(height: 8),
                        _buildNumericInput(_salePriceController),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_manageStock ? "STOCK QUANTITY" : "STOCK STATUS", style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.24), fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                  const SizedBox(height: 8),
                  _manageStock ? _buildNumericInput(_stockController) : _buildStatusSelector(),
                ],
              ),
              const SizedBox(height: 32),
              GestureDetector(
                onTap: _saveChanges,
                child: Container(
                  height: 56, // Reduced height
                  color: Theme.of(context).colorScheme.onSurface,
                  child: Center(
                    child: _isSaving 
                      ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Theme.of(context).colorScheme.onPrimary, strokeWidth: 3))
                      : Text(
                          'SAVE CHANGES',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusSelector() {
    final isInStock = _selectedStatus == 'instock';
    return Row(
      children: [
        _statusButton("IN STOCK", 'instock', isInStock),
        const SizedBox(width: 6),
        _statusButton("OUT OF STOCK", 'outofstock', !isInStock),
      ],
    );
  }

  Widget _statusButton(String label, String value, bool active) {
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedStatus = value),
        child: Container(
          height: 48, // Reduced height
          decoration: BoxDecoration(
            color: active ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.surface,
            border: Border.all(color: active ? Theme.of(context).colorScheme.onSurface : Theme.of(context).dividerColor),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: active ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurface.withOpacity(0.24),
                fontSize: 8,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNumericInput(TextEditingController controller) {
    return TextField(
      controller: controller,
      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: Theme.of(context).dividerColor, width: 1.5)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: Theme.of(context).colorScheme.onSurface, width: 2)),
      ),
    );
  }

  Widget _buildVariationsList() {
    final asyncVars = ref.watch(productVariationsProvider(widget.product.id));
    return asyncVars.when(
      data: (variations) {
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: variations.map((v) {
            final isSelected = _selectedVariation?.id == v.id;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedVariation = v;
                  _priceController.text = v.regularPrice;
                  _salePriceController.text = v.salePrice;
                  _stockController.text = v.stockQuantity?.toString() ?? '0';
                  _selectedStatus = v.stockStatus;
                  _manageStock = v.manageStock;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.surface,
                  border: Border.all(color: isSelected ? Theme.of(context).colorScheme.onSurface : Theme.of(context).dividerColor, width: 1.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      v.attributes.join(', '),
                      style: TextStyle(
                        color: isSelected ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (v.totalSales > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        '🛍️ ${v.totalSales}',
                        style: TextStyle(
                          color: isSelected ? Theme.of(context).colorScheme.onPrimary.withOpacity(0.5) : Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
      loading: () => Shimmer.fromColors(
        baseColor: Theme.of(context).colorScheme.surface,
        highlightColor: Theme.of(context).dividerColor,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List.generate(3, (index) => Container(
            width: 80,
            height: 40,
            color: Theme.of(context).colorScheme.onPrimary,
          )),
        ),
      ),
      error: (e, _) => Text('Error loading variations', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3), fontSize: 12)),
    );
  }
}
