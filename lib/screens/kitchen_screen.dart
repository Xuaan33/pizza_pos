import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shiok_pos_android_app/components/main_layout.dart';
import 'package:shiok_pos_android_app/components/receipt_printer.dart';
import 'package:shiok_pos_android_app/providers/auth_provider.dart';
import 'package:shiok_pos_android_app/service/pos_service.dart';
import 'package:fluttertoast/fluttertoast.dart';

class KitchenScreen extends ConsumerStatefulWidget {
  const KitchenScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends ConsumerState<KitchenScreen> {
  List<Map<String, dynamic>> _kitchenStations = [];
  List<Map<String, dynamic>> _kitchenOrders = [];
  List<Map<String, dynamic>> _grabOrders = [];
  String? _selectedKitchenStation;
  bool _isLoadingStations = true;
  bool _isLoadingOrders = false;
  DateTime _selectedDate = DateTime.now();
  int _selectedTabIndex = 0; // 0: Pending, 1: Done
  bool _showGrabStation = false; // Will be set based on tier - Tier 3 only
  String _userTier = ''; // Store user tier

  @override
  void initState() {
    super.initState();
    _loadKitchenStations();
  }

  @override
  void dispose() {
    // Clear any potential pending operations
    super.dispose();
  }

  Future<void> _loadKitchenStations() async {
    if (!mounted) return;

    setState(() => _isLoadingStations = true);

    final authState = ref.read(authProvider);
    await authState.whenOrNull(
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
        baseUrl,
        merchantId,
        printMerchantReceiptCopy,
        enableFiuu,
        cashDrawerPinNeeded,
        cashDrawerPin,
      ) async {
        try {
          final response = await MainLayout.of(context)!
              .safeExecuteAPICall(() => PosService().getKitchenStations(
                    posProfile: posProfile,
                  ));

          if (!mounted) return;

          if (response['success'] == true) {
            final stations = (response['message'] as List?) ?? [];

            // Check if user is Tier 3 - only Tier 3 can see GRAB
            final isTier3 = tier.toLowerCase() == 'tier 3';

            setState(() {
              _kitchenStations = stations.cast<Map<String, dynamic>>();
              _userTier = tier; // Store tier for reference
              _showGrabStation = isTier3; // Only show GRAB for Tier 3

              if (_kitchenStations.isNotEmpty) {
                // Default to GRAB station if Tier 3, otherwise first kitchen station
                if (isTier3) {
                  _selectedKitchenStation = 'GRAB';
                  _loadGrabOrders();
                } else {
                  _selectedKitchenStation = _kitchenStations[0]['name'];
                  _loadKitchenOrders();
                }
              }
            });

            debugPrint('👤 User Tier: $tier');
            debugPrint('🍔 Show GRAB Station: $_showGrabStation');
            debugPrint('📍 Selected Station: $_selectedKitchenStation');
          }
        } catch (e) {
          print('Error loading kitchen stations: $e');
        }
      },
    );
    if (mounted) {
      setState(() => _isLoadingStations = false);
    }
  }

  Future<void> _loadKitchenOrders() async {
    if (!mounted) return;
    if (_selectedKitchenStation == null || !mounted) return;

    // If GRAB station is selected, use grab orders (Tier 3 only)
    if (_selectedKitchenStation == 'GRAB') {
      if (!_showGrabStation) {
        // Safety check: If not Tier 3, switch to first kitchen station
        debugPrint(
            '⚠️ GRAB not available for ${_userTier}, switching to first kitchen station');
        if (_kitchenStations.isNotEmpty) {
          setState(() {
            _selectedKitchenStation = _kitchenStations[0]['name'];
          });
          _loadKitchenOrders();
        }
        return;
      }
      _loadGrabOrders();
      return;
    }

    if (mounted) {
      setState(() => _isLoadingOrders = true);
    }

    final authState = ref.read(authProvider);
    await authState.whenOrNull(
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
        baseUrl,
        merchantId,
        printMerchantReceiptCopy,
        enableFiuu,
        cashDrawerPinNeeded,
        cashDrawerPin,
      ) async {
        try {
          final fromDate = DateFormat('yyyy-MM-dd').format(_selectedDate);
          final toDate = DateFormat('yyyy-MM-dd').format(_selectedDate);

          final response = await MainLayout.of(context)!
              .safeExecuteAPICall(() => PosService().getKitchenOrders(
                    posProfile: posProfile,
                    kitchenStation: _selectedKitchenStation!,
                    fromDate: fromDate,
                    toDate: toDate,
                  ));

          if (!mounted) return;

          if (response['success'] == true) {
            final orders = (response['message'] as List?) ?? [];
            if (mounted) {
              setState(() {
                _kitchenOrders = orders.cast<Map<String, dynamic>>();
              });
            }
          }
        } catch (e) {
          print('Error loading kitchen orders: $e');
        }
      },
    );

