import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

class GrabNotificationOverlay {
  static OverlayEntry? _currentOverlay;
  static AudioPlayer? _audioPlayer;
  static bool _isInitialized = false;

  /// Initialize the audio player (call once at app startup)
  static Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _audioPlayer = AudioPlayer();
      await _audioPlayer!.setReleaseMode(ReleaseMode.stop);
      _isInitialized = true;
      debugPrint('✅ Audio player initialized successfully');
    } catch (e) {
      debugPrint('❌ Failed to initialize audio player: $e');
      _isInitialized = false;
    }
  }

  /// Show a custom notification at the top-right corner of the app
  static Future<void> show(
    BuildContext context, {
    required String orderId,
    required String customerName,
    VoidCallback? onTap,
  }) async {
    // Remove any existing notification
    remove();

    // Initialize audio player if not already done
    if (!_isInitialized) {
      await initialize();
    }

    // Play notification sound (non-blocking)
    _playSound();

    // Create the overlay immediately (don't wait for sound)
    final overlay = Overlay.of(context);
    if (overlay == null) {
      debugPrint('❌ Overlay not available');
      return;
    }

    _currentOverlay = OverlayEntry(
      builder: (context) => _GrabNotificationWidget(
        orderId: orderId,
        customerName: customerName,
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

  /// Play the notification sound - OPTIMIZED for speed
  static void _playSound() {
    if (_audioPlayer == null) {
      debugPrint('⚠️ Audio player not initialized');
      return;
    }

    // Play asynchronously without blocking
    _playAsync();
  }

  static Future<void> _playAsync() async {
    try {
      debugPrint('🔊 Playing notification sound...');
      
      // Create a fresh player for each notification to avoid conflicts
      final player = AudioPlayer();
      
      // Set release mode
      await player.setReleaseMode(ReleaseMode.release);
      
      // Play the sound
      await player.play(
        AssetSource('grab_notification.mp3'),
        volume: 1.0,
      );
      
      debugPrint('✅ Notification sound playing');
      
      // Auto-dispose after sound finishes
      player.onPlayerComplete.listen((event) {
        player.dispose();
        debugPrint('🔊 Sound completed and disposed');
      });
      
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

  /// Dispose audio player (call when app closes)
  static Future<void> dispose() async {
    try {
      await _audioPlayer?.stop();
      await _audioPlayer?.dispose();
      _audioPlayer = null;
      _isInitialized = false;
      debugPrint('✅ Audio player disposed');
    } catch (e) {
      debugPrint('❌ Error disposing audio player: $e');
    }
  }
}

class _GrabNotificationWidget extends StatefulWidget {
  final String orderId;
  final String customerName;
  final VoidCallback? onTap;
  final VoidCallback onDismiss;

  const _GrabNotificationWidget({
    required this.orderId,
    required this.customerName,
    this.onTap,
    required this.onDismiss,
  });

  @override
  State<_GrabNotificationWidget> createState() =>
      _GrabNotificationWidgetState();
}

class _GrabNotificationWidgetState extends State<_GrabNotificationWidget>
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
                    colors: [
                      Color(0xFF00B14F), // Grab green
                      Color(0xFF00D35C),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xFF00B14F).withOpacity(0.4),
                      blurRadius: 20,
                      spreadRadius: 2,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Grab icon
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.shopping_bag_rounded,
                          color: Color(0xFF00B14F),
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
                            '🛵 New Grab Order',
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
                            widget.customerName,
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