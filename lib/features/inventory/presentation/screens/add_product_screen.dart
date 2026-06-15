import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../providers/inventory_controller.dart';
import '../../data/inventory_repository.dart';
import '../../../../core/utils/error_popup.dart';

class _UploadableImage {
  final XFile file;
  int? serverId;
  bool isUploading;
  String? error;

  _UploadableImage({required this.file, this.serverId, this.isUploading = false, this.error});
}

class ProductAttribute {
  String name;
  List<String> options;
  ProductAttribute({required this.name, required this.options});
}

class ProductVariation {
  Map<String, String> attributes; // { "Color": "Red", "Size": "M" }
  final TextEditingController priceController = TextEditingController();
  final TextEditingController salePriceController = TextEditingController();
  final TextEditingController stockController = TextEditingController();
  String sku = "";
  bool manageStock = false;
  String stockStatus = 'instock';
  _UploadableImage? image;

  ProductVariation({required this.attributes, String price = "", String salePrice = "", String stock = ""}) {
    priceController.text = price;
    salePriceController.text = salePrice;
    stockController.text = stock;
  }

  void dispose() {
    priceController.dispose();
    salePriceController.dispose();
    stockController.dispose();
  }
}

class AddProductScreen extends ConsumerStatefulWidget {
  final bool isVariable;
  const AddProductScreen({super.key, required this.isVariable});

  @override
  ConsumerState<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends ConsumerState<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _salePriceController = TextEditingController();
  final _skuController = TextEditingController();
  final _stockController = TextEditingController();
  
  _UploadableImage? _featuredImage;
  final List<_UploadableImage> _galleryImages = [];
  
  Map<String, dynamic>? _selectedCategory;
  final List<ProductAttribute> _attributes = [];
  final List<ProductVariation> _variations = [];
  bool _isSaving = false;
  bool _manageStock = false;
  String _stockStatus = 'instock';

  final ImagePicker _picker = ImagePicker();

