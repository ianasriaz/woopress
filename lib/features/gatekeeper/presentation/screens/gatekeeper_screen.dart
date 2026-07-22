import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../data/gatekeeper_repository.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../../core/utils/error_popup.dart';

class GatekeeperScreen extends ConsumerStatefulWidget {
  const GatekeeperScreen({super.key});

  @override
  ConsumerState<GatekeeperScreen> createState() => _GatekeeperScreenState();
}

class _GatekeeperScreenState extends ConsumerState<GatekeeperScreen> {
  final TextEditingController _licenseController = TextEditingController();
  bool _isVerifying = false;

  @override
  void dispose() {
    _licenseController.dispose();
    super.dispose();
  }

  void _showAccessDeniedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: BorderSide(color: Theme.of(context).colorScheme.outline.withOpacity(0.2), width: 1)),
        title: Row(
          children: [
            Icon(LucideIcons.info, color: Theme.of(context).colorScheme.onSurface, size: 20),
            const SizedBox(width: 12),
            Text(
              "ACCESS DETAILS",
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ],
        ),
        content: Text(
          "You are not allowed to access this app.\n\nPlease visit anasriaz.com for more details.",
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 14, height: 1.5, fontWeight: FontWeight.w500),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "CLOSE",
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3), fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: () async {
              const url = 'https://anasriaz.com';
              if (await canLaunchUrl(Uri.parse(url))) {
                await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              }
            },
            child: Text(
              "VISIT ANASRIAZ.COM",
              style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w900, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _verifyLicense() async {
    final key = _licenseController.text.trim();
    if (key.isEmpty) return;

    setState(() {
      _isVerifying = true;
    });

    final repo = ref.read(gatekeeperRepositoryProvider);
    
    try {
      final gatekeeperStatus = await repo.verifyLicenseKey(key);

      if (!mounted) return;

      if (gatekeeperStatus == GatekeeperStatus.allowed) {
        if (mounted) {
          ref.read(authNotifierProvider.notifier).markGatekeeperPassed();
        }
      } else if (gatekeeperStatus == GatekeeperStatus.networkError) {
        setState(() {
          _isVerifying = false;
        });
        ErrorPopup.show(
          context, 
          title: "NETWORK TIMEOUT", 
          message: "Could not connect to authentication server.",
        );
      } else {
        setState(() {
          _isVerifying = false;
        });
        
        _showAccessDeniedDialog();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
      });
      ErrorPopup.show(
        context, 
        title: "ERROR", 
        message: e.toString(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 120),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          'assets/images/app_screen_logo.png',
                          width: 48,
                          height: 48,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(width: 16),
                        Text(
                          'WooPress',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1.0,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).dividerColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'BETA',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Welcome to your store manager',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 60),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "LICENSE KEY",
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _licenseController,
                      readOnly: _isVerifying,
                      style: TextStyle(
                        fontSize: 16, 
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      decoration: InputDecoration(
                        hintText: '5E32CA-******-1B0575-******-E61F6A-V3',
                        hintStyle: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                          fontWeight: FontWeight.w500,
                        ),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surface,
                        contentPadding: const EdgeInsets.all(20),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5),
                        ),
                      ),
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => !_isVerifying ? _verifyLicense() : null,
                    ),
                    const SizedBox(height: 32),
                    GestureDetector(
                      onTap: _isVerifying ? null : _verifyLicense,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 64,
                        decoration: BoxDecoration(
                          color: _isVerifying ? Theme.of(context).dividerColor : Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Center(
                          child: _isVerifying 
                            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2))
                            : Text(
                                'CONTINUE',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.0,
                                ),
                              ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 60),
                    Center(
                      child: Text(
                        "Developed by Anas Riaz",
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.15),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        ),
      ),
    );
  }
}
