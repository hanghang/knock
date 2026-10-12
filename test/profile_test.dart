import 'package:flutter_test/flutter_test.dart';
import 'package:fwknop/profile.dart';

void main() {
  test('raw/base64 encoding is independent per key', () {
    final p = Profile(
      name: 'mixed',
      key: 'S2V5QmFzZTY0',
      useHmac: true,
      hmacKey: 'raw-hmac-passphrase',
      rawHmacKey: true,
    );

    final copy = Profile.fromJson(p.toJson());

    expect(copy.rawKey, isFalse);
    expect(copy.rawHmacKey, isTrue);
  });

  // fwknop's KEY_BASE64 + HMAC_KEY combination is what the split exists for.
  test('a profile saved before the split keeps raw HMAC decoding', () {
    final legacy = Profile.fromJson({
      'name': 'old',
      'key': 'passphrase',
      'rawKey': true,
      'useHmac': true,
      'hmacKey': 'hmac-passphrase',
    });

    expect(legacy.rawKey, isTrue);
    expect(legacy.rawHmacKey, isTrue);
  });

  test('a legacy base64 profile stays base64', () {
    final legacy = Profile.fromJson({'name': 'old', 'rawKey': false});

    expect(legacy.rawHmacKey, isFalse);
  });
}
