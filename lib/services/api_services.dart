import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ApiServices {
  String? _currentBaseUrl;

  // Custom HTTP client that handles redirects properly
  static final http.Client _httpClient = http.Client();

  // Helper method to handle redirects by following the Location header
  Future<Map<String, dynamic>> _followRedirect(
    String redirectLocation,
    String originalEndpoint,
    Map<String, dynamic> data,
    String token,
    String method, {
    int redirectCount = 0,
    Set<String>? attemptedUrls,
  }) async {
    // Initialize attemptedUrls set to track URLs we've already tried
    attemptedUrls ??= <String>{};

    // Maximum redirect limit to prevent infinite loops
    const maxRedirects = 2;
    if (redirectCount >= maxRedirects) {
      print(
        '❌ Redirect limit reached ($redirectCount). Server misconfiguration!',
      );
      throw Exception(
        'Too many redirects ($redirectCount). This indicates a server '
        'configuration issue. Please check your Render.com API deployment.',
      );
    }

    // Check if redirect location is missing the endpoint path
    String targetUrl = redirectLocation;

    // If the redirect is to the base domain only (server stripped the path),
    // append the original endpoint
    if (!redirectLocation.contains('/api') &&
        !redirectLocation.endsWith(originalEndpoint)) {
      // Remove trailing slash from redirect location if present
      if (targetUrl.endsWith('/')) {
        targetUrl = targetUrl.substring(0, targetUrl.length - 1);
      }
      // Ensure we have /api prefix
      targetUrl = targetUrl + '/api' + originalEndpoint;
      print(
        '⚠️ Server stripped endpoint from redirect, reconstructing: $targetUrl',
      );
    }

    // Check if we've already tried this URL (infinite redirect loop detection)
    if (attemptedUrls.contains(targetUrl)) {
      print('❌ Redirect loop detected! Already tried URL: $targetUrl');
      throw Exception(
        'Redirect loop detected. The server keeps redirecting to the same URL. '
        'This is a server configuration issue on Render.com that needs fixing.',
      );
    }

    attemptedUrls.add(targetUrl);
    print('Following redirect #${redirectCount + 1} to: $targetUrl');

    http.Response response;
    if (method == 'POST') {
      response = await _httpClient
          .post(
            Uri.parse(targetUrl),
            body: json.encode(data),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 30));
    } else if (method == 'PUT') {
      response = await _httpClient
          .put(
            Uri.parse(targetUrl),
            body: json.encode(data),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 30));
    } else {
      throw Exception('Unsupported method: $method');
    }

    print('Redirect follow response status: ${response.statusCode}');

    if (response.statusCode == 201 || response.statusCode == 200) {
      final result = json.decode(response.body);
      print('✅ Successfully followed redirect after ${redirectCount + 1} try');
      return result;
    } else if (response.statusCode == 301 || response.statusCode == 302) {
      final nextLocation = response.headers['location'];
      if (nextLocation != null && nextLocation.isNotEmpty) {
        print('⚠️ Another redirect (${redirectCount + 1}/$maxRedirects)');
        // Recursively follow the next redirect
        return await _followRedirect(
          nextLocation,
          originalEndpoint,
          data,
          token,
          method,
          redirectCount: redirectCount + 1,
          attemptedUrls: attemptedUrls,
        );
      }
      print('Redirect response body: ${response.body}');
      throw Exception(
        'Redirect without location header: ${response.statusCode}',
      );
    } else {
      print('Redirect follow failed. Response body: ${response.body}');
      throw Exception(
        'Redirect follow failed: ${response.statusCode} - ${response.body}',
      );
    }
  }

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
    } else if (response.statusCode == 301 || response.statusCode == 302) {
      final location = response.headers['location'] ?? '';
      print('Redirect detected to: $location');
      print('⚠️ WARNING: API server is redirecting. This may cause issues!');

      if (location.isNotEmpty) {
        // Follow the redirect using the Location header
        return await _followRedirect(
          location,
          '/notes',
          {'title': title, 'body': body},
          token,
          'POST',
        );
      } else {
        throw Exception(
          'Redirect without location header: ${response.statusCode}',
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
      final location = response.headers['location'] ?? '';
      print('Redirect detected to: $location');
      print('⚠️ WARNING: API server is redirecting. This may cause issues!');

      if (location.isNotEmpty) {
        // Follow the redirect using the Location header
        return await _followRedirect(
          location,
          '/notes/$id',
          {'title': title, 'body': body},
          token,
          'PUT',
        );
      } else {
        throw Exception(
          'Redirect without location header: ${response.statusCode}',
        );
      }
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

    final response = await _httpClient.delete(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    print('Response status: ${response.statusCode}');

    if (response.statusCode != 204) {
      final error = json.decode(response.body);
      throw Exception(
        'Failed to delete note: ${error['error'] ?? 'Unknown error'}',
      );
    }
  }
}
