import 'package:dio/dio.dart';
import 'package:example/dio_interceptor.dart';

class Network {
  final Dio dio;

  Network({required this.dio});

  void init() {
    dio.interceptors.add(CodeScoutDioInterceptor());
  }
}
