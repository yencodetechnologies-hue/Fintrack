import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../utils/bank_card_style.dart';

class BankCardPreview extends StatelessWidget {
  final String bank, name, digits;
  final CardStyle style;
  const BankCardPreview({required this.bank, required this.name, required this.digits, required this.style});

  @override
  Widget build(BuildContext context) {
    switch (style) {
      case CardStyle.sbi:        return _SbiCard(bank: bank, name: name, digits: digits);
      case CardStyle.hdfc:       return _HdfcCard(bank: bank, name: name, digits: digits);
      case CardStyle.kotak:      return _KotakCard(bank: bank, name: name, digits: digits);
      case CardStyle.axisRibbon: return _AxisCard(bank: bank, name: name, digits: digits);
      case CardStyle.flipkart:   return _FlipkartCard(bank: bank, name: name, digits: digits);
      case CardStyle.yes:        return _YesCard(bank: bank, name: name, digits: digits);
      case CardStyle.icici:      return _IciciCard(bank: bank, name: name, digits: digits);
      case CardStyle.amexGold:   return _AmexGoldCard(bank: bank, name: name, digits: digits);
      case CardStyle.amexBlue:   return _AmexBlueCard(bank: bank, name: name, digits: digits);
      case CardStyle.federal:    return _FederalCard(bank: bank, name: name, digits: digits);
      case CardStyle.indusind:   return _IndusIndCard(bank: bank, name: name, digits: digits);
      case CardStyle.rbl:        return _RblCard(bank: bank, name: name, digits: digits);
      case CardStyle.hsbc:       return _HsbcCard(bank: bank, name: name, digits: digits);
      case CardStyle.pnb:        return _PnbCard(bank: bank, name: name, digits: digits);
      case CardStyle.idfc:       return _IdfcCard(bank: bank, name: name, digits: digits);
      case CardStyle.idbi:       return _IdbiCard(bank: bank, name: name, digits: digits);
      case CardStyle.paytm:      return _PaytmCard(bank: bank, name: name, digits: digits);
      case CardStyle.stanchart:  return _StanChartCard(bank: bank, name: name, digits: digits);
      case CardStyle.canara:     return _CanaraCard(bank: bank, name: name, digits: digits);
      case CardStyle.tmb:        return _TmbCard(bank: bank, name: name, digits: digits);
    }
  }
}

class _Shell extends StatelessWidget {
  final List<Color> colors;
  final Color shadow;
  final List<Widget> overlays;
  final Widget child;
  final AlignmentGeometry begin;
  final AlignmentGeometry end;
  const _Shell({required this.colors, required this.shadow,
    required this.overlays, required this.child,
    this.begin = Alignment.topLeft, this.end = Alignment.bottomRight});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity, height: 210,
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: colors, begin: begin, end: end),
      borderRadius: BorderRadius.circular(22),
      boxShadow: [BoxShadow(color: shadow.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))],
    ),
    child: ClipRRect(borderRadius: BorderRadius.circular(22),
        child: Stack(children: [...overlays,
          Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 16), child: child)])),
  );
}

class _BodyPreview extends StatelessWidget {
  final String bank, name, digits, sub;
  final Color text, subtext;
  final Widget chip, net;
  const _BodyPreview({required this.bank, required this.name, required this.digits,
    required this.sub, required this.text, required this.subtext,
    required this.chip, required this.net});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(bank.isEmpty ? 'BANK NAME' : bank.toUpperCase(),
            style: TextStyle(color: text, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1.1),
            overflow: TextOverflow.ellipsis),
        Text(sub, style: TextStyle(color: subtext, fontSize: 8, letterSpacing: 2)),
      ])),
      Icon(Icons.nfc_rounded, color: subtext, size: 24),
    ]),
    const SizedBox(height: 12),
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      chip,
      Icon(Icons.wifi, color: subtext, size: 22),
    ]),
    const Spacer(),
    Text('•••• •••• •••• ${digits.isEmpty ? "••••" : digits}',
        style: TextStyle(color: text, fontSize: 18, letterSpacing: 4, fontWeight: FontWeight.w700)),
    const SizedBox(height: 10),
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('CARD HOLDER', style: TextStyle(color: subtext, fontSize: 7, letterSpacing: 1.5)),
          const SizedBox(height: 2),
          Text(name.isEmpty ? 'YOUR NAME' : name.toUpperCase(),
              style: TextStyle(color: text, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.8),
              overflow: TextOverflow.ellipsis),
        ]),
      ),
      const SizedBox(width: 8),
      net,
    ]),
  ]);
}

