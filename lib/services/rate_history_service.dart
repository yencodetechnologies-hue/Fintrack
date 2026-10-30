import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

/// Single daily rate point for a pair (FROM -> TO).
class DayRate {
  final DateTime date;
  final double rate;

  const DayRate({required this.date, required this.rate});

  @override
  String toString() => '${DateFormat("yyyy-MM-dd").format(date)}: $rate';
}

/// Computed statistics for a rate history series.
class RateHistoryStats {
  final double change;        // Current rate minus first rate in range
  final double changePercent; // (change / firstRate) * 100
  final double high;
  final DateTime highDate;
  final double low;
  final DateTime lowDate;
  final double average;

  const RateHistoryStats({
    required this.change,
    required this.changePercent,
    required this.high,
    required this.highDate,
    required this.low,
    required this.lowDate,
    required this.average,
  });
}

/// Pure statistics computation function.
/// Returns null if the list is empty.
RateHistoryStats? computeStats(List<DayRate> rates) {
  if (rates.isEmpty) return null;

  if (rates.length == 1) {
    final single = rates.first;
    return RateHistoryStats(
      change: 0.0,
      changePercent: 0.0,
      high: single.rate,
      highDate: single.date,
      low: single.rate,
      lowDate: single.date,
      average: single.rate,
    );
  }

  final first = rates.first;
  final last = rates.last;
  final change = last.rate - first.rate;
  final changePercent = first.rate != 0 ? (change / first.rate) * 100 : 0.0;

  var high = rates.first.rate;
  var highDate = rates.first.date;
  var low = rates.first.rate;
  var lowDate = rates.first.date;
  var sum = 0.0;

  for (final r in rates) {
    sum += r.rate;
    if (r.rate > high) {
      high = r.rate;
      highDate = r.date;
    }
    if (r.rate < low) {
      low = r.rate;
      lowDate = r.date;
    }
  }

  final average = sum / rates.length;

  return RateHistoryStats(
    change: change,
    changePercent: changePercent,
    high: high,
    highDate: highDate,
    low: low,
    lowDate: lowDate,
    average: average,
  );
}

class RateHistoryService {
  static final DateTime minDate = DateTime.utc(2024, 3, 2);

  static Directory? _cacheDir;

  static Future<Directory> _getCacheDirectory() async {
    if (_cacheDir != null) return _cacheDir!;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory("${base.path}/rate_history_cache");
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cacheDir = dir;
    return dir;
  }

  /// Formats date to YYYY-MM-DD
  static String formatDate(DateTime d) {
    return DateFormat("yyyy-MM-dd").format(d.toUtc());
  }

  /// Generates the list of target dates (UTC) for the requested day count [daysCount] (e.g. 7, 30, 90).
  static List<DateTime> getDatesForRange(int daysCount) {
    final now = DateTime.now().toUtc();
    final today = DateTime.utc(now.year, now.month, now.day);

    final list = <DateTime>[];
    for (int i = daysCount - 1; i >= 0; i--) {
      final d = today.subtract(Duration(days: i));
      if (!d.isBefore(minDate)) {
        list.add(d);
      }
    }
    return list;
  }

  /// Fetches rates for [from] -> [to] across the requested [days] (7, 30, 90).
  /// Reuses cached daily tables, fetches missing days with max 6 concurrent requests,
  /// and fills any 404 gaps with adjacent days.
  static Future<List<DayRate>> getRateHistory({
    required String from,
    required String to,
    required int days,
  }) async {
    final dates = getDatesForRange(days);
    if (dates.isEmpty) return [];

    final cacheDir = await _getCacheDirectory();
    final fromKey = from.trim().toLowerCase();
    final toKey = to.trim().toLowerCase();

    // 1. Identify which dates are missing from local disk cache
    final dailyTables = List<Map<String, double>?>.filled(dates.length, null);
    final missingIndices = <int>[];

    final nowUtc = DateTime.now().toUtc();
    final todayStr = formatDate(nowUtc);

    for (int i = 0; i < dates.length; i++) {
      final dateStr = formatDate(dates[i]);
      final isToday = dateStr == todayStr;
      final cached = await _readDayCache(cacheDir, dateStr, isToday: isToday);
      if (cached != null) {
        dailyTables[i] = cached;
      } else {
        missingIndices.add(i);
      }
    }

    // 2. Fetch missing days concurrently (limit 6 at a time)
    if (missingIndices.isNotEmpty) {
      final tasks = missingIndices.map((idx) {
        return () async {
          final dateStr = formatDate(dates[idx]);
          final isToday = dateStr == todayStr;
          final table = await _fetchSingleDay(cacheDir, dateStr, isToday: isToday);
          dailyTables[idx] = table;
        };
      }).toList();

      await _runWithConcurrencyLimit(tasks, limit: 6);
    }

    // 3. Compute pair rate for each day and bridge any 404 gaps
    final result = <DayRate>[];
    Map<String, double>? lastKnownTable;

    // Find the first available table for initial backfilling if needed
    Map<String, double>? firstAvailableTable;
    for (final t in dailyTables) {
      if (t != null) {
        firstAvailableTable = t;
        break;
      }
    }

    if (firstAvailableTable == null) {
      // All days failed (completely offline and no cache)
      return [];
    }

    lastKnownTable = firstAvailableTable;

    for (int i = 0; i < dates.length; i++) {
      var table = dailyTables[i];
      if (table != null) {
        lastKnownTable = table;
      } else {
        // Reuse last known day so chart has no gaps
        table = lastKnownTable;
      }

      if (table != null) {
        final fromRate = fromKey == "usd" ? 1.0 : table[fromKey];
        final toRate = toKey == "usd" ? 1.0 : table[toKey];

        if (fromRate != null && toRate != null && fromRate > 0) {
          final pairRate = toRate / fromRate;
          result.add(DayRate(date: dates[i], rate: pairRate));
        }
      }
    }

    return result;
  }

