import 'dart:convert';

import 'package:dio/dio.dart';

import 'api_exception.dart';

/// Talks to server-v2's `/api/v1`, and turns Tusk's envelope
/// (`{success, message, data}` or `{success, message, errors}`) into either
/// the `data` value or an [ApiException].
///
/// Nothing here retries. The sync engine retries pushes, which its
/// operation_id makes safe. An online-only save is safe to repeat only when
/// it carries an id the phone made, which the server answers again with
/// the same record (placing a purchase order, B8); the screen keeps that
/// id across the user's retries.
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

  /// GET of a file, such as a PDF: its bytes, or an [ApiException] read
  /// from the envelope the server sends instead on failure.
  Future<List<int>> getBytes(String path, {Map<String, Object?>? query}) async {
    final Response<List<int>> response;
    try {
      response = await _dio.get<List<int>>(
        path,
        queryParameters: query,
        options: Options(responseType: ResponseType.bytes),
      );
    } on DioException catch (e) {
      throw _failure(e);
    }
    final status = response.statusCode ?? 0;
    final bytes = response.data ?? const <int>[];
    if (status >= 200 && status < 300) return bytes;
    Object? body;
    try {
      body = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      body = null;
    }
    _unwrap(status, body);
    throw ApiException(ApiFailure.server, status: status);
  }

  Future<Object?> _send(Future<Response<Object?>> Function() request) async {
    final Response<Object?> response;
    try {
      response = await request();
    } on DioException catch (e) {
      throw _failure(e);
    }
    return _unwrap(response.statusCode ?? 0, response.data);
  }

  static ApiException _failure(DioException e) => switch (e.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout => const ApiException(ApiFailure.timeout),
    _ => const ApiException(ApiFailure.offline),
  };

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
