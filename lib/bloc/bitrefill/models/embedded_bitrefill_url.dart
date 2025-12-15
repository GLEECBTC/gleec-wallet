/// Represents the URL to open the Bitrefill widget in an embedded web view.
/// This includes query parameters like the [referralCode], [theme],
/// [paymentMethods], and [refundAddress].
/// See https://www.bitrefill.com/playground/documentation/url-params for more info.
class EmbeddedBitrefillUrl {
  EmbeddedBitrefillUrl({
    required this.baseUrl,
    required this.referralCode,
    this.theme = 'dark',
    this.language = 'en',
    this.companyName = 'GLEEC',
    this.showPaymentInfo = false,
    this.refundAddress,
    this.paymentMethods,
  });

  /// The base URL to the embedded Bitrefill widget, excluding query parameters.
  final String baseUrl;

  /// The business referral code to use for the Bitrefill widget.
  final String referralCode;

  /// The theme to use when opening the Bitrefill widget.
  /// This can be 'auto', 'light', 'dark', 'crimson', 'aquamarine', or 'retro'.
  /// The default is 'dark'.
  final String theme;

  /// The language to use when opening the Bitrefill widget.
  /// This can be 'en', 'es', 'fr', 'de', 'it', 'pt', 'ru', 'ja', 'ko', or 'zh-Hans'.
  /// The default is 'en'.
  final String language;

  /// The company name to use when opening the Bitrefill widget.
  /// This defaults to 'GLEEC'.
  final String companyName;

  /// Whether to display the recipient address, amount, and QR code in the
  /// payment widget. This can be useful for the user to verify the payment
  /// details before making the payment. This is false by default, however, to
  /// reduce the visual clutter during the payment process.
  final bool showPaymentInfo;

  /// The refund address to use when opening the Bitrefill widget.
  final String? refundAddress;

  /// The payment methods to use when opening the Bitrefill widget.
  /// This limits the payment methods that are available to the user.
  /// If only one payment method is available, the payment method
  /// selection page will be skipped.
  /// The default is null, which means all payment methods are available.
  final List<String>? paymentMethods;

  @override
  String toString() {
    final Map<String, String> query = <String, String>{
      'ref': referralCode,
      'theme': theme,
      'language': language,
      'company_name': companyName,
      'show_payment_info': showPaymentInfo ? 'true' : 'false',
    };

    if (paymentMethods != null) {
      query['payment_methods'] = paymentMethods!.join(',');
    }

    if (refundAddress != null) {
      query['refund_address'] = refundAddress!;
    }

    final Uri baseUri = Uri.parse(baseUrl);
    final Uri uri = Uri(
      scheme: baseUri.scheme,
      host: baseUri.host,
      path: baseUri.path,
      port: baseUri.port,
      queryParameters: query,
    );

    return uri.toString();
  }
}
