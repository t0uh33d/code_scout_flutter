import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:example/clinet.dart';
import 'package:example/dio_interceptor.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class NetworkTestScreen extends StatefulWidget {
  const NetworkTestScreen({super.key});

  @override
  State<NetworkTestScreen> createState() => _NetworkTestScreenState();
}

class _NetworkTestScreenState extends State<NetworkTestScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Dio _dioClient = Dio();

  final List<String> _dioLogs = [];
  final List<String> _httpLogs = [];
  late CodeScoutHttpClient _client;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _setupClients();
  }

  void _setupClients() {
    // Dio client setup
    _dioClient.interceptors.add(CodeScoutDioInterceptor());
    http.Client httpClient = http.Client();

    // HTTP client setup
    _client = CodeScoutHttpClient(client: httpClient as http.BaseClient);
  }

  // Dio Methods
  Future<void> _getRequestDio() async => _handleRequest(() async {
    final response = await _dioClient.get(
      'https://jsonplaceholder.typicode.com/posts/1',
    );
    return 'GET Success: ${response.data}';
  }, 'Dio');

  Future<void> _postRequestDio() async => _handleRequest(() async {
    final response = await _dioClient.post(
      'https://jsonplaceholder.typicode.com/posts',
      data: {'title': 'foo', 'body': 'bar', 'userId': 1},
    );
    return 'POST Success: ${response.data}';
  }, 'Dio');

  // HTTP Methods
  Future<void> _getRequestHttp() async => _handleRequest(() async {
    final response = await _client.get(
      Uri.parse('https://jsonplaceholder.typicode.com/posts/1'),
    );
    return 'GET Success: ${response.body}';
  }, 'HTTP');

  Future<void> _postRequestHttp() async => _handleRequest(() async {
    final response = await _client.post(
      Uri.parse('https://jsonplaceholder.typicode.com/posts'),
      body: jsonEncode({'title': 'foo', 'body': 'bar', 'userId': 1}),
      headers: {'Content-Type': 'application/json'},
    );
    return 'POST Success: ${response.body}';
  }, 'HTTP');

  // Generic request handler
  Future<void> _handleRequest(
    Future<String> Function() request,
    String clientType,
  ) async {
    setState(() => _isLoading = true);
    try {
      final message = await request();
      _addLog(message, clientType);
    } catch (e) {
      _addLog('Error: ${e.toString()}', clientType);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _addLog(String message, String clientType) {
    setState(() {
      if (clientType == 'Dio') {
        _dioLogs.add('${DateTime.now().toIso8601String()}: $message');
      } else {
        _httpLogs.add('${DateTime.now().toIso8601String()}: $message');
      }
    });
  }

  void _clearLogs(String clientType) {
    setState(() {
      if (clientType == 'Dio') {
        _dioLogs.clear();
      } else {
        _httpLogs.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Network Test'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'Dio Client'), Tab(text: 'HTTP Client')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildClientView('Dio'), _buildClientView('HTTP')],
      ),
    );
  }

  Widget _buildClientView(String clientType) {
    final logs = clientType == 'Dio' ? _dioLogs : _httpLogs;
    final methods =
        clientType == 'Dio'
            ? [_getRequestDio, _postRequestDio]
            : [_getRequestHttp, _postRequestHttp];

    return Column(
      children: [
        NetworkControls(
          onGet: methods[0],
          onPost: methods[1],
          onClear: () => _clearLogs(clientType),
          isLoading: _isLoading,
        ),
        Expanded(child: LogListView(logs: logs)),
        if (_isLoading) const LinearProgressIndicator(),
      ],
    );
  }
}

class NetworkControls extends StatelessWidget {
  final VoidCallback onGet;
  final VoidCallback onPost;
  final VoidCallback onClear;
  final bool isLoading;

  const NetworkControls({
    super.key,
    required this.onGet,
    required this.onPost,
    required this.onClear,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Wrap(
        spacing: 8,
        children: [
          ElevatedButton(
            onPressed: isLoading ? null : onGet,
            child: const Text('GET'),
          ),
          ElevatedButton(
            onPressed: isLoading ? null : onPost,
            child: const Text('POST'),
          ),
          ElevatedButton(
            onPressed: isLoading ? null : onClear,
            child: const Text('Clear Logs'),
          ),
        ],
      ),
    );
  }
}

class LogListView extends StatelessWidget {
  final List<String> logs;

  const LogListView({super.key, required this.logs});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: logs.length,
      itemBuilder:
          (context, index) => ListTile(title: Text(logs[index]), dense: true),
    );
  }
}
