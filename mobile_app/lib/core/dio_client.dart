import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'constants/app_constants.dart';

class DioClient {
  DioClient._();

  static final Dio instance = Dio(
    BaseOptions(
      baseUrl: AppConstantsV2.apiBaseUrl,
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
