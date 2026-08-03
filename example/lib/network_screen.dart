import 'dart:convert';

import 'package:code_scout_dio/code_scout_dio.dart';
import 'package:code_scout_http/code_scout_http.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

/// Network capture, both ways it is installed.
///
/// Neither package needs the call sites to change: an interceptor on the Dio
/// you already have, or a client that wraps the one you already have. Every
/// request below is captured in three phases — request, then response or error
/// — correlated by one request id, and the dashboard pairs them back into a
/// single row.
class NetworkScreen extends StatefulWidget {
  const NetworkScreen({super.key});

  @override
  State<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends State<NetworkScreen> {
  // One line to install, where the client is built.
  final Dio _dio = Dio()..interceptors.add(CodeScoutDioInterceptor());

  // Wraps a plain http.Client() when given nothing. Pass `client:` if you
  // already have one configured.
  final CodeScoutHttpClient _http = CodeScoutHttpClient();

  final List<String> _results = [];
  bool _busy = false;

  static const _base = 'https://jsonplaceholder.typicode.com';

  Future<void> _run(String label, Future<String> Function() call) async {
    setState(() => _busy = true);
    String line;
    try {
      line = '$label — ${await call()}';
    } catch (e) {
      // Captured as an error phase before it ever reaches here. Both packages
      // rethrow, so your own error handling is unchanged.
      line = '$label — failed: $e';
    }
    if (!mounted) return;
    setState(() {
      _results.insert(0, line);
      _busy = false;
    });
  }

  String _short(Object? body) {
    final text = body is String ? body : jsonEncode(body);
    return text.length > 80 ? '${text.substring(0, 80)}…' : text;
  }

  @override
  void dispose() {
    _dio.close();
    _http.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_busy) const LinearProgressIndicator(),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _action('dio GET', () async {
                final res = await _dio.get('$_base/posts/1');
                return _short(res.data);
              }),
              _action('dio POST', () async {
                final res = await _dio.post('$_base/posts',
                    data: {'title': 'foo', 'body': 'bar', 'userId': 1});
                return _short(res.data);
              }),
              _action('http GET', () async {
                final res = await _http.get(Uri.parse('$_base/posts/1'));
                return _short(res.body);
              }),
              _action('http POST', () async {
                final res = await _http.post(
                  Uri.parse('$_base/posts'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({'title': 'foo', 'body': 'bar'}),
                );
                return _short(res.body);
              }),
              // A host that does not resolve, so the error phase is easy to
              // find in the dashboard sitting next to the successes.
              _action('a call that fails', () async {
                final res = await _dio.get('https://not-a-real-host.invalid');
                return _short(res.data);
              }),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _results.isEmpty
              ? const Center(child: Text('Make a request'))
              : ListView.separated(
                  itemCount: _results.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) => ListTile(
                    dense: true,
                    title:
                        Text(_results[i], style: const TextStyle(fontSize: 13)),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _action(String label, Future<String> Function() call) {
    return FilledButton.tonal(
      onPressed: _busy ? null : () => _run(label, call),
      child: Text(label),
    );
  }
}
