import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ApiServices {
  String? _currentBaseUrl;

  String get _baseurl {
    if (_currentBaseUrl == null) {
      final raw = dotenv.env['API_URL'];
      if (raw == null || raw.isEmpty) {
        throw Exception('API_URL not found in .env file');
      }
      _currentBaseUrl = raw;
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
    final url = Uri.parse('${_baseurl}/login');
    print('Logging in user with URL: $url');
    print(
      'Request body: ${json.encode({'email': email, 'password': password})}',
    );

    final response = await http.post(
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
      throw Exception('Failed to login: ${error['message']}');
    }
  }

  // Notes endpoints
  Future<List<Map<String, dynamic>>> getNotes(String token) async {
    final url = Uri.parse('${_baseurl}/notes');
    print('Getting notes with URL: $url');

    final response = await http.get(
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

    final response = await http.post(
      url,
      body: json.encode({'title': title, 'body': body}),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    print('Response status: ${response.statusCode}');
    print('Response body: ${response.body}');

    if (response.statusCode == 201) {
      final data = json.decode(response.body);
      return data;
    } else {
      final error = json.decode(response.body);
      throw Exception(
        'Failed to create note: ${error['error'] ?? 'Unknown error'}',
      );
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

    final response = await http.put(
      url,
      body: json.encode({'title': title, 'body': body}),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    print('Response status: ${response.statusCode}');
    print('Response body: ${response.body}');

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data;
    } else {
      final error = json.decode(response.body);
      throw Exception(
        'Failed to update note: ${error['error'] ?? 'Unknown error'}',
      );
    }
  }

  Future<void> deleteNote({required int id, required String token}) async {
    final url = Uri.parse('${_baseurl}/notes/$id');
    print('Deleting note with URL: $url');

    final response = await http.delete(
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