// ─── Chips ────────────────────────────────────────────────────────────────────
Widget _gChip() => Container(width: 48, height: 34,
    decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFE8C95D), Color(0xFFC5970A)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.5), width: 0.8)),
    child: CustomPaint(painter: _CP()));

Widget _sChip() => Container(width: 48, height: 34,
    decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFCCCCCC), Color(0xFF888888)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: Colors.white.withOpacity(0.4), width: 0.8)),
    child: CustomPaint(painter: _CP(color: const Color(0xFF666666))));

// ─── Network logos ────────────────────────────────────────────────────────────
class _Visa extends StatelessWidget {
  final Color c;
  const _Visa({this.c = Colors.white});
  @override Widget build(BuildContext context) => Text('VISA',
      style: TextStyle(color: c, fontSize: 18, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, letterSpacing: 2));
}
class _MC extends StatelessWidget {
  const _MC();
  @override Widget build(BuildContext context) => Row(children: [
    Container(width: 22, height: 22, decoration: const BoxDecoration(color: Color(0xFFEB001B), shape: BoxShape.circle)),
    Transform.translate(offset: const Offset(-8, 0),
        child: Container(width: 22, height: 22,
            decoration: BoxDecoration(color: const Color(0xFFF79E1B).withOpacity(0.9), shape: BoxShape.circle))),
  ]);
}
class _Amex extends StatelessWidget {
  final Color c;
  const _Amex({this.c = const Color(0xFF1A1400)});
  @override Widget build(BuildContext context) => Text('AMEX',
      style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 2));
}

// ─── Card implementations ──────────────────────────────────────────────────────

class _SbiCard extends StatelessWidget {
  final String bank, name, digits;
  const _SbiCard({required this.bank, required this.name, required this.digits});
  @override Widget build(BuildContext context) => _Shell(
      colors: const [Color(0xFF002366), Color(0xFF0047AB)], shadow: const Color(0xFF002366),
      overlays: [Positioned.fill(child: CustomPaint(painter: _GridPainter(color: const Color(0xFF4488CC))))],
      child: _BodyPreview(bank: bank, name: name, digits: digits, sub: 'INTERNATIONAL',
          text: Colors.white, subtext: const Color(0xFF88BBEE),
          chip: _sChip(), net: const _Visa()));
}

class _HdfcCard extends StatelessWidget {
  final String bank, name, digits;
  const _HdfcCard({required this.bank, required this.name, required this.digits});
  @override Widget build(BuildContext context) => _Shell(
      colors: const [Color(0xFF8B0000), Color(0xFFCC0000)], shadow: const Color(0xFF8B0000),
      overlays: [Positioned.fill(child: CustomPaint(painter: _BrushPainter()))],
      child: _BodyPreview(bank: bank, name: name, digits: digits, sub: 'CREDIT CARD',
          text: Colors.white, subtext: Colors.white60,
          chip: _sChip(), net: const _Visa()));
}

class _KotakCard extends StatelessWidget {
  final String bank, name, digits;
  const _KotakCard({required this.bank, required this.name, required this.digits});
  @override Widget build(BuildContext context) => _Shell(
      colors: const [Color(0xFF1A0800), Color(0xFF2D1200)], shadow: const Color(0xFFB8600A),
      overlays: [
        Positioned.fill(child: CustomPaint(painter: _InfinityPainter())),
        Positioned(top: -20, right: 20,
            child: Container(width: 180, height: 180,
                decoration: BoxDecoration(shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [const Color(0xFFFF8C00).withOpacity(0.3), Colors.transparent])))),
      ],
      child: _BodyPreview(bank: bank, name: name, digits: digits, sub: 'SIGNATURE',
          text: Colors.white, subtext: const Color(0xFFFF8C00),
          chip: _sChip(), net: const _Visa()));
}

