import 'package:flutter/material.dart';

import '../models/itinerary.dart';
import '../theme.dart';

/// Pastille de ligne : ronde pour le métro, arrondie pour tram/bus.
class LineBadge extends StatelessWidget {
  const LineBadge({
    super.key,
    required this.label,
    required this.color,
    this.darkText = false,
    this.mode = TransportMode.metro,
  });

  final String label;
  final Color color;
  final bool darkText;
  final TransportMode mode;

  @override
  Widget build(BuildContext context) {
    final isRound = mode == TransportMode.metro;
    return Container(
      padding: isRound
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      width: isRound ? 24 : null,
      height: isRound ? 24 : null,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(isRound
            ? 99
            : (mode == TransportMode.tram || mode == TransportMode.train
                ? 6
                : 4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: darkText ? MedColors.bg : Colors.white,
        ),
      ),
    );
  }
}

/// Carte de surface standard du design.
class MedCard extends StatelessWidget {
  const MedCard({super.key, required this.child, this.onTap, this.border});

  final Widget child;
  final VoidCallback? onTap;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MedColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: border != null ? Border.all(color: border!, width: 1.5) : null,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Chip de filtre/sélection.
class MedChip extends StatelessWidget {
  const MedChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? MedColors.accent : MedColors.surface,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? Colors.white : MedColors.text,
          ),
        ),
      ),
    );
  }
}

/// Bouton principal plein.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MedColors.accent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// Bouton retour circulaire.
class BackCircle extends StatelessWidget {
  const BackCircle({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).maybePop(),
      child: Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(
            color: MedColors.surface, shape: BoxShape.circle),
        child: const Icon(Icons.arrow_back, size: 18, color: MedColors.text),
      ),
    );
  }
}
