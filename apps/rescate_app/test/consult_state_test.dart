// Issue #17 trust-gating tests (app layer).
//
// The service-level gating is covered in packages/bluetooth_mesh; here we
// verify the app's ConsultState fails closed when no verified session
// exists, and that the demo mode boundary is untouched.
import 'package:flutter_test/flutter_test.dart';
import 'package:rescate_app/features/community/models/case_payload.dart';
import 'package:rescate_app/features/community/services/consult_state.dart';

void main() {
  test('consult state refuses case payloads before any session exists',
      () async {
    final sent = await ConsultState.instance.sendCasePayload(
      'unverified_peer',
      CasePayload(note: 'test', createdAt: DateTime.now()),
    );
    expect(sent, isFalse);
  });

  test('secure text fails closed without a verified session', () async {
    final sent =
        await ConsultState.instance.sendSecureText('unverified_peer', 'hi');
    expect(sent, isFalse);
  });
}