    if (mounted) {
      setState(() => _isLoadingOrders = false);
    }
  }

  Future<void> _loadGrabOrders() async {
    // Only load GRAB orders for Tier 3
    if (!_showGrabStation) {
      debugPrint('⚠️ GRAB orders not available for ${_userTier}');
      return;
    }

    if (!mounted) return;

    if (mounted && _selectedKitchenStation != 'GRAB') {
      setState(() => _isLoadingOrders = true);
    }

    final authState = ref.read(authProvider);
    await authState.whenOrNull(
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
        baseUrl,
        merchantId,
        printMerchantReceiptCopy,
        enableFiuu,
        cashDrawerPinNeeded,
        cashDrawerPin,
      ) async {
        try {
          final fromDate = DateFormat('yyyy-MM-dd').format(_selectedDate);
          final toDate = DateFormat('yyyy-MM-dd').format(_selectedDate);

          // Find a real kitchen station to use for the API call
          final firstStation =
              _kitchenStations.isNotEmpty ? _kitchenStations.first['name'] : '';

          final response = await MainLayout.of(context)!
              .safeExecuteAPICall(() => PosService().getKitchenOrders(
                    posProfile: posProfile,
                    kitchenStation: firstStation,
                    fromDate: fromDate,
                    toDate: toDate,
                    orderSource: 'grab', // Add this parameter for GRAB orders
                  ));

          if (!mounted) return;

          if (response['success'] == true) {
            final orders = (response['message'] as List?) ?? [];
            if (mounted) {
              setState(() {
                _grabOrders = orders.cast<Map<String, dynamic>>();
              });
            }
          }
        } catch (e) {
          print('Error loading GRAB orders: $e');
        }
      },
    );

    if (mounted && _selectedKitchenStation != 'GRAB') {
      setState(() => _isLoadingOrders = false);
    }
  }

  Future<void> _fulfillItem(String posInvoiceItem, bool fulfilled) async {
    try {
      final response = await MainLayout.of(context)!
          .safeExecuteAPICall(() => PosService().fulfillKitchenItem(
                posInvoiceItem: posInvoiceItem,
                fulfilled: fulfilled ? 1 : 0,
              ));
      if (!mounted) return;

      if (response['success'] == true) {
        // Reload appropriate orders based on current station
        if (_selectedKitchenStation == 'GRAB') {
          _loadGrabOrders();
        } else {
          _loadKitchenOrders();
        }

        if (mounted) {
          Fluttertoast.showToast(
            msg: fulfilled ? 'Item marked as fulfilled' : 'Item unmarked',
            toastLength: Toast.LENGTH_SHORT,
            gravity: ToastGravity.BOTTOM,
            backgroundColor: Colors.green,
            textColor: Colors.white,
            fontSize: 16.0,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Fluttertoast.showToast(
          msg: 'Error updating item: $e',
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
          fontSize: 16.0,
        );
      }
    }
  }

  Future<void> _fulfillOrder(String posInvoice, bool fulfilled) async {
    if (_selectedKitchenStation == null || !mounted)
      return; // Add mounted check

    try {
      final response = await MainLayout.of(context)!
          .safeExecuteAPICall(() => PosService().fulfillKitchenOrder(
                posInvoice: posInvoice,
                kitchenStation: _selectedKitchenStation!,
                fulfilled: fulfilled ? 1 : 0,
              ));
      if (!mounted) return; // Check after async operation

      if (response['success'] == true) {
        // Reload appropriate orders based on current station
        if (_selectedKitchenStation == 'GRAB') {
          _loadGrabOrders();
        } else {
          _loadKitchenOrders();
        }

        if (mounted) {
          // Check before showing toast
          Fluttertoast.showToast(
            msg: fulfilled ? 'Order marked as fulfilled' : 'Order unmarked',
            toastLength: Toast.LENGTH_SHORT,
            gravity: ToastGravity.BOTTOM,
            backgroundColor: Colors.green,
            textColor: Colors.white,
            fontSize: 16.0,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        // Check before showing toast
        Fluttertoast.showToast(
          msg: 'Error updating order: $e',
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
          fontSize: 16.0,
        );
      }
    }
  }

  Widget _buildVariantInfo(Map<String, dynamic> item) {
    final variantInfo = item['custom_variant_info'];
    if (variantInfo == null) return SizedBox();

    try {
      dynamic parsed =
          variantInfo is String ? jsonDecode(variantInfo) : variantInfo;

      if (parsed is List && parsed.isNotEmpty) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: parsed.expand((variant) {
            if (variant is Map && variant['options'] is List) {
              return (variant['options'] as List).take(3).map((option) {
                return Padding(
                  padding: const EdgeInsets.only(left: 4.0, top: 2.0),
                  child: Text(
                    '• ${variant['variant_group']}: ${option['option']}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList();
            }
            return <Widget>[];
          }).toList(),
        );
      }
    } catch (e) {
      print('Error parsing variant info: $e');
    }

    return SizedBox();
  }

  // Build Serve Later tag
  Widget _buildServeLaterTag() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.purple[50],
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: Colors.purple,
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schedule,
            size: 12,
            color: Colors.purple[700],
          ),
          SizedBox(width: 4),
          Text(
            'Serve Later',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.purple[700],
            ),
          ),
        ],
      ),
    );
  }

  // Build GRAB order tag
  Widget _buildGrabTag() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Color(0xFF00B14F).withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: Color(0xFF00B14F),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/icon-grab.png',
            width: 12,
            height: 12,
          ),
          SizedBox(width: 4),
          Text(
            'GRAB',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Color(0xFF00B14F),
            ),
          ),
        ],
      ),
    );
  }

  Color _getUrgencyColor(String? orderTime) {
    if (orderTime == null) return Colors.grey;
    try {
      final time = DateTime.parse(orderTime);
      final minutes = DateTime.now().difference(time).inMinutes;
      if (minutes > 30) return Colors.red;
      if (minutes > 15) return Colors.orange;
      return Colors.green;
    } catch (e) {
      return Colors.grey;
    }
  }

  // Get pending orders (not fully fulfilled) for current station
  List<Map<String, dynamic>> get _pendingOrders {
    if (_selectedKitchenStation == 'GRAB') {
      return _grabOrders.where((order) {
        return order['custom_fulfilled'] != 1;
      }).toList();
    } else {
      return _kitchenOrders.where((order) {
        return order['custom_fulfilled'] != 1;
      }).toList();
    }
  }

  // Get completed orders (fully fulfilled) for current station
  List<Map<String, dynamic>> get _completedOrders {
    if (_selectedKitchenStation == 'GRAB') {
      return _grabOrders.where((order) {
        return order['custom_fulfilled'] == 1;
      }).toList();
    } else {
      return _kitchenOrders.where((order) {
        return order['custom_fulfilled'] == 1;
      }).toList();
    }
  }

  // Count unread GRAB orders (pending orders)
  int get _unreadGrabCount {
    return _grabOrders.where((order) {
      return order['custom_fulfilled'] != 1;
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Fulfilment Queue",
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
                // Date selector
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.grey.shade300, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextButton.icon(
                    onPressed: () async {
                      final DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(Duration(days: 365)),
                      );
                      if (picked != null && picked != _selectedDate) {
                        setState(() => _selectedDate = picked);
                        if (_selectedKitchenStation == 'GRAB') {
                          _loadGrabOrders();
                        } else {
                          _loadKitchenOrders();
                        }
                      }
                    },
                    icon: Icon(Icons.calendar_today, size: 20),
                    label: Text(
                      DateFormat('dd MMM yyyy').format(_selectedDate),
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding:
                          EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 10),

            // Kitchen Station Pill Buttons (including GRAB)
            _isLoadingStations
                ? Center(child: CircularProgressIndicator())
                : Container(
                    height: 60,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount:
                          _kitchenStations.length + (_showGrabStation ? 1 : 0),
                      itemBuilder: (context, index) {
                        // First item is GRAB station
                        if (index == 0 && _showGrabStation) {
                          final isSelected = _selectedKitchenStation == 'GRAB';
                          return Container(
                            height: 60, // ✅ Match the ListView height
                            alignment: Alignment.center, // ✅ Center vertically
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  margin: EdgeInsets.only(right: 12),
                                  child: ChoiceChip(
                                    label: Row(
                                      children: [
                                        Image.asset(
                                          'assets/icon-grab.png',
                                          width: 20,
                                          height: 20,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'GRAB',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            color: isSelected
                                                ? Colors.white
                                                : Colors.black87,
                                          ),
                                        ),
                                      ],
                                    ),
                                    selected: isSelected,
                                    onSelected: (selected) {
                                      setState(() {
                                        _selectedKitchenStation = 'GRAB';
                                      });
                                      _loadGrabOrders();
                                    },
                                    selectedColor:
                                        Color(0xFF00B14F), // Grab green
                                    backgroundColor: Colors.white,
                                    side: BorderSide(
                                      color: isSelected
                                          ? Color(0xFF00B14F)
                                          : Colors.grey.shade300,
                                      width: 2,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 10,
                                    ),
                                  ),
                                ),
                                // Unread notification badge for GRAB
                                if (_unreadGrabCount > 0 && !isSelected)
                                  Positioned(
                                    top: -6,
                                    right: 0,
                                    child: Container(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.red,
                                        borderRadius: BorderRadius.circular(10),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.red.withOpacity(0.3),
                                            blurRadius: 4,
                                            spreadRadius: 1,
                                          ),
                                        ],
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 2,
                                        ),
                                      ),
                                      constraints: BoxConstraints(
                                        minWidth: 20,
                                        minHeight: 20,
                                      ),
                                      child: Center(
                                        child: Text(
                                          _unreadGrabCount > 99
                                              ? '99+'
                                              : _unreadGrabCount.toString(),
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }

                        // Regular kitchen stations
                        final stationIndex = index - (_showGrabStation ? 1 : 0);
                        if (stationIndex >= 0 &&
                            stationIndex < _kitchenStations.length) {
                          final station = _kitchenStations[stationIndex];
                          final isSelected =
                              _selectedKitchenStation == station['name'];

                          return Container(
                            margin: EdgeInsets.only(right: 12),
                            child: ChoiceChip(
                              label: Text(
                                station['title'] ?? station['name'],
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.black87,
                                ),
                              ),
                              selected: isSelected,
                              onSelected: (selected) {
                                setState(() {
                                  _selectedKitchenStation = station['name'];
                                });
                                _loadKitchenOrders();
                              },
                              selectedColor: Color(0xFFE732A0),
                              backgroundColor: Colors.white,
                              side: BorderSide(
                                color: isSelected
                                    ? Color(0xFFE732A0)
                                    : Colors.grey.shade300,
                                width: 2,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              padding: EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                            ),
                          );
                        }

                        return SizedBox.shrink();
                      },
                    ),
                  ),

            SizedBox(height: 16),

            // Pending/Done Tabs (only for non-GRAB stations)
            if (_selectedKitchenStation != 'GRAB')
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildTabButton(
                        index: 0,
                        label: 'Pending',
                        count: _pendingOrders.length,
                        isSelected: _selectedTabIndex == 0,
                      ),
                    ),
                    Expanded(
                      child: _buildTabButton(
                        index: 1,
                        label: 'Done',
                        count: _completedOrders.length,
                        isSelected: _selectedTabIndex == 1,
                      ),
                    ),
                  ],
                ),
              )
            else
              // GRAB Orders Summary Header
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Color(0xFF00B14F).withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Color(0xFF00B14F).withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildGrabStatCard(
                      'Pending',
                      _pendingOrders.length.toString(),
                      Colors.orange,
                    ),
                    _buildGrabStatCard(
                      'Completed',
                      _completedOrders.length.toString(),
                      Colors.green,
                    ),
                    _buildGrabStatCard(
                      'Total',
                      _grabOrders.length.toString(),
                      Color(0xFF00B14F),
                    ),
                  ],
                ),
              ),

            SizedBox(height: 16),

            // Orders Grid based on selected tab/station
            Expanded(
              child: _isLoadingOrders
                  ? Center(child: CircularProgressIndicator())
                  : _buildOrdersGrid(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton({
    required int index,
    required String label,
    required int count,
    required bool isSelected,
  }) {
    return Material(
      color: isSelected ? Color(0xFFE732A0) : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedTabIndex = index;
          });
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : Colors.grey[700],
                ),
              ),
              SizedBox(height: 4),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : Color(0xFFE732A0),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Color(0xFFE732A0) : Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGrabStatCard(String title, String value, Color color) {
    return Column(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 4),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color, width: 1.5),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOrdersGrid() {
    final isGrabStation = _selectedKitchenStation == 'GRAB';

    if (isGrabStation) {
      // GRAB station - show all grab orders
      final orders = _grabOrders;

      if (orders.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/icon-grab.png',
                width: 80,
                height: 80,
                color: Colors.grey[400],
              ),
              SizedBox(height: 20),
              Text(
                'No GRAB orders for selected date',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      }

      return GridView.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 0.75,
        ),
        itemCount: orders.length,
        itemBuilder: (context, index) {
          final order = orders[index];
          final items = (order['items'] as List?) ?? [];
          final isOrderFulfilled = order['custom_fulfilled'] == 1;
          final unfulfilledItems =
              items.where((item) => item['custom_fulfilled'] != 1).length;

          return _buildOrderCard(
            order: order,
            items: items,
            isOrderFulfilled: isOrderFulfilled,
            unfulfilledItems: unfulfilledItems,
            showInDoneTab: false, // GRAB station doesn't have Done tab
            isGrabOrder: true,
          );
        },
      );
    } else {
      // Regular kitchen station - show pending/done based on selected tab
      final orders = _selectedTabIndex == 0 ? _pendingOrders : _completedOrders;

      if (orders.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _selectedTabIndex == 0
                    ? Icons.restaurant_menu
                    : Icons.check_circle,
                size: 80,
                color: Colors.grey[400],
              ),
              SizedBox(height: 20),
              Text(
                _selectedTabIndex == 0
                    ? 'No pending orders for selected date'
                    : 'No completed orders for selected date',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      }

      return GridView.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 0.75,
        ),
        itemCount: orders.length,
        itemBuilder: (context, index) {
          final order = orders[index];
          final items = (order['items'] as List?) ?? [];
          final isOrderFulfilled = order['custom_fulfilled'] == 1;
          final unfulfilledItems =
              items.where((item) => item['custom_fulfilled'] != 1).length;

          return _buildOrderCard(
            order: order,
            items: items,
            isOrderFulfilled: isOrderFulfilled,
            unfulfilledItems: unfulfilledItems,
            showInDoneTab: _selectedTabIndex == 1,
            isGrabOrder: false,
          );
        },
      );
    }
  }

  Widget _buildOrderCard({
    required Map<String, dynamic> order,
    required List<dynamic> items,
    required bool isOrderFulfilled,
    required int unfulfilledItems,
    bool showInDoneTab = false,
    bool isGrabOrder = false,
  }) {
    final urgencyColor = _getUrgencyColor(order['order_time']);
    final isTableGrab =
        (order['table']?.toString() ?? '').toUpperCase().contains('GRAB');

    return Card(
      elevation: isOrderFulfilled ? 1 : 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isOrderFulfilled
              ? (isGrabOrder ? Color(0xFF00B14F) : Colors.green)
              : (isGrabOrder ? Color(0xFF00B14F) : urgencyColor),
          width: 3,
        ),
      ),
      color: isOrderFulfilled
          ? (isGrabOrder
              ? Color(0xFF00B14F).withOpacity(0.05)
              : Colors.green[50])
          : Colors.white,
      child: Container(
        constraints: BoxConstraints(minHeight: 75, maxHeight: 75),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Order Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'ORDER',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[600],
                                letterSpacing: 1,
                              ),
                            ),
                            SizedBox(width: 8),
                            if (isGrabOrder || isTableGrab) _buildGrabTag(),
                          ],
                        ),
                        SizedBox(height: 2),
                        Text(
                          '#${order['name']?.toString().split('-').last ?? 'N/A'}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 24,
                            color: isGrabOrder
                                ? Color(0xFF00B14F)
                                : Colors.black87,
                          ),
                        ),
                        SizedBox(height: 2),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isGrabOrder
                                ? Color(0xFF00B14F).withOpacity(0.1)
                                : Color(0xFFE732A0).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isGrabOrder
                                  ? Color(0xFF00B14F)
                                  : Color(0xFFE732A0),
                              width: 1.5,
                            ),
                          ),
                          child: Text(
                            '${isTableGrab ? 'GRAB' : 'TABLE'} ${order['table']?.toString() ?? 'N/A'}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isGrabOrder
                                  ? Color(0xFF00B14F)
                                  : Color(0xFFE732A0),
                            ),
                          ),
                        ),
                        if (order['order_time'] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              _formatTime(order['order_time']),
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Print Order Button
                  Container(
                    width: 60,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isGrabOrder ? Color(0xFF00B14F) : Colors.blue,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 20,
                      onPressed: () => _showPrintSelectionDialog(order),
                      icon: Text(
                        'PRINT',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: 10),

              // Progress indicator (only show in pending tab for non-GRAB orders)
              if (!isOrderFulfilled && !showInDoneTab && !isGrabOrder)
                Column(
                  children: [
                    if (items.length > 0)
                      LinearProgressIndicator(
                        value: (items.length - unfulfilledItems) / items.length,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(urgencyColor),
                        minHeight: 6,
                      )
                    else
                      LinearProgressIndicator(
                        value: 0,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(urgencyColor),
                        minHeight: 6,
                      ),
                    SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        items.length > 0
                            ? '${items.length - unfulfilledItems}/${items.length} completed'
                            : '0/0 completed',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),

              SizedBox(height: 10),

              // Items List (Scrollable)
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: isGrabOrder
                          ? Color(0xFF00B14F).withOpacity(0.3)
                          : Colors.grey[300]!,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    color: isGrabOrder
                        ? Color(0xFF00B14F).withOpacity(0.05)
                        : Colors.grey[50],
                  ),
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      scrollbars: false,
                    ),
                    child: ListView.builder(
                      physics: BouncingScrollPhysics(),
                      padding: EdgeInsets.all(8),
                      itemCount: items.length,
                      shrinkWrap: true,
                      itemBuilder: (context, itemIndex) {
                        final item = items[itemIndex];
                        final isItemFulfilled = item['custom_fulfilled'] == 1;
                        final isServeLater = item['custom_serve_later'] == 1;

                        return Container(
                          margin: EdgeInsets.only(bottom: 8),
                          padding: EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isItemFulfilled
                                ? (isGrabOrder
                                    ? Color(0xFF00B14F).withOpacity(0.1)
                                    : Colors.green[100])
                                : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isItemFulfilled
                                  ? (isGrabOrder
                                      ? Color(0xFF00B14F)
                                      : Colors.green)
                                  : (isGrabOrder
                                      ? Color(0xFF00B14F).withOpacity(0.3)
                                      : Colors.grey[300]!),
                              width: 2,
                            ),
                          ),
                          child: Row(
                            children: [
                              // Interactive checkbox for both tabs
                              InkWell(
                                onTap: () {
                                  _showFulfillItemDialog(
                                      item, !isItemFulfilled);
                                },
                                child: Container(
                                  width: 32,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isItemFulfilled
                                        ? (isGrabOrder
                                            ? Color(0xFF00B14F)
                                            : Colors.green)
                                        : Colors.white,
                                    border: Border.all(
                                      color: isItemFulfilled
                                          ? (isGrabOrder
                                              ? Color(0xFF00B14F)
                                              : Colors.green)
                                          : (isGrabOrder
                                              ? Color(0xFF00B14F)
                                                  .withOpacity(0.5)
                                              : Colors.grey.shade400),
                                      width: 2,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.check,
                                    color: isItemFulfilled
                                        ? Colors.white
                                        : Colors.transparent,
                                    size: 20,
                                  ),
                                ),
                              ),
                              SizedBox(width: 12),
                              // Item details
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isGrabOrder
                                                ? Color(0xFF00B14F)
                                                : Colors.orange,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            'x${(item['qty'] as num?)?.toStringAsFixed(0) ?? '1'}',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            item['item_name']?.toString() ??
                                                'Unknown',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              decoration: isItemFulfilled
                                                  ? TextDecoration.lineThrough
                                                  : null,
                                              color: Colors.black87,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        // Serve Later Tag
                                        if (isServeLater) _buildServeLaterTag(),
                                      ],
                                    ),
                                    if (item['custom_item_remarks'] != null &&
                                        item['custom_item_remarks']
                                            .toString()
                                            .isNotEmpty)
                                      Container(
                                        margin: EdgeInsets.only(top: 6),
                                        padding: EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: Colors.orange[50],
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                            color: Colors.orange[200]!,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.comment,
                                              size: 14,
                                              color: Colors.orange[700],
                                            ),
                                            SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                item['custom_item_remarks'],
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.orange[900],
                                                  fontWeight: FontWeight.w600,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    _buildVariantInfo(item),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),

              SizedBox(height: 12),

              // Order Remarks
              if (order['remarks'] != null &&
                  order['remarks'].toString().isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange[300]!, width: 2),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline,
                          size: 18, color: Colors.orange[800]),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Order Notes: ${order['remarks']}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.orange[900],
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

              // Status and Action (show appropriate button based on tab)
              SizedBox(height: 12),
              if (!showInDoneTab && !isOrderFulfilled)
                // Pending tab - Mark as Complete button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => _showFulfillOrderDialog(order, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isGrabOrder ? Color(0xFF00B14F) : Colors.green,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child: Text(
                      'MARK AS COMPLETE',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                )
              else if (showInDoneTab && isOrderFulfilled)
                // Done tab - Reopen Order button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => _showFulfillOrderDialog(order, false),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isGrabOrder
                          ? Color(0xFF00B14F).withOpacity(0.8)
                          : Colors.orange,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child: Text(
                      'REOPEN ORDER',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                )
              else if (!showInDoneTab && isOrderFulfilled)
                // Pending tab - Completed indicator (shouldn't normally happen)
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: isGrabOrder
                        ? Color(0xFF00B14F).withOpacity(0.1)
                        : Colors.green[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isGrabOrder ? Color(0xFF00B14F) : Colors.green,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: isGrabOrder ? Color(0xFF00B14F) : Colors.green,
                        size: 24,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'COMPLETED',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isGrabOrder
                              ? Color(0xFF00B14F)
                              : Colors.green[800],
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFulfillItemDialog(Map<String, dynamic> item, bool fulfilled) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          fulfilled ? 'Mark Item as Fulfilled?' : 'Unmark Item?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          fulfilled
              ? 'Are you sure you want to mark "${item['item_name']}" as fulfilled?'
              : 'Are you sure you want to unmark "${item['item_name']}"?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style:
                  TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _fulfillItem(item['name']?.toString() ?? '', fulfilled);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: fulfilled ? Colors.green : Colors.orange,
            ),
            child: Text(
              fulfilled ? 'Mark Fulfilled' : 'Unmark',
              style:
                  TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _showFulfillOrderDialog(Map<String, dynamic> order, bool fulfilled) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          fulfilled ? 'Mark Order as Fulfilled?' : 'Reopen Order?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          fulfilled
              ? 'Are you sure you want to mark order ${order['name']} as fulfilled?'
              : 'Are you sure you want to reopen order ${order['name']}? This will move it back to pending orders.',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style:
                  TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _fulfillOrder(order['name']?.toString() ?? '', fulfilled);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: fulfilled ? Colors.green : Colors.orange,
            ),
            child: Text(
              fulfilled ? 'Mark Fulfilled' : 'Reopen Order',
              style:
                  TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _printSelectedKitchenOrder(
    String posInvoice,
    List<String> selectedItems,
  ) async {
    if (_selectedKitchenStation == null || !mounted) return;

    try {
      // Use ReceiptPrinter instead of handling response directly
      await ReceiptPrinter.printSelectedKitchenOrder(
        posInvoice,
        selectedItems,
      );

      if (!mounted) return;

      Fluttertoast.showToast(
        msg: 'Kitchen order sent to printer',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.green,
        textColor: Colors.white,
        fontSize: 16.0,
      );
    } catch (e) {
      if (!mounted) return;

      Fluttertoast.showToast(
        msg: 'Error printing kitchen order: $e',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
        fontSize: 16.0,
      );
    }
  }

  void _showPrintSelectionDialog(Map<String, dynamic> order) {
    final items = (order['items'] as List?) ?? [];
    final List<bool> selectedItems =
        List.generate(items.length, (index) => false);
    bool selectAll = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            title: Text(
              'Select Items to Print',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: Container(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Select All checkbox
                  Container(
                    padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Row(
                      children: [
                        Checkbox(
                          value: selectAll,
                          onChanged: (value) {
                            setDialogState(() {
                              selectAll = value ?? false;
                              for (int i = 0; i < selectedItems.length; i++) {
                                selectedItems[i] = selectAll;
                              }
                            });
                          },
                          activeColor: Colors.blue,
                        ),
                        Text(
                          'Select All Items',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[800],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 12),
                  // Items list
                  Container(
                    constraints: BoxConstraints(maxHeight: 300),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final isItemFulfilled = item['custom_fulfilled'] == 1;
                        final isServeLater = item['custom_serve_later'] == 1;

                        return Container(
                          margin: EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey[300]!),
                            borderRadius: BorderRadius.circular(8),
                            color: isItemFulfilled
                                ? Colors.green[50]
                                : Colors.white,
                          ),
                          child: CheckboxListTile(
                            value: selectedItems[index],
                            onChanged: (value) {
                              setDialogState(() {
                                selectedItems[index] = value ?? false;
                                // Update selectAll if all items are selected/deselected
                                selectAll = selectedItems.every((item) => item);
                              });
                            },
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item['item_name']?.toString() ??
                                        'Unknown Item',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      decoration: isItemFulfilled
                                          ? TextDecoration.lineThrough
                                          : null,
                                      color: isItemFulfilled
                                          ? Colors.grey[600]
                                          : Colors.black87,
                                    ),
                                  ),
                                ),
                                if (isServeLater) _buildServeLaterTag(),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Qty: ${item['qty'] ?? '1'}'),
                                if (item['custom_item_remarks'] != null &&
                                    item['custom_item_remarks']
                                        .toString()
                                        .isNotEmpty)
                                  Text(
                                    'Remarks: ${item['custom_item_remarks']}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.orange[700],
                                      fontStyle: FontStyle.italic,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                            secondary: Container(
                              padding: EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.orange,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'x${(item['qty'] as num?)?.toStringAsFixed(0) ?? '1'}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: Colors.blue,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.black),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  final selectedItemNames = <String>[];
                  for (int i = 0; i < items.length; i++) {
                    if (selectedItems[i]) {
                      selectedItemNames.add(items[i]['name']?.toString() ?? '');
                    }
                  }

                  if (selectedItemNames.isEmpty) {
                    Fluttertoast.showToast(
                      msg: 'Please select at least one item to print',
                      toastLength: Toast.LENGTH_SHORT,
                      gravity: ToastGravity.BOTTOM,
                      backgroundColor: Colors.orange,
                      textColor: Colors.white,
                      fontSize: 16.0,
                    );
                    return;
                  }

                  Navigator.pop(context);
                  _printSelectedKitchenOrder(
                    order['name']?.toString() ?? '',
                    selectedItemNames,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                ),
                child: Text(
                  'Print Selected',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatTime(String? timeString) {
    if (timeString == null) return 'N/A';
    try {
      final time = DateTime.parse(timeString);
      return DateFormat('HH:mm').format(time);
    } catch (e) {
      return timeString;
    }
  }
}
