import 'package:shared_preferences/shared_preferences.dart';

class NotificationQueue {
  static const String _queueKey = 'pending_notifications_queue';

  /// Add an order to the notification queue
  static Future<void> queueNotification(String orderId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queue = prefs.getStringList(_queueKey) ?? [];
      
      if (!queue.contains(orderId)) {
        queue.add(orderId);
        await prefs.setStringList(_queueKey, queue);
        print('📬 Queued notification for order: $orderId');
      }
    } catch (e) {
      print('❌ Error queuing notification: $e');
    }
  }

  /// Get all queued notifications and clear the queue
  static Future<List<String>> getAndClearQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queue = prefs.getStringList(_queueKey) ?? [];
      
      if (queue.isNotEmpty) {
        await prefs.remove(_queueKey);
        print('📭 Retrieved ${queue.length} queued notification(s)');
      }
      
      return queue;
    } catch (e) {
      print('❌ Error getting queued notifications: $e');
      return [];
    }
  }
}