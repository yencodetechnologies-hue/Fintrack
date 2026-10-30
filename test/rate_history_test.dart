import 'package:flutter_test/flutter_test.dart';
import 'package:card/services/rate_history_service.dart';

void main() {
  group('RateHistoryService - computeStats()', () {
    test('1. Empty list returns null', () {
      final stats = computeStats([]);
      expect(stats, isNull);
    });

    test('2. Single point returns zero change with identical high, low, and average', () {
      final singleDate = DateTime.utc(2026, 10, 1);
      final stats = computeStats([
        DayRate(date: singleDate, rate: 83.5),
      ]);

      expect(stats, isNotNull);
      expect(stats!.change, equals(0.0));
      expect(stats.changePercent, equals(0.0));
      expect(stats.high, equals(83.5));
      expect(stats.highDate, equals(singleDate));
      expect(stats.low, equals(83.5));
      expect(stats.lowDate, equals(singleDate));
      expect(stats.average, equals(83.5));
    });

    test('3. Rising rates compute positive change and percent', () {
      final d1 = DateTime.utc(2026, 10, 1);
      final d2 = DateTime.utc(2026, 10, 2);
      final d3 = DateTime.utc(2026, 10, 3);

      final stats = computeStats([
        DayRate(date: d1, rate: 100.0),
        DayRate(date: d2, rate: 105.0),
        DayRate(date: d3, rate: 110.0),
      ]);

      expect(stats, isNotNull);
      expect(stats!.change, closeTo(10.0, 0.0001));
      expect(stats.changePercent, closeTo(10.0, 0.0001));
      expect(stats.high, equals(110.0));
      expect(stats.highDate, equals(d3));
      expect(stats.low, equals(100.0));
      expect(stats.lowDate, equals(d1));
      expect(stats.average, closeTo(105.0, 0.0001));
    });

    test('4. Falling rates compute negative change and percent', () {
      final d1 = DateTime.utc(2026, 10, 1);
      final d2 = DateTime.utc(2026, 10, 2);
      final d3 = DateTime.utc(2026, 10, 3);

      final stats = computeStats([
        DayRate(date: d1, rate: 200.0),
        DayRate(date: d2, rate: 180.0),
        DayRate(date: d3, rate: 150.0),
      ]);

      expect(stats, isNotNull);
      expect(stats!.change, closeTo(-50.0, 0.0001));
      expect(stats.changePercent, closeTo(-25.0, 0.0001));
      expect(stats.high, equals(200.0));
      expect(stats.highDate, equals(d1));
      expect(stats.low, equals(150.0));
      expect(stats.lowDate, equals(d3));
      expect(stats.average, closeTo((200 + 180 + 150) / 3, 0.0001));
    });

    test('5. Flat rates return zero change and percent', () {
      final d1 = DateTime.utc(2026, 10, 1);
      final d2 = DateTime.utc(2026, 10, 2);

      final stats = computeStats([
        DayRate(date: d1, rate: 50.0),
        DayRate(date: d2, rate: 50.0),
      ]);

      expect(stats, isNotNull);
      expect(stats!.change, equals(0.0));
      expect(stats.changePercent, equals(0.0));
      expect(stats.high, equals(50.0));
      expect(stats.low, equals(50.0));
      expect(stats.average, equals(50.0));
    });

    test('6. Missing day / non-consecutive series handled smoothly', () {
      final d1 = DateTime.utc(2026, 10, 1);
      final d3 = DateTime.utc(2026, 10, 3); // Oct 2 was skipped

      final stats = computeStats([
        DayRate(date: d1, rate: 80.0),
        DayRate(date: d3, rate: 88.0),
      ]);

      expect(stats, isNotNull);
      expect(stats!.change, closeTo(8.0, 0.0001));
      expect(stats.changePercent, closeTo(10.0, 0.0001));
      expect(stats.average, closeTo(84.0, 0.0001));
    });
  });

  group('RateHistoryService - getDatesForRange()', () {
    test('never generates dates before minDate (2024-03-02)', () {
      final dates = RateHistoryService.getDatesForRange(90);
      expect(dates.isNotEmpty, isTrue);
      for (final d in dates) {
        expect(d.isBefore(RateHistoryService.minDate), isFalse);
      }
    });

    test('generates expected count for standard ranges', () {
      final d7 = RateHistoryService.getDatesForRange(7);
      expect(d7.length, equals(7));

      final d30 = RateHistoryService.getDatesForRange(30);
      expect(d30.length, equals(30));

      final d90 = RateHistoryService.getDatesForRange(90);
      expect(d90.length, equals(90));
    });
  });
}

