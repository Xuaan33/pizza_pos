// components/kitchen_notification_overlay.dart
// Universal notification for ALL kitchen orders with custom audio

import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

class KitchenNotificationOverlay {
  static OverlayEntry? _currentOverlay;
  static AudioPlayer? _audioPlayer;
  static bool _isInitialized = false;

  /// Initialize the audio player
  static Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint('⚠️ Audio player already initialized');
      return;
    }
    
    try {
      _audioPlayer = AudioPlayer();
      await _audioPlayer!.setReleaseMode(ReleaseMode.stop);
      _isInitialized = true;
      debugPrint('✅ Kitchen notification audio initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize audio player: $e');
      _isInitialized = false;
    }
  }

  /// Dispose audio player
  static Future<void> dispose() async {
    if (!_isInitialized || _audioPlayer == null) {
      debugPrint('⚠️ Audio player not initialized, nothing to dispose');
      return;
    }
    
    try {
      await _audioPlayer?.stop();
      await _audioPlayer?.dispose();
      _audioPlayer = null;
      _isInitialized = false;
      debugPrint('✅ Kitchen notification audio disposed');
    } catch (e) {
      debugPrint('❌ Error disposing audio player: $e');
    }
  }

  /// Show a notification for any new kitchen order
  static Future<void> show(
    BuildContext context, {
    required String orderId,
    required String customerName,
    required String tableName,
    bool isGrab = false,
    String? stationName,
    VoidCallback? onTap,
  }) async {
    // Remove any existing notification
    remove();

    // Initialize if not already done
    if (!_isInitialized) {
      await initialize();
    }

    // Play notification sound (non-blocking)
    _playSound(isGrab: isGrab);

    // Create the overlay
    final overlay = Overlay.of(context);
    if (overlay == null) {
      debugPrint('❌ Overlay not available');
      return;
    }

    _currentOverlay = OverlayEntry(
      builder: (context) => _KitchenNotificationWidget(
        orderId: orderId,
        customerName: customerName,
        tableName: tableName,
        isGrab: isGrab,
        stationName: stationName,
        onTap: onTap,
        onDismiss: remove,
      ),
    );

    overlay.insert(_currentOverlay!);

    // Auto-dismiss after 5 seconds
    Future.delayed(const Duration(seconds: 5), () {
      remove();
    });
  }

  /// Play notification sound using the static audio player
  static void _playSound({required bool isGrab}) {
    if (_audioPlayer == null || !_isInitialized) {
      debugPrint('⚠️ Audio player not initialized, cannot play sound');
      return;
    }

    // Play asynchronously without blocking
    _playAsync(isGrab: isGrab);
  }

  /// Play sound using the static audio player (not creating new ones)
  static Future<void> _playAsync({required bool isGrab}) async {
    try {
      debugPrint('🔊 Playing notification sound...');
      
      // 🔥 FIX: Use the static _audioPlayer instead of creating new ones
      if (_audioPlayer == null) {
        debugPrint('❌ Audio player is null');
        return;
      }
      
      // Stop any currently playing sound first
      await _audioPlayer!.stop();
      
      // Play the sound based on order type
      final soundFile = isGrab ? 'grab_notification.mp3' : 'order.mp3';
      
      await _audioPlayer!.play(
        AssetSource(soundFile),
        volume: 1.0,
      );
      
      debugPrint('✅ Playing $soundFile');
      
    } catch (e) {
      debugPrint('❌ Error playing notification sound: $e');
      // Silent fail - notification still shows without sound
    }
  }

  /// Remove the current notification
  static void remove() {
    _currentOverlay?.remove();
    _currentOverlay = null;
  }
}

class _KitchenNotificationWidget extends StatefulWidget {
  final String orderId;
  final String customerName;
  final String tableName;
  final bool isGrab;
  final String? stationName;
  final VoidCallback? onTap;
  final VoidCallback onDismiss;

  const _KitchenNotificationWidget({
    required this.orderId,
    required this.customerName,
    required this.tableName,
    required this.isGrab,
    this.stationName,
    this.onTap,
    required this.onDismiss,
  });

  @override
  State<_KitchenNotificationWidget> createState() =>
      _KitchenNotificationWidgetState();
}

class _KitchenNotificationWidgetState extends State<_KitchenNotificationWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    // Animation controller
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    // Slide from right
    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.2, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    // Fade in
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    ));

    // Start animation
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleDismiss() async {
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isGrab ? Color(0xFF00B14F) : Color(0xFFE732A0);
    final displayStation = widget.isGrab ? 'GRAB' : (widget.stationName ?? 'Kitchen');

    return Positioned(
      top: 20,
      right: 20,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: () {
                widget.onTap?.call();
                _handleDismiss();
              },
              child: Container(
                width: 380,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: widget.isGrab
                        ? [
                            Color(0xFF00B14F), // Grab green
                            Color(0xFF00D35C),
                          ]
                        : [
                            Color(0xFFE732A0), // Regular pink
                            Color(0xFFFF4DB8),
                          ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.4),
                      blurRadius: 20,
                      spreadRadius: 2,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Icon
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: widget.isGrab
                            ? Image.asset(
                                'assets/icon-grab.png',
                                width: 32,
                                height: 32,
                              )
                            : Icon(
                                Icons.restaurant_menu,
                                color: color,
                                size: 32,
                              ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.isGrab
                                ? '🛵 New Grab Order'
                                : '🔔 New Order',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Order #${widget.orderId}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.95),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$displayStation - ${widget.tableName}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.touch_app,
                                size: 14,
                                color: Colors.white.withOpacity(0.8),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Tap to view details',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Close button
                    GestureDetector(
                      onTap: _handleDismiss,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}