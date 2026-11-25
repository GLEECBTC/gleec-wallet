import 'package:komodo_defi_types/komodo_defi_types.dart'
    show KdfDesktopDataDirectory;

/// Where KDF keeps wallet data on desktop, out of the user's Documents:
/// `%LOCALAPPDATA%\Gleec\kdf` on Windows, next to the credential vault, and
/// `$XDG_DATA_HOME/com.gleec.GleecDEX/kdf` on Linux, named after the
/// `APPLICATION_ID` in `linux/CMakeLists.txt`.
///
/// Never rename these. KDF would start from an empty folder, and the wallets
/// would look gone while their data sat in the old one.
final gleecKdfDesktopDataDirectory = KdfDesktopDataDirectory(
  windowsFolder: 'Gleec',
  linuxFolder: 'com.gleec.GleecDEX',
);
