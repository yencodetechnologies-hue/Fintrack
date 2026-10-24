import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'ledger_common.dart';

// decoded logos, so a list of company tiles doesn't decode base64 on every rebuild
final Map<int, Uint8List> _logoCache = {};

Uint8List? _logoBytes(String? dataUrl) {
  if (dataUrl == null || !dataUrl.startsWith("data:image")) return null;
  return _logoCache.putIfAbsent(dataUrl.hashCode, () {
    final comma = dataUrl.indexOf(",");
    return base64Decode(dataUrl.substring(comma + 1));
  });
}

/// The company's logo (set by its Admin in Settings), or its first letter when it has none.
class CompanyAvatar extends StatelessWidget {
  final Map<String, dynamic> company;
  final double size;
  final double radius;
  final Color letterBackground;
  final Color letterColor;
  const CompanyAvatar({
    super.key,
    required this.company,
    this.size = 40,
    this.radius = 12,
    this.letterBackground = kForestDark,
    this.letterColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    final bytes = _logoBytes(company["logo"]?.toString());
    if (bytes != null) {
      return Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(radius)),
        // fills the whole tile (uploads are already trimmed to the logo itself)
        child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
      );
    }
    final name = company["name"]?.toString() ?? "";
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: letterBackground, borderRadius: BorderRadius.circular(radius)),
      alignment: Alignment.center,
      child: Text(name.isNotEmpty ? name[0].toUpperCase() : "C",
          style: GoogleFonts.inter(color: letterColor, fontSize: size * 0.45, fontWeight: FontWeight.bold)),
    );
  }
}

/// Pick a logo from the gallery: plain borders are trimmed and it's fitted to a 256px square, like the web does.
Future<String?> pickCompanyLogo() async {
  final img = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1400, maxHeight: 1400);
  if (img == null) return null;
  final png = await _squareLogoPng(await File(img.path).readAsBytes());
  return png == null ? null : "data:image/png;base64,${base64Encode(png)}";
}

/// Trim rows/columns that only repeat the corner colour (white page margins, transparent padding), then
/// fill a 256px square: near-square logos edge to edge (centre crop), wide/tall ones shown whole.
Future<Uint8List?> _squareLogoPng(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final src = (await codec.getNextFrame()).image;
  final w = src.width, h = src.height;
  final rgba = (await src.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
  int at(int x, int y) => (y * w + x) * 4;
  final bg = [rgba[0], rgba[1], rgba[2], rgba[3]];
  bool isBorder(int i) =>
      (rgba[i + 3] < 16 && bg[3] < 16) ||
      ((rgba[i] - bg[0]).abs() + (rgba[i + 1] - bg[1]).abs() + (rgba[i + 2] - bg[2]).abs() < 36 && (rgba[i + 3] - bg[3]).abs() < 16);
  var top = 0, bottom = h - 1, left = 0, right = w - 1;
  bool rowIsBorder(int y) {
    for (var x = 0; x < w; x += 2) {
      if (!isBorder(at(x, y))) return false;
    }
    return true;
  }

  bool colIsBorder(int x) {
    for (var y = top; y <= bottom; y += 2) {
      if (!isBorder(at(x, y))) return false;
    }
    return true;
  }

  while (top < bottom && rowIsBorder(top)) {
    top++;
  }
  while (bottom > top && rowIsBorder(bottom)) {
    bottom--;
  }
  while (left < right && colIsBorder(left)) {
    left++;
  }
  while (right > left && colIsBorder(right)) {
    right--;
  }
  var box = Rect.fromLTRB(left.toDouble(), top.toDouble(), right + 1.0, bottom + 1.0);
  if (box.width < 8 || box.height < 8) box = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());

  const s = 256.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint()..filterQuality = FilterQuality.high;
  final ratio = box.width / box.height;
  if (ratio > 0.8 && ratio < 1.25) {
    final side = box.shortestSide;
    canvas.drawImageRect(src, Rect.fromCenter(center: box.center, width: side, height: side), const Rect.fromLTWH(0, 0, s, s), paint);
  } else {
    final scale = (s / box.width) < (s / box.height) ? s / box.width : s / box.height;
    final dw = box.width * scale, dh = box.height * scale;
    canvas.drawImageRect(src, box, Rect.fromLTWH((s - dw) / 2, (s - dh) / 2, dw, dh), paint);
  }
  final out = await recorder.endRecording().toImage(s.toInt(), s.toInt());
  final data = await out.toByteData(format: ui.ImageByteFormat.png);
  src.dispose();
  out.dispose();
  return data?.buffer.asUint8List();
}