class _AxisCard extends StatelessWidget {
  final String bank, name, digits;
  const _AxisCard({required this.bank, required this.name, required this.digits});
  @override Widget build(BuildContext context) => _Shell(
      colors: const [Color(0xFF050505), Color(0xFF0A0A0A)], shadow: const Color(0xFF2244AA),
      overlays: [Positioned.fill(child: CustomPaint(painter: _NeonRibbonPainter()))],
      child: _BodyPreview(bank: bank, name: name, digits: digits, sub: 'SIGNATURE',
          text: Colors.white, subtext: Colors.white54,
          chip: _gChip(), net: const _Visa()));
}

class _FlipkartCard extends StatelessWidget {
  final String bank, name, digits;
  const _FlipkartCard({required this.bank, required this.name, required this.digits});
  @override Widget build(BuildContext context) => _Shell(
      colors: const [Color(0xFF0B1C6B), Color(0xFF1A3399)], shadow: const Color(0xFF0B1C6B),
      overlays: [Positioned.fill(child: CustomPaint(painter: _RibbonPainter(
          c1: const Color(0xFF4499FF), c2: const Color(0xFFFF44AA))))],
      child: _BodyPreview(bank: bank, name: name, digits: digits, sub: 'AXIS BANK',
          text: Colors.white, subtext: Colors.white54,
          chip: _gChip(), net: const _Visa()));
}

class _YesCard extends StatelessWidget {
  final String bank, name, digits;
  const _YesCard({required this.bank, required this.name, required this.digits});
  @override Widget build(BuildContext context) => _Shell(
      colors: const [Color(0xFF003087), Color(0xFF0050C8)], shadow: const Color(0xFF003087),
      overlays: [Positioned.fill(child: CustomPaint(painter: _MandalaPainter()))],
      child: _BodyPreview(bank: bank, name: name, digits: digits, sub: 'WORLD MASTERCARD',
          text: Colors.white, subtext: Colors.white60,
          chip: _sChip(), net: const _MC()));
}

class _IciciCard extends StatelessWidget {
  final String bank, name, digits;
  const _IciciCard({required this.bank, required this.name, required this.digits});
  @override Widget build(BuildContext context) => _Shell(
      colors: const [Color(0xFF1A1A1A), Color(0xFF0D0D0D)], shadow: Colors.black,
      overlays: [Positioned.fill(child: CustomPaint(painter: _BrushPainter()))],
      child: _BodyPreview(bank: bank, name: name, digits: digits, sub: 'CREDIT CARD',
          text: Colors.white, subtext: Colors.white54,
          chip: _sChip(), net: const _Visa()));
}

class _AmexGoldCard extends StatelessWidget {
  final String bank, name, digits;
  const _AmexGoldCard({required this.bank, required this.name, required this.digits});
  @override Widget build(BuildContext context) => _Shell(
      colors: const [Color(0xFFB8970A), Color(0xFFDAA520), Color(0xFFEDD060)],
      shadow: const Color(0xFFB8860B),
      overlays: [Positioned.fill(child: CustomPaint(painter: _GoldWavePainter()))],
      child: _BodyPreview(bank: bank, name: name, digits: digits, sub: 'GOLD CARD',
          text: const Color(0xFF1A1400), subtext: const Color(0xFF4A3A00),
          chip: Container(width: 48, height: 34,
              decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFDDDDDD), Color(0xFF999999)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: const Color(0xFF1A1400).withOpacity(0.3))),
              child: CustomPaint(painter: _CP(color: const Color(0xFF555555)))),
          net: const _Amex()));
}

class _AmexBlueCard extends StatelessWidget {
  final String bank, name, digits;
  const _AmexBlueCard({required this.bank, required this.name, required this.digits});
  @override Widget build(BuildContext context) => _Shell(
      colors: const [Color(0xFF003087), Color(0xFF0050C8)], shadow: const Color(0xFF001A66),
      overlays: [Positioned.fill(child: CustomPaint(painter: _DotGridPainter(color: const Color(0xFF4488DD))))],
      child: _BodyPreview(bank: bank, name: name, digits: digits, sub: 'BLUE CASH CARD',
          text: Colors.white, subtext: Colors.white60,
          chip: _gChip(), net: const _Amex(c: Colors.white)));
}

