import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ScanCardSection extends StatelessWidget {
  final VoidCallback onScan;
  final bool enabled;

  const ScanCardSection({
    super.key,
    required this.onScan,
    this.enabled = true,
  });

  static const Color _forestDark = Color(0xFF0F261C);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _forestDark.withValues(alpha: 0.3),
              width: 1.5,
            ),
            color: _forestDark.withValues(alpha: 0.06),
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
              color: _forestDark,
            ),
            label: Text(
              'Scan Card',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
                color: _forestDark,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Statement and payment due dates must be selected manually.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            color: Colors.black54,
            fontSize: 12,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }
}
