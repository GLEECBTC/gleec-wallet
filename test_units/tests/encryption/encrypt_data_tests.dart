import 'package:test/test.dart';
import 'package:web_dex/shared/utils/encryption_tool.dart';

void testEncryptDataTool() {
  test('Test that algorithm is consistent', () async {
    // Should produce the same text after every encryption
    final tool = EncryptionTool();
    const password = '123';
    const data = 'Hello my friend';

    expect(
        await tool.decryptData(
            password, await tool.encryptData(password, data)),
        data);
  });

  test('Test that algorithm encrypt every time diff result', () async {
    // For security reasons, should produce different ciphertext after every encryption
    // But decryption should produce the same plaintext
    final tool = EncryptionTool();
    const password = '123';
    const data = 'Hello my friend';

    final cipherText1 = await tool.encryptData(password, data);
    final cipherText2 = await tool.encryptData(password, data);

    expect(cipherText1 != cipherText2, true);

    final plainText1 = await tool.decryptData(password, cipherText1);
    final plainText2 = await tool.decryptData(password, cipherText2);
    expect(plainText1, plainText2);
  });
}
