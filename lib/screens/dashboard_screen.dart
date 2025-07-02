import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shiok_pos_android_app/providers/auth_provider.dart';
import 'package:shiok_pos_android_app/service/pos_service.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  late Future<Map<String, dynamic>> _dashboardData;
  late String _posProfile;
  String baseImageUrl = 'http://shiokpos.byondwave.com';

  @override
  void initState() {
    super.initState();
    _dashboardData = _loadDashboardData();
  }

  Future<Map<String, dynamic>> _loadDashboardData() async {
    final authState = ref.read(authProvider);
    return authState.maybeWhen(
      authenticated: (sid, apiKey, apiSecret, username, email, fullName,
          posProfile, branch, paymentMethods, taxes, hasOpening, tier) async {
        _posProfile = posProfile;
        final today = DateTime.now();
        final firstDayOfMonth = DateTime(today.year, today.month, 1);
        final dateFormat = DateFormat('yyyy-MM-dd');

        // Fetch all data concurrently
        final results = await Future.wait([
          PosService().makeRequest(
            endpoint:
                'shiok_pos.api.get_total_sales?pos_profile=$posProfile&from_date=${dateFormat.format(firstDayOfMonth)}&to_date=${dateFormat.format(today)}',
          ),
          PosService().makeRequest(
            endpoint:
                'shiok_pos.api.get_total_customer?pos_profile=$posProfile&from_date=${dateFormat.format(firstDayOfMonth)}&to_date=${dateFormat.format(today)}',
          ),
          PosService().getTodayInfo(),
          PosService().makeRequest(
            endpoint: 'shiok_pos.api.get_ltm_revenue?pos_profile=$posProfile',
          ),
          PosService().makeRequest(
            endpoint:
                'shiok_pos.api.get_peak_time?pos_profile=$posProfile&from_date=${dateFormat.format(firstDayOfMonth)}&to_date=${dateFormat.format(today)}',
          ),
          PosService().makeRequest(
            endpoint:
                'shiok_pos.api.get_top_five_items?pos_profile=$posProfile&from_date=${dateFormat.format(firstDayOfMonth)}&to_date=${dateFormat.format(today)}',
          ),
        ]);

        // Convert to proper types
        return <String, dynamic>{
          'totalSales': _convertToDouble(results[0]['message']),
          'totalCustomers': _convertToInt(results[1]['message']),
          'todayInfo': _convertMapToStringDynamic(results[2]['message']),
          'revenueData': _convertListToProperType(results[3]['message']),
          'peakTimes': _convertListToProperType(results[4]['message']),
          'topItems': _convertListToProperType(results[5]['message']),
        };
      },
      orElse: () => Future.value(<String, dynamic>{}),
    );
  }

  // Helper methods to convert types
  double _convertToDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  int _convertToInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  Map<String, dynamic> _convertMapToStringDynamic(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _convertListToProperType(dynamic value) {
    if (value is List) {
      return value.map((item) {
        if (item is Map<String, dynamic>) return item;
        if (item is Map) return Map<String, dynamic>.from(item);
        return <String, dynamic>{};
      }).toList();
    }
    return <Map<String, dynamic>>[];
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return authState.when(
      initial: () => const Center(child: CircularProgressIndicator()),
      unauthenticated: () => const Center(child: Text('Unauthorized')),
      authenticated: (sid, apiKey, apiSecret, username, email, fullName,
          posProfile, branch, paymentMethods, taxes, hasOpening, tier) {
        return FutureBuilder<Map<String, dynamic>>(
          future: _dashboardData,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }

            final data = snapshot.data ?? <String, dynamic>{};
            final totalSales = data['totalSales'] as double? ?? 0.0;
            final totalCustomers = data['totalCustomers'] as int? ?? 0;
            final todayInfo = data['todayInfo'] as Map<String, dynamic>? ??
                <String, dynamic>{};
            final revenueData =
                data['revenueData'] as List<Map<String, dynamic>>? ??
                    <Map<String, dynamic>>[];
            final peakTimes =
                data['peakTimes'] as List<Map<String, dynamic>>? ??
                    <Map<String, dynamic>>[];
            final topItems = data['topItems'] as List<Map<String, dynamic>>? ??
                <Map<String, dynamic>>[];

            return Container(
              color: Colors.grey[100],
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 10),
                    _buildTopSection(),
                    const SizedBox(height: 20),
                    _buildSummaryCards(totalSales, totalCustomers, todayInfo),
                    const SizedBox(height: 30),
                    _buildRevenueChart(revenueData),
                    const SizedBox(height: 30),
                    Row(
                      children: [
                        Expanded(child: _buildPeakTimeChart(peakTimes)),
                        const SizedBox(width: 20),
                        Expanded(child: _buildTopItemsList(topItems)),
                      ],
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTopSection() {
    return const Row(
      children: [
        Text(
          'Dashboard',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCards(
      double totalSales, int totalCustomers, Map<String, dynamic> todayInfo) {
    final totalRevenue = _convertToDouble(todayInfo['total_revenue']);
    final totalCost = _convertToDouble(todayInfo['total_cost']);
    final profit = totalRevenue - totalCost;

    return Row(
      children: [
        _buildSummaryCard(
          title: 'Total Sales',
          value: 'RM ${totalSales.toStringAsFixed(2)}',
          icon: Icons.attach_money,
        ),
        const SizedBox(width: 15),
        _buildSummaryCard(
          title: 'Total Customers',
          value: NumberFormat.decimalPattern().format(totalCustomers),
          icon: Icons.people,
        ),
        const SizedBox(width: 15),
        _buildSummaryCard(
          title: 'Total Profit',
          value: 'RM ${profit.toStringAsFixed(2)}',
          icon: Icons.trending_up,
          isProfit: profit >= 0,
        ),
      ],
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    bool isProfit = true,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              spreadRadius: 1,
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isProfit ? Colors.green : Colors.red,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRevenueChart(List<Map<String, dynamic>> revenueData) {
    // Process revenue data for chart
    final chartData = revenueData.map((monthData) {
      final monthName =
          DateFormat('MMM').format(DateTime.parse('${monthData['month']}-01'));
      final dineIn = _convertToDouble(monthData['Dine In']);
      final takeAway = _convertToDouble(monthData['Take Away']);
      final delivery = _convertToDouble(monthData['Delivery']);
      final totalRevenue = dineIn + takeAway + delivery;

      return <String, dynamic>{'month': monthName, 'revenue': totalRevenue};
    }).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Total Revenue',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 200,
            child: SfCartesianChart(
              primaryXAxis: CategoryAxis(),
              series: <ColumnSeries<Map<String, dynamic>, String>>[
                ColumnSeries<Map<String, dynamic>, String>(
                  dataSource: chartData,
                  xValueMapper: (data, _) => data['month'] as String,
                  yValueMapper: (data, _) => data['revenue'] as double,
                  color: const Color(0xFFE732A0),
                  borderRadius: BorderRadius.circular(5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeakTimeChart(List<Map<String, dynamic>> peakTimes) {
    // Process peak time data for chart
    final chartData = peakTimes.map((timeData) {
      return <String, dynamic>{
        'time': timeData['time_period'] as String? ?? 'Unknown',
        'count': _convertToInt(timeData['invoice_count']),
      };
    }).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Time Count',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 200,
            child: SfCircularChart(
              series: <DoughnutSeries<Map<String, dynamic>, String>>[
                DoughnutSeries<Map<String, dynamic>, String>(
                  dataSource: chartData,
                  xValueMapper: (data, _) => data['time'] as String,
                  yValueMapper: (data, _) => data['count'] as int,
                  dataLabelSettings: const DataLabelSettings(isVisible: true),
                  radius: '70%',
                  innerRadius: '60%',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopItemsList(List<Map<String, dynamic>> topItems) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Popular Items',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          ...topItems
              .take(5)
              .map((item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(8),
                            image: item['image'] != null
                                ? DecorationImage(
                                    image: NetworkImage(
                                        '$baseImageUrl${item['image'] as String}'),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            item['item_code'] as String? ?? 'Unknown Item',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        Text(
                          '${_convertToInt(item['total_qty_sold'])} sold',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ))
              .toList(),
        ],
      ),
    );
  }
}
