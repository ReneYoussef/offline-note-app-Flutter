import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'database/app_database.dart';
import 'pages/auth/login.dart';
import 'pages/auth/Bloc/auth_bloc.dart';
import 'pages/auth/Bloc/auth_state.dart';
import 'pages/auth/Bloc/auth_event.dart';
import 'pages/Notes/Bloc/note_bloc.dart';
import 'pages/Notes/NotesPage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: ".env");
    print('Environment variables loaded successfully');
  } catch (e) {
    print('Error loading .env file: $e');
    // Continue without .env file - you can set default values
  }
  runApp(const MyApp());
}

final db = AppDatabase();

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (context) => AuthBloc()),
        BlocProvider(
          create: (context) => NoteBloc(authBloc: context.read<AuthBloc>()),
        ),
      ],
      child: MaterialApp(
        title: 'Drift Notes App',
        debugShowCheckedModeBanner: false,
        home: const AuthWrapper(),
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  void initState() {
    super.initState();
    // Check authentication status on app start
    context.read<AuthBloc>().add(const AuthCheckRequested());
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        if (state is AuthCheckStarted || state is AuthLoading) {
          // Show loading screen while checking authentication
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        } else if (state is AuthAuthenticated) {
          // User is logged in, go to NotesPage
          return const NotesPage();
        } else {
          // User is not logged in, go to Login
          return const Login();
        }
      },
    );
  }
}
