// An in-memory stand-in for server-v2's /sync endpoints, for the sync
// engine's failure tests: it can lose answers, time out, fail with a 500,
// replay a repeated operation, refuse records, and forget deletions so the
// phone has to resync. The live tests check the same engine against the
// real server.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// What goes wrong with the next request.
enum Fault {
  /// No connection: the request never reaches the server.
  offline,

  /// The server does the work, and the answer is lost on the way back.
  lostAnswer,

  /// No answer in time; the server never saw the request.
  timeout,

  /// The server fails with a 500 before doing anything.
  serverError,
}

class FakeServer implements HttpClientAdapter {
  /// Records by kind (`customers`, `transactions`, …) and id, as the server
  /// would send them.
  final records = <String, Map<String, Map<String, dynamic>>>{};
  final _seq = <String, int>{};
  var _nextSeq = 0;

  /// Cursors at or below this are told to resync, as after the server
  /// collects old deletions.
  var horizon = 0;

  /// The server's clock.
  DateTime Function() now;

  /// Faults for the coming requests, used up in order.
  final faults = <Fault>[];

  /// Called on every pull, before answering: a test can move the phone's
  /// clock to make the page slow, or change the records.
  void Function(int cursor, int limit)? onPull;

  /// Decides whether to refuse a pushed record, and why. Null accepts it.
  String? Function(String kind, Map<String, dynamic> record)? refuse;

  /// Kinds hidden from the phone on a pull, as suppliers are from staff.
  final hidden = <String>{};

  /// Whether a push answer includes the server's copies (B2). An older
  /// server does not.
  var sendsCurrent = true;

  /// Every push body received, as sent.
  final pushes = <Map<String, dynamic>>[];

  /// Every pull's limit, in order.
  final pullLimits = <int>[];

  final _answers = <String, Map<String, dynamic>>{};

  FakeServer({DateTime Function()? now})
    : now = now ?? (() => DateTime.now().toUtc());

  /// Stores a record as if another phone had pushed it.
  void put(String kind, Map<String, dynamic> record) {
    final id = record['id'] as String;
    (records[kind] ??= {})[id] = {...record};
    _seq['$kind/$id'] = ++_nextSeq;
  }

  /// Deletes a record and collects its tombstone at once, as the server
  /// does after the retention period: the record is gone, and phones that
  /// had not pulled the deletion must resync.
  void purge(String kind, String id) {
    records[kind]?.remove(id);
    _seq.remove('$kind/$id');
    horizon = ++_nextSeq;
  }

  int get seq => _nextSeq;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final fault = faults.isEmpty ? null : faults.removeAt(0);
    switch (fault) {
      case Fault.offline:
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      case Fault.timeout:
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.receiveTimeout,
        );
      case Fault.serverError:
        return _json(500, {'success': false, 'message': 'boom'});
      case Fault.lostAnswer || null:
        break;
    }

    final Map<String, dynamic> data;
    if (options.path.endsWith('/sync/push')) {
      final bytes = <int>[];
      await requestStream?.forEach(bytes.addAll);
      data = _push(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);
    } else if (options.path.endsWith('/sync/pull')) {
      data = _pull(
        int.parse('${options.queryParameters['cursor']}'),
        int.parse('${options.queryParameters['limit']}'),
      );
    } else {
      return _json(404, {'success': false, 'message': 'not found'});
    }

    if (fault == Fault.lostAnswer) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    return _json(200, {'success': true, 'data': data});
  }

  Map<String, dynamic> _push(Map<String, dynamic> body) {
    pushes.add(body);
    final op = body['operation_id'] as String;
    final stored = _answers[op];
    if (stored != null) {
      return {
        ...stored,
        'replayed': true,
        'current': _current(stored['conflicts'] as List<dynamic>),
        'server_time': now().toIso8601String(),
      };
    }

    final conflicts = <Map<String, dynamic>>[];
    for (final entry in body.entries) {
      if (entry.value is! List) continue;
      for (final record
          in (entry.value as List<dynamic>).cast<Map<String, dynamic>>()) {
        final reason = refuse?.call(entry.key, record);
        if (reason != null) {
          conflicts.add({
            'table': entry.key,
            'id': record['id'],
            'reason': reason,
          });
        } else {
          final known = records[entry.key]?[record['id']] ?? {};
          put(
            entry.key,
            {...known, ...record, 'updated_at': now().toIso8601String()}
              ..remove('changed_fields'),
          );
        }
      }
    }
    final answer = <String, dynamic>{
      'operation_id': op,
      'conflicts': conflicts,
      'replayed': false,
    };
    _answers[op] = answer;
    return {
      ...answer,
      if (sendsCurrent) 'current': _current(conflicts),
      'server_time': now().toIso8601String(),
    };
  }

  /// The server's copies of the records the conflicts name, read now.
  Map<String, dynamic>? _current(List<dynamic> conflicts) {
    if (!sendsCurrent) return null;
    final out = <String, List<Map<String, dynamic>>>{};
    for (final c in conflicts.cast<Map<String, dynamic>>()) {
      final kind = c['table'] as String;
      final copy = records[kind]?[c['id']];
      if (copy != null && !hidden.contains(kind)) {
        (out[kind] ??= []).add(copy);
      }
    }
    return out;
  }

  Map<String, dynamic> _pull(int cursor, int limit) {
    pullLimits.add(limit);
    onPull?.call(cursor, limit);
    if (cursor > 0 && cursor <= horizon) {
      return {
        'next_cursor': 0,
        'has_more': false,
        'resync_required': true,
        'server_time': now().toIso8601String(),
      };
    }
    // One sequence across every kind, as on the server; the page limit is
    // applied to the whole page here, which is stricter than per kind.
    final after =
        _seq.entries
            .where((e) => e.value > cursor && !hidden.contains(_kindOf(e.key)))
            .toList()
          ..sort((a, b) => a.value.compareTo(b.value));
    final page = after.take(limit).toList();
    final out = <String, dynamic>{
      'next_cursor': page.isEmpty ? cursor : page.last.value,
      'has_more': after.length > page.length,
      'resync_required': false,
      'server_time': now().toIso8601String(),
    };
    for (final e in page) {
      final kind = _kindOf(e.key);
      ((out[kind] ??= <Map<String, dynamic>>[]) as List).add(
        records[kind]![e.key.substring(kind.length + 1)],
      );
    }
    return out;
  }

  static String _kindOf(String key) => key.substring(0, key.indexOf('/'));

  static ResponseBody _json(int status, Object body) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}
