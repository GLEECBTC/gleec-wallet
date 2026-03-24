import 'package:web_dex/mm2/mm2_api/rpc/base.dart';

class TextError implements BaseError {
  TextError({required this.error, this.technicalDetails});
  static TextError empty() {
    return TextError(error: '');
  }

  static TextError? fromString(String? text) {
    if (text == null) return null;

    return TextError(error: text);
  }

  static const String type = 'TextError';

  /// User-friendly error message.
  final String error;

  /// Raw technical details for debugging. When non-null, the UI should show
  /// this in an expandable "Technical Details" section instead of [error].
  final String? technicalDetails;

  @override
  String get message => error;
}