class _FederalCard extends StatelessWidget {
  final String bank, name, digits;
  const _FederalCard({required this.bank, required this.name, required this.digits});
  @override Widget build(BuildContext context) => _Shell(
      colors: const [Color(0xFF050505), Color(0xFF111111)], shadow: Colors.black,
      overlays: [Positioned.fill(child: CustomPaint(painter: _PolygonPainter(color: const Color(0xFF333333))))],
      child: _BodyPreview(bank: bank, name: name, digits: digits, sub: 'CELESTA',
          text: const Color(0xFFD4AF37), subtext: const Color(0xFF888888),
          chip: _gChip(), net: const _MC()));
}

class _IndusIndCard extends StatelessWidget {
  final String bank, name, digits;
  const _IndusIndCard({required this.bank, required this.name, required this.digits});
  @override Widget build(BuildContext context) => _Shell(
      colors: const [Color(0xFF111111), Color(0xFF1C1C1C)], shadow: Colors.black,
      overlays: [Positioned.fill(child: CustomPaint(painter: _GridTexturePainter()))],
      child: _BodyPreview(bank: bank, name: name, digits: digits, sub: 'LEGEND',
          text: Colors.white, subtext: Colors.white38,
          chip: _sChip(), net: const _Visa()));
}

class _RblCard extends StatelessWidget {
  final String bank, name, digits;
  const _RblCard({required this.bank, required this.name, required this.digits});
  @override Widget build(BuildContext context) => _Shell(
      colors: const [Color(0xFF1A1A1A), Color(0xFF2A2A2A)], shadow: Colors.black,
      overlays: [Positioned.fill(child: CustomPaint(painter: _BrushPainter())),
        Positioned(bottom: -20, right: -10,
            child: Text('PLAY', style: TextStyle(fontSize: 110, fontWeight: FontWeight.w900,
                color: Colors.white.withOpacity(0.07), letterSpacing: -4)))],
      child: _BodyPreview(bank: bank, name: name, digits: digits, sub: 'CREDIT CARD',
          text: Colors.white, subtext: Colors.white38,
          chip: _sChip(), net: const _Visa()));
}

class _HsbcCard extends StatelessWidget {
  final String bank, name, digits;
  const _HsbcCard({required this.bank, required this.name, required this.digits});
  @override Widget build(BuildContext context) => _Shell(
      colors: const [Color(0xFF9B0000), Color(0xFFBB0000)], shadow: const Color(0xFF9B0000),
      overlays: [Positioned.fill(child: CustomPaint(painter: _HexPainter()))],
      child: _BodyPreview(bank: bank, name: name, digits: digits, sub: 'PREMIER INFINITE',
          text: Colors.white, subtext: Colors.white60,
          chip: _gChip(), net: const _Visa()));
}

class _PnbCard extends StatelessWidget {
  final String bank, name, digits;
  const _PnbCard({required this.bank, required this.name, required this.digits});
  @override Widget build(BuildContext context) => _Shell(
      colors: const [Color(0xFF5C0018), Color(0xFF8B0025)], shadow: const Color(0xFF5C0018),
      overlays: [Positioned.fill(child: CustomPaint(painter: _AuroraPainter()))],
      child: _BodyPreview(bank: bank, name: name, digits: digits, sub: 'CREDIT CARD',
          text: Colors.white, subtext: const Color(0xFFFFAAAA),
          chip: _gChip(), net: const _Visa()));
}

class _IdfcCard extends StatelessWidget {
  final String bank, name, digits;
  const _IdfcCard({required this.bank, required this.name, required this.digits});
  @override Widget build(BuildContext context) => _Shell(
      colors: const [Color(0xFF003344), Color(0xFF005566)], shadow: const Color(0xFF003344),
      overlays: [Positioned.fill(child: CustomPaint(painter: _CarbonPainter()))],
      child: _BodyPreview(bank: bank, name: name, digits: digits, sub: 'FIRST METAL',
          text: Colors.white, subtext: Colors.white54,
          chip: _sChip(), net: const _Visa()));
}

