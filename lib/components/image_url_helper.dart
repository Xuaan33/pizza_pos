import 'package:shared_preferences/shared_preferences.dart';

class ImageUrlHelper {
  static Future<String> getBaseImageUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('base_url') ?? 'https://asdf.byondwave.com';
  }

  static Future<String> getFullImageUrl(String imagePath) async {
    if (imagePath.startsWith('http')) {
      return imagePath; // Already a full URL
    }
    
    final baseUrl = await getBaseImageUrl();
    // Handle different image path formats
    if (imagePath.startsWith('/')) {
      return '$baseUrl$imagePath';
    } else {
      return '$baseUrl/$imagePath';
    }
  }

  // Helper method for payment method images
  static Future<String> getPaymentMethodImage(String imagePath) async {
    return getFullImageUrl(imagePath);
  }

  // Helper method for item images
  static Future<String> getItemImage(String imagePath) async {
    return getFullImageUrl(imagePath);
  }
}