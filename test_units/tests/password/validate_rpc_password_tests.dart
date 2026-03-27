import 'package:test/test.dart';
import 'package:web_dex/shared/utils/password.dart';

void testValidateRPCPassword() {
  test('validate password', () {
    expect(validateRPCPassword('123'), false);
    expect(validateRPCPassword(''), false);
    expect(validateRPCPassword('OneTwoThree123?'), true);
  });
}