class _IdbiCard extends StatelessWidget {
  final String bank, name, digits;
  const _IdbiCard({required this.bank, required this.name, required this.digits});
  @override Widget build(BuildContext context) => _Shell(
      colors: const [Color(0xFF1A0050), Color(0xFF2D0080)], shadow: const Color(0xFF1A0050),
      overlays: [Positioned.fill(child: CustomPaint(painter: _SunburstPainter()))],
      child: _BodyPreview(bank: bank, name: name, digits: digits, sub: 'CREDIT CARD',
          text: Colors.white, subtext: const Color(0xFFAA88FF),
          chip: _gChip(), net: const _MC()));
}

class _PaytmCard extends StatelessWidget {
  final String bank, name, digits;
  const _PaytmCard({required this.bank, required this.name, required this.digits});
  @override Widget build(BuildContext context) => _Shell(
      colors: const [Color(0xFF000814), Color(0xFF001A4D)], shadow: const Color(0xFF002D72),
      overlays: [Positioned.fill(child: CustomPaint(painter: _GalaxyPainter()))],
      child: _BodyPreview(bank: bank, name: name, digits: digits, sub: 'DIGITAL CARD',
          text: Colors.white, subtext: const Color(0xFF6699FF),
          chip: _gChip(), net: const _Visa()));
}

class _StanChartCard extends StatelessWidget {
  final String bank, name, digits;
  const _StanChartCard({required this.bank, required this.name, required this.digits});
  @override Widget build(BuildContext context) => _Shell(
      colors: const [Color(0xFF006B3C), Color(0xFF009B5B)], shadow: const Color(0xFF006B3C),
      overlays: [Positioned.fill(child: CustomPaint(painter: _ShimmerPainter()))],
      child: _BodyPreview(bank: bank, name: name, digits: digits, sub: 'INFINITE',
          text: Colors.white, subtext: Colors.white60,
          chip: _gChip(), net: const _Visa()));
}

class _CanaraCard extends StatelessWidget {
  final String bank, name, digits;
  const _CanaraCard({required this.bank, required this.name, required this.digits});
  @override Widget build(BuildContext context) => _Shell(
      colors: const [Color(0xFF004D00), Color(0xFF007700)], shadow: const Color(0xFF004D00),
      overlays: [Positioned.fill(child: CustomPaint(painter: _SparklePainter()))],
      child: _BodyPreview(bank: bank, name: name, digits: digits, sub: 'PLATINUM',
          text: Colors.white, subtext: const Color(0xFF88FF88),
          chip: _gChip(), net: const _Visa()));
}

class _TmbCard extends StatelessWidget {
  final String bank, name, digits;
  const _TmbCard({required this.bank, required this.name, required this.digits});
  @override Widget build(BuildContext context) => _Shell(
      colors: const [Color(0xFF00008B), Color(0xFF0000CD)], shadow: const Color(0xFF00008B),
      overlays: [Positioned.fill(child: CustomPaint(painter: _OceanPainter()))],
      child: _BodyPreview(bank: bank, name: name, digits: digits, sub: 'PLATINUM',
          text: Colors.white, subtext: const Color(0xFF88AAFF),
          chip: _gChip(), net: const _Visa()));
}

// ─── Custom Painters ─────────────────────────────────────────────────────────

class _CP extends CustomPainter {
  final Color color;
  const _CP({this.color = const Color(0xFFB8960C)});
  @override void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 0.8;
    canvas.drawLine(Offset(size.width/2, 0), Offset(size.width/2, size.height), p);
    canvas.drawLine(Offset(0, size.height/2), Offset(size.width, size.height/2), p);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0,0,size.width,size.height), const Radius.circular(6)), p);
  }
  @override bool shouldRepaint(_) => false;
}

