import 'package:flutter/material.dart';
import '../config/app_config.dart';

class ScanCardSection extends StatelessWidget {
  final VoidCallback onScan;
  final bool enabled;

  const ScanCardSection({
    super.key,
    required this.onScan,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppConfig.primaryTeal.withOpacity(0.35),
              width: 1.5,
            ),
            color: AppConfig.primaryTeal.withOpacity(0.08),
          ),
          child: ElevatedButton.icon(
            onPressed: enabled ? onScan : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              disabledBackgroundColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: const Icon(
              Icons.camera_alt_rounded,
              color: AppConfig.primaryTeal,
            ),
            label: const Text(
              'Scan Card',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
                color: AppConfig.primaryTeal,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Statement and payment due dates must be selected manually.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withOpacity(0.55),
            fontSize: 12,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }
}
