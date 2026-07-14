import 'package:flutter/material.dart';
import 'package:shs_cardscan/shs_cardscan.dart';

import '../data/indian_banks.dart';

class CardScanFillResult {
  final bool success;
  final String? errorMessage;
  final bool filledLast4;
  final bool filledNickname;
  final bool filledBank;
  final String? matchedBankId;

  const CardScanFillResult({
    required this.success,
    this.errorMessage,
    this.filledLast4 = false,
    this.filledNickname = false,
    this.filledBank = false,
    this.matchedBankId,
  });
}

bool _passesLuhnCheck(String digits) {
  if (digits.length < 13 || digits.length > 19) {
    return false;
  }

  var sum = 0;
  var alternate = false;
  for (var i = digits.length - 1; i >= 0; i--) {
    var digit = int.parse(digits[i]);
    if (alternate) {
      digit *= 2;
      if (digit > 9) {
        digit -= 9;
      }
    }
    sum += digit;
    alternate = !alternate;
  }

  return sum % 10 == 0;
}

String _formatNetworkName(String networkName) {
  return networkName
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map(
        (part) => part.length == 1
            ? part.toUpperCase()
            : '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
      )
      .join(' ');
}

CardScanFillResult applyScanResult(
  CardScanResult result, {
  required TextEditingController bankController,
  required TextEditingController cardController,
  required TextEditingController last4Controller,
}) {
  final digits = (result.cardNumber ?? '').replaceAll(RegExp(r'\D'), '');

  if (digits.length < 4) {
    return const CardScanFillResult(
      success: false,
      errorMessage: 'Could not read a valid card number. Please try again.',
    );
  }

  if (!_passesLuhnCheck(digits)) {
    return const CardScanFillResult(
      success: false,
      errorMessage: 'Scanned card number looks invalid. Please try again.',
    );
  }

  final last4 = digits.substring(digits.length - 4);
  last4Controller.text = last4;

  var filledNickname = false;
  final holderName = result.cardholderName?.trim();
  if (holderName != null && holderName.isNotEmpty) {
    cardController.text = holderName;
    filledNickname = true;
  }

  var filledBank = false;
  String? matchedBankId;
  final networkName = result.networkName?.trim();
  if (bankController.text.trim().isEmpty &&
      networkName != null &&
      networkName.isNotEmpty) {
    bankController.text = _formatNetworkName(networkName);
    filledBank = true;
    final matchedBank = matchBankByName(bankController.text);
    matchedBankId = matchedBank?.id ?? kCustomBankId;
  }

  return CardScanFillResult(
    success: true,
    filledLast4: true,
    filledNickname: filledNickname,
    filledBank: filledBank,
    matchedBankId: matchedBankId,
  );
}

Future<CardScanFillResult?> performCardScan({
  required TextEditingController bankController,
  required TextEditingController cardController,
  required TextEditingController last4Controller,
}) async {
  const scanner = Cardscan();
  final supported = await scanner.isSupported();
  if (!supported) {
    return const CardScanFillResult(
      success: false,
      errorMessage: 'Card scanning is not supported on this device.',
    );
  }

  final result = await scanner.scanCard(
    const CardScanOptions(
      enableExpiryExtraction: true,
      enableNameExtraction: true,
      enableEnterManually: true,
    ),
  );

  if (result == null) {
    return null;
  }

  return applyScanResult(
    result,
    bankController: bankController,
    cardController: cardController,
    last4Controller: last4Controller,
  );
}