class _GridPainter extends CustomPainter {
  final Color color;
  const _GridPainter({required this.color});
  @override void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color.withOpacity(0.18)..style = PaintingStyle.stroke..strokeWidth = 0.5;
    for (double y = 0.2; y < 1.0; y += 0.2) { canvas.drawLine(Offset(0, size.height*y), Offset(size.width, size.height*y), p); }
    for (double x = 0.12; x < 1.0; x += 0.12) { canvas.drawLine(Offset(size.width*x, 0), Offset(size.width*x, size.height), p); }
    final fp = Paint()..color = color.withOpacity(0.15)..style = PaintingStyle.fill;
    canvas.drawOval(Rect.fromCenter(center: Offset(size.width*0.22, size.height*0.42), width: size.width*0.22, height: size.height*0.42), fp);
    canvas.drawOval(Rect.fromCenter(center: Offset(size.width*0.52, size.height*0.38), width: size.width*0.28, height: size.height*0.45), fp);
  }
  @override bool shouldRepaint(_) => false;
}

class _BrushPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    for (int i = 0; i < 60; i++) {
      canvas.drawLine(Offset(0, (size.height/60)*i), Offset(size.width, (size.height/60)*i+2),
          Paint()..color = Colors.white.withOpacity(i%3==0 ? 0.04 : 0.02)..strokeWidth = 1.2);
    }
  }
  @override bool shouldRepaint(_) => false;
}

class _InfinityPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    final cx = size.width*0.65; final cy = size.height*0.48; final r = 40.0;
    canvas.drawCircle(Offset(cx, cy), 65,
        Paint()..color = const Color(0xFFFF8C00).withOpacity(0.22)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22));
    final p = Paint()..style = PaintingStyle.stroke..strokeWidth = 6..strokeCap = StrokeCap.round;
    p.color = const Color(0xFFFFAA00).withOpacity(0.6);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx-r*0.7, cy), width: r*1.3, height: r*0.95), p);
    p.color = const Color(0xFFFF6600).withOpacity(0.5);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx+r*0.7, cy), width: r*1.3, height: r*0.95), p);
  }
  @override bool shouldRepaint(_) => false;
}

class _NeonRibbonPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    final bluePath = Path()
      ..moveTo(size.width*0.05, size.height*0.85)
      ..cubicTo(size.width*0.25, size.height*0.05, size.width*0.55, size.height, size.width*0.80, size.height*0.15);
    canvas.drawPath(bluePath, Paint()..color = const Color(0xFF4488FF).withOpacity(0.28)
      ..style = PaintingStyle.stroke..strokeWidth = 34..strokeCap = StrokeCap.round..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
    canvas.drawPath(bluePath, Paint()..color = const Color(0xFF2266FF).withOpacity(0.9)
      ..style = PaintingStyle.stroke..strokeWidth = 18..strokeCap = StrokeCap.round..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    final pinkPath = Path()
      ..moveTo(size.width*0.18, size.height*0.95)
      ..cubicTo(size.width*0.40, size.height*0.08, size.width*0.65, size.height*0.95, size.width*0.95, size.height*0.22);
    canvas.drawPath(pinkPath, Paint()..color = const Color(0xFFFF44BB).withOpacity(0.24)
      ..style = PaintingStyle.stroke..strokeWidth = 28..strokeCap = StrokeCap.round..maskFilter = const MaskFilter.blur(BlurStyle.normal, 11));
    canvas.drawPath(pinkPath, Paint()..color = const Color(0xFFDD1199).withOpacity(0.85)
      ..style = PaintingStyle.stroke..strokeWidth = 14..strokeCap = StrokeCap.round..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
  }
  @override bool shouldRepaint(_) => false;
}

class _RibbonPainter extends CustomPainter {
  final Color c1, c2;
  const _RibbonPainter({required this.c1, required this.c2});
  @override void paint(Canvas canvas, Size size) {
    canvas.drawPath(Path()..moveTo(size.width*0.1, size.height*0.9)..cubicTo(size.width*0.3, size.height*0.1, size.width*0.6, size.height*0.95, size.width*0.9, size.height*0.2),
        Paint()..color = c1.withOpacity(0.6)..style = PaintingStyle.stroke..strokeWidth = 16..strokeCap = StrokeCap.round);
    canvas.drawPath(Path()..moveTo(size.width*0.2, size.height*0.95)..cubicTo(size.width*0.5, size.height*0.05, size.width*0.7, size.height*0.9, size.width*0.95, size.height*0.25),
        Paint()..color = c2.withOpacity(0.6)..style = PaintingStyle.stroke..strokeWidth = 13..strokeCap = StrokeCap.round);
  }
  @override bool shouldRepaint(_) => false;
}

class _MandalaPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withOpacity(0.09)..style = PaintingStyle.stroke..strokeWidth = 0.8;
    final cx = size.width*0.5; final cy = size.height*0.5;
    for (double r = 18; r <= 120; r += 20) { canvas.drawCircle(Offset(cx, cy), r, p); }
    for (int i = 0; i < 12; i++) {
      final a = i*30*3.14159/180;
      canvas.drawLine(Offset(cx+18*_c(a), cy+18*_s(a)), Offset(cx+120*_c(a), cy+120*_s(a)), p);
    }
  }
  @override bool shouldRepaint(_) => false;
}

