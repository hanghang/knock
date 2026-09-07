/// fwknop (FKO) SPA packet builder, pure Dart.
///
/// Implements the client-side encoding of the Single Packet Authorization
/// protocol: lib/fko_encode.c, fko_encryption.c, fko_hmac.c and
/// cipher_funcs.c in https://github.com/mrash/fwknop.
///
/// Only the modern defaults are supported: AES (Rijndael) in CBC mode,
/// SHA256 digest, optional HMAC-SHA256 (encrypt-then-MAC).
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

const String fkoProtocolVersion = '3.0.0';

/// base64('Salted__'), prefix of every Rijndael ciphertext (fko.h).
const String b64RijndaelSalt = 'U2FsdGVkX1';
const int b64RijndaelSaltLen = 10;

/// Base64 with '=' padding stripped, as used throughout libfko.
String b64(List<int> bytes) => base64Encode(bytes).replaceAll('=', '');

/// Base64 decode tolerant of missing padding (libfko strips it).
Uint8List b64Decode(String s) {
  final pad = (4 - s.length % 4) % 4;
  return base64Decode(s + '=' * pad);
}

/// Decode a key string as given in access.conf / on the CLI: base64 by
/// default, or raw bytes if [raw] is set.
Uint8List decodeKey(String s, {bool raw = false}) {
  final trimmed = s.trim();
  if (trimmed.isEmpty) throw ArgumentError('key is empty');
  if (raw) return Uint8List.fromList(utf8.encode(trimmed));
  try {
    return b64Decode(trimmed);
  } on FormatException {
    throw ArgumentError('key is not valid base64 (enable "raw key" for ASCII keys)');
  }
}

/// OpenSSL EVP_BytesToKey(MD5) key+IV derivation: 32-byte AES key and
/// 16-byte IV from (key, salt). Mirrors rij_salt_and_iv() in cipher_funcs.c.
Uint8List _kiv(List<int> key, List<int> salt) {
  final out = BytesBuilder();
  var prev = const <int>[];
  while (out.length < 48) {
    prev = md5.convert([...prev, ...key, ...salt]).bytes;
    out.add(prev);
  }
  return out.toBytes();
}

/// AES-256-CBC, PKCS7, OpenSSL-compatible output: "Salted__" + salt + data.
Uint8List _aesEncrypt(List<int> plain, List<int> key, List<int> salt) {
  final kiv = _kiv(key, salt);
  final cipher = PaddedBlockCipher('AES/CBC/PKCS7')
    ..init(
      true,
      PaddedBlockCipherParameters<CipherParameters, CipherParameters>(
        ParametersWithIV<KeyParameter>(
          KeyParameter(Uint8List.fromList(kiv.sublist(0, 32))),
          Uint8List.fromList(kiv.sublist(32, 48)),
        ),
        null,
      ),
    );
  final ct = cipher.process(Uint8List.fromList(plain));
  return (BytesBuilder()
        ..add(utf8.encode('Salted__'))
        ..add(salt)
        ..add(ct))
      .toBytes();
}

/// HMAC digest algorithms supported by `fwknop --hmac-digest-type`.
const hmacDigestTypes = ['md5', 'sha1', 'sha256', 'sha384', 'sha512'];

Hash _hmacHash(String type) => switch (type) {
      'md5' => md5,
      'sha1' => sha1,
      'sha256' => sha256,
      'sha384' => sha384,
      'sha512' => sha512,
      _ => throw ArgumentError('unsupported hmac digest type: $type'),
    };

/// Build the final SPA packet string (base64 ciphertext [+ base64 HMAC]).
///
/// [accessRequest] is e.g. `tcp/22` or `none/0`.
/// [natAccess] is e.g. `192.168.1.10,22` (optional).
/// [clientTimeout] > 0 requests a server-side firewall timeout (seconds).
/// [hmacDigest] selects the HMAC algorithm (default sha256, see
/// [hmacDigestTypes]).
String buildSpaPacket({
  required String sourceIp,
  required String accessRequest,
  required Uint8List key,
  String username = '',
  String natAccess = '',
  int clientTimeout = 0,
  Uint8List? hmacKey,
  String hmacDigest = 'sha256',
  DateTime? now,
}) {
  final rng = Random.secure();
  // 16 random digits (fko_rand_value.c)
  final rand16 = List.generate(16, (_) => rng.nextInt(10)).join();
  final ts = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;

  // fko_message_type_t: ACCESS=1, NAT=2, +2 when client timeout is set.
  var msgType = 1;
  if (natAccess.isNotEmpty) msgType += 1;
  if (clientTimeout > 0) msgType += 2;

  final encoded = [
    rand16,
    b64(utf8.encode(username)),
    '$ts',
    fkoProtocolVersion,
    '$msgType',
    b64(utf8.encode('$sourceIp,$accessRequest')),
    if (natAccess.isNotEmpty) b64(utf8.encode(natAccess)),
    if (clientTimeout > 0) '$clientTimeout',
  ].join(':');

  // Digest of the encoded message, appended inside the plaintext.
  final digest = b64(sha256.convert(utf8.encode(encoded)).bytes);
  final plain = utf8.encode('$encoded:$digest');

  final salt = Uint8List.fromList(List.generate(8, (_) => rng.nextInt(256)));
  final full = b64(_aesEncrypt(plain, key, salt));

  // fko_get_spa_data() strips the constant 'U2FsdGVkX1' (base64 of the
  // "Salted__" prefix) from the wire packet; the receiver re-adds it.
  // The HMAC covers the full string, prefix included.
  var packet = full.substring(b64RijndaelSaltLen);
  if (hmacKey != null) {
    final mac = Hmac(_hmacHash(hmacDigest), hmacKey).convert(utf8.encode(full)).bytes;
    packet += b64(mac);
  }
  return packet;
}
