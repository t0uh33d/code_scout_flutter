// Wiring the Dio interceptor into an app that already uses CodeScout.
//
// The interceptor is the whole integration: add it once and every call Dio
// makes shows up in the in-app panel and, if you have configured a dashboard,
// on the Network screen there too. It never fails a request it is observing.
import 'package:code_scout/code_scout.dart';
import 'package:code_scout_dio/code_scout_dio.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

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
  final _dio = Dio()..interceptors.add(CodeScoutDioInterceptor());
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

  Future<void> _call() async {
    try {
      final res = await _dio.get<dynamic>('https://example.com');
      setState(() => _status = 'GET example.com -> ${res.statusCode}');
    } on DioException catch (e) {
      // Captured either way. A failed call is usually the interesting one.
      setState(() => _status = 'failed: ${e.type.name}');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('code_scout_dio')),
        body: Center(child: Text(_status)),
        floatingActionButton: FloatingActionButton(
          onPressed: _call,
          child: const Icon(Icons.download),
        ),
      );
}
