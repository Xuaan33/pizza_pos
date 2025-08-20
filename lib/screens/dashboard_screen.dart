import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shiok_pos_android_app/components/no_stretch_scroll_behavior.dart';
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
  String _selectedTimeRange = 'Daily'; // 'Daily', 'Weekly', 'Monthly', 'Custom'
  DateTimeRange? _customDateRange;
  DateTime _selectedDate = DateTime.now();
  String _selectedPopularItemsLimit = '5';
  int _customLimit = 10;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    setState(() {
      _dashboardData = _loadDashboardData();
    });
  }

  Future<Map<String, dynamic>> _loadDashboardData() async {
    final authState = ref.read(authProvider);
    return authState.maybeWhen(
      authenticated: (sid, apiKey, apiSecret, username, email, fullName,
          posProfile, branch, paymentMethods, taxes, hasOpening, tier) async {
        _posProfile = posProfile;
        final dateFormat = DateFormat('yyyy-MM-dd');

        // Calculate dates based on selected time range
        DateTime fromDate;
        DateTime toDate = _selectedDate;

        switch (_selectedTimeRange) {
          case 'Daily':
            fromDate = toDate;
            break;
          case 'Weekly':
            fromDate = toDate.subtract(Duration(days: toDate.weekday - 1));
            break;
          case 'Monthly':
            fromDate = DateTime(toDate.year, toDate.month, 1);
            break;
          case 'Custom':
            if (_customDateRange != null) {
              fromDate = _customDateRange!.start;
              toDate = _customDateRange!.end;
            } else {
              fromDate = toDate;
            }
            break;
          default:
            fromDate = toDate;
        }

        // Determine limit for popular items
        int limit;
        if (_selectedPopularItemsLimit == 'Custom') {
          limit = _customLimit;
        } else {
          limit = int.parse(_selectedPopularItemsLimit);
        }

        // Fetch all data concurrently
        final results = await Future.wait([
          PosService().makeRequest(
            endpoint:
                'shiok_pos.api.get_total_sales?pos_profile=$posProfile&from_date=${dateFormat.format(fromDate)}&to_date=${dateFormat.format(toDate)}',
          ),
          PosService().makeRequest(
            endpoint:
                'shiok_pos.api.get_peak_time?pos_profile=$posProfile&from_date=${dateFormat.format(fromDate)}&to_date=${dateFormat.format(toDate)}',
          ),
          PosService().getTodayInfo(),
          PosService().makeRequest(
            endpoint: 'shiok_pos.api.get_ltm_revenue?pos_profile=$posProfile',
          ),
          PosService().makeRequest(
            endpoint:
                'shiok_pos.api.get_peak_time?pos_profile=$posProfile&from_date=${dateFormat.format(fromDate)}&to_date=${dateFormat.format(toDate)}',
          ),
          PosService().makeRequest(
            endpoint:
                'shiok_pos.api.get_popular_items?pos_profile=$posProfile&from_date=${dateFormat.format(fromDate)}&to_date=${dateFormat.format(toDate)}&limit=$limit',
          ),
          PosService().getPaymentMethodDistribution(
            // Add this new call
            posProfile: posProfile,
            fromDate: dateFormat.format(fromDate),
            toDate: dateFormat.format(toDate),
          ),
        ]);

        final peakTimes = _convertListToProperType(results[1]['message']);
        final totalOrders = peakTimes.fold(0, (sum, timeData) {
          return sum + _convertToInt(timeData['invoice_count']);
        });

        // After getting peakTimes data
        print('Peak times data: $peakTimes');
        print('Calculated total orders: $totalOrders');

        // Convert to proper types
        return <String, dynamic>{
          'totalSales': _convertToDouble(results[0]['message']),
          'totalOrders': totalOrders,
          'todayInfo': _convertMapToStringDynamic(results[2]['message']),
          'revenueData': _convertListToProperType(results[3]['message']),
          'peakTimes': _convertListToProperType(results[4]['message']),
          'topItems': _convertListToProperType(results[5]['message']),
          'paymentMethods': _convertListToProperType(results[6]['message']),
          'fromDate': fromDate,
          'toDate': toDate,
        };
      },
      orElse: () => Future.value(<String, dynamic>{}),
    );
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _loadData();
      });
    }
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      initialDateRange: _customDateRange ??
          DateTimeRange(
            start: DateTime.now().subtract(const Duration(days: 7)),
            end: DateTime.now(),
          ),
    );
    if (picked != null) {
      setState(() {
        _customDateRange = picked;
        _selectedTimeRange = 'Custom';
        _loadData();
      });
    }
  }

  // Add method to show custom limit dialog
  Future<void> _showCustomLimitDialog() async {
    final TextEditingController limitController = TextEditingController(
      text: _customLimit.toString(),
    );

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text(
            'Custom Limit',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: TextField(
            controller: limitController,
            decoration: const InputDecoration(
              labelText: 'Number of items to show',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
          actions: <Widget>[
            TextButton(
              child: const Text(
                'Cancel',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE732A0),
                foregroundColor: Colors.white,
              ),
              child: const Text(
                'Apply',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                final newLimit = int.tryParse(limitController.text) ?? 10;
                setState(() {
                  _customLimit =
                      newLimit.clamp(1, 50); // Limit to reasonable range
                  _selectedPopularItemsLimit = 'Custom';
                  _loadData();
                });
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  // Helper methods to convert types (keep existing ones)
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
            final totalOrders = data['totalOrders'] as int? ?? 0;
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
            final paymentMethods =
                data['paymentMethods'] as List<Map<String, dynamic>>? ??
                    <Map<String, dynamic>>[];
            final fromDate = data['fromDate'] as DateTime? ?? DateTime.now();
            final toDate = data['toDate'] as DateTime? ?? DateTime.now();

            return Container(
              color: Colors.grey[100],
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 10),
                    _buildTopSection(fromDate, toDate),
                    const SizedBox(height: 20),
                    _buildSummaryCards(totalSales, totalOrders, todayInfo),
                    const SizedBox(height: 30),
                    _buildRevenueChart(revenueData),
                    const SizedBox(height: 30),
                    _buildPaymentMethodChart(paymentMethods),
                    const SizedBox(height: 30),
                    Row(
                      children: [
                        Expanded(child: _buildPeakTimeChart(peakTimes)),
                        const SizedBox(width: 20),
                        Expanded(child: _buildTopItemsList(topItems)),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTopSection(DateTime fromDate, DateTime toDate) {
    String dateRangeText;
    if (_selectedTimeRange == 'Custom') {
      dateRangeText =
          '${DateFormat('dd MMM yyyy').format(fromDate)} - ${DateFormat('dd MMM yyyy').format(toDate)}';
    } else {
      dateRangeText = _selectedTimeRange == 'Daily'
          ? DateFormat('dd MMM yyyy').format(fromDate)
          : '${DateFormat('dd MMM yyyy').format(fromDate)} - ${DateFormat('dd MMM yyyy').format(toDate)}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Dashboard',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            DropdownButton<String>(
              value: _selectedTimeRange,
              style: const TextStyle(
                // Add this style to make dropdown text bold
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
              dropdownColor: Colors.white,
              items:
                  ['Daily', 'Weekly', 'Monthly', 'Custom'].map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: (String? newValue) {
                if (newValue != null) {
                  setState(() {
                    _selectedTimeRange = newValue;
                    if (newValue != 'Custom') {
                      _loadData();
                    } else {
                      _selectDateRange(context);
                    }
                  });
                }
              },
            ),
            const SizedBox(width: 10),
            if (_selectedTimeRange != 'Custom')
              IconButton(
                icon: const Icon(Icons.calendar_today, size: 20),
                onPressed: () => _selectDate(context),
              ),
            const Spacer(),
            Text(
              dateRangeText,
              style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryCards(
      double totalSales, int totalOrders, Map<String, dynamic> todayInfo) {
    final totalRevenue = _convertToDouble(todayInfo['total_revenue']);
    final totalCost = _convertToDouble(todayInfo['total_cost']);
    final profit = totalRevenue - totalCost;
    final averageOrderValue = totalOrders > 0 ? totalSales / totalOrders : 0.0;

    return Row(
      children: [
        _buildSummaryCard(
          title: 'Total Sales',
          value: 'RM ${totalSales.toStringAsFixed(2)}',
          icon: Icons.attach_money,
        ),
        const SizedBox(width: 15),
        _buildSummaryCard(
          title: 'Total Orders',
          value: '${totalOrders}',
          icon: Icons.receipt,
        ),
        const SizedBox(width: 15),
        _buildSummaryCard(
          title: 'Avg Order Value',
          value: 'RM ${averageOrderValue.toStringAsFixed(2)}',
          icon: Icons.calculate,
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

      return <String, dynamic>{
        'month': monthName,
        'monthDate': DateTime.parse('${monthData['month']}-01'),
        'revenue': totalRevenue,
        'dineIn': dineIn,
        'takeAway': takeAway,
        'delivery': delivery,
      };
    }).toList();

    // Sort by date to ensure proper order
    chartData.sort((a, b) =>
        (a['monthDate'] as DateTime).compareTo(b['monthDate'] as DateTime));

    // Find current month index or closest to current date
    final currentDate = DateTime.now();
    int currentMonthIndex = chartData.indexWhere((data) {
      final monthDate = data['monthDate'] as DateTime;
      return monthDate.year == currentDate.year &&
          monthDate.month == currentDate.month;
    });

    // If current month not found, find the closest month
    if (currentMonthIndex == -1) {
      int closestIndex = 0;
      int minDifference = (chartData[0]['monthDate'] as DateTime)
          .difference(currentDate)
          .inDays
          .abs();

      for (int i = 1; i < chartData.length; i++) {
        int difference = (chartData[i]['monthDate'] as DateTime)
            .difference(currentDate)
            .inDays
            .abs();
        if (difference < minDifference) {
          minDifference = difference;
          closestIndex = i;
        }
      }
      currentMonthIndex = closestIndex;
    }

    // Calculate initial visible range (latest 3 months)
    int startIndex = (chartData.length - 3).clamp(0, chartData.length - 3);
    int endIndex = chartData.length - 1;

    // Adjust if we don't have enough data
    if (chartData.length < 3) {
      startIndex = 0;
      endIndex = chartData.length - 1;
    }

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
              primaryXAxis: CategoryAxis(
                // Show all data but allow scrolling
                autoScrollingDelta: 3, // Show 3 months at a time
                autoScrollingMode:
                    AutoScrollingMode.end, // Start from the end (latest months)
              ),
              primaryYAxis: NumericAxis(
                  // Dynamic Y-axis
                  ),
              // Enable zooming and panning
              zoomPanBehavior: ZoomPanBehavior(
                enablePinching: true,
                enablePanning: true,
                enableDoubleTapZooming: true,
                enableMouseWheelZooming: true,
                enableSelectionZooming: false,
                zoomMode: ZoomMode.x, // Only allow horizontal zooming/panning
              ),
              tooltipBehavior: TooltipBehavior(
                enable: true,
                canShowMarker: true,
                activationMode: ActivationMode.singleTap,
                builder: (data, point, series, pointIndex, seriesIndex) {
                  if (pointIndex < 0 || pointIndex >= chartData.length) {
                    return const SizedBox.shrink();
                  }
                  final item = chartData[pointIndex];
                  return Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.3),
                          spreadRadius: 1,
                          blurRadius: 5,
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${item['month']}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text('Total: RM ${item['revenue'].toStringAsFixed(2)}'),
                        if (item['dineIn'] > 0)
                          Text(
                              'Dine In: RM ${item['dineIn'].toStringAsFixed(2)}'),
                        if (item['takeAway'] > 0)
                          Text(
                              'Take Away: RM ${item['takeAway'].toStringAsFixed(2)}'),
                        if (item['delivery'] > 0)
                          Text(
                              'Delivery: RM ${item['delivery'].toStringAsFixed(2)}'),
                      ],
                    ),
                  );
                },
              ),
              trackballBehavior: TrackballBehavior(
                enable: true,
                activationMode: ActivationMode.longPress,
                tooltipDisplayMode: TrackballDisplayMode.groupAllPoints,
                builder: (BuildContext context, TrackballDetails details) {
                  if (details.pointIndex != null &&
                      details.pointIndex! >= 0 &&
                      details.pointIndex! < chartData.length) {
                    final item = chartData[details.pointIndex!];
                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.3),
                            spreadRadius: 1,
                            blurRadius: 5,
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${item['month']}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                              'Total: RM ${item['revenue'].toStringAsFixed(2)}'),
                          if (item['dineIn'] > 0)
                            Text(
                                'Dine In: RM ${item['dineIn'].toStringAsFixed(2)}'),
                          if (item['takeAway'] > 0)
                            Text(
                                'Take Away: RM ${item['takeAway'].toStringAsFixed(2)}'),
                          if (item['delivery'] > 0)
                            Text(
                                'Delivery: RM ${item['delivery'].toStringAsFixed(2)}'),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
              // Load event to set initial visible range
              onChartTouchInteractionUp: (ChartTouchInteractionArgs args) {
                // You can add custom logic here if needed
              },
              series: <ColumnSeries<Map<String, dynamic>, String>>[
                ColumnSeries<Map<String, dynamic>, String>(
                  dataSource: chartData,
                  xValueMapper: (data, _) => data['month'] as String,
                  yValueMapper: (data, _) => data['revenue'] as double,
                  color: const Color(0xFFE732A0),
                  borderRadius: BorderRadius.circular(5),
                  width: 0.2,
                  name: 'Revenue',
                  dataLabelSettings: const DataLabelSettings(
                    isVisible: false,
                  ),
                ),
              ],
            ),
          ),
          // Add instruction text with better styling
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.swipe_left,
                  size: 16,
                  color: Colors.grey[500],
                ),
                const SizedBox(width: 4),
                Text(
                  'Swipe to explore',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.pinch,
                  size: 16,
                  color: Colors.grey[500],
                ),
                const SizedBox(width: 4),
                Text(
                  'Pinch to zoom',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeakTimeChart(List<Map<String, dynamic>> peakTimes) {
    final chartData = peakTimes.map((timeData) {
      return <String, dynamic>{
        'time': timeData['time_period'] as String? ?? 'Unknown',
        'count': _convertToInt(timeData['invoice_count']),
      };
    }).toList();

    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: 315,
        maxHeight: 315,
      ),
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
            const Text(
              'Time Count',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 230,
              child: SfCircularChart(
                legend: Legend(
                  isVisible: true,
                  position: LegendPosition.bottom,
                  overflowMode: LegendItemOverflowMode.wrap,
                ),
                series: <DoughnutSeries<Map<String, dynamic>, String>>[
                  DoughnutSeries<Map<String, dynamic>, String>(
                    dataSource: chartData,
                    xValueMapper: (data, _) => data['time'] as String,
                    yValueMapper: (data, _) => data['count'] as int,
                    dataLabelSettings: const DataLabelSettings(
                      isVisible: true,
                      labelPosition: ChartDataLabelPosition.inside,
                    ),
                    radius: '110%',
                    innerRadius: '60%',
                    // Add legend text mapping
                    pointColorMapper: (data, _) {
                      // You can customize colors here if needed
                      return null; // Let the chart auto-assign colors
                    },
                    name: 'Time Periods', // This will be shown in the legend
                  ),
                ],
              ),
            ),
            if (chartData.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  'Showing data for ${DateFormat('MMM yyyy').format(DateTime.now())}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
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
      constraints: BoxConstraints(
        minHeight: 315,
        maxHeight: 315,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Popular Items',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              DropdownButton<String>(
                value: _selectedPopularItemsLimit,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
                dropdownColor: Colors.white,
                items: ['3', '5', '10', 'Custom'].map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    setState(() {
                      if (newValue == 'Custom') {
                        _showCustomLimitDialog();
                      } else {
                        _selectedPopularItemsLimit = newValue;
                        _loadData();
                      }
                    });
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: topItems
                    .take(_selectedPopularItemsLimit == 'Custom'
                        ? _customLimit
                        : int.parse(_selectedPopularItemsLimit))
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
                                  item['item_code'] as String? ??
                                      'Unknown Item',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                              Text(
                                '${_convertToInt(item['total_qty_sold'])} sold',
                                style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodChart(List<Map<String, dynamic>> paymentMethods) {
    // Filter and sort data
    final filteredMethods = paymentMethods
        .where((method) => _convertToDouble(method['total_paid']) > 0)
        .toList()
      ..sort((a, b) => _convertToDouble(b['total_paid'])
          .compareTo(_convertToDouble(a['total_paid'])));

    final totalAmount = filteredMethods.fold(
        0.0, (sum, method) => sum + _convertToDouble(method['total_paid']));

    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: 315,
        maxHeight: 315,
      ),
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
            const Text(
              'Payment Methods Distribution',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Total: RM ${totalAmount.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 16,
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            if (filteredMethods.isEmpty)
              const Expanded(
                child: Center(
                  child: Text('No payment data available'),
                ),
              )
            else
              Expanded(
                child: ScrollConfiguration(
                  behavior: NoStretchScrollBehavior(),
                  child: ListView(
                    physics: const BouncingScrollPhysics(),
                    shrinkWrap: true,
                    children: filteredMethods.map((method) {
                      final amount = _convertToDouble(method['total_paid']);
                      final percentage =
                          totalAmount > 0 ? (amount / totalAmount * 100) : 0.0;
                      final methodName =
                          method['mode_of_payment'] as String? ?? 'Unknown';

                      // Get payment method image from auth provider
                      final authState = ref.read(authProvider);
                      final paymentMethodData = authState.maybeWhen(
                        authenticated: (sid,
                            apiKey,
                            apiSecret,
                            username,
                            email,
                            fullName,
                            posProfile,
                            branch,
                            paymentMethods,
                            taxes,
                            hasOpening,
                            tier) {
                          return paymentMethods.firstWhere(
                            (pm) => pm['name'] == methodName,
                            orElse: () => {},
                          );
                        },
                        orElse: () => {},
                      );

                      final imageUrl = paymentMethodData[
                                  'custom_payment_mode_image'] !=
                              null
                          ? 'https://shiokpos.byondwave.com${paymentMethodData['custom_payment_mode_image']}'
                          : null;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                if (imageUrl != null)
                                  Container(
                                    width: 40,
                                    height: 40,
                                    margin: const EdgeInsets.only(right: 12),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(6),
                                      image: DecorationImage(
                                        image: NetworkImage(imageUrl),
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  )
                                else
                                  Container(
                                    width: 40,
                                    height: 40,
                                    margin: const EdgeInsets.only(right: 12),
                                    decoration: BoxDecoration(
                                      color: _getPaymentMethodColor(methodName),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Icon(
                                      Icons.payment,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        methodName,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        '${percentage.toStringAsFixed(1)}% of total',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      'RM ${amount.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.green[700],
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 6,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: percentage / 100,
                                  backgroundColor: Colors.grey[200],
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    _getPaymentMethodColor(methodName),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Helper method to assign colors based on payment method
  Color _getPaymentMethodColor(String method) {
    switch (method.toLowerCase()) {
      case 'cash':
        return Colors.green;
      case 'credit card':
        return Colors.purple;
      case 'touch n go':
        return Colors.blue;
      case 'duitnow':
        return Colors.pink;
      default:
        return Colors.grey;
    }
  }
}

// Custom painter for progress bars (more efficient than LinearProgressIndicator)
class _ProgressBarPainter extends CustomPainter {
  final double value;
  final Color color;
  final Color backgroundColor;

  _ProgressBarPainter({
    required this.value,
    required this.color,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw background
    final backgroundPaint = Paint()..color = backgroundColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Radius.circular(size.height / 2),
      ),
      backgroundPaint,
    );

    // Draw progress
    if (value > 0) {
      final progressPaint = Paint()..color = color;
      final progressWidth = size.width * value.clamp(0.0, 1.0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, progressWidth, size.height),
          Radius.circular(size.height / 2),
        ),
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ProgressBarPainter oldDelegate) {
    return value != oldDelegate.value ||
        color != oldDelegate.color ||
        backgroundColor != oldDelegate.backgroundColor;
  }
}
