/// Arborescence de la structure du réseau — attendu explicite de l'AO
/// ("afficher l'arborescence de la structure").
///
/// Choix retenu (plan §2) : arbre couvrant minimal (ACM) par algorithme de
/// Prim avec tas binaire min, en O(E log V). L'écran "Impact & Performance"
/// expose la visualisation (bouton "Visualiser l'arborescence du réseau").
///
/// ── Hypothèses de modélisation (exigence AO : documenter) ──────────────────
/// • Un ACM n'a de sens que sur un graphe NON orienté. Or `TransportGraph` est
///   orienté (adjacence sortante uniquement). On travaille donc sur le graphe
///   non-orienté SOUS-JACENT : chaque arête orientée u→v (poids w) est vue
///   comme une arête non orientée {u, v} de poids w. Si u→v et v→u existent
///   tous deux avec des poids différents, Prim retient naturellement le moins
///   cher (les deux sens sont injectés dans le tas).
/// • Connexité : un arbre COUVRANT n'existe que si le graphe (non orienté) est
///   connexe. On le détecte directement pendant le parcours de Prim — si tous
///   les nœuds ne sont pas atteints — et on lève une `StateError`.
///   NB : on ne réutilise PAS `ConnectivityChecker` ici, car il parcourt les
///   arêtes ORIENTÉES (sortantes). Un graphe faiblement connexe mais non
///   fortement connexe serait alors rejeté à tort alors qu'il admet un ACM.
///   La détection native ci-dessous est la bonne sémantique (et sans surcoût).
library;

import '../graph.dart';

class SpanningTreeResult {
  const SpanningTreeResult({required this.edges, required this.totalWeight});

  /// Arêtes de l'arbre, orientées parent → enfant depuis la racine de Prim
  /// (pratique pour un rendu d'arborescence dans l'UI).
  final List<Edge> edges;

  /// Somme des poids des arêtes retenues (en secondes, comme `weightSeconds`).
  final double totalWeight;
}

// ---------------------------------------------------------------------------
//  Arête frontière candidate
//  Relie un nœud DÉJÀ dans l'arbre (`parent`) à un nœud encore hors de l'arbre
//  (`child`). C'est l'unité manipulée par le tas.
// ---------------------------------------------------------------------------
class _Frontier {
  final String parent;
  final String child;
  final double weight;
  final EdgeType type;
  const _Frontier(this.parent, this.child, this.weight, this.type);
}

// ---------------------------------------------------------------------------
//  Tas binaire min — implémenté à la main (exigence AO)
//  Même structure que le `_MinHeap` de shortest_path.dart, mais ce dernier est
//  privé à son fichier (donc non réutilisable) : on en refait un, clé = poids.
// ---------------------------------------------------------------------------
class _MinHeap {
  final _data = <_Frontier>[];

  bool get isEmpty => _data.isEmpty;
  bool get isNotEmpty => _data.isNotEmpty;

  void add(_Frontier f) {
    _data.add(f);
    _bubbleUp(_data.length - 1);
  }

  _Frontier removeFirst() {
    final first = _data[0];
    final last = _data.removeLast();
    if (_data.isNotEmpty) {
      _data[0] = last;
      _sinkDown(0);
    }
    return first;
  }

  void _bubbleUp(int i) {
    while (i > 0) {
      final parent = (i - 1) ~/ 2;
      if (_data[i].weight < _data[parent].weight) {
        final tmp = _data[i];
        _data[i] = _data[parent];
        _data[parent] = tmp;
        i = parent;
      } else {
        break;
      }
    }
  }

  void _sinkDown(int i) {
    final n = _data.length;
    while (true) {
      int smallest = i;
      final l = 2 * i + 1;
      final r = 2 * i + 2;
      if (l < n && _data[l].weight < _data[smallest].weight) smallest = l;
      if (r < n && _data[r].weight < _data[smallest].weight) smallest = r;
      if (smallest == i) break;
      final tmp = _data[i];
      _data[i] = _data[smallest];
      _data[smallest] = tmp;
      i = smallest;
    }
  }
}

// ---------------------------------------------------------------------------
//  Prim — arbre couvrant minimal, version "paresseuse" (lazy)
// ---------------------------------------------------------------------------
class PrimMst {
  /// Calcule un arbre couvrant minimal du graphe non-orienté sous-jacent.
  ///
  /// Complexité : O(E log V).
  ///   - Chaque arête (non orientée) est empilée au plus deux fois ;
  ///   - chaque opération de tas est en O(log V) (car E ≤ V², log E = O(log V)).
  ///
  /// Cas limites :
  ///   - graphe vide        → résultat vide (poids 0) ;
  ///   - graphe à 1 nœud    → arbre sans arête (poids 0) ;
  ///   - graphe non connexe → `StateError`.
  SpanningTreeResult compute(TransportGraph graph) {
    // Arbre trivial : 0 ou 1 nœud → aucune arête à choisir.
    if (graph.nodeCount <= 1) {
      return const SpanningTreeResult(edges: [], totalWeight: 0);
    }

    // 1) Vue non-orientée : pour chaque arête orientée u→v, on enregistre la
    //    possibilité de franchir {u, v} dans LES DEUX sens.
    final undirected = <String, List<_Frontier>>{};
    for (final id in graph.nodes.keys) {
      undirected[id] = <_Frontier>[];
    }
    for (final fromId in graph.nodes.keys) {
      for (final e in graph.neighbors(fromId)) {
        // sens direct : depuis e.from on peut rejoindre e.to
        undirected[e.from]!
            .add(_Frontier(e.from, e.to, e.weightSeconds, e.type));
        // sens inverse : depuis e.to on peut rejoindre e.from
        undirected[e.to]!
            .add(_Frontier(e.to, e.from, e.weightSeconds, e.type));
      }
    }

    // 2) Prim paresseux depuis un nœud de départ arbitraire.
    final inTree = <String>{};
    final treeEdges = <Edge>[];
    double total = 0;
    final heap = _MinHeap();

    final start = graph.nodes.keys.first;
    inTree.add(start);
    for (final f in undirected[start]!) {
      heap.add(f);
    }

    while (heap.isNotEmpty && inTree.length < graph.nodeCount) {
      final f = heap.removeFirst();

      // Entrée périmée : l'enfant a déjà rejoint l'arbre (lazy deletion).
      if (inTree.contains(f.child)) continue;

      // On rattache l'enfant via l'arête frontière de poids minimal.
      inTree.add(f.child);
      treeEdges.add(Edge(
        from: f.parent,
        to: f.child,
        weightSeconds: f.weight,
        type: f.type,
      ));
      total += f.weight;

      // Les arêtes du nouveau nœud deviennent des candidates frontières.
      for (final next in undirected[f.child]!) {
        if (!inTree.contains(next.child)) heap.add(next);
      }
    }

    // 3) Précondition de connexité : un arbre COUVRANT relie tous les nœuds.
    //    S'il en manque, le graphe non-orienté n'est pas connexe.
    if (inTree.length != graph.nodeCount) {
      throw StateError(
        'Graphe non connexe : ACM impossible '
        '(${inTree.length}/${graph.nodeCount} nœuds atteints). '
        'Vérifier la connexité avant d\'appeler PrimMst.compute().',
      );
    }

    return SpanningTreeResult(edges: treeEdges, totalWeight: total);
  }
}
