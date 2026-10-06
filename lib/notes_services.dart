import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class NotesService {
  // Your laptop IP on local WiFi (backend running at 8000)
  // Override at build time: --dart-define=BACKEND_URL=https://... --dart-define=APP_KEY=...
  static const String backendBaseUrl =
      String.fromEnvironment('BACKEND_URL', defaultValue: "http://192.168.1.5:8000");
  static const String _appKey = String.fromEnvironment('APP_KEY');

  /// ping endpoint for connection test
  static Future<String> ping() async {
    final resp = await http
        .get(Uri.parse("$backendBaseUrl/ping"))
        .timeout(const Duration(seconds: 70)); // allows a free-tier cold start

    if (resp.statusCode == 200) return resp.body;
    throw Exception("Ping failed: ${resp.statusCode}");
  }

  /// Call backend to generate notes (returns PDF bytes)
  static Future<Uint8List> generatePdfBytes(String topic,
      {Duration timeout = const Duration(seconds: 60)}) async {
    final resp = await http
        .post(
      Uri.parse("$backendBaseUrl/generate-notes"),
      headers: {"Content-Type": "application/json", if (_appKey.isNotEmpty) "X-App-Key": _appKey},
      body: jsonEncode({"topic": topic}),
    )
        .timeout(timeout);

    if (resp.statusCode == 200) {
      return resp.bodyBytes;
    } else {
      throw Exception("Server returned ${resp.statusCode}: ${resp.body}");
    }
  }
}
