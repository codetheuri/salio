import 'package:dio/dio.dart';

import 'api_exception.dart';

/// Talks to server-v2's `/api/v1`, and turns Tusk's envelope
/// (`{success, message, data}` or `{success, message, errors}`) into either
/// the `data` value or an [ApiException].
///
/// Nothing here retries. The sync engine retries pushes, which its
/// operation_id makes safe; an online-only save must not be retried until
/// the server accepts an Idempotency-Key (docs/10, §4.6, B8).
class ApiClient {
  final Dio _dio;

  ApiClient({
    required Uri origin,
    required String? Function() token,
    required String appHeader,
    HttpClientAdapter? adapter,
  }) : _dio = Dio(
         BaseOptions(
           baseUrl: origin.resolve('/api/v1').toString(),
           // DairyGo's limits, set for 2G and 3G (docs/10, §4.6).
           connectTimeout: const Duration(seconds: 20),
           receiveTimeout: const Duration(seconds: 45),
           sendTimeout: const Duration(seconds: 45),
           responseType: ResponseType.json,
           // Every status comes back as a response; _unwrap reads the envelope.
           validateStatus: (_) => true,
           headers: {'X-Salio-App': appHeader},
         ),
       ) {
    if (adapter != null) _dio.httpClientAdapter = adapter;
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final t = token();
          if (t != null) options.headers['Authorization'] = 'Bearer $t';
          handler.next(options);
        },
      ),
    );
  }

  /// GET, returning the envelope's `data`.
  Future<Object?> get(String path, {Map<String, Object?>? query}) =>
      _send(() => _dio.get<Object?>(path, queryParameters: query));

  /// POST, returning the envelope's `data`.
  Future<Object?> post(String path, Object? body) =>
      _send(() => _dio.post<Object?>(path, data: body));

  Future<Object?> _send(Future<Response<Object?>> Function() request) async {
    final Response<Object?> response;
    try {
      response = await request();
    } on DioException catch (e) {
      throw switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout => const ApiException(
          ApiFailure.timeout,
        ),
        _ => const ApiException(ApiFailure.offline),
      };
    }
    return _unwrap(response.statusCode ?? 0, response.data);
  }

  static Object? _unwrap(int status, Object? body) {
    final envelope = body is Map<String, dynamic> ? body : null;
    if (status >= 200 && status < 300 && envelope?['success'] == true) {
      return envelope!['data'];
    }

    final message = envelope?['message'];
    final errors = envelope?['errors'];
    throw ApiException(
      switch (status) {
        401 => ApiFailure.unauthorized,
        403 => ApiFailure.forbidden,
        400 || 422 => ApiFailure.invalid,
        404 => ApiFailure.notFound,
        409 => ApiFailure.conflict,
        _ => ApiFailure.server,
      },
      status: status,
      message: message is String ? message : '',
      fieldErrors: errors is Map<String, dynamic>
          ? {
              for (final e in errors.entries)
                if (e.value is String) e.key: e.value as String,
            }
          : const {},
    );
  }
}
