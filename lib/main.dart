import 'package:flutter/material.dart';

import 'core/graph.dart';
import 'core/graph_store.dart';
import 'screens/main_shell.dart';
import 'theme.dart';

// Singleton graphe — défini dans core/graph_store.dart, ré-exporté ici pour
// que les écrans continuent de l'importer via main.dart.
export 'core/graph_store.dart' show appGraph;

// Chemin actif partagé entre ResultsScreen (écriture) et MapScreen (lecture).
// null = aucun trajet sélectionné (vue réseau globale).
final pathNotifier = ValueNotifier<List<String>?>(null);

// Durée totale du trajet actif (secondes) — pour calcul d'horaires sur la carte.
final tripSecondsNotifier = ValueNotifier<double>(0);
// Noms des stations départ et arrivée du trajet actif.
final tripFromNotifier = ValueNotifier<String>('');
final tripToNotifier = ValueNotifier<String>('');

// Incrémenté chaque fois qu'un trajet est sauvegardé → ImpactScreen se rafraîchit.
final tripSavedNotifier = ValueNotifier<int>(0);

void main() async {
  // Obligatoire avant tout appel à rootBundle ou compute() hors widget tree.
  WidgetsFlutterBinding.ensureInitialized();
  graphInstance = await TransportGraph.fromAsset('assets/graph/idfm_graph.json');
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
