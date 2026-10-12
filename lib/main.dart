import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'fko.dart';
import 'profile.dart';

void main() => runApp(const FwknopApp());

class FwknopApp extends StatelessWidget {
  const FwknopApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Fwknop',
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
        home: const ProfileListPage(),
      );
}

/// A send failure worth showing the user verbatim. `toString()` returns just
/// the message so `'Send failed: $e'` stays readable.
class SpaException implements Exception {
  SpaException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Returns the provider's answer, or null when it is not a usable address: a
/// proxy or captive-portal error page must not become the SPA source IP, or the
/// packet is sent for the wrong address and still reports success.
Future<String?> _fetchExternalIp(HttpClient client, String url) async {
  final res = await client.getUrl(Uri.parse(url)).then((req) => req.close());
  final body = await res.transform(utf8.decoder).join();
  if (res.statusCode != HttpStatus.ok) return null;
  final ip = body.trim();
  return InternetAddress.tryParse(ip) == null ? null : ip;
}

/// Resolve this device's external IP (like fwknop's -R option).
Future<String> resolveExternalIp() async {
  for (final url in [
    'https://api.ipify.org',
    'https://icanhazip.com',
  ]) {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      // connectionTimeout only bounds connect, not a stalled response.
      final ip = await _fetchExternalIp(client, url)
          .timeout(const Duration(seconds: 10));
      if (ip != null) return ip;
    } catch (_) {
    } finally {
      client.close(force: true);
    }
  }
  throw SpaException(
      'Could not resolve external IP. Set the source IP manually.');
}

Future<void> sendSpa(Profile p) async {
  final key = decodeKey(p.key, raw: p.rawKey);
  final hmac = p.useHmac ? decodeKey(p.hmacKey, raw: p.rawHmacKey) : null;
  final sourceIp = p.autoSource ? await resolveExternalIp() : p.sourceIp.trim();
  if (sourceIp.isEmpty) {
    throw SpaException('No source IP (enable auto-resolve or set one).');
  }

  final packet = buildSpaPacket(
    sourceIp: sourceIp,
    accessRequest: p.access.trim(),
    key: key,
    username: p.username.trim(),
    natAccess: p.natAccess.trim(),
    clientTimeout: p.timeout,
    hmacKey: hmac,
    hmacDigest: p.hmacDigest,
  );

  // send() fails if the socket family does not match the destination, so pick
  // an address first (IPv4 where available) and bind the matching wildcard.
  final addrs = await InternetAddress.lookup(p.host.trim());
  final addr = addrs.firstWhere((a) => a.type == InternetAddressType.IPv4,
      orElse: () => addrs.first);
  final socket = await RawDatagramSocket.bind(
    addr.type == InternetAddressType.IPv6
        ? InternetAddress.anyIPv6
        : InternetAddress.anyIPv4,
    0,
  );
  try {
    socket.send(utf8.encode(packet), addr, p.port);
  } finally {
    socket.close();
  }
}

class ProfileListPage extends StatefulWidget {
  const ProfileListPage({super.key});

  @override
  State<ProfileListPage> createState() => _ProfileListPageState();
}