class _GoldWavePainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    for (double i = -size.height; i < size.width+size.height; i += 18) {
      canvas.drawLine(Offset(i, 0), Offset(i+size.height, size.height), Paint()..color = const Color(0xFF1A1400).withOpacity(0.06)..strokeWidth = 6);
    }
  }
  @override bool shouldRepaint(_) => false;
}

class _DotGridPainter extends CustomPainter {
  final Color color;
  const _DotGridPainter({required this.color});
  @override void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color.withOpacity(0.2);
    for (double x = 12; x < size.width; x += 14) {
      for (double y = 12; y < size.height; y += 14) {
        canvas.drawCircle(Offset(x, y), 0.8, p);
      }
    }
  }
  @override bool shouldRepaint(_) => false;
}

class _PolygonPainter extends CustomPainter {
  final Color color;
  const _PolygonPainter({required this.color});
  @override void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color.withOpacity(0.5)..style = PaintingStyle.stroke..strokeWidth = 0.8;
    canvas.drawPath(Path()..moveTo(size.width*0.1,size.height*0.8)..lineTo(size.width*0.3,size.height*0.3)..lineTo(size.width*0.55,size.height*0.7)..lineTo(size.width*0.35,size.height*0.95)..close(), p);
    canvas.drawPath(Path()..moveTo(size.width*0.3,size.height*0.3)..lineTo(size.width*0.55,size.height*0.05)..lineTo(size.width*0.75,size.height*0.45)..lineTo(size.width*0.55,size.height*0.7)..close(), p);
  }
  @override bool shouldRepaint(_) => false;
}

class _GridTexturePainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withOpacity(0.06)..style = PaintingStyle.stroke..strokeWidth = 0.5;
    for (double x = 0; x < size.width; x += 8) { canvas.drawLine(Offset(x, 0), Offset(x, size.height), p); }
    for (double y = 0; y < size.height; y += 8) { canvas.drawLine(Offset(0, y), Offset(size.width, y), p); }
  }
  @override bool shouldRepaint(_) => false;
}

class _HexPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withOpacity(0.08)..style = PaintingStyle.stroke..strokeWidth = 0.8;
    for (double cx = 0; cx < size.width+30; cx += 30) {
      for (double cy = 0; cy < size.height+20; cy += 26) {
        final offset = (cy ~/ 26 % 2 == 0) ? 0.0 : 15.0;
        final path = Path();
        for (int i = 0; i < 6; i++) {
          final a = i*60*3.14159/180;
          if (i == 0) {
            path.moveTo(cx+offset+12*_c(a), cy+12*_s(a));
          } else {
            path.lineTo(cx+offset+12*_c(a), cy+12*_s(a));
          }
        }
        path.close();
        canvas.drawPath(path, p);
      }
    }
  }
  @override bool shouldRepaint(_) => false;
}

