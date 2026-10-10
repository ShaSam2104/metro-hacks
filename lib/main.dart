import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'ui/features/auth/views/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MetroHacksApp());
}

class MetroHacksApp extends StatelessWidget {
  const MetroHacksApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ShadApp(
      title: 'Metro Hacks',
      debugShowCheckedModeBanner: false,
      theme: ShadThemeData(
        brightness: Brightness.dark,
        colorScheme: const ShadZincColorScheme.dark(),
      ),
      home: const AuthGate(),
    );
  }
}
