class ChartDataPoint {
  final DateTime date;
  final double revenue;

  ChartDataPoint({required this.date, required this.revenue});
}

class SalesChartData {
  final String period; // 'week', 'month', 'year'
  final List<ChartDataPoint> points;

  SalesChartData({
    required this.period,
    required this.points,
  });
}
