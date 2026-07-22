import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import '../providers/dashboard_controller.dart';
import '../../domain/models/sales_chart_data.dart';
import '../../domain/models/store_stats.dart';

class SalesChartWidget extends ConsumerWidget {
  const SalesChartWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(chartPeriodProvider);
    final chartAsync = ref.watch(salesChartProvider);
    final statsAsync = ref.watch(dashboardControllerProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header & Toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "SALES TREND",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(2),
                child: Row(
                  children: [
                    _buildToggleBtn(context, ref, 'week', '7D', period == 'week'),
                    _buildToggleBtn(context, ref, 'month', '30D', period == 'month'),
                    _buildToggleBtn(context, ref, 'year', '12M', period == 'year'),
                  ],
                ),
              )
            ],
          ),
          const SizedBox(height: 24),
          // Chart Area
          SizedBox(
            height: 200,
            child: chartAsync.when(
              data: (chartData) {
                // Real-time patching: Inject today's live revenue into the chart
                final liveStats = statsAsync.value;
                final patchedPoints = _patchLiveRevenue(chartData.points, liveStats, period);
                
                if (patchedPoints.isEmpty) {
                  return const Center(child: Text("No sales data available."));
                }
                return _buildChart(context, patchedPoints, period);
              },
              loading: () => _buildSkeleton(context),
              error: (err, _) => const Center(child: Text("Failed to load chart")),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleBtn(BuildContext context, WidgetRef ref, String targetPeriod, String label, bool isSelected) {
    return GestureDetector(
      onTap: () => ref.read(chartPeriodProvider.notifier).updatePeriod(targetPeriod),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).colorScheme.primary.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  List<ChartDataPoint> _patchLiveRevenue(List<ChartDataPoint> points, StoreStats? liveStats, String period) {
    if (points.isEmpty || liveStats == null) return points;
    if (period == 'year') return points;
    
    final liveRevenue = double.tryParse(liveStats.todayRevenue) ?? 0.0;
    
    // Create a new list so we don't mutate the cached one directly
    final patched = List<ChartDataPoint>.from(points);
    final now = DateTime.now();
    
    // Find today's point and update it, or append if missing
    final todayIndex = patched.indexWhere((p) => 
      p.date.year == now.year && p.date.month == now.month && p.date.day == now.day);
      
    if (todayIndex != -1) {
      // Only patch if liveRevenue is greater (to avoid overriding with 0 while fetching)
      if (liveRevenue > patched[todayIndex].revenue) {
        patched[todayIndex] = ChartDataPoint(date: patched[todayIndex].date, revenue: liveRevenue);
      }
    } else {
      patched.add(ChartDataPoint(
        date: DateTime(now.year, now.month, now.day),
        revenue: liveRevenue,
      ));
    }
    
    return patched;
  }

  Widget _buildChart(BuildContext context, List<ChartDataPoint> points, String period) {
    if (points.isEmpty) return const SizedBox.shrink();

    double maxY = points.map((p) => p.revenue).reduce((a, b) => a > b ? a : b);
    if (maxY == 0) maxY = 100; // default scale
    
    // Add 20% padding to top
    maxY = maxY * 1.2;

    List<FlSpot> spots = [];
    for (int i = 0; i < points.length; i++) {
      spots.add(FlSpot(i.toDouble(), points[i].revenue));
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 4,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: Theme.of(context).dividerColor.withOpacity(0.5),
              strokeWidth: 1,
              dashArray: [4, 4],
            );
          },
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: period == 'year' ? (points.length / 6).ceilToDouble() : (points.length / 5).ceilToDouble(),
              getTitlesWidget: (value, meta) {
                if (value.toInt() < 0 || value.toInt() >= points.length) return const SizedBox.shrink();
                final date = points[value.toInt()].date;
                String text;
                if (period == 'year') {
                  text = DateFormat('MMM').format(date);
                } else {
                  text = DateFormat('d MMM').format(date);
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    text,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: maxY / 4,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                if (value == 0) return const SizedBox.shrink();
                return Text(
                  NumberFormat.compact().format(value),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: (points.length - 1).toDouble(),
        minY: 0,
        maxY: maxY,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.3,
            color: Theme.of(context).colorScheme.primary,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
            ),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 350), // smooth transition on period change
    );
  }

  Widget _buildSkeleton(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.05),
      highlightColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.02),
      child: Container(
        width: double.infinity,
        height: 200,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
