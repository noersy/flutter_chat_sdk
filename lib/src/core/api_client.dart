import 'dart:convert';
import 'dart:developer';
import 'package:http/http.dart' as http;
import 'errors/failures.dart';

class ApiClient {
  final String baseUrl;
  final http.Client client;

  ApiClient({required this.baseUrl, http.Client? client}) : client = client ?? http.Client();

  Future<dynamic> post(String endpoint, {Map<String, dynamic>? body}) async {
    try {
      final response = await client.post(
        Uri.parse('$baseUrl$endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: body != null ? jsonEncode(body) : null,
      );
      return _handleResponse(response);
    } catch (e) {
      throw const ConnectionFailure('Failed to connect to server');
    }
  }

  Future<dynamic> get(String endpoint) async {
    try {
      final response = await client.get(
        Uri.parse('$baseUrl$endpoint'),
        headers: {'Content-Type': 'application/json'},
      );
      return _handleResponse(response);
    } catch (e) {
      throw const ConnectionFailure('Failed to connect to server');
    }
  }

  Future<dynamic> put(String endpoint, {Map<String, dynamic>? body}) async {
    try {
      final response = await client.put(
        Uri.parse('$baseUrl$endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: body != null ? jsonEncode(body) : null,
      );
      return _handleResponse(response);
    } catch (e) {
      throw const ConnectionFailure('Failed to connect to server');
    }
  }

  Future<dynamic> delete(String endpoint) async {
    try {
      final response = await client.delete(
        Uri.parse('$baseUrl$endpoint'),
        headers: {'Content-Type': 'application/json'},
      );
      return _handleResponse(response);
    } catch (e) {
      throw const ConnectionFailure('Failed to connect to server');
    }
  }

  dynamic _handleResponse(http.Response response) {
    log('Response status: ${response.statusCode}', name: 'SDK CHAT');
    log('Response body: ${response.body}', name: 'SDK CHAT');
    final body = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body['data'];
    } else {
      String message = 'Unknown error';
      if (body is Map && body.containsKey('error')) {
        message = body['error'];
      }
      throw ServerFailure(message);
    }
  }
}
