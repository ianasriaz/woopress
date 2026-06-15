class StoreStats {
  final String todayRevenue;
  final String monthlyRevenue;
  final String yearlyRevenue;
  final int ordersToday;
  final int itemsSold;
  final int visitorsToday;
  final double conversionRate;

  StoreStats({
    required this.todayRevenue,
    required this.monthlyRevenue,
    required this.yearlyRevenue,
    required this.ordersToday,
    required this.itemsSold,
    this.visitorsToday = 0,
    this.conversionRate = 0.0,
  });
}
