import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ErrorPopup {
  static Future<void> show(BuildContext context, {required String title, required String message}) async {
    HapticFeedback.heavyImpact();
    
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: Color(0xFFFF3B30),
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
        content: Text(
          message,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            fontWeight: FontWeight.w500,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "CLOSE",
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
