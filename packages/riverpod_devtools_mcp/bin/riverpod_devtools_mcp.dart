import 'dart:io' as io;

import 'package:dart_mcp/stdio.dart';
import 'package:riverpod_devtools_mcp/riverpod_devtools_mcp.dart';

void main() {
  RiverpodDevToolsMcpServer(stdioChannel(input: io.stdin, output: io.stdout));
}
