const url = getBitrefillUrlFromParameters();
document.getElementById('bitrefill-iframe').src = url;
window.onmessage = onBitrefillMessage;

/**
 * Get the Bitrefill widget URL from the parameters in the URL
 * 
 * @returns {string} Bitrefill widget URL
 */
function getBitrefillUrlFromParameters() {
    // Extract parameters from the URL
    const urlParams = new URLSearchParams(window.location.search);

    const ref = urlParams.get('ref');
    const theme = urlParams.get('theme') || 'dark';
    const language = urlParams.get('language') || 'en';
    const company_name = urlParams.get('company_name') || 'Gleec Wallet';

    /* Optional parameters */
    const payment_methods = urlParams.get('payment_methods');
    const refund_address = urlParams.get('refund_address');
    // Enable showPaymentInfo to display the recipient address, amount and QR code in the widget
    // This is useful for the user to verify the payment details before making the payment
    // This is disabled by default to reduce the amount of information displayed to the user
    // and to avoid any confusion with the payment process
    const show_payment_info = urlParams.get('show_payment_info') || 'false';

    // Use the parameters to set the iframe's src
    let bitrefillUrl = `https://embed.bitrefill.com/?ref=${ref}
                &theme=${theme}&language=${language}&companyName=${company_name}
                &showPaymentInfo=${show_payment_info}`;

    if (payment_methods) {
        console.log(payment_methods);
        bitrefillUrl += `&paymentMethods=${payment_methods}`;
    }
    if (refund_address) {
        bitrefillUrl += `&refundAddress=${refund_address}`;
    }

    return bitrefillUrl;
}

/**
 * Handle messages from Bitrefill widget iframe. 
 * Send payment and invoice events to the parent window.
 * Show a banner to the user when the payment is complete.
 * 
 * @param {MessageEvent} bitrefillEvent 
 */
function onBitrefillMessage(bitrefillEvent) {
    const data = JSON.parse(bitrefillEvent.data);
    const strData = JSON.stringify(data);
    const {
        event,
        invoiceId,
        paymentUri
    } = data;

    switch (event) {
        case 'invoice_created':
            postMessageToParent(strData);
            showEmailWarningBanner();
            break;
        case 'payment_intent':
            postMessageToParent(strData);
            returnToWallet();
            break;
        default:
            break;
    }
}

/** 
 * Post a message to the parent window
 * 
 * @param {string} message 
 */
function postMessageToParent(message) {
    // flutter_inappwebview
    console.log(message);

    // universal_url opener 
    if (window.opener) {
        return window.opener.postMessage(message, "*");
    }

    // desktop_webview_window - https://github.com/MixinNetwork/flutter-plugins/blob/main/packages/desktop_webview_window/example/test_web_pages/test.html
    if (window.webkit) {
        return window.webkit.messageHandlers.test.postMessage(message);
    }

    // Windows WebView2 (desktop_webview_window) - https://learn.microsoft.com/en-us/microsoft-edge/webview2/how-to/communicate-btwn-web-native 
    if (window.chrome && window.chrome.webview) {
        return window.chrome.webview.postMessage(message);
    }

    console.error('No valid postMessage target found');
}

/**
 * Close the widget and show a banner to the user to navigate back to the wallet
 */
function returnToWallet() {
    // window.close();

    // In some cases the window doesn't close (i.e. Desktop platforms)
    // In that case, we show a banner to the user to navigate back to the wallet
    document.getElementById('bitrefill-payment-banner').style.display = 'block';
    document.getElementById('bitrefill-email-banner').style.display = 'none';
}

function showEmailWarningBanner() {
    document.getElementById('bitrefill-email-banner').style.display = 'block';
    document.getElementById('bitrefill-payment-banner').style.display = 'none';
}