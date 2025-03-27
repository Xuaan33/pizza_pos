import 'package:flutter/material.dart';
import 'package:shiok_pos_android_app/screens/login_screen.dart';

class NavigationSidebar extends StatefulWidget {
  const NavigationSidebar({Key? key}) : super(key: key);

  @override
  _NavigationSidebarState createState() => _NavigationSidebarState();
}

class _NavigationSidebarState extends State<NavigationSidebar> {
  int _selectedIndex = 0;

  void _showLogoutConfirmationDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Logout Confirmation'),
          content: const Text('Are you sure you want to log out?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                // Close the dialog
                Navigator.of(context).pop();
                
                // Navigate to login screen and remove all previous routes
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (context) => const LoginPage()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, // Optional: make the confirm button red
              ),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      color: Colors.black,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset('assets/logo-shiokpos.png', height: 50),
          const SizedBox(height: 20),
          _buildNavItem(
            activeIcon: 'assets/img-sidebar-delivery.png', 
            inactiveIcon: 'assets/img-sidebar-delivery.png', 
            label: 'Delivery', 
            index: 0
          ),
          _buildNavItem(
            activeIcon: 'assets/img-sidebar-orders.png', 
            inactiveIcon: 'assets/img-sidebar-orders.png', 
            label: 'Orders', 
            index: 1
          ),
          _buildNavItem(
            activeIcon: 'assets/img-sidebar-dashboard.png', 
            inactiveIcon: 'assets/img-sidebar-dashboard.png', 
            label: 'Dashboard', 
            index: 2
          ),
          _buildNavItem(
            activeIcon: 'assets/img-sidebar-settings.png', 
            inactiveIcon: 'assets/img-sidebar-settings.png', 
            label: 'Settings', 
            index: 3
          ),
          const Spacer(),
          // Logout section
          GestureDetector(
            onTap: _showLogoutConfirmationDialog,
            child: Container(
              width: 80,
              height: 80,
              color: Colors.transparent,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(
                    Icons.logout,
                    color: Colors.white,
                    size: 30,
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Log Out',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required String activeIcon, 
    required String inactiveIcon, 
    required String label, 
    required int index
  }) {
    bool isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedIndex = index;
        });
      },
      child: Container(
        width: 80,
        height: 80,
        color: isSelected ? Colors.white24 : Colors.transparent,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              isSelected ? activeIcon : inactiveIcon,
              width: 30,
              height: 30,
              color: isSelected ? Colors.yellow : Colors.white,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.yellow : Colors.white,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}