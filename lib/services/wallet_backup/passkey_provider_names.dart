/// The password manager that made a passkey, from the AAGUID it reported.
/// A display hint only: under "none" attestation nothing authenticates the
/// AAGUID, so it never decides anything.
String? passkeyProviderName(String? aaguid) =>
    aaguid == null ? null : _providers[aaguid.toLowerCase()];

const _providers = {
  'ea9b8d66-4d01-1d21-3ce4-b6b48cb575d4': 'Google Password Manager',
  'fbfc3007-154e-4ecc-8c0b-6e020557d7bd': 'Apple Passwords',
  'bada5566-a7aa-401f-bd96-45619a55120d': '1Password',
  '50726f74-6f6e-5061-7373-50726f746f6e': 'Proton Pass',
  'd548826e-79b4-db40-a3d8-11116f7e8349': 'Bitwarden',
  '531126d6-e717-415c-9320-3d9aa6981239': 'Dashlane',
  '53414d53-554e-4700-0000-000000000000': 'Samsung Pass',
  '0ea242b4-43c4-4a1b-8b17-dd6d0b6baec6': 'Keeper',
};
