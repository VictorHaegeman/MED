import 'package:flutter/material.dart';

import '../models/itinerary.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'impact_screen.dart';
import 'results_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _from = 'Gare de Lyon';
  String _to = 'Porte de Versailles';
  final Set<TransportMode> _enabledModes = {...TransportMode.values};

  static const _recents = ['EFREI — Villejuif', 'Châtelet', 'République'];

  void _swap() => setState(() {
        final tmp = _from;
        _from = _to;
        _to = tmp;
      });

  void _search() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ResultsScreen(from: _from, to: _to),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ListView(
                  children: [
                    _header(),
                    const SizedBox(height: 20),
                    _searchCard(),
                    const SizedBox(height: 20),
                    _sectionTitle('Modes activés'),
                    const SizedBox(height: 8),
                    _modeChips(),
                    const SizedBox(height: 20),
                    _sectionTitle('Récents'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final r in _recents)
                          MedChip(
                            label: r,
                            onTap: () {
                              setState(() => _to = r);
                              _search();
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _networkCard(),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _bottomNav(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: MedColors.accent,
            borderRadius: BorderRadius.circular(99),
          ),
          child: const Text('MED',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
        ),
        const SizedBox(width: 10),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bonsoir Victor',
                style: TextStyle(fontSize: 13, color: MedColors.secondary)),
            Text('Où allez-vous ?',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          ],
        ),
      ],
    );
  }

  Widget _searchCard() {
    return MedCard(
      child: Column(
        children: [
          Row(
            children: [
              const _FieldDot(color: MedColors.green),
              const SizedBox(width: 10),
              Expanded(child: _field('Départ', _from)),
              GestureDetector(
                onTap: _swap,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                      color: MedColors.surface2, shape: BoxShape.circle),
                  child: const Icon(Icons.swap_vert,
                      size: 18, color: MedColors.accent),
                ),
              ),
            ],
          ),
          const Divider(color: MedColors.dividerColor, height: 22),
          Row(
            children: [
              const _FieldDot(color: MedColors.accent),
              const SizedBox(width: 10),
              Expanded(child: _field('Arrivée', _to)),
            ],
          ),
          const SizedBox(height: 14),
          PrimaryButton(label: 'Rechercher un itinéraire', onTap: _search),
        ],
      ),
    );
  }

  Widget _field(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: MedColors.secondary)),
        Text(value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _modeChips() {
    const labels = {
      TransportMode.metro: '🚇 Métro',
      TransportMode.tram: '🚊 Tram',
      TransportMode.bus: '🚌 Bus',
      TransportMode.walk: '🚶 Marche',
    };
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final mode in TransportMode.values)
          MedChip(
            label: labels[mode]!,
            selected: _enabledModes.contains(mode),
            onTap: () => setState(() {
              _enabledModes.contains(mode)
                  ? _enabledModes.remove(mode)
                  : _enabledModes.add(mode);
            }),
          ),
      ],
    );
  }

  Widget _networkCard() {
    return MedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Réseau intermodal',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              // TODO(V1): brancher sur ConnectivityChecker.analyze().
              Text('● Connexe',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: MedColors.green)),
            ],
          ),
          const SizedBox(height: 10),
          const Row(
            children: [
              LineBadge(label: '1', color: MedColors.m1, darkText: true),
              SizedBox(width: 8),
              LineBadge(label: '12', color: MedColors.m12),
              SizedBox(width: 8),
              LineBadge(label: '14', color: MedColors.m14),
              SizedBox(width: 8),
              LineBadge(
                  label: 'T3a',
                  color: MedColors.orange,
                  darkText: true,
                  mode: TransportMode.tram),
              SizedBox(width: 8),
              LineBadge(
                  label: '87', color: MedColors.busGrey, mode: TransportMode.bus),
              SizedBox(width: 8),
              Text('🚶', style: TextStyle(fontSize: 14)),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            // TODO(V1): valeurs réelles depuis TransportGraph (nodeCount...).
            '1 842 nœuds · métro + tram + bus + marche · graphe vérifié au lancement',
            style: TextStyle(fontSize: 11, color: MedColors.secondary),
          ),
        ],
      ),
    );
  }

  Widget _bottomNav() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: MedColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _navItem('🔍', 'Recherche', active: true, onTap: () {}),
          _navItem('🗺', 'Itinéraires', onTap: _search),
          _navItem('🌱', 'Impact', onTap: _openImpact),
          _navItem('⚙', 'Réseau', onTap: _openImpact),
        ],
      ),
    );
  }

  void _openImpact() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ImpactScreen()));
  }

  Widget _navItem(String icon, String label,
      {bool active = false, required VoidCallback onTap}) {
    final color = active ? MedColors.accent : MedColors.secondary;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Text(icon, style: TextStyle(fontSize: 16, color: color)),
          const SizedBox(height: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: color)),
        ],
      ),
    );
  }

  Widget _sectionTitle(String s) => Text(s,
      style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600, color: MedColors.secondary));
}

class _FieldDot extends StatelessWidget {
  const _FieldDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
