import 'package:flutter_test/flutter_test.dart';
import 'package:card/utils/currency_converter.dart';

void main() {
  group('Currency Converter - convert()', () {
    final sampleRates = <String, double>{
      'USD': 1.0,
      'EUR': 0.85,
      'INR': 83.0,
      'GBP': 0.75,
      'JPY': 150.0,
    };

    test('1. same currency returns original amount', () {
      final resUsd = convert(amount: 100.0, from: 'USD', to: 'USD', rates: sampleRates);
      expect(resUsd, equals(100.0));

      final resEur = convert(amount: 45.67, from: 'EUR', to: 'EUR', rates: sampleRates);
      expect(resEur, equals(45.67));

      // case-insensitive check
      final resLower = convert(amount: 50.0, from: 'inr', to: 'INR', rates: sampleRates);
      expect(resLower, equals(50.0));
    });

    test('2. USD to X calculates amount * rate(X)', () {
      // 100 USD to INR @ 83.0 = 8300.0
      final res = convert(amount: 100.0, from: 'USD', to: 'INR', rates: sampleRates);
      expect(res, closeTo(8300.0, 0.0001));

      // 50 USD to EUR @ 0.85 = 42.5
      final resEur = convert(amount: 50.0, from: 'USD', to: 'EUR', rates: sampleRates);
      expect(resEur, closeTo(42.5, 0.0001));
    });

    test('3. X to Y calculates correctly via base USD rate(Y) / rate(X)', () {
      // 85 EUR (rate 0.85) to USD (rate 1.0) -> 85 * (1.0 / 0.85) = 100.0
      final resEurToUsd = convert(amount: 85.0, from: 'EUR', to: 'USD', rates: sampleRates);
      expect(resEurToUsd, closeTo(100.0, 0.0001));

      // 85 EUR (rate 0.85) to INR (rate 83.0) -> 85 * (83.0 / 0.85) = 8300.0
      final resEurToInr = convert(amount: 85.0, from: 'EUR', to: 'INR', rates: sampleRates);
      expect(resEurToInr, closeTo(8300.0, 0.0001));

      // 150 JPY (rate 150) to GBP (rate 0.75) -> 150 * (0.75 / 150) = 0.75
      final resJpyToGbp = convert(amount: 150.0, from: 'JPY', to: 'GBP', rates: sampleRates);
      expect(resJpyToGbp, closeTo(0.75, 0.0001));
    });

    test('4. missing code returns null safely', () {
      // Unknown FROM currency
      final resUnknownFrom = convert(amount: 100.0, from: 'XYZ', to: 'USD', rates: sampleRates);
      expect(resUnknownFrom, isNull);

      // Unknown TO currency
      final resUnknownTo = convert(amount: 100.0, from: 'USD', to: 'ABC', rates: sampleRates);
      expect(resUnknownTo, isNull);

      // Both unknown
      final resBothUnknown = convert(amount: 100.0, from: 'FOO', to: 'BAR', rates: sampleRates);
      expect(resBothUnknown, isNull);
    });

    test('5. zero amount returns 0.0', () {
      final resZero = convert(amount: 0.0, from: 'USD', to: 'EUR', rates: sampleRates);
      expect(resZero, equals(0.0));

      final resZeroSame = convert(amount: 0.0, from: 'INR', to: 'INR', rates: sampleRates);
      expect(resZeroSame, equals(0.0));
    });

    test('unitRate calculates 1 FROM = X TO', () {
      final rate = unitRate(from: 'USD', to: 'INR', rates: sampleRates);
      expect(rate, equals(83.0));

      final inverseRate = unitRate(from: 'INR', to: 'USD', rates: sampleRates);
      expect(inverseRate, closeTo(1.0 / 83.0, 0.00001));
    });

    test('formatAmount formats with commas and sensible decimals', () {
      expect(formatAmount(1234.56), equals('1,234.56'));
      expect(formatAmount(1000000.0), equals('1,000,000.00'));
      expect(formatAmount(0.000123), equals('0.000123'));
      expect(formatAmount(0.0), equals('0.00'));
    });
  });
}

