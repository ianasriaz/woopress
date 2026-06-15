import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import '../providers/notifications_controller.dart';
import '../../../orders/presentation/screens/orders_screen.dart';
import '../../../../core/widgets/empty_state_view.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsControllerProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text("NOTIFICATIONS", style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: -0.5)),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        iconTheme: IconThemeData(color: Theme.of(context).colorScheme.onSurface),
        actions: [
          IconButton(
            icon: Icon(LucideIcons.trash2, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2), size: 20),
            onPressed: () => _showClearConfirmDialog(context, ref),
          ),
        ],
      ),
      body: notificationsAsync.when(
        data: (list) {
          if (list.isEmpty) {
            return const EmptyStateView(
              icon: LucideIcons.bellOff,
              title: "No alerts yet",
              subtitle: "When you receive new orders or store updates, they will appear here in real-time.",
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final n = list[index];
              return Dismissible(
                key: Key(n.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(LucideIcons.trash, color: Colors.red, size: 20),
                ),
                onDismissed: (_) {
                  ref.read(notificationsControllerProvider.notifier).deleteNotification(n.id);
                },
                child: GestureDetector(
                  onTap: () {
                    ref.read(notificationsControllerProvider.notifier).markAsRead(n.id);
                    if (n.orderId != null) {
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => OrdersScreen(openOrderId: int.tryParse(n.orderId!))
                      ));
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      border: Border.all(color: n.isRead ? Theme.of(context).dividerColor : Colors.blueAccent.withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (!n.isRead) ...[
                              Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle)),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: Text(n.title.toUpperCase(), style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                            ),
                            Text(DateFormat('MMM d, h:mm a').format(n.timestamp), style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3), fontSize: 9, fontWeight: FontWeight.w700)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(n.body, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 13, height: 1.4)),
                        if (n.orderId != null) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(LucideIcons.arrowRightCircle, size: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3)),
                              const SizedBox(width: 6),
                              Text("TAP TO VIEW ORDER #${n.orderId}", style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3), fontSize: 9, fontWeight: FontWeight.w900)),
                            ],
                          )
                        ]
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
        loading: () => Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary, strokeWidth: 2)),
        error: (_, __) => const Center(child: Text("Error loading notifications")),
      ),
    );
  }

  void _showClearConfirmDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Text("CLEAR ALL", style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.w900)),
        content: Text("Are you sure you want to permanently delete all notifications?", style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("CANCEL", style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5), fontSize: 12, fontWeight: FontWeight.w800)),
          ),
          TextButton(
            onPressed: () {
              ref.read(notificationsControllerProvider.notifier).clearAll();
              Navigator.pop(ctx);
            },
            child: const Text("CLEAR", style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }
}