class _AuroraPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    final colors = [const Color(0xFFFF6666).withOpacity(0.18), const Color(0xFFFF9999).withOpacity(0.13), const Color(0xFFFFBBBB).withOpacity(0.09)];
    for (int i = 0; i < 3; i++) {
      canvas.drawPath(Path()..moveTo(0, size.height*(0.3+i*0.1))..cubicTo(size.width*0.3, size.height*(0.6-i*0.15), size.width*0.65, size.height*(0.2+i*0.1), size.width, size.height*(0.5-i*0.1)),
          Paint()..color = colors[i]..style = PaintingStyle.stroke..strokeWidth = 40-i*10.0..strokeCap = StrokeCap.round..maskFilter = MaskFilter.blur(BlurStyle.normal, 20-i*4.0));
    }
  }
  @override bool shouldRepaint(_) => false;
}

class _CarbonPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    for (int i = 0; i < 60; i++) {
      canvas.drawRect(Rect.fromLTWH((size.width/60)*i*1.5, 0, 4, size.height), Paint()..color = Colors.white.withOpacity(0.025));
    }
  }
  @override bool shouldRepaint(_) => false;
}

class _SunburstPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    canvas.drawCircle(Offset(size.width*0.72, size.height*0.38), 72, Paint()..color = const Color(0xFF8800FF).withOpacity(0.22)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 25));
    canvas.drawCircle(Offset(size.width*0.72, size.height*0.38), 32, Paint()..color = const Color(0xFFBB44FF).withOpacity(0.3)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
  }
  @override bool shouldRepaint(_) => false;
}

class _GalaxyPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    canvas.drawCircle(Offset(size.width*0.6, size.height*0.4), 80, Paint()..color = const Color(0xFF0044FF).withOpacity(0.14)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30));
    final sp = Paint()..color = Colors.white.withOpacity(0.75);
    for (final s in [[0.08,0.12,1.0],[0.22,0.08,1.5],[0.38,0.22,1.0],[0.52,0.06,1.2],[0.65,0.18,1.8],[0.80,0.10,1.0],[0.92,0.28,1.3],[0.15,0.38,1.0],[0.45,0.42,0.8],[0.70,0.48,1.5],[0.88,0.80,0.8],[0.60,0.88,1.0]]) {
      canvas.drawCircle(Offset(size.width*s[0], size.height*s[1]), s[2], sp);
    }
  }
  @override bool shouldRepaint(_) => false;
}

class _ShimmerPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    for (double i = -size.height; i < size.width+size.height; i += 24) {
      canvas.drawPath(Path()..moveTo(i, 0)..lineTo(i+size.height, size.height)..lineTo(i+size.height+10, size.height)..lineTo(i+10, 0)..close(),
          Paint()..color = Colors.white.withOpacity(0.055));
    }
  }
  @override bool shouldRepaint(_) => false;
}

class _SparklePainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    for (final d in [[0.15,0.25,3.0],[0.28,0.45,2.0],[0.42,0.18,4.0],[0.55,0.55,2.5],[0.68,0.30,3.5],[0.80,0.60,2.0],[0.90,0.20,3.0]]) {
      canvas.drawCircle(Offset(size.width*d[0], size.height*d[1]), d[2]*3, Paint()..color = const Color(0xFF88FF88).withOpacity(0.14)..maskFilter = MaskFilter.blur(BlurStyle.normal, d[2]*2.5));
      canvas.drawCircle(Offset(size.width*d[0], size.height*d[1]), d[2]*0.6, Paint()..color = const Color(0xFFAAFFAA).withOpacity(0.9));
    }
  }
  @override bool shouldRepaint(_) => false;
}

class _OceanPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    for (int w = 0; w < 4; w++) {
      final p = Paint()..color = const Color(0xFF0088CC).withOpacity(0.12)..style = PaintingStyle.stroke..strokeWidth = 1.5;
      final path = Path(); path.moveTo(0, size.height*(0.45+w*0.12));
      for (double x = 0; x <= size.width; x += 20) {
        path.quadraticBezierTo(x+10, size.height*(0.45+w*0.12)+(w%2==0 ? -12.0 : 12.0), x+20, size.height*(0.45+w*0.12));
      }
      canvas.drawPath(path, p);
    }
  }
  @override bool shouldRepaint(_) => false;
}

double _c(double r) {
  final n = r % (2 * 3.14159265);
  return 1 - n * n / 2 + n * n * n * n / 24 - n * n * n * n * n * n / 720;
}
double _s(double r) => _c(r - 3.14159265 / 2);