import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth.dart';
import 'errors.dart';
import 'storage.dart';

class Vybase {
  /// [key] is the project's publishable key (`pk_…`). Use a secret key (`sk_…`) only in server code.
  Vybase({required String url, required this.key, VybaseStorage? storage, http.Client? httpClient})
      : url = url.replaceAll(RegExp(r'/+$'), ''),
        _http = httpClient ?? http.Client() {
    if (key.isEmpty) throw ArgumentError('key is required (your publishable key, pk_…)');
    auth = VybaseAuth(this, storage ?? MemoryStorage());
  }

  final String url;
  final String key;
  final http.Client _http;
  late final VybaseAuth auth;

  /// Low-level request used by the SDK. Throws [VybaseException] for every failure.
  Future<Map<String, dynamic>?> request(String method, String path, {Object? body, String? token}) async {
    final headers = <String, String>{'x-zyvraon-key': key};
    if (body != null) headers['content-type'] = 'application/json';
    if (token != null) headers['authorization'] = 'Bearer $token';
    final req = http.Request(method, Uri.parse('$url$path'))..headers.addAll(headers);
    if (body != null) req.body = jsonEncode(body);
    http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(req));
    } catch (e) {
      throw VybaseException('network_error', e.toString());
    }
    if (res.statusCode == 204) return null;
    Map<String, dynamic>? json;
    try {
      json = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      json = null;
    }
    if (res.statusCode >= 400) {
      final err = json?['error'] as Map<String, dynamic>?;
      throw VybaseException(err?['code'] as String? ?? 'http_error', err?['message'] as String? ?? res.reasonPhrase ?? 'Request failed',
          status: res.statusCode);
    }
    return json;
  }

  void dispose() {
    auth.dispose();
    _http.close();
  }
}
