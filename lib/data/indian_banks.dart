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
    matchKeywords: ['idfc', 'onecard', 'slice'],
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
    matchKeywords: ['canara', 'union', 'boi', 'central'],
  ),
  BankOption(
    id: 'tmb',
    displayName: 'Tamilnad Mercantile Bank (TMB)',
    matchKeywords: ['tmb', 'tamilnadu'],
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
