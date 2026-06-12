import 'package:flutter/material.dart';

import 'screens/main_shell.dart';
import 'theme.dart';

void main() {
  // TODO(V1): charger TransportGraph.fromAsset(...) ici (une seule fois),
  // lancer ConnectivityChecker.analyze(...) et injecter le résultat.
  runApp(const MedApp());
}

class MedApp extends StatelessWidget {
  const MedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MED — Itinéraires Paris',
      debugShowCheckedModeBanner: false,
      theme: buildMedTheme(),
      home: const MainShell(),
    );
  }
}
