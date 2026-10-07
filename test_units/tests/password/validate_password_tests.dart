import 'dart:math';

import 'package:test/test.dart';
import 'package:web_dex/shared/utils/validators.dart';

void testcheckPasswordRequirements() {
  group('Password validation tests', () {
    test('Too short passwords should fail', () {
      expect(
        checkPasswordRequirements('Abc1!'),
        PasswordValidationError.tooShort,
      );
      expect(checkPasswordRequirements(''), PasswordValidationError.tooShort);
      expect(
        checkPasswordRequirements('A1b!'),
        PasswordValidationError.tooShort,
      );
    });

    test('Passwords containing "password" should fail', () {
      expect(
        checkPasswordRequirements('myPassword123!'),
        PasswordValidationError.containsPassword,
      );
      expect(
        checkPasswordRequirements('PASSWORDabc123!'),
        PasswordValidationError.containsPassword,
      );
      expect(
        checkPasswordRequirements('pAsSwOrD123!'),
        PasswordValidationError.containsPassword,
      );
      expect(
        checkPasswordRequirements('My-password-is-secure!123'),
        PasswordValidationError.containsPassword,
      );
    });

    test('Passwords without digits should fail', () {
      expect(
        checkPasswordRequirements('StrongPass!'),
        PasswordValidationError.missingDigit,
      );
      expect(
        checkPasswordRequirements('NoDigitsHere!@#'),
        PasswordValidationError.missingDigit,
      );
    });

    test('Passwords without lowercase should fail', () {
      expect(
        checkPasswordRequirements('STRONG123!'),
        PasswordValidationError.missingLowercase,
      );
      expect(
        checkPasswordRequirements('ALL123CAPS!@#'),
        PasswordValidationError.missingLowercase,
      );
    });

    test('Passwords without uppercase should fail', () {
      expect(
        checkPasswordRequirements('strong123!'),
        PasswordValidationError.missingUppercase,
      );
      expect(
        checkPasswordRequirements('all123lower!@#'),
        PasswordValidationError.missingUppercase,
      );
    });

    test('Passwords without special characters should fail', () {
      expect(
        checkPasswordRequirements('Strong123'),
        PasswordValidationError.missingSpecialCharacter,
      );
      expect(
        checkPasswordRequirements('NoSpecial1Characters2'),
        PasswordValidationError.missingSpecialCharacter,
      );
    });

    test('Multiple validation errors should return most critical first', () {
      expect(
        checkPasswordRequirements('pass'),
        PasswordValidationError.tooShort,
      );
      expect(
        checkPasswordRequirements('passwordddd'),
        PasswordValidationError.containsPassword,
      );
      expect(
        checkPasswordRequirements('Abcaaa1234*%'),
        PasswordValidationError.consecutiveCharacters,
      );
      expect(
        checkPasswordRequirements('Abcde123'),
        PasswordValidationError.missingSpecialCharacter,
      );
    });

    test('Edge cases with spaces and special formatting', () {
      expect(
        checkPasswordRequirements('Pass 123!'),
        PasswordValidationError.none,
      );
      expect(
        checkPasswordRequirements('Tab\t123!A'),
        PasswordValidationError.none,
      );
      expect(
        checkPasswordRequirements('Line\nBreak123!A'),
        PasswordValidationError.none,
      );
    });

    test('Passwords with numbers in various positions', () {
      expect(
        checkPasswordRequirements('1AbcSpecial!'),
        PasswordValidationError.none,
      );
      expect(
        checkPasswordRequirements('Abc1Special!'),
        PasswordValidationError.none,
      );
      expect(
        checkPasswordRequirements('AbcSpecial!1'),
        PasswordValidationError.none,
      );
    });

    test('Various special characters', () {
      expect(
        checkPasswordRequirements('AbcDef123@'),
        PasswordValidationError.none,
      );
      expect(
        checkPasswordRequirements('Abc_Def123#'),
        PasswordValidationError.none,
      );
      expect(
        checkPasswordRequirements(r'AbcDef123$'),
        PasswordValidationError.none,
      );
      expect(
        checkPasswordRequirements('AbcDef123%'),
        PasswordValidationError.none,
      );
      expect(
        checkPasswordRequirements('AbcDef123&'),
        PasswordValidationError.none,
      );
    });

    test('Valid passwords should not fail', () {
      expect(
        checkPasswordRequirements('Very!hard!pass!77'),
        PasswordValidationError.none,
      );
      expect(
        checkPasswordRequirements('Komodo2024!'),
        PasswordValidationError.none,
      );
      expect(
        checkPasswordRequirements('Complex!P4ssword123'),
        PasswordValidationError.none,
      );
      expect(
        checkPasswordRequirements(r'!P4ssword#$@'),
        PasswordValidationError.none,
      );
      expect(
        checkPasswordRequirements('Mix3d_Ch4r4ct3rs!'),
        PasswordValidationError.none,
      );
    });

    test('Password specifically mentioned in the issue should be rejected', () {
      // Should fail (has consecutive characters)
      expect(
        checkPasswordRequirements('Very!hard!pass!777'),
        PasswordValidationError.consecutiveCharacters,
      );
    });

    test('Passwords with three or more consecutive identical '
        'characters should fail', () {
      expect(
        checkPasswordRequirements('Strong111Security!'),
        PasswordValidationError.consecutiveCharacters,
      );
      expect(
        checkPasswordRequirements('Secure222!A'),
        PasswordValidationError.consecutiveCharacters,
      );
      expect(
        checkPasswordRequirements('A1!Secure333'),
        PasswordValidationError.consecutiveCharacters,
      );

      expect(
        checkPasswordRequirements('aaaStrong1!'),
        PasswordValidationError.consecutiveCharacters,
      );
      expect(
        checkPasswordRequirements('Strong1!bbb'),
        PasswordValidationError.consecutiveCharacters,
      );
      expect(
        checkPasswordRequirements('Strong1!CCC'),
        PasswordValidationError.consecutiveCharacters,
      );
      expect(
        checkPasswordRequirements('Strong1!!!Secure'),
        PasswordValidationError.consecutiveCharacters,
      );
      expect(
        checkPasswordRequirements('Strong1###Secure'),
        PasswordValidationError.consecutiveCharacters,
      );
      expect(
        checkPasswordRequirements(r'Strong1$$$Secure'),
        PasswordValidationError.consecutiveCharacters,
      );
      expect(
        checkPasswordRequirements('Strong1!aaaaa'),
        PasswordValidationError.consecutiveCharacters,
      );
      expect(
        checkPasswordRequirements('Strong1!44444'),
        PasswordValidationError.consecutiveCharacters,
      );
      expect(
        checkPasswordRequirements('Strong1!!!!!'),
        PasswordValidationError.consecutiveCharacters,
      );
    });

    test(
      'Valid passwords with two consecutive identical characters should pass',
      () {
        expect(
          checkPasswordRequirements('Strong11Secured!'),
          PasswordValidationError.none,
        );
        expect(
          checkPasswordRequirements('Strong!!Secured1'),
          PasswordValidationError.none,
        );
        expect(
          checkPasswordRequirements('aaStrong1!Secured'),
          PasswordValidationError.none,
        );
      },
    );

    test('Special case - passwords with unicode characters', () {
      expect(
        checkPasswordRequirements('Пароль123!'),
        PasswordValidationError.none,
      );
      expect(
        checkPasswordRequirements('密码Abc123!'),
        PasswordValidationError.none,
      );
      expect(
        checkPasswordRequirements('Mötley123!'),
        PasswordValidationError.none,
      );
    });

    test('Extended Unicode character password tests', () {
      expect(
        checkPasswordRequirements('علي123!Abc'), // Arabic
        PasswordValidationError.none,
      );
      expect(
        checkPasswordRequirements('こんにちは123!Ab'), // Japanese
        PasswordValidationError.none,
      );
      expect(
        checkPasswordRequirements('안녕하세요123!Ab'), // Korean
        PasswordValidationError.none,
      );
      expect(
        checkPasswordRequirements('Привет123!Ab'), // Cyrillic
        PasswordValidationError.none,
      );
      expect(
        checkPasswordRequirements('Γειά123!Aa'), // Greek
        PasswordValidationError.none,
      );
      expect(
        checkPasswordRequirements('שלום123!Aa'), // Hebrew
        PasswordValidationError.none,
      );
      expect(
        checkPasswordRequirements('नमस्ते123!Ab'), // Devanagari
        PasswordValidationError.none,
      );
    });

    test('Unicode edge cases and challenging patterns', () {
      expect(
        checkPasswordRequirements('Раssw0rd!'), // Cyrillic 'Р' (not Latin 'P')
        PasswordValidationError.none,
      );

      expect(
        checkPasswordRequirements('Pass\u200Bword123!'),
        PasswordValidationError.none,
      );

      expect(
        // a + combining acute accent
        checkPasswordRequirements('Pa\u0301ssword123!'),
        PasswordValidationError.none,
      );

      expect(
        checkPasswordRequirements('Strong🔑123!A'),
        PasswordValidationError.none,
      );
      expect(
        checkPasswordRequirements('A1!🎮🎲🎯aa'),
        PasswordValidationError.none,
      );

      expect(
        checkPasswordRequirements('Strоng123!'),
        PasswordValidationError.none,
      );
    });

    test('Unicode sequential characters detection', () {
      expect(
        checkPasswordRequirements('Strong爱爱爱123!'),
        PasswordValidationError.consecutiveCharacters,
      );
      expect(
        checkPasswordRequirements('Strong😊😊😊123!'),
        PasswordValidationError.consecutiveCharacters,
      );

      // Characters that look similar but are actually different code points
      expect(
        checkPasswordRequirements('StrongАААbc123!'),
        PasswordValidationError.consecutiveCharacters,
      );
    });

    test('Bidirectional text and special Unicode formatting', () {
      // Right-to-left marks and embedding
      expect(
        checkPasswordRequirements('Pass\u200Eword123!A'), // Contains LTR mark
        PasswordValidationError.none,
      );
      expect(
        checkPasswordRequirements('Pass\u200Fword123!A'), // Contains RTL mark
        PasswordValidationError.none,
      );

      // Mixed directionality
      expect(
        checkPasswordRequirements('Abcהמסיסמ123!'), // Hebrew mixed with Latin
        PasswordValidationError.none,
      );

      // Special spaces
      expect(
        checkPasswordRequirements('Pass\u2007word123!A'), // Figure space
        PasswordValidationError.none,
      );
      expect(
        checkPasswordRequirements('Pass\u00A0word123!A'), // Non-breaking space
        PasswordValidationError.none,
      );
    });

    test('Advanced emoji password tests in valid passwords', () {
      expect(
        checkPasswordRequirements('Strong123!🔒'),
        PasswordValidationError.none,
      );
      expect(
        checkPasswordRequirements('🔑Abcasba123!'),
        PasswordValidationError.none,
      );
      expect(
        checkPasswordRequirements('Pass🔥123!A'),
        PasswordValidationError.none,
      );
      expect(
        checkPasswordRequirements('Abc123!🌟✨🚀'),
        PasswordValidationError.none,
      );
      expect(
        checkPasswordRequirements('🎮🎯A1!abaa'),
        PasswordValidationError.none,
      );
      expect(
        checkPasswordRequirements('Strong👨‍👩‍👧‍👦123!'),
        PasswordValidationError.none,
      );
      expect(
        checkPasswordRequirements('A1!👍🏽Strong1234'),
        PasswordValidationError.none,
      );
      expect(
        checkPasswordRequirements('Pass🇺🇸123!A'),
        PasswordValidationError.none,
      );
      expect(
        checkPasswordRequirements('Strong123A🎯'),
        PasswordValidationError.none,
      );
      expect(
        checkPasswordRequirements('Strong1A🎯🎯🎯'),
        PasswordValidationError.consecutiveCharacters,
      );
      expect(
        checkPasswordRequirements('🔥🔥🔥Strong1A!'),
        PasswordValidationError.consecutiveCharacters,
      );
    });
    test('Complex emoji sequences and ZWJ', () {
      expect(
        // ZWJ sequence (man technologist)
        checkPasswordRequirements('Strong123A👨‍💻'),
        PasswordValidationError.none,
      );
      expect(
        // Complex ZWJ sequence
        checkPasswordRequirements('Strong123A👁️‍🗨️'),
        PasswordValidationError.none,
      );
      expect(
        // Emoji presentation selector
        checkPasswordRequirements('Strong123A☺️'),
        PasswordValidationError.none,
      );
    });

    test('Mixed emoji and text patterns', () {
      expect(
        checkPasswordRequirements('Aaba🔒1🔑!🚀'),
        PasswordValidationError.none,
      );
      expect(
        checkPasswordRequirements('Se🔒cure123!'),
        PasswordValidationError.none,
      );
      expect(
        checkPasswordRequirements('St🔑r🔒ng1!'),
        PasswordValidationError.none,
      );
      expect(
        // Should not trigger containsPassword
        checkPasswordRequirements('p🔑ssw🔒rd123A!'),
        PasswordValidationError.none,
      );
      expect(
        checkPasswordRequirements('🔒🚀🎮🎯Aa1!'),
        PasswordValidationError.none,
      );
    });

    test('Limited fuzzy testing', () {
      final random = Random();
      const chars =
          'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123'
          r'456789!@#$%^&*()';

      for (int i = 0; i < 10; i++) {
        final int length = random.nextInt(15) + 1;
        final StringBuffer passwordBuffer = StringBuffer();

        for (int j = 0; j < length; j++) {
          passwordBuffer.write(chars[random.nextInt(chars.length)]);
        }

        // Test the random password - we don't assert specific errors,
        // just verify the validator properly handles random input
        checkPasswordRequirements(passwordBuffer.toString());
      }

      final List<String> problematicInputs = [
        // Password too short
        'a',
        // Repeated characters
        'aaaPassword1!',
        'Password111!',
        'Password!!!1',
        // Mixed borderline cases
        'pass A1!',
        'PASS a1!',
        'Pass A!',
        'Pass A1',
        // Contains "password"
        'MyPasswordIs1!',
        'password123A!',
        '!PASSWORDabc1',
      ];

      for (final String input in problematicInputs) {
        checkPasswordRequirements(input);
      }
    });
  });
}
