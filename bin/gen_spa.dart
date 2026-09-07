import 'dart:io';
import 'package:fwknop/fko.dart';

void main(List<String> args) {
  final packet = buildSpaPacket(
    sourceIp: '9.9.9.9',
    accessRequest: 'tcp/22',
    key: decodeKey(args[0]),
    username: 'testuser',
    clientTimeout: 300,
    hmacKey: args.length > 1 ? decodeKey(args[1]) : null,
  );
  stdout.write(packet);
}
