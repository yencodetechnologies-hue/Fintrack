import 'package:intl/intl.dart';

/// Information about a currency for display in the selector and cards.
class CurrencyInfo {
  final String code;
  final String name;
  final String symbol;
  final String flag;

  const CurrencyInfo({
    required this.code,
    required this.name,
    required this.symbol,
    required this.flag,
  });

  @override
  String toString() => '$code ($name)';
}

/// Pure currency conversion function:
///   rate(FROM -> TO) = rates[TO] / rates[FROM]
///   converted = amount * rate
///
/// Returns [0.0] when amount is 0.
/// Returns [amount] when from == to.
/// Returns null when a rate is missing, invalid or <= 0.
double? convert({
  required double amount,
  required String from,
  required String to,
  required Map<String, double> rates,
}) {
  if (amount == 0.0) return 0.0;
  final f = from.trim().toUpperCase();
  final t = to.trim().toUpperCase();
  if (f == t) return amount;

  final fromRate = rates[f];
  final toRate = rates[t];
  if (fromRate == null || toRate == null || fromRate <= 0 || toRate <= 0) {
    return null;
  }

  final rate = toRate / fromRate;
  return amount * rate;
}

/// Computes the unit rate (1 FROM = ? TO).
double? unitRate({
  required String from,
  required String to,
  required Map<String, double> rates,
}) {
  return convert(amount: 1.0, from: from, to: to, rates: rates);
}

/// Formats converted amount with thousand separators and sensible decimals:
/// - 2 decimals for normal currencies (e.g. 1,234.56)
/// - up to 6 decimals for tiny rates/amounts (e.g. 0.000123)
String formatAmount(double value) {
  if (value == 0) return "0.00";
  final absVal = value.abs();

  if (absVal < 0.000001) {
    return value.toStringAsFixed(8).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }
  if (absVal < 0.01) {
    // Show up to 6 decimal places, removing unnecessary trailing zeroes
    final s = value.toStringAsFixed(6).replaceAll(RegExp(r'0+$'), '');
    return s.endsWith('.') ? '${s}00' : s;
  }

  final formatter = NumberFormat("#,##0.00", "en_US");
  return formatter.format(value);
}

/// Formats a single exchange rate for the "1 FROM = X TO" text.
String formatRate(double rate) {
  if (rate == 0) return "0";
  if (rate >= 1000) {
    return NumberFormat("#,##0.00", "en_US").format(rate);
  }
  if (rate >= 100) {
    return NumberFormat("#,##0.000", "en_US").format(rate);
  }
  if (rate >= 1) {
    return NumberFormat("#,##0.0000", "en_US").format(rate);
  }
  if (rate >= 0.0001) {
    final s = rate.toStringAsFixed(6).replaceAll(RegExp(r'0+$'), '');
    return s.endsWith('.') ? '${s}0' : s;
  }
  return rate.toStringAsPrecision(4);
}

/// Looks up currency metadata by code, with graceful fallback for unlisted codes.
CurrencyInfo getCurrencyInfo(String code) {
  final upper = code.trim().toUpperCase();
  return kCurrenciesMap[upper] ??
      CurrencyInfo(
        code: upper,
        name: upper,
        symbol: upper,
        flag: "🌐",
      );
}

