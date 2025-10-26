import 'package:offline_note_app/services/shared_preferences_service.dart';

class AuthService {
  static int? _currentUserId;

  // Set the current user ID when user logs in
  static void setCurrentUser(int userId) {
    _currentUserId = userId;
  }

  // Get the current user ID
  static Future<int?> getCurrentUserId() async {
    // First try to get from memory
    if (_currentUserId != null) {
      return _currentUserId;
    }

    // If not in memory, get from SharedPreferences
    final userIdString = await SharedPreferencesService.getUserId();
    if (userIdString != null) {
      _currentUserId = int.tryParse(userIdString);
    }

    return _currentUserId;
  }

  // Check if user is logged in
  static Future<bool> isLoggedIn() async {
    return await SharedPreferencesService.isLoggedIn();
  }

  // Logout user
  static void logout() {
    _currentUserId = null;
    // Note: SharedPreferences will be cleared by AuthBloc
  }
}
