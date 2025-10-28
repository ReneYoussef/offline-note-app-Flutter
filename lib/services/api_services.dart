import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ApiServices {
  String? _currentBaseUrl;

  // Custom HTTP client that handles redirects properly
  static final http.Client _httpClient = http.Client();

  // Test API connectivity
  Future<bool> testApiConnection() async {
    try {
      final url = Uri.parse('${_baseurl}/notes');
      print('Testing API connection to: $url');

      final response = await _httpClient
          .get(url, headers: {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 10));

      print('API test response status: ${response.statusCode}');
      print('API test response headers: ${response.headers}');

      if (response.statusCode == 302) {
        print('API redirect detected to: ${response.headers['location']}');
        return false;
      }

      return response.statusCode <
          500; // Any 2xx, 3xx, or 4xx is considered "reachable"
    } catch (e) {
      print('API connection test failed: $e');
      return false;
    }
  }

  String get _baseurl {
    if (_currentBaseUrl == null) {
      try {
        final raw = dotenv.env['API_URL'];
        if (raw == null || raw.isEmpty) {
          throw Exception('API_URL not found in .env file');
        } else {
          _currentBaseUrl = raw;
          print('Using API URL from .env: $_currentBaseUrl');
        }
      } catch (e) {
        print('Error getting API_URL from .env: $e');
        throw Exception('Failed to load API_URL from .env file: $e');
      }
    }
    return _currentBaseUrl!;
  }

  //authentication endpoints
  Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final url = Uri.parse('${_baseurl}/register');
    print('Registering user with URL: $url');
    print(
      'Request body: ${json.encode({'name': name, 'email': email, 'password': password})}',
    );

    final response = await http.post(
      url,
      body: json.encode({'name': name, 'email': email, 'password': password}),
      headers: {'Content-Type': 'application/json'},
    );

    print('Response status: ${response.statusCode}');
    print('Response body: ${response.body}');

    if (response.statusCode == 201) {
      final data = json.decode(response.body);
      return data;
    } else {
      final error = json.decode(response.body);
      throw Exception('Failed to register: ${error['message']}');
    }
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      final url = Uri.parse('${_baseurl}/login');
      print('Logging in user with URL: $url');
      print(
        'Request body: ${json.encode({'email': email, 'password': password})}',
      );

      final response = await _httpClient.post(
        url,
        body: json.encode({'email': email, 'password': password}),
        headers: {'Content-Type': 'application/json'},
      );

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data;
      } else {
        final error = json.decode(response.body);
        print(
          'Login failed with status ${response.statusCode}: ${response.body}',
        );
        throw Exception('Failed to login: ${error['message']}');
      }
    } catch (e) {
      print('Login error: $e');
      throw Exception('Login error: $e');
    }
  }

  // Notes endpoints
  Future<List<Map<String, dynamic>>> getNotes(String token) async {
    final url = Uri.parse('${_baseurl}/notes');
    print('Getting notes with URL: $url');

    final response = await _httpClient.get(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    print('Response status: ${response.statusCode}');
    print('Response body: ${response.body}');

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else if (response.statusCode == 301 || response.statusCode == 302) {
      // GET requests should auto-follow redirects, but handle manually if needed
      final location = response.headers['location'] ?? '';
      print('Redirect detected for GET: $location');

      if (location.isNotEmpty) {
        // Retry the GET request with the redirect location
        final retryResponse = await _httpClient.get(
          Uri.parse(location),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        );

        if (retryResponse.statusCode == 200) {
          final List<dynamic> data = json.decode(retryResponse.body);
          return data.cast<Map<String, dynamic>>();
        }
      }

      throw Exception(
        'Failed to get notes after redirect: ${response.statusCode}',
      );
    } else {
      final error = json.decode(response.body);
      throw Exception(
        'Failed to get notes: ${error['error'] ?? 'Unknown error'}',
      );
    }
  }

  Future<Map<String, dynamic>> createNote({
    required String title,
    required String body,
    required String token,
  }) async {
    final url = Uri.parse('${_baseurl}/notes');
    print('Creating note with URL: $url');
    print('Request body: ${json.encode({'title': title, 'body': body})}');

    final response = await _httpClient
        .post(
          url,
          body: json.encode({'title': title, 'body': body}),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(const Duration(seconds: 30));

    print('Response status: ${response.statusCode}');
    print('Response body: ${response.body}');

    if (response.statusCode == 201) {
      final data = json.decode(response.body);
      return data;
    } else if (response.statusCode == 200) {
      // Handle case where server returns 200 instead of 201
      final data = json.decode(response.body);
      return data;
    } else if (response.statusCode == 301 || response.statusCode == 302) {
      print('⚠️ Server redirect detected - trying with base URL');

      // Try with the base URL without /api
      final baseUrl = _baseurl.replaceAll('/api', '');
      final retryUrl = Uri.parse('$baseUrl/api/notes');
      print('Retrying with URL: $retryUrl');

      final retryResponse = await _httpClient
          .post(
            retryUrl,
            body: json.encode({'title': title, 'body': body}),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 30));

      print('Retry response status: ${retryResponse.statusCode}');
      print('Retry response body: ${retryResponse.body}');

      if (retryResponse.statusCode == 201 || retryResponse.statusCode == 200) {
        final data = json.decode(retryResponse.body);
        return data;
      } else {
        throw Exception(
          'Failed to create note after redirect: HTTP ${retryResponse.statusCode}',
        );
      }
    } else {
      try {
        final error = json.decode(response.body);
        throw Exception(
          'Failed to create note: ${error['error'] ?? 'Unknown error'}',
        );
      } catch (e) {
        throw Exception(
          'Failed to create note: HTTP ${response.statusCode} - ${response.body}',
        );
      }
    }
  }

  Future<Map<String, dynamic>> updateNote({
    required int id,
    required String title,
    required String body,
    required String token,
  }) async {
    final url = Uri.parse('${_baseurl}/notes/$id');
    print('Updating note with URL: $url');
    print('Request body: ${json.encode({'title': title, 'body': body})}');

    final response = await _httpClient
        .put(
          url,
          body: json.encode({'title': title, 'body': body}),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(const Duration(seconds: 30));

    print('Response status: ${response.statusCode}');
    print('Response body: ${response.body}');

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data;
    } else if (response.statusCode == 301 || response.statusCode == 302) {
      print('⚠️ Server redirect detected - skipping sync for this note');
      throw Exception(
        'Server redirect issue - note will sync when server is fixed',
      );
    } else {
      try {
        final error = json.decode(response.body);
        throw Exception(
          'Failed to update note: ${error['error'] ?? 'Unknown error'}',
        );
      } catch (e) {
        throw Exception(
          'Failed to update note: HTTP ${response.statusCode} - ${response.body}',
        );
      }
    }
  }

  Future<void> deleteNote({required int id, required String token}) async {
    final url = Uri.parse('${_baseurl}/notes/$id');
    print('Deleting note with URL: $url');
    print('Deleting note ID: $id');

    final response = await _httpClient.delete(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    print('Delete response status: ${response.statusCode}');
    print('Delete response body: ${response.body}');

    if (response.statusCode == 204 || response.statusCode == 200) {
      print('Note $id successfully deleted from API');
    } else if (response.statusCode == 404) {
      print('Note $id not found on API (may already be deleted)');
    } else if (response.statusCode == 301 || response.statusCode == 302) {
      print('⚠️ Server redirect detected during deletion');
      throw Exception('Server redirect issue during deletion');
    } else {
      try {
        final error = json.decode(response.body);
        throw Exception(
          'Failed to delete note: ${error['error'] ?? 'Unknown error'}',
        );
      } catch (e) {
        throw Exception(
          'Failed to delete note: HTTP ${response.statusCode} - ${response.body}',
        );
      }
    }
  }
}
