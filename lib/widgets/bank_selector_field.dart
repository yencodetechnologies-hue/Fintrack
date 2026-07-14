import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../data/indian_banks.dart';

class BankSelectorField extends StatelessWidget {
  final String? selectedBankId;
  final TextEditingController customBankController;
  final ValueChanged<String?> onBankIdChanged;
  final VoidCallback onCustomBankChanged;

  const BankSelectorField({
    super.key,
    required this.selectedBankId,
    required this.customBankController,
    required this.onBankIdChanged,
    required this.onCustomBankChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          value: selectedBankId,
          dropdownColor: AppConfig.darkSlate,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
          ),
          decoration: InputDecoration(
            labelText: 'Select Bank',
            labelStyle: const TextStyle(
              color: AppConfig.hintColor,
              fontSize: 14,
            ),
            prefixIcon: const Icon(
              Icons.account_balance_rounded,
              color: AppConfig.primaryTeal,
              size: 20,
            ),
            filled: true,
            fillColor: Colors.white.withOpacity(0.03),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: Colors.white.withOpacity(0.08),
                width: 1.2,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(
                color: AppConfig.primaryTeal,
                width: 1.5,
              ),
            ),
          ),
          items: [
            ...indianBanks.map(
              (bank) => DropdownMenuItem<String>(
                value: bank.id,
                child: Text(
                  bank.displayName,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
            const DropdownMenuItem<String>(
              value: kCustomBankId,
              child: Text(
                kCustomBankLabel,
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
          onChanged: onBankIdChanged,
        ),
        if (selectedBankId == kCustomBankId) ...[
          const SizedBox(height: 18),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withOpacity(0.08),
                width: 1.2,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: TextField(
              controller: customBankController,
              onChanged: (_) => onCustomBankChanged(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
              ),
              decoration: InputDecoration(
                labelText: 'Enter Bank Name',
                labelStyle: const TextStyle(
                  color: AppConfig.hintColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
                prefixIcon: Icon(
                  Icons.edit_rounded,
                  color: AppConfig.primaryTeal.withOpacity(0.7),
                  size: 20,
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 20,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
      ],
    );
  }
}
