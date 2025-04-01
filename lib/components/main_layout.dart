import 'package:flutter/material.dart';
import 'package:shiok_pos_android_app/screens/table_screen.dart';
import 'package:shiok_pos_android_app/screens/orders_screen.dart';
import 'package:shiok_pos_android_app/screens/dashboard_screen.dart';
import 'package:shiok_pos_android_app/screens/settings_screen.dart';
import 'package:shiok_pos_android_app/screens/delivery_screen.dart';

class MainLayout extends StatefulWidget {
  @override
  _MainLayoutState createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _selectedTabIndex = 0;

  final List<Widget> _screens = [
    const TableScreen(),
    const DeliveryScreen(),
    const OrdersScreen(),
    const DashboardScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _buildNavigationSidebar(),
          Expanded(
            child: IndexedStack(
              index: _selectedTabIndex,
              children: _screens,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationSidebar() {
    return Container(
      width: 80,
      color: Colors.black,
      child: Column(
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                _selectedTabIndex = 0; // Go to TableScreen when tapping logo
              });
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              child: Image.asset(
                'assets/logo-shiokpos.png',
                width: 50,
                height: 50,
              ),
            ),
          ),
          _buildNavItem(1, 'assets/img-sidebar-delivery.png', 'Delivery'),
          _buildNavItem(2, 'assets/img-sidebar-orders.png', 'Orders'),
          _buildNavItem(3, 'assets/img-sidebar-dashboard.png', 'Dashboard'),
          _buildNavItem(4, 'assets/img-sidebar-settings.png', 'Settings'),
          const Spacer(),
          _buildNavItem(-1, 'assets/img-sidebar-logout.png', 'Logout', _logout),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, String imagePath, String label, [VoidCallback? action]) {
    final bool isSelected = index == _selectedTabIndex;
    return GestureDetector(
      onTap: action ?? () => setState(() => _selectedTabIndex = index),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                border: isSelected ? const Border(left: BorderSide(color: Colors.pink, width: 3)) : null,
              ),
              child: Image.asset(
                imagePath,
                color: isSelected ? Colors.pink : Colors.white,
                width: 26,
                height: 26,
              ),
            ),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: isSelected ? Colors.pink : Colors.white, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  void _logout() {
    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }
}
