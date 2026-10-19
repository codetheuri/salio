import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'server_clock.dart';

/// One clock for the app. The sync engine sets its offset from each answer
/// and saves it in the account's database.
final serverClockProvider = Provider<ServerClock>((ref) => ServerClock());
