enum CardStyle {
  sbi,
  hdfc,
  kotak,
  axisRibbon,
  flipkart,
  yes,
  icici,
  amexGold,
  amexBlue,
  federal,
  indusind,
  rbl,
  hsbc,
  pnb,
  idfc,
  idbi,
  paytm,
  stanchart,
  canara,
  tmb,
  bob,
  aubank,
  amazonPay,
  onecard,
  union,
  boi,
  indianBank,
  scapia,
  slice,
  dbs,
  sib,
  kvb,
  centralBank,
  sbm,
}

CardStyle styleForBank(String bankName) {
  final b = bankName.toLowerCase().trim();
  if (b.contains('amazon pay') || b.contains('amazonicici') || b.contains('amazon icici')) {
    return CardStyle.amazonPay;
  }
  if (b.contains('onecard') || b.contains('one card')) {
    return CardStyle.onecard;
  }
  if (b.contains('scapia')) {
    return CardStyle.scapia;
  }
  if (b.contains('slice')) {
    return CardStyle.slice;
  }
  if (b.contains('bobcard') || b.contains('bank of baroda') || b.contains('baroda')) {
    return CardStyle.bob;
  }
  if (b.contains('au small') || b.contains('au bank') || b.contains('aubank')) {
    return CardStyle.aubank;
  }
  if (b.contains('union bank') || b.contains('union')) {
    return CardStyle.union;
  }
  if (b.contains('bank of india') || b.contains('boi')) {
    return CardStyle.boi;
  }
  if (b.contains('indian bank') || b.contains('allahabad')) {
    return CardStyle.indianBank;
  }
  if (b.contains('dbs') || b.contains('digibank')) {
    return CardStyle.dbs;
  }
  if (b.contains('south indian') || b.contains('sib')) {
    return CardStyle.sib;
  }
  if (b.contains('karur vysya') || b.contains('kvb')) {
    return CardStyle.kvb;
  }
  if (b.contains('central bank')) {
    return CardStyle.centralBank;
  }
  if (b.contains('sbm')) {
    return CardStyle.sbm;
  }
  if (b.contains('sbi') || b.contains('state bank')) {
    return CardStyle.sbi;
  }
  if (b.contains('hdfc')) {
    return CardStyle.hdfc;
  }
  if (b.contains('kotak')) {
    return CardStyle.kotak;
  }
  if (b.contains('axis')) {
    return CardStyle.axisRibbon;
  }
  if (b.contains('flipkart')) {
    return CardStyle.flipkart;
  }
  if (b.contains('yes')) {
    return CardStyle.yes;
  }
  if (b.contains('icici') || b.contains('amazon')) {
    return CardStyle.icici;
  }
  if (b.contains('amex gold') || b.contains('american express gold')) {
    return CardStyle.amexGold;
  }
  if (b.contains('amex') || b.contains('american')) {
    return CardStyle.amexBlue;
  }
  if (b.contains('federal')) {
    return CardStyle.federal;
  }
  if (b.contains('indus')) {
    return CardStyle.indusind;
  }
  if (b.contains('rbl')) {
    return CardStyle.rbl;
  }
  if (b.contains('hsbc')) {
    return CardStyle.hsbc;
  }
  if (b.contains('pnb') || b.contains('punjab')) {
    return CardStyle.pnb;
  }
  if (b.contains('idfc')) {
    return CardStyle.idfc;
  }
  if (b.contains('idbi') || b.contains('bandhan')) {
    return CardStyle.idbi;
  }
  if (b.contains('paytm') || b.contains('airtel') || b.contains('jupiter')) {
    return CardStyle.paytm;
  }
  if (b.contains('standard') || b.contains('scbank')) {
    return CardStyle.stanchart;
  }
  if (b.contains('canara')) {
    return CardStyle.canara;
  }
  if (b.contains('tmb') || b.contains('tamilnadu')) {
    return CardStyle.tmb;
  }
  if (bankName.isEmpty) {
    return CardStyle.idfc;
  }

  final index =
      bankName.codeUnits.reduce((a, b) => a + b) % CardStyle.values.length;
  return CardStyle.values[index];
}
