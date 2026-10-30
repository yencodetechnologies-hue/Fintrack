import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Encapsulates the loaded exchange rates, last updated timestamp, and offline/cache status.
class CurrencyRatesResult {
  final Map<String, double> rates;
  final String lastUpdateDate;
  final bool isOffline;
  final bool isFromCache;
  final bool rateLimited;
  final DateTime fetchedAt;

  const CurrencyRatesResult({
    required this.rates,
    required this.lastUpdateDate,
    this.isOffline = false,
    this.isFromCache = false,
    this.rateLimited = false,
    required this.fetchedAt,
  });
}

class CurrencyService {
  static const String _primaryUrl = "https://open.er-api.com/v6/latest/USD";
  static const String _fallbackUrl =
      "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.json";

  static const String _keyRates = "currency_rates_json";
  static const String _keyDate = "currency_rates_date";
  static const String _keyFetchedMs = "currency_rates_fetched_ms";
  static const String _keyPairFrom = "currency_pair_from";
  static const String _keyPairTo = "currency_pair_to";

  /// Returns cached rates if available from today.
  /// If [force] is true (e.g. manual pull-to-refresh), enforces a 1-hour throttle.
  static Future<CurrencyRatesResult> getRates({bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = _readCachedRates(prefs);

    final now = DateTime.now();

    // 1. If not forcing a refresh, check if we already have valid rates fetched today
    if (!force && cached != null) {
      final fetchedAt = cached.fetchedAt;
      final isFromToday = fetchedAt.year == now.year &&
          fetchedAt.month == now.month &&
          fetchedAt.day == now.day;

      if (isFromToday) {
        return CurrencyRatesResult(
          rates: cached.rates,
          lastUpdateDate: cached.lastUpdateDate,
          isOffline: false,
          isFromCache: true,
          fetchedAt: fetchedAt,
        );
      }
    }

    // 2. If forcing a refresh, enforce the 1-hour rate limit
    if (force && cached != null) {
      final diff = now.difference(cached.fetchedAt);
      if (diff.inMinutes < 60) {
        return CurrencyRatesResult(
          rates: cached.rates,
          lastUpdateDate: cached.lastUpdateDate,
          isOffline: false,
          isFromCache: true,
          rateLimited: true,
          fetchedAt: cached.fetchedAt,
        );
      }
    }

    // 3. Attempt to fetch from network (primary first, then fallback)
    try {
      final networkResult = await _fetchFromNetwork();
      await _saveCachedRates(prefs, networkResult.rates, networkResult.lastUpdateDate, now);
      return networkResult;
    } catch (e) {
      debugPrint("CurrencyService: network fetch failed ($e)");

      // 4. If network fails, serve cache if available (offline state)
      if (cached != null) {
        return CurrencyRatesResult(
          rates: cached.rates,
          lastUpdateDate: cached.lastUpdateDate,
          isOffline: true,
          isFromCache: true,
          fetchedAt: cached.fetchedAt,
        );
      }

      // If no cache exists at all, rethrow so UI can show full error state
      rethrow;
    }
  }

  /// Attempts to fetch from primary source, falling back to secondary source.
  static Future<CurrencyRatesResult> _fetchFromNetwork() async {
    // Primary: open.er-api.com
    try {
      final res = await http.get(Uri.parse(_primaryUrl)).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final rawRates = data["rates"];
        if (rawRates is Map) {
          final rates = <String, double>{};
          rawRates.forEach((k, v) {
            if (v is num) rates[k.toString().toUpperCase()] = v.toDouble();
          });

          final dateStr = data["time_last_update_utc"]?.toString() ??
              DateTime.now().toUtc().toIso8601String().substring(0, 10);

          if (rates.isNotEmpty) {
            return CurrencyRatesResult(
              rates: rates,
              lastUpdateDate: _cleanDateString(dateStr),
              isOffline: false,
              isFromCache: false,
              fetchedAt: DateTime.now(),
            );
          }
        }
      }
    } catch (primaryErr) {
      debugPrint("CurrencyService: primary source failed: $primaryErr. Trying fallback...");
    }

    // Fallback: jsdelivr currency-api
    try {
      final res = await http.get(Uri.parse(_fallbackUrl)).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final rawRates = data["usd"];
        if (rawRates is Map) {
          final rates = <String, double>{};
          rawRates.forEach((k, v) {
            if (v is num) rates[k.toString().toUpperCase()] = v.toDouble();
          });
          // Ensure USD itself is present
          rates["USD"] = 1.0;

          final dateStr = data["date"]?.toString() ??
              DateTime.now().toUtc().toIso8601String().substring(0, 10);

          if (rates.isNotEmpty) {
            return CurrencyRatesResult(
              rates: rates,
              lastUpdateDate: _cleanDateString(dateStr),
              isOffline: false,
              isFromCache: false,
              fetchedAt: DateTime.now(),
            );
          }
        }
      }
    } catch (fallbackErr) {
      debugPrint("CurrencyService: fallback source failed: $fallbackErr");
    }

    throw Exception("Could not fetch exchange rates from any source");
  }

  static String _cleanDateString(String raw) {
    // E.g. "Fri, 30 Oct 2026 00:02:31 +0000" -> "30 Oct 2026, 00:02 UTC"
    final regex = RegExp(r'[A-Za-z]{3},\s*(\d{1,2}\s+[A-Za-z]{3}\s+\d{4})\s+(\d{2}:\d{2})');
    final m = regex.firstMatch(raw);
    if (m != null) {
      return "${m.group(1)}, ${m.group(2)} UTC";
    }
    return raw;
  }

  static CurrencyRatesResult? _readCachedRates(SharedPreferences prefs) {
    try {
      final jsonStr = prefs.getString(_keyRates);
      final dateStr = prefs.getString(_keyDate);
      final fetchedMs = prefs.getInt(_keyFetchedMs);

      if (jsonStr == null || dateStr == null || fetchedMs == null) {
        return null;
      }

      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map) return null;

      final rates = <String, double>{};
      decoded.forEach((k, v) {
        if (v is num) rates[k.toString().toUpperCase()] = v.toDouble();
      });

      if (rates.isEmpty) return null;

      return CurrencyRatesResult(
        rates: rates,
        lastUpdateDate: dateStr,
        isOffline: false,
        isFromCache: true,
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(fetchedMs),
      );
    } catch (e) {
      debugPrint("CurrencyService: error reading cached rates: $e");
      return null;
    }
  }

  static Future<void> _saveCachedRates(
    SharedPreferences prefs,
    Map<String, double> rates,
    String dateStr,
    DateTime fetchedAt,
  ) async {
    try {
      await prefs.setString(_keyRates, jsonEncode(rates));
      await prefs.setString(_keyDate, dateStr);
      await prefs.setInt(_keyFetchedMs, fetchedAt.millisecondsSinceEpoch);
    } catch (e) {
      debugPrint("CurrencyService: error saving rates cache: $e");
    }
  }

  /// Saves the last selected pair (e.g. "USD", "INR").
  static Future<void> saveSelectedPair(String from, String to) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPairFrom, from.trim().toUpperCase());
    await prefs.setString(_keyPairTo, to.trim().toUpperCase());
  }

  /// Restores the last selected pair, defaulting to "USD" and "INR".
  static Future<Map<String, String>> getSelectedPair() async {
    final prefs = await SharedPreferences.getInstance();
    final from = prefs.getString(_keyPairFrom) ?? "USD";
    final to = prefs.getString(_keyPairTo) ?? "INR";
    return {"from": from, "to": to};
  }
}