  /// Reads a cached day file from disk.
  /// Past days are permanent. Today's snapshot is valid if modified today UTC.
  static Future<Map<String, double>?> _readDayCache(
    Directory dir,
    String dateStr, {
    required bool isToday,
  }) async {
    try {
      final fileName = isToday ? "latest.json" : "$dateStr.json";
      final file = File("${dir.path}/$fileName");
      if (!await file.exists()) return null;

      if (isToday) {
        final lastModified = (await file.lastModified()).toUtc();
        final nowUtc = DateTime.now().toUtc();
        // If latest was saved on a previous day, expire it
        if (lastModified.year != nowUtc.year ||
            lastModified.month != nowUtc.month ||
            lastModified.day != nowUtc.day) {
          return null;
        }
      }

      final content = await file.readAsString();
      final data = jsonDecode(content);
      if (data is! Map) return null;

      final rawUsd = data["usd"] ?? data;
      if (rawUsd is! Map) return null;

      final rates = <String, double>{};
      rawUsd.forEach((k, v) {
        if (v is num) rates[k.toString().toLowerCase()] = v.toDouble();
      });
      rates["usd"] = 1.0;
      return rates.isNotEmpty ? rates : null;
    } catch (e) {
      debugPrint("RateHistoryService: error reading cache for $dateStr: $e");
      return null;
    }
  }

  /// Fetches a single day snapshot from primary or fallback URL.
  /// Saves successfully fetched past days permanently to disk.
  static Future<Map<String, double>?> _fetchSingleDay(
    Directory dir,
    String dateStr, {
    required bool isToday,
  }) async {
    final queryDate = isToday ? "latest" : dateStr;
    final primaryUrl =
        "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@$queryDate/v1/currencies/usd.min.json";
    final fallbackUrl =
        "https://$queryDate.currency-api.pages.dev/v1/currencies/usd.min.json";

    // 1. Try Primary
    Map<String, double>? table = await _downloadJson(primaryUrl);

    // 2. Try Fallback if primary failed
    table ??= await _downloadJson(fallbackUrl);

    if (table != null && table.isNotEmpty) {
      table["usd"] = 1.0;
      // Save to disk
      try {
        final fileName = isToday ? "latest.json" : "$dateStr.json";
        final file = File("${dir.path}/$fileName");
        await file.writeAsString(jsonEncode({"date": dateStr, "usd": table}));
      } catch (e) {
        debugPrint("RateHistoryService: failed saving cache for $dateStr: $e");
      }
      return table;
    }

    return null;
  }

  static Future<Map<String, double>?> _downloadJson(String url) async {
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map && data["usd"] is Map) {
          final raw = data["usd"] as Map;
          final map = <String, double>{};
          raw.forEach((k, v) {
            if (v is num) map[k.toString().toLowerCase()] = v.toDouble();
          });
          return map;
        }
      }
    } catch (_) {
      // Ignored for fallback chaining
    }
    return null;
  }

  /// Worker pool limiter: runs at most [limit] asynchronous tasks in parallel.
  static Future<void> _runWithConcurrencyLimit(
    List<Future<void> Function()> tasks, {
    int limit = 6,
  }) async {
    if (tasks.isEmpty) return;
    int index = 0;

    Future<void> worker() async {
      while (true) {
        int current;
        if (index >= tasks.length) return;
        current = index++;
        try {
          await tasks[current]();
        } catch (_) {}
      }
    }

    final workerCount = tasks.length < limit ? tasks.length : limit;
    final workers = List.generate(workerCount, (_) => worker());
    await Future.wait(workers);
  }
}

