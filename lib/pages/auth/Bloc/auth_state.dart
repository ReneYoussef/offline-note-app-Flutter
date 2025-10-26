import 'package:equatable/equatable.dart';

abstract class AuthState extends Equatable {
  const AuthState();
  @override
  List<Object> get props => [];
}

class AuthInitial extends AuthState {
  const AuthInitial();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthAuthenticated extends AuthState {
  final String userId;
  final String name;
  final String email;
  final String token;
  const AuthAuthenticated({
    required this.userId,
    required this.name,
    required this.email,
    required this.token,
  });
  @override
  List<Object> get props => [userId, name, email, token];
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
  @override
  List<Object> get props => [];
}

class AuthFailure extends AuthState {
  final String message;
  const AuthFailure({required this.message});
  @override
  List<Object> get props => [message];
}

class AuthCheckStarted extends AuthState {
  const AuthCheckStarted();
  @override
  List<Object> get props => [];
}

class AuthCheckCompleted extends AuthState {
  final bool isAuthenticated;
  const AuthCheckCompleted({required this.isAuthenticated});
  @override
  List<Object> get props => [isAuthenticated];
}

class AuthRegistrationSuccess extends AuthState {
  const AuthRegistrationSuccess();
  @override
  List<Object> get props => [];
}

class AuthRegistrationFailed extends AuthState {
  final String message;
  const AuthRegistrationFailed({required this.message});
  @override
  List<Object> get props => [message];
}
