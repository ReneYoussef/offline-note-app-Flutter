import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'firebase_options.dart';
import 'pages/auth/login.dart';
import 'pages/auth/Bloc/auth_bloc.dart';
import 'pages/auth/Bloc/auth_state.dart';
import 'pages/auth/Bloc/auth_event.dart';
import 'pages/Notes/Bloc/note_bloc.dart';
import 'pages/Notes/NotesPage.dart';
import 'services/firestore_service.dart';
import 'services/sync_service.dart';
import 'services/shared_preferences_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Initialize Firebase
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('Firebase initialized successfully');

    // Initialize Firestore service for offline functionality
    await FirestoreService.initialize();
    print('Firestore service initialized for offline functionality');
  } catch (e) {
    print('Error initializing Firebase: $e');
    print('Stack trace: ${StackTrace.current}');
    rethrow;
  }

  try {
    await dotenv.load(fileName: ".env");
    print('Environment variables loaded successfully');
    print('API_URL: ${dotenv.env['API_URL']}');
  } catch (e) {
    print('Error loading .env file: $e');
    print('Please ensure .env file exists and contains API_URL');
    // The app will fail if .env is not loaded properly
  }

  runApp(const MyApp());
}

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
        title: 'Offline Notes App',
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
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    try {
      // Check authentication status on app start
      context.read<AuthBloc>().add(const AuthCheckRequested());

      // Listen for connectivity changes for background sync
      _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
        List<ConnectivityResult> results,
      ) {
        final isOnline = results.any(
          (result) => result != ConnectivityResult.none,
        );
        if (isOnline) {
          _triggerBackgroundSync();
        }
      });
    } catch (e) {
      print('Error in AuthWrapper initState: $e');
      print('Stack trace: ${StackTrace.current}');
    }
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  // Trigger background sync when coming online
  Future<void> _triggerBackgroundSync() async {
    try {
      final userId = await SharedPreferencesService.getUserId();
      final token = await SharedPreferencesService.getToken();

      if (userId != null && token != null) {
        print('Device came online, triggering background sync...');
        // Run sync in background without blocking UI
        Future.microtask(() async {
          await SyncService.syncFromApiToFirestore(userId, token);
          await SyncService.syncFromFirestoreToApi(userId, token);
          print('Background sync completed');
        });
      }
    } catch (e) {
      print('Error in background sync: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        try {
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
        } catch (e) {
          print('Error in AuthWrapper build: $e');
          print('Stack trace: ${StackTrace.current}');
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: $e'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {});
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
      },
    );
  }
}
