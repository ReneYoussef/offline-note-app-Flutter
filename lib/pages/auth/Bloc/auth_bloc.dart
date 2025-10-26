import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:offline_note_app/pages/auth/Bloc/auth_event.dart';
import 'package:offline_note_app/pages/auth/Bloc/auth_state.dart';
import 'package:offline_note_app/services/api_services.dart';
import 'package:offline_note_app/services/shared_preferences_service.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final ApiServices _apiServices = ApiServices();
  String? _currentToken;

  AuthBloc() : super(const AuthInitial()) {
    on<AuthRegisterRequested>(_onRegisterRequested);
    on<AuthLoginRequested>(_onLoginRequested);
    on<AuthLogoutRequested>(_onLogoutRequested);
    on<AuthCheckRequested>(_onAuthCheckRequested);
  }

  Future<void> _onRegisterRequested(
    AuthRegisterRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());

    try {
      // Validate passwords match
      if (event.password != event.confirmPassword) {
        emit(const AuthRegistrationFailed(message: 'Passwords do not match'));
        return;
      }

      // Call API service
      await _apiServices.register(
        name: event.name,
        email: event.email,
        password: event.password,
      );

      // Handle successful registration
      emit(const AuthRegistrationSuccess());
    } catch (e) {
      emit(AuthRegistrationFailed(message: e.toString()));
    }
  }

  Future<void> _onLoginRequested(
    AuthLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());

    try {
      // Call API service for login
      final response = await _apiServices.login(
        email: event.email,
        password: event.password,
      );

      print('Login response received: $response');

      // Store the token
      _currentToken = response['token'];

      // Save user data to SharedPreferences
      await SharedPreferencesService.saveUserData(
        token: response['token'],
        userId: '1', // Temporary - you should get this from API
        name: 'User', // Temporary - you should get this from API
        email: event.email,
      );

      // Handle successful login
      // Note: Your API returns token but not user details in login response
      // You might need to fetch user details separately or modify your API
      emit(
        AuthAuthenticated(
          userId: '1', // Temporary - you should get this from API
          name: 'User', // Temporary - you should get this from API
          email: event.email, // Use the email from the request
          token: response['token'],
        ),
      );
    } catch (e) {
      print('Login error: $e');
      emit(AuthFailure(message: e.toString()));
    }
  }

  Future<void> _onLogoutRequested(
    AuthLogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    _currentToken = null; // Clear the token on logout
    await SharedPreferencesService.clearUserData(); // Clear SharedPreferences
    emit(const AuthUnauthenticated());
  }

  Future<void> _onAuthCheckRequested(
    AuthCheckRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthCheckStarted());

    try {
      // Check if user is logged in from SharedPreferences
      final isLoggedIn = await SharedPreferencesService.isLoggedIn();

      if (isLoggedIn) {
        // Get user data from SharedPreferences
        final userData = await SharedPreferencesService.getAllUserData();

        if (userData['token'] != null && userData['userId'] != null) {
          _currentToken = userData['token'];

          emit(
            AuthAuthenticated(
              userId: userData['userId']!,
              name: userData['name'] ?? 'User',
              email: userData['email'] ?? '',
              token: userData['token']!,
            ),
          );
        } else {
          // Data is incomplete, clear it
          await SharedPreferencesService.clearUserData();
          emit(const AuthUnauthenticated());
        }
      } else {
        emit(const AuthUnauthenticated());
      }
    } catch (e) {
      print('Auth check error: $e');
      emit(AuthFailure(message: e.toString()));
    }
  }

  // Getter for the current token
  String? get currentToken => _currentToken;
}