  Future<void> _pickFeaturedImage() async {
    final pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1200,
    );
    if (pickedFile != null) {
      final img = _UploadableImage(file: pickedFile, isUploading: true);
      setState(() => _featuredImage = img);
      _uploadImage(img, isFeatured: true);
    }
  }

  Future<void> _pickGalleryImage() async {
    final pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1200,
    );
    if (pickedFile != null) {
      final img = _UploadableImage(file: pickedFile, isUploading: true);
      setState(() => _galleryImages.add(img));
      _uploadImage(img, isFeatured: false);
    }
  }

  Future<void> _uploadImage(_UploadableImage img, {required bool isFeatured}) async {
    try {
      final repo = ref.read(inventoryRepositoryProvider);
      final bytes = await img.file.readAsBytes();
      final fileName = img.file.path.split('/').last;
      
      final id = await repo.uploadImage(bytes, fileName);
      if (mounted) {
        setState(() {
          img.serverId = id;
          img.isUploading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          img.isUploading = false;
          img.error = e.toString();
        });
      }
    }
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_featuredImage != null && _featuredImage!.isUploading) {
      ErrorPopup.show(context, title: "UPLOAD IN PROGRESS", message: "Please wait for the main image to finish uploading.");
      return;
    }

    setState(() => _isSaving = true);
    HapticFeedback.mediumImpact();

    try {
      final repo = ref.read(inventoryRepositoryProvider);
      
      final List<Map<String, dynamic>> imagesData = [];
      if (_featuredImage?.serverId != null) {
        imagesData.add({'id': _featuredImage!.serverId});
      }
      for (var img in _galleryImages) {
        if (img.serverId != null) {
          imagesData.add({'id': img.serverId});
        }
      }

      final Map<String, dynamic> productData = {
        'name': _nameController.text,
        'type': widget.isVariable ? 'variable' : 'simple',
        'regular_price': widget.isVariable ? "" : _priceController.text,
        'sale_price': widget.isVariable ? "" : _salePriceController.text,
        'sku': _skuController.text,
        'manage_stock': _manageStock,
        'stock_quantity': _manageStock ? int.tryParse(_stockController.text) : null,
        'stock_status': _manageStock ? null : _stockStatus,
        'categories': _selectedCategory != null ? [{'id': _selectedCategory!['id']}] : [],
        'images': imagesData,
        'attributes': _attributes.map((a) => {
          'name': a.name,
          'options': a.options,
          'visible': true,
          'variation': true,
        }).toList(),
      };

      final productId = await repo.createProduct(productData);

      // Stage 2: Create Variations if applicable
      if (widget.isVariable && _variations.isNotEmpty) {
        for (var v in _variations) {
          final Map<String, dynamic> variationData = {
            'regular_price': v.priceController.text,
            'sale_price': v.salePriceController.text,
            'manage_stock': v.manageStock,
            'stock_quantity': v.manageStock ? int.tryParse(v.stockController.text) : null,
            'stock_status': v.manageStock ? null : v.stockStatus,
            'attributes': v.attributes.entries.map((e) => {
              'name': e.key,
              'option': e.value,
            }).toList(),
          };

          // Include variation image if uploaded
          if (v.image?.serverId != null) {
            variationData['image'] = {'id': v.image!.serverId};
          }

          await repo.createVariation(productId, variationData);
        }
      }
      
      if (mounted) {
        ref.invalidate(inventoryControllerProvider);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product Published Successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ErrorPopup.show(context, title: "UPLOAD FAILED", message: "Could not add the product. $e");
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(widget.isVariable ? "VARIABLE PRODUCT" : "SIMPLE PRODUCT", style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w900, fontSize: 16)),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        iconTheme: IconThemeData(color: Theme.of(context).colorScheme.onSurface),
        elevation: 0,
      ),
      body: AbsorbPointer(
        absorbing: _isSaving,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionLabel("PRODUCT IMAGE"),
                const SizedBox(height: 12),
                _buildFeaturedImageSlot(),
                const SizedBox(height: 32),
                _buildSectionLabel("PRODUCT GALLERY"),
                const SizedBox(height: 12),
                _buildGallerySection(),
                const SizedBox(height: 32),
                _buildSectionLabel("BASIC INFORMATION"),
                const SizedBox(height: 12),
                _buildTextField("Product Name", _nameController, LucideIcons.tag),
                if (!widget.isVariable) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: _buildTextField("Price (Rs.)", _priceController, LucideIcons.banknote, isNumeric: true)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildTextField("Sale Price", _salePriceController, LucideIcons.percent, isNumeric: true)),
                    ],
                  ),
                ],
                const SizedBox(height: 32),
                _buildSectionLabel("INVENTORY"),
                const SizedBox(height: 12),
                _buildTextField("SKU (Optional)", _skuController, LucideIcons.hash),
                const SizedBox(height: 16),
                _buildStockToggle(),
                if (_manageStock) ...[
                  const SizedBox(height: 16),
                  _buildTextField("Stock Quantity", _stockController, LucideIcons.package, isNumeric: true),
                ] else ...[
                  const SizedBox(height: 16),
                  _buildStockStatusDropdown(),
                ],
                if (widget.isVariable) ...[
                  const SizedBox(height: 32),
                  _buildSectionLabel("ATTRIBUTES & VARIATIONS"),
                  const SizedBox(height: 12),
                  _buildVariationsManager(),
                ],
                const SizedBox(height: 32),
                _buildSectionLabel("ORGANIZATION"),
                const SizedBox(height: 12),
                _buildCategoryPicker(),
                const SizedBox(height: 48),
                _buildSaveButton(),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5),
    );
  }

  Widget _buildFeaturedImageSlot() {
    return GestureDetector(
      onTap: _pickFeaturedImage,
      child: Container(
        height: 200,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: _featuredImage != null
            ? _buildImageOverlay(_featuredImage!)
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.image, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.15), size: 48),
                  const SizedBox(height: 12),
                  Text(
                    "TAP TO ADD PRODUCT IMAGE", 
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.0)
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildGallerySection() {
    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _galleryImages.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          if (index == _galleryImages.length) {
            return _buildAddGalleryButton();
          }
          return _buildGalleryItem(_galleryImages[index]);
        },
      ),
    );
  }

  Widget _buildAddGalleryButton() {
    return GestureDetector(
      onTap: _pickGalleryImage,
      child: Container(
        width: 100,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Center(
          child: Icon(LucideIcons.plus, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3), size: 24),
        ),
      ),
    );
  }

  Widget _buildGalleryItem(_UploadableImage img) {
    return Container(
      width: 100,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: _buildImageOverlay(img, isGallery: true),
    );
  }

  Widget _buildImageOverlay(_UploadableImage img, {bool isGallery = false}) {
    return Stack(
      children: [
        Positioned.fill(
          child: kIsWeb 
            ? Image.network(img.file.path, fit: BoxFit.cover) 
            : Image.file(File(img.file.path), fit: BoxFit.cover),
        ),
        if (img.isUploading)
          Positioned.fill(
            child: Container(
              color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.54),
              child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.onSurface))),
            ),
          ),
        if (img.serverId != null)
          Positioned(
            right: 4,
            top: 4,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(color: Color(0xFF34C759), shape: BoxShape.circle),
              child: Icon(LucideIcons.check, color: Theme.of(context).colorScheme.onSurface, size: 10),
            ),
          ),
        if (img.error != null)
          Positioned.fill(
            child: Container(
              color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.8),
              padding: const EdgeInsets.all(4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(LucideIcons.alertCircle, color: Colors.red, size: 16),
                  const SizedBox(height: 4),
                  Text(
                    img.error!.replaceAll("Exception: ", ""), 
                    style: const TextStyle(color: Colors.red, fontSize: 6, fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        Positioned(
          left: 4,
          top: 4,
          child: GestureDetector(
            onTap: () {
              setState(() {
                if (isGallery) {
                  _galleryImages.remove(img);
                } else {
                  _featuredImage = null;
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.54)),
              child: Icon(LucideIcons.x, color: Theme.of(context).colorScheme.onSurface, size: 10),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, IconData icon, {bool isNumeric = false}) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          labelText: label.toUpperCase(),
          labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4), fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.0),
          prefixIcon: Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        validator: (val) {
          if (label.contains("Name") && (val == null || val.isEmpty)) return "Required";
          if (label.contains("Price") && !label.contains("Sale") && (val == null || val.isEmpty)) return "Required";
          return null;
        },
      ),
    );
  }

  Widget _buildStockToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text("MANAGE STOCK", style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5), fontSize: 12, fontWeight: FontWeight.w800)),
          Switch(
            value: _manageStock,
            onChanged: (val) => setState(() => _manageStock = val),
            activeColor: Theme.of(context).colorScheme.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildStockStatusDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _stockStatus,
          isExpanded: true,
          dropdownColor: Theme.of(context).colorScheme.surface,
          icon: Icon(LucideIcons.chevronDown, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5), size: 16),
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.w600),
          items: const [
            DropdownMenuItem(value: 'instock', child: Text("IN STOCK")),
            DropdownMenuItem(value: 'outofstock', child: Text("OUT OF STOCK")),
            DropdownMenuItem(value: 'onbackorder', child: Text("ON BACKORDER")),
          ],
          onChanged: (val) {
            if (val != null) setState(() => _stockStatus = val);
          },
        ),
      ),
    );
  }

  Widget _buildVariationsManager() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Attribute List
        ..._attributes.asMap().entries.map((entry) {
          final idx = entry.key;
          final attr = entry.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border.all(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.05)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(attr.name.toUpperCase(), style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 10, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      Text(attr.options.join(", "), style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3), fontSize: 11)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.trash2, size: 16, color: Colors.red),
                  onPressed: () => setState(() => _attributes.removeAt(idx)),
                ),
              ],
            ),
          );
        }),
        
        const SizedBox(height: 12),
        
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: _showGlobalAttributeSelector,
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurface,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.globe, size: 14, color: Theme.of(context).colorScheme.onPrimary),
                        const SizedBox(width: 8),
                        Text("SELECT FROM STORE", style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontSize: 10, fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: _showAddAttributeDialog,
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.plus, size: 14, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
                        const SizedBox(width: 8),
                        Text("CREATE CUSTOM", style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5), fontSize: 10, fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),

        if (_attributes.isNotEmpty) ...[
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _generateVariations,
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF34C759),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.sparkles, size: 14, color: Theme.of(context).colorScheme.onSurface),
                    const SizedBox(width: 8),
                    Text("GENERATE ALL VARIATIONS", style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ),
        ],

        if (_variations.isNotEmpty) ...[
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("GENERATED VARIATIONS", style: TextStyle(color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.54), fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
              GestureDetector(
                onTap: _showBulkPriceDialog,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(LucideIcons.copy, size: 12, color: Colors.blueAccent),
                      SizedBox(width: 6),
                      Text("BULK SET PRICES", style: TextStyle(color: Colors.blueAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._variations.map((v) => _buildVariationItem(v)),
        ],
      ],
    );
  }

  void _showBulkPriceDialog() {
    final regController = TextEditingController();
    final saleController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text("BULK SET PRICES", style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: regController,
              keyboardType: TextInputType.number,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              decoration: InputDecoration(
                labelText: "REGULAR PRICE",
                labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3), fontSize: 10),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Theme.of(context).dividerColor)),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: saleController,
              keyboardType: TextInputType.number,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              decoration: InputDecoration(
                labelText: "SALE PRICE (OPTIONAL)",
                labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3), fontSize: 10),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Theme.of(context).dividerColor)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("CANCEL", style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3))),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                for (var v in _variations) {
                  v.priceController.text = regController.text;
                  v.salePriceController.text = saleController.text;
                }
              });
              Navigator.pop(context);
            },
            child: const Text("APPLY TO ALL", style: TextStyle(color: Color(0xFF34C759), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _showGlobalAttributeSelector() async {
    final repo = ref.read(inventoryRepositoryProvider);
    
    // Show Loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.onSurface)),
    );

    try {
      final attributes = await repo.fetchGlobalAttributes();
      if (mounted) Navigator.pop(context); // Pop loading

      if (attributes.isEmpty) {
        if (mounted) ErrorPopup.show(context, title: "NO ATTRIBUTES", message: "No global attributes found in store.");
        return;
      }

      final selectedAttr = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Text("SELECT ATTRIBUTE", style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.w900)),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: attributes.length,
              itemBuilder: (context, i) => ListTile(
                title: Text(attributes[i]['name'].toString().toUpperCase(), style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 12, fontWeight: FontWeight.w700)),
                onTap: () => Navigator.pop(context, attributes[i]),
              ),
            ),
          ),
        ),
      );

      if (selectedAttr == null) return;

      // Fetch Terms
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.onSurface)),
      );
      
      final terms = await repo.fetchAttributeTerms(selectedAttr['id']);
      if (mounted) Navigator.pop(context); // Pop loading

      final List<String> selectedTerms = [];
      
      await showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            title: Text("SELECT ${selectedAttr['name'].toString().toUpperCase()} OPTIONS", style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.w900)),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: terms.length,
                itemBuilder: (context, i) {
                  final term = terms[i];
                  final isSelected = selectedTerms.contains(term);
                  return CheckboxListTile(
                    title: Text(term, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 12)),
                    value: isSelected,
                    onChanged: (val) {
                      setDialogState(() {
                        if (val == true) selectedTerms.add(term);
                        else selectedTerms.remove(term);
                      });
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
              TextButton(
                onPressed: () => Navigator.pop(context), 
                child: Text("ADD SELECTED", style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w900))
              ),
            ],
          ),
        ),
      );

      if (selectedTerms.isNotEmpty) {
        setState(() {
          _attributes.add(ProductAttribute(
            name: selectedAttr['name'].toString(),
            options: selectedTerms,
          ));
        });
      }

    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ErrorPopup.show(context, title: "ERROR", message: e.toString());
      }
    }
  }

  void _showAddAttributeDialog() {
    final nameCtrl = TextEditingController();
    final optionsCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text("NEW ATTRIBUTE", style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.w900)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              decoration: InputDecoration(labelText: "NAME (E.G. SIZE)", labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.24))),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: optionsCtrl,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              decoration: InputDecoration(
                labelText: "OPTIONS (SEPARATED BY COMMA)", 
                labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.24)),
                hintText: "S, M, L",
                hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
          TextButton(
            onPressed: () {
              if (nameCtrl.text.isNotEmpty && optionsCtrl.text.isNotEmpty) {
                setState(() {
                  _attributes.add(ProductAttribute(
                    name: nameCtrl.text.trim(),
                    options: optionsCtrl.text.split(",").map((s) => s.trim()).toList(),
                  ));
                });
                Navigator.pop(context);
              }
            },
            child: const Text("ADD"),
          ),
        ],
      ),
    );
  }

  void _generateVariations() {
    if (_attributes.isEmpty) return;

    List<Map<String, String>> combinations = [{}];

    for (var attr in _attributes) {
      List<Map<String, String>> newCombinations = [];
      for (var existing in combinations) {
        for (var option in attr.options) {
          final combo = Map<String, String>.from(existing);
          combo[attr.name] = option;
          newCombinations.add(combo);
        }
      }
      combinations = newCombinations;
    }

    setState(() {
      _variations.clear();
      for (var combo in combinations) {
        _variations.add(ProductVariation(
          attributes: combo,
          price: _priceController.text,
          salePrice: _salePriceController.text,
        ));
      }
    });
  }

  Future<void> _pickVariationImage(ProductVariation v) async {
    HapticFeedback.lightImpact();
    final pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1200,
    );
    if (pickedFile != null) {
      final img = _UploadableImage(file: pickedFile, isUploading: true);
      setState(() => v.image = img);
      _uploadImage(img, isFeatured: false);
    }
  }

  Widget _buildVariationItem(ProductVariation v) {
    final label = v.attributes.values.join(" / ");
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border.all(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.05)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Variation Image Slot
          GestureDetector(
            onTap: () => _pickVariationImage(v),
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border.all(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.05)),
              ),
              child: v.image != null
                  ? _buildImageOverlay(v.image!, isGallery: true)
                  : Stack(
                      children: [
                        Center(child: Icon(LucideIcons.image, size: 20, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1))),
                        Positioned(
                          bottom: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(color: Color(0xFF34C759), shape: BoxShape.circle),
                            child: Icon(LucideIcons.plus, size: 10, color: Theme.of(context).colorScheme.onSurface),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(), style: const TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildVariationMiniField("REGULAR PRICE", v.priceController, isNumeric: true),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildVariationMiniField("SALE PRICE", v.salePriceController, isNumeric: true),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("MANAGE STOCK", style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2), fontSize: 8, fontWeight: FontWeight.w900)),
                          SizedBox(
                            height: 32,
                            child: Switch(
                              value: v.manageStock,
                              onChanged: (val) {
                                HapticFeedback.lightImpact();
                                setState(() => v.manageStock = val);
                              },
                              activeColor: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: v.manageStock
                          ? _buildVariationMiniField("STOCK QUANTITY", v.stockController, isNumeric: true)
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("STOCK STATUS", style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2), fontSize: 8, fontWeight: FontWeight.w900)),
                                DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: v.stockStatus,
                                    isExpanded: true,
                                    dropdownColor: Theme.of(context).colorScheme.surface,
                                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 11),
                                    icon: Icon(LucideIcons.chevronDown, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3), size: 14),
                                    items: const [
                                      DropdownMenuItem(value: 'instock', child: Text("IN STOCK")),
                                      DropdownMenuItem(value: 'outofstock', child: Text("OUT OF STOCK")),
                                      DropdownMenuItem(value: 'onbackorder', child: Text("ON BACKORDER")),
                                    ],
                                    onChanged: (val) {
                                      if (val != null) setState(() => v.stockStatus = val);
                                    },
                                  ),
                                ),
                                Container(height: 1, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.10)),
                              ],
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVariationMiniField(String label, TextEditingController controller, {bool isNumeric = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2), fontSize: 8, fontWeight: FontWeight.w900)),
        TextField(
          controller: controller,
          keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.10))),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryPicker() {
    return GestureDetector(
      onTap: _showCategoryPicker,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.list, size: 16, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _selectedCategory?['name']?.toUpperCase() ?? "SELECT CATEGORY",
                style: TextStyle(
                  color: _selectedCategory != null ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Icon(LucideIcons.chevronDown, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.24), size: 16),
          ],
        ),
      ),
    );
  }

  void _showCategoryPicker() async {
    final repo = ref.read(inventoryRepositoryProvider);
    final categories = await repo.fetchCategories();
    
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) => ListView.builder(
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final cat = categories[index];
          return ListTile(
            title: Text(cat['name'], style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.w700)),
            onTap: () {
              setState(() => _selectedCategory = cat);
              Navigator.pop(context);
            },
          );
        },
      ),
    );
  }

  Widget _buildSaveButton() {
    return GestureDetector(
      onTap: _isSaving ? null : _saveProduct,
      child: Container(
        height: 64,
        color: _isSaving ? Colors.white.withOpacity(0.5) : Colors.white,
        child: Center(
          child: _isSaving 
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2)),
                  SizedBox(width: 12),
                  Text(
                    "PUBLISHING...",
                    style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                  ),
                ],
              )
            : const Text(
                "PUBLISH PRODUCT",
                style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: -0.5),
              ),
        ),
      ),
    );
  }
}
