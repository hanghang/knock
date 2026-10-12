import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Profile {
  String name;
  String host;
  int port;
  String access; // e.g. tcp/22
  String key; // base64 (or raw, see rawKey)
  bool useHmac;
  String hmacKey;
  String hmacDigest; // md5|sha1|sha256|sha384|sha512
  bool rawKey; // encryption key is ASCII instead of base64
  bool rawHmacKey; // HMAC key is ASCII instead of base64
  bool autoSource; // resolve external IP instead of using sourceIp
  String sourceIp;
  String username; // spoof user, optional
  String natAccess; // e.g. 192.168.1.10,22
  int timeout; // server-side firewall timeout, 0 = off

  Profile({
    required this.name,
    this.host = '',
    this.port = 62201,
    this.access = 'tcp/22',
    this.key = '',
    this.useHmac = false,
    this.hmacKey = '',
    this.hmacDigest = 'sha256',
    this.rawKey = false,
    this.rawHmacKey = false,
    this.autoSource = true,
    this.sourceIp = '',
    this.username = '',
    this.natAccess = '',
    this.timeout = 0,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'host': host,
        'port': port,
        'access': access,
        'key': key,
        'useHmac': useHmac,
        'hmacKey': hmacKey,
        'hmacDigest': hmacDigest,
        'rawKey': rawKey,
        'rawHmacKey': rawHmacKey,
        'autoSource': autoSource,
        'sourceIp': sourceIp,
        'username': username,
        'natAccess': natAccess,
        'timeout': timeout,
      };

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        name: j['name'] as String? ?? '',
        host: j['host'] as String? ?? '',
        port: j['port'] as int? ?? 62201,
        access: j['access'] as String? ?? 'tcp/22',
        key: j['key'] as String? ?? '',
        useHmac: j['useHmac'] as bool? ?? false,
        hmacKey: j['hmacKey'] as String? ?? '',
        hmacDigest: j['hmacDigest'] as String? ?? 'sha256',
        rawKey: j['rawKey'] as bool? ?? false,
        // Before the flags were split, one rawKey covered both keys, so a
        // profile saved then must keep decoding its HMAC key as raw.
        rawHmacKey: j['rawHmacKey'] as bool? ?? j['rawKey'] as bool? ?? false,
        autoSource: j['autoSource'] as bool? ?? true,
        sourceIp: j['sourceIp'] as String? ?? '',
        username: j['username'] as String? ?? '',
        natAccess: j['natAccess'] as String? ?? '',
        timeout: j['timeout'] as int? ?? 0,
      );
}

const _storageKey = 'profiles';

/// Profiles hold the KEY/HMAC_KEY that open a firewall, so they live in the
/// platform keystore/keychain rather than plaintext preferences.
/// `first_unlock_this_device` + non-synchronizable keeps them off iCloud
/// Keychain and off a migrated device.
const _secure = FlutterSecureStorage(
  aOptions: AndroidOptions(),
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
);

List<Profile> _decode(String raw) => (jsonDecode(raw) as List)
    .map((e) => Profile.fromJson(e as Map<String, dynamic>))
    .toList();

/// Reads the stored profiles, migrating a pre-secure-storage plaintext copy.
///
/// The legacy copy must be deleted even when it is not migrated: leaving it
/// behind would keep the keys readable on disk, defeating the move.
Future<String?> _readStored() async {
  final stored = await _secure.read(key: _storageKey);

  final prefs = await SharedPreferences.getInstance();
  final legacy = prefs.getString(_storageKey);
  if (legacy == null) return stored;
  await prefs.remove(_storageKey);
  if (stored != null) return stored;

  await _secure.write(key: _storageKey, value: legacy);
  return legacy;
}

Future<List<Profile>> loadProfiles() async {
  final raw = await _readStored();
  return raw == null ? [] : _decode(raw);
}

Future<void> saveProfiles(List<Profile> profiles) =>
    _secure.write(key: _storageKey, value: jsonEncode(profiles));
