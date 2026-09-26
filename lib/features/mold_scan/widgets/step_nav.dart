import 'package:flutter/material.dart';

import '../theme/mold_scan_colors.dart';

class MoldScanStep {
  final IconData icon;
  final String label;
  final bool enabled;

  const MoldScanStep(this.icon, this.label, {this.enabled = true});
}

const moldScanSteps = [
  MoldScanStep(Icons.cloud_upload_outlined, 'Upload de Foto'),
  MoldScanStep(Icons.crop_free, 'Calibração & Perspectiva'),
  MoldScanStep(Icons.auto_fix_high_outlined, 'Vetorização & DXF'),
  MoldScanStep(Icons.precision_manufacturing_outlined, 'Produção', enabled: false),
  MoldScanStep(Icons.receipt_long_outlined, 'Orçamentos', enabled: false),
  MoldScanStep(Icons.collections_bookmark_outlined, 'Biblioteca', enabled: false),
  MoldScanStep(Icons.history_outlined, 'Histórico', enabled: false),
];

class MoldScanStepNav extends StatelessWidget implements PreferredSizeWidget {
  final int currentIndex;

  const MoldScanStepNav({super.key, required this.currentIndex});

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: preferredSize.height,
      color: MoldScanColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < moldScanSteps.length; i++) ...[
              _StepChip(step: moldScanSteps[i], active: i == currentIndex),
              if (i != moldScanSteps.length - 1)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 2),
                  child: Icon(Icons.chevron_right, size: 16, color: MoldScanColors.border),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  final MoldScanStep step;
  final bool active;

  const _StepChip({required this.step, required this.active});

  @override
  Widget build(BuildContext context) {
    final color = !step.enabled
        ? MoldScanColors.textSecondary.withValues(alpha: 0.4)
        : active
            ? MoldScanColors.accent
            : MoldScanColors.textSecondary;

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: active ? MoldScanColors.accent.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: active ? Border.all(color: MoldScanColors.accent.withValues(alpha: 0.4)) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(step.icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            step.label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          if (!step.enabled) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: MoldScanColors.surfaceLight,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'em breve',
                style: TextStyle(color: MoldScanColors.textSecondary, fontSize: 9),
              ),
            ),
          ],
        ],
      ),
    );

    return step.enabled ? chip : Tooltip(message: 'Em breve', child: chip);
  }
}
