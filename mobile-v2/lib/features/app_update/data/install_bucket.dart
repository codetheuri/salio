import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

/// This phone's place in staged rollouts: a number from 0 to 99, chosen at
/// random once and kept (docs/10, §6.2). A release at 10% reaches the phones
/// numbered 0 to 9, and raising it to 50% adds 10 to 49 without taking it
/// away from anyone. Kept in a file of its own, not in an account's
/// database: it belongs to the phone, whoever signs in.
class InstallBucket {
  final File file;

  InstallBucket(Directory dir)
    : file = File(p.join(dir.path, 'install_bucket'));

  Future<int> read() async {
    if (file.existsSync()) {
      final saved = int.tryParse((await file.readAsString()).trim());
      if (saved != null && saved >= 0 && saved < 100) return saved;
    }
    final bucket = Random.secure().nextInt(100);
    await file.parent.create(recursive: true);
    await file.writeAsString('$bucket', flush: true);
    return bucket;
  }
}

/// Whether a phone in [bucket] is offered a release at [percent].
bool inRollout(int bucket, int percent) => bucket < percent;
