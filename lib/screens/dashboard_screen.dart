import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shiok_pos_android_app/components/no_stretch_scroll_behavior.dart';
import 'package:shiok_pos_android_app/providers/auth_provider.dart';
import 'package:shiok_pos_android_app/service/pos_service.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';

enum _TimeGrouping { hourly, daily, weekly, monthly }

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  late Future<Map<String, dynamic>> _dashboardData;
  late String _posProfile;
  String baseImageUrl = 'https://harper.briosocialclub.com';
  String _selectedTimeRange = 'Daily'; // 'Daily', 'Weekly', 'Monthly', 'Custom'
  DateTimeRange? _customDateRange;
  DateTime _selectedDate = DateTime.now();
  String _selectedPopularItemsLimit = '10';
  String _selectedVouchersLimit = '10';
  int _customVouchersLimit = 10;
  int _customLimit = 10;
  late Future<double> _payLaterData;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadPayLaterData();
  }

  void _loadData() {
    setState(() {
      _dashboardData = _loadDashboardData();
    });
  }

  void _loadPayLaterData() {
    setState(() {
      _payLaterData = _loadPayLaterAmount();
    });
  }

  Future<double> _loadPayLaterAmount() async {
    final authState = ref.read(authProvider);
    return authState.maybeWhen(
      authenticated: (
        sid,
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
        tier,
        printKitchenOrder,
        openingDate,
        itemsGroups,
      ) async {
        try {
          print('Fetching pay later orders for posProfile: $posProfile');

          final response = await PosService().getOrders(
            posProfile: posProfile,
            status: 'Draft',
            pageLength: 1000,
          );

          print('Raw API response keys: ${response.keys}');
          print('Full response structure: ${response.toString()}');

          // Check if message exists and what it contains
          if (response['message'] == null) {
            print('ERROR: message field is null');
            return 0.0;
          }

          print('Message type: ${response['message'].runtimeType}');
          print('Message content: ${response['message']}');

          // Fix: The orders are nested at response['message']['message']
          final messageData = response['message'] as Map<String, dynamic>?;
          final orders =
              _convertListToProperType(messageData?['message'] ?? []);

          print('Found ${orders.length} draft orders after conversion');

          if (orders.isEmpty) {
            print('WARNING: No orders found after conversion');
            return 0.0;
          }

          // Calculate total and debug each order
          double totalPayLater = 0.0;
          int validOrderCount = 0;

          for (int i = 0; i < orders.length; i++) {
            final order = orders[i];
            final orderName = order['name'] as String? ?? 'Unknown';
            final netTotal = _convertToDouble(order['net_total']);
            final grandTotal = _convertToDouble(order['grand_total']);
            final total = _convertToDouble(order['total']);
            final status = order['status'] as String? ?? 'Unknown';
            final docstatus = order['docstatus'] as int? ?? 1;

            print(
                'Order ${i + 1}/${orders.length}: $orderName, Status: $status, DocStatus: $docstatus');
            print('  - net_total: $netTotal');
            print('  - total: $total');
            print('  - grand_total: $grandTotal');

            // Only include orders with docstatus = 0 (Draft)
            if (docstatus == 0) {
              totalPayLater += netTotal;
              validOrderCount++;
              print(
                  '  ✓ Added to total: $netTotal (Running total: $totalPayLater)');
            } else {
              print('  ✗ Skipped (docstatus != 0)');
            }
          }

          print('===========================================');
          print('Valid draft orders counted: $validOrderCount');
          print('Calculated Total Pay Later Amount: $totalPayLater');
          print('===========================================');

          return totalPayLater;
        } catch (e, stackTrace) {
          print('Error loading pay later data: $e');
          print('Stack trace: $stackTrace');
          return 0.0;
        }
      },
      orElse: () => Future.value(0.0),
    );
  }

  Future<Map<String, dynamic>> _loadDashboardData() async {
    final authState = ref.read(authProvider);
    return authState.maybeWhen(
      authenticated: (
        sid,
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
        tier,
        printKitchenOrder,
        openingDate,
        itemsGroups,
      ) async {
        _posProfile = posProfile;
        final dateFormat = DateFormat('yyyy-MM-dd');

        // Calculate dates based on selected time range
        DateTime fromDate;
        DateTime toDate = _selectedDate;

        switch (_selectedTimeRange) {
          case 'Daily':
            fromDate = toDate;
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

        // Determine limit for applied vouchers
        int vouchersLimit;
        if (_selectedVouchersLimit == 'Custom') {
          vouchersLimit = _customVouchersLimit;
        } else {
          vouchersLimit = int.parse(_selectedVouchersLimit);
        }

        final grouping = _determineTimeGrouping(fromDate, toDate);
        final xaxisParam = _getXAxisParameter(grouping);

        // Fetch all data concurrently - UPDATED: Now 7 futures
        final results = await Future.wait([
          // 0: Total sales
          PosService().makeRequest(
            endpoint:
                'shiok_pos.api.get_total_sales?pos_profile=$posProfile&from_date=${dateFormat.format(fromDate)}&to_date=${dateFormat.format(toDate)}',
          ),
          // 1: Peak time
          PosService().makeRequest(
            endpoint:
                'shiok_pos.api.get_peak_time?pos_profile=$posProfile&from_date=${dateFormat.format(fromDate)}&to_date=${dateFormat.format(toDate)}',
          ),
          // 2: Today info
          PosService().getTodayInfo(),
          // 3: Revenue data
          PosService().makeRequest(
            endpoint: 'shiok_pos.api.get_revenue?'
                'pos_profile=$posProfile&'
                'daterange=["${dateFormat.format(fromDate)}","${dateFormat.format(toDate)}"]&'
                'xaxis=$xaxisParam',
          ),
          // 4: Popular items
          PosService().makeRequest(
            endpoint:
                'shiok_pos.api.get_popular_items?pos_profile=$posProfile&from_date=${dateFormat.format(fromDate)}&to_date=${dateFormat.format(toDate)}&limit=$limit',
          ),
          // 5: Payment methods
          PosService().getPaymentMethodDistribution(
            posProfile: posProfile,
            fromDate: dateFormat.format(fromDate),
            toDate: dateFormat.format(toDate),
          ),
          // 6: Applied vouchers
          PosService().getAppliedUserVouchers(
            posProfile: posProfile,
            fromDate: dateFormat.format(fromDate),
            toDate: dateFormat.format(toDate),
            limit: vouchersLimit,
          ),
        ]);

        final peakTimes = _convertListToProperType(results[1]['message']);
        final totalOrders = peakTimes.fold(0, (sum, timeData) {
          return sum + _convertToInt(timeData['invoice_count']);
        });

        // NEW: Calculate total voucher redemption amount
        final appliedVouchers =
            _convertListToProperType(results[6]['message'] ?? []);
        final totalVoucherRedemption =
            appliedVouchers.fold(0.0, (sum, voucher) {
          return sum + _convertToDouble(voucher['voucher_amount']);
        });

        // Convert to proper types - UPDATED: Include totalVoucherRedemption
        return <String, dynamic>{
          'totalSales': _convertToDouble(results[0]['message']),
          'totalOrders': totalOrders,
          'todayInfo': _convertMapToStringDynamic(results[2]['message']),
          'revenueData': _convertListToProperType(results[3]['message'] ?? []),
          'peakTimes': _convertListToProperType(results[1]['message']),
          'topItems': _convertListToProperType(results[4]['message']),
          'paymentMethods': _convertListToProperType(results[5]['message']),
          'appliedVouchers': appliedVouchers,
          'totalVoucherRedemption': totalVoucherRedemption, // NEW
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
      authenticated: (
        sid,
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
        tier,
        printKitchenOrder,
        openingDate,
        itemsGroups,
      ) {
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
            final appliedVouchers =
                data['appliedVouchers'] as List<Map<String, dynamic>>? ??
                    <Map<String, dynamic>>[];
            final totalVoucherRedemption =
                data['totalVoucherRedemption'] as double? ?? 0.0; // NEW

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
                    _buildSummaryCards(totalSales, totalOrders, todayInfo,
                        totalVoucherRedemption),
                    const SizedBox(height: 30),
                    _buildRevenueChart(revenueData, fromDate, toDate),
                    const SizedBox(height: 30),
                    Row(
                      children: [
                        Expanded(
                            child: _buildPaymentMethodChart(paymentMethods)),
                        const SizedBox(width: 20),
                        Expanded(child: _buildAppliedVouchers(appliedVouchers)),
                      ],
                    ),
                    const SizedBox(height: 30),
                    _buildPayLaterSection(),
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
              items: ['Daily', 'Custom'].map((String value) {
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
            const SizedBox(width: 10),
            Text(
              dateRangeText,
              style: TextStyle(
                  fontSize: 18,
                  color: Colors.black,
                  fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryCards(double totalSales, int totalOrders,
      Map<String, dynamic> todayInfo, double totalVoucherRedemption) {
    // UPDATED: Added parameter
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
        const SizedBox(width: 15),
        // NEW: Total Voucher Redemption card
        _buildSummaryCard(
          title: 'Voucher Redemption',
          value: 'RM ${totalVoucherRedemption.toStringAsFixed(2)}',
          icon: Icons.card_giftcard,
          isProfit: false, // Typically red since it's discount/cost
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

  Widget _buildRevenueChart(List<Map<String, dynamic>> revenueData,
      DateTime fromDate, DateTime toDate) {
    final grouping = _determineTimeGrouping(fromDate, toDate);

    // Process revenue data for chart
    final chartData = revenueData.map((periodData) {
      final xaxisValue = periodData['xaxis'] as String? ?? '';
      final dineIn = _convertToDouble(periodData['Dine In']);
      final takeAway = _convertToDouble(periodData['Take Away']);
      final delivery = _convertToDouble(periodData['Delivery']);
      final totalRevenue = dineIn + takeAway + delivery;

      return <String, dynamic>{
        'period': _formatXAxisLabel(xaxisValue, grouping),
        'rawPeriod': xaxisValue,
        'revenue': totalRevenue,
        'dineIn': dineIn,
        'takeAway': takeAway,
        'delivery': delivery,
        'grouping': grouping,
      };
    }).toList();

    // Sort data chronologically
    chartData.sort((a, b) {
      switch (grouping) {
        case _TimeGrouping.hourly:
          return (a['rawPeriod'] as String).compareTo(b['rawPeriod'] as String);
        case _TimeGrouping.daily:
          return DateTime.parse(a['rawPeriod'] as String)
              .compareTo(DateTime.parse(b['rawPeriod'] as String));
        case _TimeGrouping.weekly:
          // Handle format "2025-07-21 - 2025-07-27"
          if ((a['rawPeriod'] as String).contains(' - ')) {
            final aDates = (a['rawPeriod'] as String).split(' - ');
            final bDates = (b['rawPeriod'] as String).split(' - ');
            if (aDates.length == 2 && bDates.length == 2) {
              return DateTime.parse(aDates[0])
                  .compareTo(DateTime.parse(bDates[0]));
            }
          }
          return (a['rawPeriod'] as String).compareTo(b['rawPeriod'] as String);
        case _TimeGrouping.monthly:
          return DateTime.parse('${a['rawPeriod'] as String}-01')
              .compareTo(DateTime.parse('${b['rawPeriod'] as String}-01'));
      }
    });

    // Build stacked column series for better visualization
    final series = <CartesianSeries>[
      StackedColumnSeries<Map<String, dynamic>, String>(
        dataSource: chartData,
        xValueMapper: (data, _) => data['period'] as String,
        yValueMapper: (data, _) => data['dineIn'] as double,
        name: 'Dine In',
        color: Colors.blue,
      ),
      StackedColumnSeries<Map<String, dynamic>, String>(
        dataSource: chartData,
        xValueMapper: (data, _) => data['period'] as String,
        yValueMapper: (data, _) => data['takeAway'] as double,
        name: 'Take Away',
        color: Colors.green,
      ),
      StackedColumnSeries<Map<String, dynamic>, String>(
        dataSource: chartData,
        xValueMapper: (data, _) => data['period'] as String,
        yValueMapper: (data, _) => data['delivery'] as double,
        name: 'Delivery',
        color: Colors.orange,
      ),
    ];

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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Revenue Breakdown',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Chip(
                label: Text(
                  _getGroupingLabel(grouping),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold),
                ),
                backgroundColor: Colors.white,
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: grouping == _TimeGrouping.weekly
                ? 300
                : 250, // Increase height for weekly
            child: SfCartesianChart(
              primaryXAxis: CategoryAxis(
                labelRotation: (chartData.length > 10 ? 45 : 0),
                labelIntersectAction: AxisLabelIntersectAction.wrap,
                interval: grouping == _TimeGrouping.weekly ? 1 : null,
              ),
              primaryYAxis: NumericAxis(
                numberFormat: NumberFormat.compactCurrency(symbol: 'RM '),
              ),
              legend: Legend(
                isVisible: true,
                position: LegendPosition.bottom,
              ),
              tooltipBehavior: TooltipBehavior(enable: true),
              series: series,
            ),
          ),
        ],
      ),
    );
  }

  String _getGroupingLabel(_TimeGrouping grouping) {
    switch (grouping) {
      case _TimeGrouping.hourly:
        return 'Hourly';
      case _TimeGrouping.daily:
        return 'Daily';
      case _TimeGrouping.weekly:
        return 'Weekly';
      case _TimeGrouping.monthly:
        return 'Monthly';
    }
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
                items: ['10', '30', '50', 'Custom'].map((String value) {
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
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: item['image'] != null
                                      ? Image.network(
                                          '$baseImageUrl${item['image'] as String}',
                                          width: 40,
                                          height: 40,
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (context, error, stackTrace) {
                                            return Image.asset(
                                              'assets/pizza.png',
                                              width: 40,
                                              height: 40,
                                              fit: BoxFit.cover,
                                            );
                                          },
                                        )
                                      : Image.asset(
                                          'assets/pizza.png',
                                          width: 40,
                                          height: 40,
                                          fit: BoxFit.cover,
                                        ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  item['item_name'] as String? ??
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
                        authenticated: (
                          sid,
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
                          tier,
                          printKitchenOrder,
                          openingDate,
                          itemsGroups,
                        ) {
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
                          ? 'https://harper.briosocialclub.com${paymentMethodData['custom_payment_mode_image']}'
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
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: Image.network(
                                        imageUrl,
                                        width: 40,
                                        height: 40,
                                        fit: BoxFit.contain,
                                        errorBuilder:
                                            (context, error, stackTrace) {
                                          return Container(
                                            color: _getPaymentMethodColor(
                                                methodName),
                                            child: const Icon(Icons.payment,
                                                color: Colors.white, size: 20),
                                          );
                                        },
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

  Widget _buildAppliedVouchers(List<Map<String, dynamic>> appliedVouchers) {
    // Calculate total voucher amount
    final totalVoucherAmount = appliedVouchers.fold(0.0, (sum, voucher) {
      return sum + _convertToDouble(voucher['voucher_amount']);
    });

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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Applied Vouchers',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                // NEW: Dropdown for vouchers limit
                DropdownButton<String>(
                  value: _selectedVouchersLimit,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                  dropdownColor: Colors.white,
                  items: ['10', '30', '50', 'Custom'].map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                      setState(() {
                        if (newValue == 'Custom') {
                          _showCustomVouchersLimitDialog();
                        } else {
                          _selectedVouchersLimit = newValue;
                          _loadData();
                        }
                      });
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Total Discount: RM ${totalVoucherAmount.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 16,
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            if (appliedVouchers.isEmpty)
              const Expanded(
                child: Center(
                  child: Text(
                    'No vouchers applied',
                    style: TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: ScrollConfiguration(
                  behavior: NoStretchScrollBehavior(),
                  child: ListView(
                    physics: const BouncingScrollPhysics(),
                    shrinkWrap: true,
                    children: appliedVouchers.map((voucher) {
                      final voucherCode =
                          voucher['voucher_code'] as String? ?? 'Unknown';
                      final userVoucher =
                          voucher['user_voucher'] as String? ?? 'Unknown';
                      final amount =
                          _convertToDouble(voucher['voucher_amount']);
                      final orderID = voucher['name'] as String? ?? 'Unknown';
                      final voucherName =
                          voucher['name'] as String? ?? 'Unknown';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        voucherCode,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFFE732A0),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Code: $userVoucher',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.black,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Order: $orderID',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.black,
                                          fontStyle: FontStyle.italic,
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
                                    Text(
                                      'Discount',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              height: 6,
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: 1.0, // Full width for consistency
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE732A0),
                                    borderRadius: BorderRadius.circular(3),
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

  Widget _buildPayLaterSection() {
    return FutureBuilder<double>(
      future: _payLaterData,
      builder: (context, snapshot) {
        double payLaterAmount = 0.0;
        bool hasError = false;
        bool isLoading = false;

        if (snapshot.connectionState == ConnectionState.waiting) {
          isLoading = true;
        } else if (snapshot.hasError) {
          payLaterAmount = 0.0;
          hasError = true;
          print('Pay Later Error: ${snapshot.error}');
        } else {
          payLaterAmount = snapshot.data ?? 0.0;
          isLoading = false;
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.payment, size: 20, color: Colors.orange[700]),
                      const SizedBox(width: 8),
                      const Text(
                        'Pay Later Summary',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.refresh,
                      color: isLoading ? Colors.grey : Colors.orange[700],
                    ),
                    onPressed: isLoading
                        ? null
                        : () {
                            _loadPayLaterData();
                          },
                    tooltip: 'Refresh Pay Later Data',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Total Outstanding Amount',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              if (isLoading)
                const CircularProgressIndicator()
              else
                Text(
                  'RM ${payLaterAmount.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: hasError
                        ? Colors.red
                        : (payLaterAmount > 0
                            ? Colors.orange[700]
                            : Colors.green),
                  ),
                ),
              const SizedBox(height: 8),
              if (isLoading)
                Text(
                  'Loading pay later data...',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                )
              else if (hasError)
                Text(
                  'Error loading pay later data',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.red,
                  ),
                )
              else
                Text(
                  'Total amount from all pending Pay Later orders (Draft status)',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
              if (payLaterAmount > 0 && !isLoading && !hasError) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 16, color: Colors.orange[700]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Collect payments from customers to complete these orders',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _showCustomVouchersLimitDialog() async {
    final TextEditingController limitController = TextEditingController(
      text: _customVouchersLimit.toString(),
    );

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text(
            'Custom Vouchers Limit',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: TextField(
            controller: limitController,
            decoration: const InputDecoration(
              labelText: 'Number of vouchers to show',
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
                  _customVouchersLimit =
                      newLimit.clamp(1, 50); // Limit to reasonable range
                  _selectedVouchersLimit = 'Custom';
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

  _TimeGrouping _determineTimeGrouping(DateTime fromDate, DateTime toDate) {
    final difference = toDate.difference(fromDate).inDays;

    if (difference == 0) {
      // Same day - show hourly
      return _TimeGrouping.hourly;
    } else if (difference <= 21) {
      // Up to 3 weeks - show daily
      return _TimeGrouping.daily;
    } else if (difference <= 60) {
      // Up to 2 months - show weekly
      return _TimeGrouping.weekly;
    } else {
      // More than 2 months - show monthly
      return _TimeGrouping.monthly;
    }
  }

  String _getXAxisParameter(_TimeGrouping grouping) {
    switch (grouping) {
      case _TimeGrouping.hourly:
        return 'hour';
      case _TimeGrouping.daily:
        return 'day';
      case _TimeGrouping.weekly:
        return 'week';
      case _TimeGrouping.monthly:
        return 'month';
    }
  }

  String _formatXAxisLabel(String xaxisValue, _TimeGrouping grouping) {
    switch (grouping) {
      case _TimeGrouping.hourly:
        // Format: "HH:00" (e.g., "14:00")
        final time = xaxisValue.split(' ').last;
        return time.substring(0, 5); // Get "HH:MM"
      case _TimeGrouping.daily:
        // Format: "DD MMM" (e.g., "15 Jan")
        return DateFormat('dd MMM').format(DateTime.parse(xaxisValue));
      case _TimeGrouping.weekly:
        // Handle the format "2025-07-21 - 2025-07-27"
        if (xaxisValue.contains(' - ')) {
          final dates = xaxisValue.split(' - ');
          if (dates.length == 2) {
            try {
              final startDate = DateTime.parse(dates[0]);
              final endDate = DateTime.parse(dates[1]);
              return '${DateFormat('dd MMM').format(startDate)} - ${DateFormat('dd MMM').format(endDate)}';
            } catch (e) {
              return xaxisValue;
            }
          }
        }
        return xaxisValue;
      case _TimeGrouping.monthly:
        // Format: "MMM YY" (e.g., "Jan 23")
        return DateFormat('MMM yy').format(DateTime.parse('$xaxisValue-01'));
    }
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
