/// Singleton du graphe intermodal — chargé une seule fois au démarrage
/// (voir lib/main.dart).
///
/// Séparé de main.dart pour que le cœur algorithmique (router_service) ne
/// dépende pas de l'UI : main.dart importe les écrans web (dart:js_interop),
/// ce qui rendait le routeur impossible à tester/benchmarker sur la VM Dart.
library;

import 'graph.dart';

TransportGraph? graphInstance;

TransportGraph get appGraph => graphInstance!;
