

class ReportSummary {
  final double totalOutstandingDebt;
  final String highestDebtCustomerName;
  final double highestDebtAmount;
  final int overstayedDebtCount;
  final int totalCustomers;

  ReportSummary({
    required this.totalOutstandingDebt,
    required this.highestDebtCustomerName,
    required this.highestDebtAmount,
    required this.overstayedDebtCount,
    required this.totalCustomers,
  });

  factory ReportSummary.fromJson(Map<String, dynamic> json) {
    return ReportSummary(
      totalOutstandingDebt: (json['total_outstanding_debt'] as num?)?.toDouble() ?? 0.0,
      highestDebtCustomerName: json['highest_debt_customer_name'] as String? ?? 'N/A',
      highestDebtAmount: (json['highest_debt_amount'] as num?)?.toDouble() ?? 0.0,
      overstayedDebtCount: json['overstayed_debt_count'] as int? ?? 0,
      totalCustomers: json['total_customers'] as int? ?? 0,
    );
  }
}
