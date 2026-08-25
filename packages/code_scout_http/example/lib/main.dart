// Wiring the http client wrapper into an app that already uses CodeScout.
//
// CodeScoutHttpClient wraps any http.Client. Use it wherever you would have
// used the inner one and every call it makes is captured. Closing it closes
// the client it wraps, so a caller following package:http's own advice does
// not leak the inner connection pool.
import 'package:code_scout/code_scout.dart';
import 'package:code_scout_http/code_scout_http.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(home: Home());
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final _client = CodeScoutHttpClient(client: http.Client());
  String _status = 'Tap to make a request';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // No credentials here, so this stays entirely on the device: the console
      // and the floating panel work with no server at all.
      await CodeScout.instance.init(freshContextFetcher: () => context);
    });
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Future<void> _call() async {
    try {
      final res = await _client.get(Uri.parse('https://example.com'));
      setState(() => _status = 'GET example.com -> ${res.statusCode}');
    } catch (e) {
      // Errors from the inner client are rethrown untouched, so your own error
      // handling is unchanged by wrapping.
      setState(() => _status = 'failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('code_scout_http')),
        body: Center(child: Text(_status)),
        floatingActionButton: FloatingActionButton(
          onPressed: _call,
          child: const Icon(Icons.download),
        ),
      );
}
