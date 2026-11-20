import 'package:test/test.dart';
import 'package:web_dex/shared/utils/encryption_tool.dart';

import '../../support/legacy_wallet_file_writer.dart';

void testEncryptDataTool() {
  test('Legacy data still decrypts', () async {
    const password = '123';
    const data = 'Hello my friend';

    expect(
      await EncryptionTool().decryptData(
        password,
        await legacyEncrypt(password, data),
      ),
      data,
    );
  });

  test('Legacy data does not decrypt with another password', () async {
    const data = 'Hello my friend';
    final encrypted = await legacyEncrypt('123', data);

    expect(await EncryptionTool().decryptData('1234', encrypted), isNot(data));
  });
}
