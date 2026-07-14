import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shs_cardscan/shs_cardscan.dart';
import 'package:card/data/indian_banks.dart';
import 'package:card/utils/card_scan_mapper.dart';

void main() {
  group('applyScanResult', () {
    late TextEditingController bankController;
    late TextEditingController cardController;
    late TextEditingController last4Controller;

    setUp(() {
      bankController = TextEditingController();
      cardController = TextEditingController();
      last4Controller = TextEditingController();
    });

    tearDown(() {
      bankController.dispose();
      cardController.dispose();
      last4Controller.dispose();
    });

    test('fills last4, nickname, and bank hint from scan result', () {
      const result = CardScanResult(
        cardNumber: '4242424242424242',
        expiryMonth: '12',
        expiryYear: '28',
        cardholderName: 'JANE DOE',
        networkName: 'visa',
      );

      final fillResult = applyScanResult(
        result,
        bankController: bankController,
        cardController: cardController,
        last4Controller: last4Controller,
      );

      expect(fillResult.success, isTrue);
      expect(last4Controller.text, '4242');
      expect(cardController.text, 'JANE DOE');
      expect(bankController.text, 'Visa');
      expect(fillResult.filledLast4, isTrue);
      expect(fillResult.filledNickname, isTrue);
      expect(fillResult.filledBank, isTrue);
      expect(fillResult.matchedBankId, kCustomBankId);
    });

    test('does not overwrite existing bank name', () {
      bankController.text = 'HDFC';

      const result = CardScanResult(
        cardNumber: '4242424242424242',
        expiryMonth: null,
        expiryYear: null,
        cardholderName: null,
        networkName: 'mastercard',
      );

      final fillResult = applyScanResult(
        result,
        bankController: bankController,
        cardController: cardController,
        last4Controller: last4Controller,
      );

      expect(fillResult.success, isTrue);
      expect(bankController.text, 'HDFC');
      expect(fillResult.filledBank, isFalse);
    });

    test('rejects invalid card numbers', () {
      const result = CardScanResult(
        cardNumber: '1234567890123456',
        expiryMonth: null,
        expiryYear: null,
        cardholderName: null,
        networkName: null,
      );

      final fillResult = applyScanResult(
        result,
        bankController: bankController,
        cardController: cardController,
        last4Controller: last4Controller,
      );

      expect(fillResult.success, isFalse);
      expect(last4Controller.text, isEmpty);
    });
  });
}
