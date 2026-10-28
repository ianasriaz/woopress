import 'package:flutter/material.dart';

import '../../../../core/widgets/pressable.dart';

/// Quick status filters shown above the order list.
///
/// Each chip's width is proportional to its label length, and labels render
/// inside a [FittedBox] so they always stay on a single line on any screen
/// width instead of wrapping (e.g. the trailing "G" of PROCESSING).
class StatusFilterBar extends StatelessWidget {
  final String currentStatus;
  final ValueChanged<String> onSelected;

  const StatusFilterBar({super.key, required this.currentStatus, required this.onSelected});

  static const _filters = <({String id, String label})>[
    (id: 'all', label: 'ALL'),
    (id: 'processing', label: 'PROCESSING'),
    (id: 'on-hold', label: 'ON HOLD'),
    (id: 'completed', label: 'COMPLETED'),
    (id: 'cancelled', label: 'CANCELLED'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        height: 34,
        margin: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            for (final filter in _filters)
              Expanded(
                flex: filter.label.length.clamp(2, 10),
                child: Pressable(
                  onTap: () => onSelected(filter.id),
                  child: Container(
                    height: double.infinity,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: currentStatus == filter.id ? theme.colorScheme.primary : theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            filter.label,
                            maxLines: 1,
                            softWrap: false,
                            style: TextStyle(
                              color: currentStatus == filter.id
                                  ? theme.colorScheme.onPrimary
                                  : theme.colorScheme.onSurface.withValues(alpha: 0.3),
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
