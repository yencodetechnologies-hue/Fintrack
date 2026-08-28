class BankOption {
  final String id;
  final String displayName;
  final List<String> matchKeywords;

  const BankOption({
    required this.id,
    required this.displayName,
    required this.matchKeywords,
  });
}

const kCustomBankId = '__custom__';
const kCustomBankLabel = 'Other / Custom Bank';

const indianBanks = <BankOption>[
  BankOption(
    id: 'sbi',
    displayName: 'State Bank of India (SBI)',
    matchKeywords: ['sbi', 'statebank', 'state bank'],
  ),
  BankOption(
    id: 'hdfc',
    displayName: 'HDFC Bank',
    matchKeywords: ['hdfc'],
  ),
  BankOption(
    id: 'kotak',
    displayName: 'Kotak Mahindra Bank',
    matchKeywords: ['kotak'],
  ),
  BankOption(
    id: 'axis',
    displayName: 'Axis Bank',
    matchKeywords: ['axis'],
  ),
  BankOption(
    id: 'flipkart',
    displayName: 'Flipkart Axis Card',
    matchKeywords: ['flipkart'],
  ),
  BankOption(
    id: 'icici',
    displayName: 'ICICI Bank',
    matchKeywords: ['icici', 'amazon'],
  ),
  BankOption(
    id: 'yes',
    displayName: 'YES Bank',
    matchKeywords: ['yes'],
  ),
  BankOption(
    id: 'amex_gold',
    displayName: 'American Express Gold',
    matchKeywords: ['amexgold', 'americanexpressgold'],
  ),
  BankOption(
    id: 'amex',
    displayName: 'American Express',
    matchKeywords: ['amex', 'americanexpress', 'american'],
  ),
  BankOption(
    id: 'federal',
    displayName: 'Federal Bank',
    matchKeywords: ['federal'],
  ),
  BankOption(
    id: 'indusind',
    displayName: 'IndusInd Bank',
    matchKeywords: ['indusind', 'indus'],
  ),
  BankOption(
    id: 'rbl',
    displayName: 'RBL Bank',
    matchKeywords: ['rbl'],
  ),
  BankOption(
    id: 'hsbc',
    displayName: 'HSBC',
    matchKeywords: ['hsbc'],
  ),
  BankOption(
    id: 'pnb',
    displayName: 'Punjab National Bank (PNB)',
    matchKeywords: ['pnb', 'punjab'],
  ),
  BankOption(
    id: 'idfc',
    displayName: 'IDFC First Bank',
    matchKeywords: ['idfc', 'idfcfirst'],
  ),
  BankOption(
    id: 'idbi',
    displayName: 'IDBI Bank',
    matchKeywords: ['idbi', 'bandhan'],
  ),
  BankOption(
    id: 'paytm',
    displayName: 'Paytm Payments Bank',
    matchKeywords: ['paytm', 'airtel', 'jupiter'],
  ),
  BankOption(
    id: 'stanchart',
    displayName: 'Standard Chartered',
    matchKeywords: ['standardchartered', 'standard', 'scbank'],
  ),
  BankOption(
    id: 'canara',
    displayName: 'Canara Bank',
    matchKeywords: ['canara'],
  ),
  BankOption(
    id: 'tmb',
    displayName: 'Tamilnad Mercantile Bank (TMB)',
    matchKeywords: ['tmb', 'tamilnadu'],
  ),
  BankOption(
    id: 'bob',
    displayName: 'Bank of Baroda (BOBcard)',
    matchKeywords: ['bob', 'baroda', 'bobcard'],
  ),
  BankOption(
    id: 'aubank',
    displayName: 'AU Small Finance Bank',
    matchKeywords: ['aubank', 'aubankcard', 'au small'],
  ),
  BankOption(
    id: 'amazon_pay',
    displayName: 'Amazon Pay ICICI Card',
    matchKeywords: ['amazonpay', 'amazonicici', 'amazon pay'],
  ),
  BankOption(
    id: 'onecard',
    displayName: 'OneCard Metal',
    matchKeywords: ['onecard', 'one card'],
  ),
  BankOption(
    id: 'union',
    displayName: 'Union Bank of India',
    matchKeywords: ['union', 'unionbank'],
  ),
  BankOption(
    id: 'boi',
    displayName: 'Bank of India (BOI)',
    matchKeywords: ['boi', 'bankofindia'],
  ),
  BankOption(
    id: 'indian_bank',
    displayName: 'Indian Bank / Allahabad',
    matchKeywords: ['indianbank', 'allahabad'],
  ),
  BankOption(
    id: 'scapia',
    displayName: 'Scapia Federal Card',
    matchKeywords: ['scapia'],
  ),
  BankOption(
    id: 'slice',
    displayName: 'Slice Card',
    matchKeywords: ['slice', 'sliceit'],
  ),
  BankOption(
    id: 'dbs',
    displayName: 'DBS Bank (digibank)',
    matchKeywords: ['dbs', 'digibank'],
  ),
  BankOption(
    id: 'sib',
    displayName: 'South Indian Bank (SIB)',
    matchKeywords: ['sib', 'southindianbank'],
  ),
  BankOption(
    id: 'kvb',
    displayName: 'Karur Vysya Bank (KVB)',
    matchKeywords: ['kvb', 'karurvysya'],
  ),
  BankOption(
    id: 'central_bank',
    displayName: 'Central Bank of India',
    matchKeywords: ['centralbank', 'central'],
  ),
  BankOption(
    id: 'sbm',
    displayName: 'SBM Bank India',
    matchKeywords: ['sbm', 'sbmbank'],
  ),
];

String _normalizeBankName(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

BankOption? bankOptionById(String id) {
  for (final bank in indianBanks) {
    if (bank.id == id) {
      return bank;
    }
  }
  return null;
}

BankOption? matchBankByName(String name) {
  final normalized = _normalizeBankName(name);
  if (normalized.isEmpty) {
    return null;
  }

  for (final bank in indianBanks) {
    if (_normalizeBankName(bank.displayName) == normalized) {
      return bank;
    }
  }

  BankOption? bestMatch;
  var bestScore = 0;

  for (final bank in indianBanks) {
    for (final keyword in bank.matchKeywords) {
      final normalizedKeyword = _normalizeBankName(keyword);
      if (normalizedKeyword.isEmpty) {
        continue;
      }

      if (normalized == normalizedKeyword ||
          normalized.contains(normalizedKeyword) ||
          normalizedKeyword.contains(normalized)) {
        final score = normalizedKeyword.length;
        if (score > bestScore) {
          bestScore = score;
          bestMatch = bank;
        }
      }
    }
  }

  return bestMatch;
}

String resolveBankName({
  required String? selectedBankId,
  required String customBankName,
}) {
  if (selectedBankId == null || selectedBankId.isEmpty) {
    return '';
  }

  if (selectedBankId == kCustomBankId) {
    return customBankName.trim();
  }

  return bankOptionById(selectedBankId)?.displayName ?? '';
}
