import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_config.dart';

class DioClient {
  DioClient._();

  static final Dio instance = Dio(
    BaseOptions(
      baseUrl: ApiConfig.resolveBaseUrl(),
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      contentType: 'application/json',
    ),
  )..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.headers['Accept'] = 'application/json';
          handler.next(options);
        },
        onError: (e, handler) {
          if (kDebugMode) {
            debugPrint('Dio error [${e.requestOptions.method}] ${e.requestOptions.uri}: ${e.message}');
          }
          handler.next(e);
        },
      ),
    );
}
