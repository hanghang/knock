import 'dart:convert';

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
  bool rawKey; // keys are ASCII instead of base64
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
        autoSource: j['autoSource'] as bool? ?? true,
        sourceIp: j['sourceIp'] as String? ?? '',
        username: j['username'] as String? ?? '',
        natAccess: j['natAccess'] as String? ?? '',
        timeout: j['timeout'] as int? ?? 0,
      );
}

const _prefsKey = 'profiles';

Future<List<Profile>> loadProfiles() async {
  final prefs = await SharedPreferences.getInstance();
  final list = (jsonDecode(prefs.getString(_prefsKey) ?? '[]') as List)
      .map((e) => Profile.fromJson(e as Map<String, dynamic>))
      .toList();
  return list;
}

Future<void> saveProfiles(List<Profile> profiles) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_prefsKey, jsonEncode(profiles));
}