/// Comprehensive bundled map of world currencies with code, name, symbol, and country flag.
const Map<String, CurrencyInfo> kCurrenciesMap = {
  "USD": CurrencyInfo(code: "USD", name: "United States Dollar", symbol: "\$", flag: "🇺🇸"),
  "EUR": CurrencyInfo(code: "EUR", name: "Euro", symbol: "€", flag: "🇪🇺"),
  "GBP": CurrencyInfo(code: "GBP", name: "British Pound", symbol: "£", flag: "🇬🇧"),
  "INR": CurrencyInfo(code: "INR", name: "Indian Rupee", symbol: "₹", flag: "🇮🇳"),
  "AED": CurrencyInfo(code: "AED", name: "UAE Dirham", symbol: "د.إ", flag: "🇦🇪"),
  "AUD": CurrencyInfo(code: "AUD", name: "Australian Dollar", symbol: "A\$", flag: "🇦🇺"),
  "CAD": CurrencyInfo(code: "CAD", name: "Canadian Dollar", symbol: "CA\$", flag: "🇨🇦"),
  "SGD": CurrencyInfo(code: "SGD", name: "Singapore Dollar", symbol: "S\$", flag: "🇸🇬"),
  "JPY": CurrencyInfo(code: "JPY", name: "Japanese Yen", symbol: "¥", flag: "🇯🇵"),
  "CNY": CurrencyInfo(code: "CNY", name: "Chinese Yuan", symbol: "¥", flag: "🇨🇳"),
  "CHF": CurrencyInfo(code: "CHF", name: "Swiss Franc", symbol: "CHF", flag: "🇨🇭"),
  "SAR": CurrencyInfo(code: "SAR", name: "Saudi Riyal", symbol: "﷼", flag: "🇸🇦"),
  "QAR": CurrencyInfo(code: "QAR", name: "Qatari Riyal", symbol: "﷼", flag: "🇶🇦"),
  "KWD": CurrencyInfo(code: "KWD", name: "Kuwaiti Dinar", symbol: "د.ك", flag: "🇰🇼"),
  "BHD": CurrencyInfo(code: "BHD", name: "Bahraini Dinar", symbol: ".د.ب", flag: "🇧🇭"),
  "OMR": CurrencyInfo(code: "OMR", name: "Omani Rial", symbol: "﷼", flag: "🇴🇲"),
  "NZD": CurrencyInfo(code: "NZD", name: "New Zealand Dollar", symbol: "NZ\$", flag: "🇳🇿"),
  "HKD": CurrencyInfo(code: "HKD", name: "Hong Kong Dollar", symbol: "HK\$", flag: "🇭🇰"),
  "KRW": CurrencyInfo(code: "KRW", name: "South Korean Won", symbol: "₩", flag: "🇰🇷"),
  "MYR": CurrencyInfo(code: "MYR", name: "Malaysian Ringgit", symbol: "RM", flag: "🇲🇾"),
  "THB": CurrencyInfo(code: "THB", name: "Thai Baht", symbol: "฿", flag: "🇹🇭"),
  "IDR": CurrencyInfo(code: "IDR", name: "Indonesian Rupiah", symbol: "Rp", flag: "🇮🇩"),
  "PHP": CurrencyInfo(code: "PHP", name: "Philippine Peso", symbol: "₱", flag: "🇵🇭"),
  "VND": CurrencyInfo(code: "VND", name: "Vietnamese Dong", symbol: "₫", flag: "🇻🇳"),
  "BRL": CurrencyInfo(code: "BRL", name: "Brazilian Real", symbol: "R\$", flag: "🇧🇷"),
  "ZAR": CurrencyInfo(code: "ZAR", name: "South African Rand", symbol: "R", flag: "🇿🇦"),
  "RUB": CurrencyInfo(code: "RUB", name: "Russian Ruble", symbol: "₽", flag: "🇷🇺"),
  "TRY": CurrencyInfo(code: "TRY", name: "Turkish Lira", symbol: "₺", flag: "🇹🇷"),
  "MXN": CurrencyInfo(code: "MXN", name: "Mexican Peso", symbol: "\$", flag: "🇲🇽"),
  "SEK": CurrencyInfo(code: "SEK", name: "Swedish Krona", symbol: "kr", flag: "🇸🇪"),
  "NOK": CurrencyInfo(code: "NOK", name: "Norwegian Krone", symbol: "kr", flag: "🇳🇴"),
  "DKK": CurrencyInfo(code: "DKK", name: "Danish Krone", symbol: "kr", flag: "🇩🇰"),
  "PLN": CurrencyInfo(code: "PLN", name: "Polish Zloty", symbol: "zł", flag: "🇵🇱"),
  "EGP": CurrencyInfo(code: "EGP", name: "Egyptian Pound", symbol: "E£", flag: "🇪🇬"),
  "PKR": CurrencyInfo(code: "PKR", name: "Pakistani Rupee", symbol: "₨", flag: "🇵🇰"),
  "BDT": CurrencyInfo(code: "BDT", name: "Bangladeshi Taka", symbol: "৳", flag: "🇧🇩"),
  "LKR": CurrencyInfo(code: "LKR", name: "Sri Lankan Rupee", symbol: "Rs", flag: "🇱🇰"),
  "NPR": CurrencyInfo(code: "NPR", name: "Nepalese Rupee", symbol: "रू", flag: "🇳🇵"),
  "ILS": CurrencyInfo(code: "ILS", name: "Israeli New Shekel", symbol: "₪", flag: "🇮🇱"),
  "CZK": CurrencyInfo(code: "CZK", name: "Czech Koruna", symbol: "Kč", flag: "🇨🇿"),
  "HUF": CurrencyInfo(code: "HUF", name: "Hungarian Forint", symbol: "Ft", flag: "🇭🇺"),
  "RON": CurrencyInfo(code: "RON", name: "Romanian Leu", symbol: "lei", flag: "🇷🇴"),
  "CLP": CurrencyInfo(code: "CLP", name: "Chilean Peso", symbol: "\$", flag: "🇨🇱"),
  "COP": CurrencyInfo(code: "COP", name: "Colombian Peso", symbol: "\$", flag: "🇨🇴"),
  "PEN": CurrencyInfo(code: "PEN", name: "Peruvian Sol", symbol: "S/", flag: "🇵🇪"),
  "ARS": CurrencyInfo(code: "ARS", name: "Argentine Peso", symbol: "\$", flag: "🇦🇷"),
  "NGN": CurrencyInfo(code: "NGN", name: "Nigerian Naira", symbol: "₦", flag: "🇳🇬"),
  "KES": CurrencyInfo(code: "KES", name: "Kenyan Shilling", symbol: "KSh", flag: "🇰🇪"),
  "GHS": CurrencyInfo(code: "GHS", name: "Ghanaian Cedi", symbol: "GH₵", flag: "🇬🇭"),
  "TZS": CurrencyInfo(code: "TZS", name: "Tanzanian Shilling", symbol: "TSh", flag: "🇹🇿"),
  "UGX": CurrencyInfo(code: "UGX", name: "Ugandan Shilling", symbol: "USh", flag: "🇺🇬"),
  "MAD": CurrencyInfo(code: "MAD", name: "Moroccan Dirham", symbol: "DH", flag: "🇲🇦"),
  "JOD": CurrencyInfo(code: "JOD", name: "Jordanian Dinar", symbol: "JD", flag: "🇯🇴"),
  "KZT": CurrencyInfo(code: "KZT", name: "Kazakhstani Tenge", symbol: "₸", flag: "🇰🇿"),
  "UAH": CurrencyInfo(code: "UAH", name: "Ukrainian Hryvnia", symbol: "₴", flag: "🇺🇦"),
  "BGN": CurrencyInfo(code: "BGN", name: "Bulgarian Lev", symbol: "лв", flag: "🇧🇬"),
  "HRK": CurrencyInfo(code: "HRK", name: "Croatian Kuna", symbol: "kn", flag: "🇭🇷"),
  "CRC": CurrencyInfo(code: "CRC", name: "Costa Rican Colon", symbol: "₡", flag: "🇨🇷"),
  "DOP": CurrencyInfo(code: "DOP", name: "Dominican Peso", symbol: "RD\$", flag: "🇩🇴"),
  "JMD": CurrencyInfo(code: "JMD", name: "Jamaican Dollar", symbol: "J\$", flag: "🇯🇲"),
  "BBD": CurrencyInfo(code: "BBD", name: "Barbadian Dollar", symbol: "Bds\$", flag: "🇧🇧"),
  "BIF": CurrencyInfo(code: "BIF", name: "Burundian Franc", symbol: "FBu", flag: "🇧🇮"),
  "BMD": CurrencyInfo(code: "BMD", name: "Bermudian Dollar", symbol: "\$", flag: "🇧🇲"),
  "BND": CurrencyInfo(code: "BND", name: "Brunei Dollar", symbol: "B\$", flag: "🇧🇳"),
  "BOB": CurrencyInfo(code: "BOB", name: "Bolivian Boliviano", symbol: "Bs.", flag: "🇧🇴"),
  "BSD": CurrencyInfo(code: "BSD", name: "Bahamian Dollar", symbol: "B\$", flag: "🇧🇸"),
  "BTN": CurrencyInfo(code: "BTN", name: "Bhutanese Ngultrum", symbol: "Nu.", flag: "🇧🇹"),
  "BWP": CurrencyInfo(code: "BWP", name: "Botswana Pula", symbol: "P", flag: "🇧🇼"),
  "BYN": CurrencyInfo(code: "BYN", name: "Belarusian Ruble", symbol: "Br", flag: "🇧🇾"),
  "BZD": CurrencyInfo(code: "BZD", name: "Belize Dollar", symbol: "BZ\$", flag: "🇧🇿"),
  "CDF": CurrencyInfo(code: "CDF", name: "Congolese Franc", symbol: "FC", flag: "🇨🇩"),
  "CUP": CurrencyInfo(code: "CUP", name: "Cuban Peso", symbol: "\$", flag: "🇨🇺"),
  "CVE": CurrencyInfo(code: "CVE", name: "Cape Verdean Escudo", symbol: "\$", flag: "🇨🇻"),
  "DJF": CurrencyInfo(code: "DJF", name: "Djiboutian Franc", symbol: "Fdj", flag: "🇩🇯"),
  "DZD": CurrencyInfo(code: "DZD", name: "Algerian Dinar", symbol: "د.ج", flag: "🇩🇿"),
  "ETB": CurrencyInfo(code: "ETB", name: "Ethiopian Birr", symbol: "Br", flag: "🇪🇹"),
  "FJD": CurrencyInfo(code: "FJD", name: "Fijian Dollar", symbol: "FJ\$", flag: "🇫🇯"),
  "GEL": CurrencyInfo(code: "GEL", name: "Georgian Lari", symbol: "₾", flag: "🇬🇪"),
  "GIP": CurrencyInfo(code: "GIP", name: "Gibraltar Pound", symbol: "£", flag: "🇬🇮"),
  "GMD": CurrencyInfo(code: "GMD", name: "Gambian Dalasi", symbol: "D", flag: "🇬🇲"),
  "GNF": CurrencyInfo(code: "GNF", name: "Guinean Franc", symbol: "FG", flag: "🇬🇳"),
  "GTQ": CurrencyInfo(code: "GTQ", name: "Guatemalan Quetzal", symbol: "Q", flag: "🇬🇹"),
  "GYD": CurrencyInfo(code: "GYD", name: "Guyanese Dollar", symbol: "G\$", flag: "🇬🇾"),
  "HNL": CurrencyInfo(code: "HNL", name: "Honduran Lempira", symbol: "L", flag: "🇭🇳"),
  "HTG": CurrencyInfo(code: "HTG", name: "Haitian Gourde", symbol: "G", flag: "🇭🇹"),
  "IQD": CurrencyInfo(code: "IQD", name: "Iraqi Dinar", symbol: "ع.د", flag: "🇮🇶"),
  "ISK": CurrencyInfo(code: "ISK", name: "Icelandic Krona", symbol: "kr", flag: "🇮🇸"),
  "KGS": CurrencyInfo(code: "KGS", name: "Kyrgystani Som", symbol: "с", flag: "🇰🇬"),
  "KHR": CurrencyInfo(code: "KHR", name: "Cambodian Riel", symbol: "៛", flag: "🇰🇭"),
  "LAK": CurrencyInfo(code: "LAK", name: "Laotian Kip", symbol: "₭", flag: "🇱🇦"),
  "LBP": CurrencyInfo(code: "LBP", name: "Lebanese Pound", symbol: "L£", flag: "🇱🇧"),
  "MDL": CurrencyInfo(code: "MDL", name: "Moldovan Leu", symbol: "L", flag: "🇲🇩"),
  "MKD": CurrencyInfo(code: "MKD", name: "Macedonian Denar", symbol: "ден", flag: "🇲🇰"),
  "MMK": CurrencyInfo(code: "MMK", name: "Myanmar Kyat", symbol: "K", flag: "🇲🇲"),
  "MNT": CurrencyInfo(code: "MNT", name: "Mongolian Tugrik", symbol: "₮", flag: "🇲🇳"),
  "MOP": CurrencyInfo(code: "MOP", name: "Macanese Pataca", symbol: "MOP\$", flag: "🇲🇴"),
  "MRU": CurrencyInfo(code: "MRU", name: "Mauritanian Ouguiya", symbol: "UM", flag: "🇲🇷"),
  "MUR": CurrencyInfo(code: "MUR", name: "Mauritian Rupee", symbol: "₨", flag: "🇲🇺"),
  "MVR": CurrencyInfo(code: "MVR", name: "Maldivian Rufiyaa", symbol: "Rf", flag: "🇲🇻"),
  "MWK": CurrencyInfo(code: "MWK", name: "Malawian Kwacha", symbol: "MK", flag: "🇲🇼"),
  "MZN": CurrencyInfo(code: "MZN", name: "Mozambican Metical", symbol: "MT", flag: "🇲🇿"),
  "NAD": CurrencyInfo(code: "NAD", name: "Namibian Dollar", symbol: "N\$", flag: "🇳🇦"),
  "NIO": CurrencyInfo(code: "NIO", name: "Nicaraguan Cordoba", symbol: "C\$", flag: "🇳🇮"),
  "PAB": CurrencyInfo(code: "PAB", name: "Panamanian Balboa", symbol: "B/.", flag: "🇵🇦"),
  "PGK": CurrencyInfo(code: "PGK", name: "Papua New Guinean Kina", symbol: "K", flag: "🇵🇬"),
  "PYG": CurrencyInfo(code: "PYG", name: "Paraguayan Guarani", symbol: "₲", flag: "🇵🇾"),
  "RSD": CurrencyInfo(code: "RSD", name: "Serbian Dinar", symbol: "дин.", flag: "🇷🇸"),
  "RWF": CurrencyInfo(code: "RWF", name: "Rwandan Franc", symbol: "FRw", flag: "🇷🇼"),
  "SZL": CurrencyInfo(code: "SZL", name: "Swazi Lilangeni", symbol: "L", flag: "🇸🇿"),
  "TND": CurrencyInfo(code: "TND", name: "Tunisian Dinar", symbol: "د.ت", flag: "🇹🇳"),
  "TTD": CurrencyInfo(code: "TTD", name: "Trinidad & Tobago Dollar", symbol: "TT\$", flag: "🇹🇹"),
  "TWD": CurrencyInfo(code: "TWD", name: "New Taiwan Dollar", symbol: "NT\$", flag: "🇹🇼"),
  "UYU": CurrencyInfo(code: "UYU", name: "Uruguayan Peso", symbol: "\$U", flag: "🇺🇾"),
  "UZS": CurrencyInfo(code: "UZS", name: "Uzbekistani Som", symbol: "so'm", flag: "🇺🇿"),
  "XAF": CurrencyInfo(code: "XAF", name: "Central African CFA Franc", symbol: "FCFA", flag: "🇨🇲"),
  "XOF": CurrencyInfo(code: "XOF", name: "West African CFA Franc", symbol: "CFA", flag: "🇸🇳"),
  "XCD": CurrencyInfo(code: "XCD", name: "East Caribbean Dollar", symbol: "EC\$", flag: "🇦🇮"),
  "YER": CurrencyInfo(code: "YER", name: "Yemeni Rial", symbol: "﷼", flag: "🇾🇪"),
  "ZMW": CurrencyInfo(code: "ZMW", name: "Zambian Kwacha", symbol: "ZK", flag: "🇿🇲"),
};

/// Popular currencies shown at the top of the selector.
const List<String> kPopularCurrencies = [
  "USD",
  "EUR",
  "GBP",
  "INR",
  "AED",
  "AUD",
  "CAD",
  "SGD",
  "JPY",
  "CNY",
  "CHF",
  "SAR",
  "QAR",
  "KWD",
];
