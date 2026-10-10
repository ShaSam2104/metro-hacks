import 'dart:io';

import 'package:metro_hacks/src/data_prep.dart';

Future<void> main(List<String> args) async {
  exitCode = await runDataPrepCli(args);
}