class _ProfileListPageState extends State<ProfileListPage> {
  List<Profile> _profiles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    loadProfiles().then((p) => setState(() {
          _profiles = p;
          _loading = false;
        }));
  }

  Future<void> _send(Profile p) async {
    final messenger = ScaffoldMessenger.of(context);
    // Dismissible so a stalled IP resolve can be backed out of. Popping via the
    // dialog's own context is what keeps a user-dismissed dialog from taking the
    // profile list down with it.
    BuildContext? dialog;
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        dialog = ctx;
        return const Center(child: CircularProgressIndicator());
      },
    );

    String message;
    try {
      await sendSpa(p);
      message = 'SPA packet sent to ${p.host}:${p.port}';
    } catch (e) {
      message = 'Send failed: $e';
    }
    if (!mounted) return;
    final progress = dialog;
    if (progress != null && progress.mounted) Navigator.pop(progress);
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  // docs/features.md: long-press item -> popup menu -> duplicate profile
  void _showItemMenu(Offset globalPos, Profile p) {
    final size = MediaQuery.of(context).size;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(globalPos.dx, globalPos.dy,
          size.width - globalPos.dx, size.height - globalPos.dy),
      items: const [
        PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
      ],
    ).then((v) {
      if (v != 'duplicate') return;
      final copy = Profile.fromJson(p.toJson())..name = '${p.name} (copy)';
      setState(() => _profiles.insert(_profiles.indexOf(p) + 1, copy));
      saveProfiles(_profiles);
    });
  }

  Future<void> _edit(Profile? profile) async {
    final result = await Navigator.push<Profile>(
      context,
      MaterialPageRoute(builder: (_) => ProfileEditPage(profile: profile)),
    );
    if (result == null) return;
    setState(() {
      if (profile == null) {
        _profiles.add(result);
      } else {
        _profiles[_profiles.indexOf(profile)] = result;
      }
    });
    await saveProfiles(_profiles);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Fwknop')),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _edit(null),
          child: const Icon(Icons.add),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _profiles.isEmpty
                ? const Center(child: Text('No profiles yet.\nTap + to add a server.', textAlign: TextAlign.center))
                : ListView.builder(
                    itemCount: _profiles.length,
                    itemBuilder: (_, i) {
                      final p = _profiles[i];
                      return Dismissible(
                        key: ObjectKey(p),
                        onDismissed: (_) {
                          final at = _profiles.indexOf(p);
                          setState(() => _profiles.removeAt(at));
                          saveProfiles(_profiles);
                          // Keys are hard to recreate, so make this reversible.
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('Deleted "${p.name}"'),
                            action: SnackBarAction(
                              label: 'Undo',
                              onPressed: () {
                                if (!mounted) return;
                                final index =
                                    at > _profiles.length ? _profiles.length : at;
                                setState(() => _profiles.insert(index, p));
                                saveProfiles(_profiles);
                              },
                            ),
                          ));
                        },
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onLongPressStart: (d) =>
                              _showItemMenu(d.globalPosition, p),
                          child: ListTile(
                            title: Text(p.name),
                            subtitle: Text('${p.host}:${p.port} · ${p.access}'),
                            onTap: () => _edit(p),
                            trailing: IconButton(
                              icon: const Icon(Icons.send),
                              tooltip: 'Send SPA packet',
                              onPressed: () => _send(p),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
      );
}

class ProfileEditPage extends StatefulWidget {
  final Profile? profile;
  const ProfileEditPage({super.key, this.profile});

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  final _form = GlobalKey<FormState>();
  late final Profile _p;
  final _revealed = <String>{}; // key fields currently shown in clear

  late final _name = TextEditingController(text: _p.name);
  late final _host = TextEditingController(text: _p.host);
  late final _port = TextEditingController(text: '${_p.port}');
  late final _access = TextEditingController(text: _p.access);
  late final _key = TextEditingController(text: _p.key);
  late final _hmacKey = TextEditingController(text: _p.hmacKey);
  late final _sourceIp = TextEditingController(text: _p.sourceIp);
  late final _username = TextEditingController(text: _p.username);
  late final _natAccess = TextEditingController(text: _p.natAccess);
  late final _timeout = TextEditingController(text: _p.timeout == 0 ? '' : '${_p.timeout}');

  @override
  void initState() {
    _p = widget.profile == null
        ? Profile(name: '')
        : Profile.fromJson(widget.profile!.toJson()); // copy
    super.initState();
  }

  @override
  void dispose() {
    for (final c in [
      _name, _host, _port, _access, _key, _hmacKey,
      _sourceIp, _username, _natAccess, _timeout,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    _p.name = _name.text.trim();
    _p.host = _host.text.trim();
    _p.port = int.parse(_port.text.trim());
    _p.access = _access.text.trim();
    _p.key = _key.text.trim();
    _p.hmacKey = _hmacKey.text.trim();
    _p.sourceIp = _sourceIp.text.trim();
    _p.username = _username.text.trim();
    _p.natAccess = _natAccess.text.trim();
    _p.timeout = _timeout.text.trim().isEmpty ? 0 : int.parse(_timeout.text.trim());
    // fail early on unusable keys
    try {
      decodeKey(_p.key, raw: _p.rawKey);
      if (_p.useHmac) decodeKey(_p.hmacKey, raw: _p.rawHmacKey);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      return;
    }
    Navigator.pop(context, _p);
  }

  Widget _field(String label, TextEditingController c,
          {String? hint, bool required = false, bool obscure = false,
          TextInputType type = TextInputType.text, String? toggleKey,
          int? min, int? max}) {
    final hidden = obscure && !_revealed.contains(toggleKey);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        obscureText: hidden,
        keyboardType: type,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          suffixIcon: toggleKey == null
              ? null
              : IconButton(
                  icon: Icon(hidden ? Icons.visibility : Icons.visibility_off),
                  tooltip: hidden ? 'Show key' : 'Hide key',
                  onPressed: () => setState(() => hidden
                      ? _revealed.add(toggleKey)
                      : _revealed.remove(toggleKey)),
                ),
        ),
        // A numeric keyboard still accepts pasted text, so validate before
        // _save() parses these.
        validator: (v) {
          final text = v?.trim() ?? '';
          if (text.isEmpty) return required ? 'Required' : null;
          if (min == null && max == null) return null;
          final n = int.tryParse(text);
          if (n == null) return 'Must be a whole number';
          if (min != null && n < min) return 'Must be at least $min';
          if (max != null && n > max) return 'Must be at most $max';
          return null;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.profile == null ? 'New profile' : 'Edit profile'),
          actions: [
            TextButton(onPressed: _save, child: const Text('Save')),
          ],
        ),
        body: Form(
          key: _form,
          child: ListView(
            // An explicit padding stops ScrollView from applying MediaQuery
            // padding itself, so the nav-bar inset must be added by hand.
            padding: EdgeInsets.fromLTRB(
                16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
            children: [
              _field('Name', _name, required: true),
              _field('Server (IP or hostname)', _host, required: true),
              _field('UDP port', _port, type: TextInputType.number, required: true,
                  min: 1, max: 65535),
              _field('Access request', _access, hint: 'tcp/22', required: true),
              _field('Key (base64, like access.conf KEY)', _key, obscure: true, required: true, toggleKey: 'key'),
              SwitchListTile(
                title: const Text('Use HMAC'),
                subtitle: const Text('Recommended; needs HMAC_KEY in access.conf'),
                value: _p.useHmac,
                onChanged: (v) => setState(() => _p.useHmac = v),
              ),
              if (_p.useHmac)
                _field('HMAC key (base64)', _hmacKey, obscure: true, required: true, toggleKey: 'hmacKey'),
              if (_p.useHmac)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DropdownButtonFormField<String>(
                    initialValue: _p.hmacDigest,
                    decoration: const InputDecoration(
                      labelText: 'HMAC digest type',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final t in hmacDigestTypes)
                        DropdownMenuItem(value: t, child: Text(t.toUpperCase())),
                    ],
                    onChanged: (v) => setState(() => _p.hmacDigest = v ?? 'sha256'),
                  ),
                ),
              SwitchListTile(
                title: const Text('Key is raw ASCII'),
                subtitle: const Text('Off = base64 (fwknop default)'),
                value: _p.rawKey,
                onChanged: (v) => setState(() => _p.rawKey = v),
              ),
              // fwknop has independent KEY/KEY_BASE64 and HMAC_KEY/
              // HMAC_KEY_BASE64, so the two keys can differ in encoding.
              if (_p.useHmac)
                SwitchListTile(
                  title: const Text('HMAC key is raw ASCII'),
                  value: _p.rawHmacKey,
                  onChanged: (v) => setState(() => _p.rawHmacKey = v),
                ),
              SwitchListTile(
                title: const Text('Auto-resolve source IP'),
                subtitle: const Text('Queries your public IP before sending'),
                value: _p.autoSource,
                onChanged: (v) => setState(() => _p.autoSource = v),
              ),
              if (!_p.autoSource)
                _field('Source IP', _sourceIp, required: true),
              _field('Username (spoof user, optional)', _username),
              _field('NAT access (optional)', _natAccess, hint: '192.168.1.10,22'),
              _field('Firewall timeout seconds (optional)', _timeout,
                  type: TextInputType.number, min: 1),
            ],
          ),
        ),
      );
}
