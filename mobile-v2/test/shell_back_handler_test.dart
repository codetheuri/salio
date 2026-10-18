import 'package:flutter_test/flutter_test.dart';
import 'package:salio/app/shell/shell_back_handler.dart';

void main() {
  test('back never closes the app from a section', () {
    expect(
      backTargetFor(onHome: false, openedFromMore: false),
      BackTarget.home,
    );
    expect(backTargetFor(onHome: false, openedFromMore: true), BackTarget.more);
  });

  test('back on Home asks before closing', () {
    expect(backTargetFor(onHome: true, openedFromMore: false), BackTarget.exit);
  });
}
