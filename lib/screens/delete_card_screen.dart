import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/card_service.dart';

class DeleteCardTheme {
  static const Color creamSheet = Color(0xFFF6F4EB);
  static const Color forestDark = Color(0xFF0F261C);
  static const Color darkText = Color(0xFF132A20);
  static const Color terracotta = Color(0xFFB8452D);
  static const Color textMuted = Color(0xFF68786E);
  static const Color cardBg = Colors.white;
}

class DeleteCardScreen extends StatefulWidget {
  final String userId;

  const DeleteCardScreen({
    super.key,
    required this.userId,
  });

  @override
  State<DeleteCardScreen> createState() => _DeleteCardScreenState();
}

class _DeleteCardScreenState extends State<DeleteCardScreen> {
  late Future<List<dynamic>> cardsFuture;

  @override
  void initState() {
    super.initState();
    cardsFuture = CardService.getCards(widget.userId);
  }

  Future<void> refreshCards() async {
    setState(() {
      cardsFuture = CardService.getCards(widget.userId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DeleteCardTheme.creamSheet,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: DeleteCardTheme.forestDark.withValues(alpha: 0.06),
              shape: BoxShape.circle,
              border: Border.all(color: DeleteCardTheme.forestDark.withValues(alpha: 0.12)),
            ),
            child: const Icon(
              Icons.arrow_back_rounded,
              color: DeleteCardTheme.darkText,
              size: 20,
            ),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Delete Card",
          style: GoogleFonts.fraunces(
            color: DeleteCardTheme.darkText,
            fontWeight: FontWeight.w600,
            fontSize: 22,
            fontStyle: FontStyle.italic,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: FutureBuilder<List<dynamic>>(
          future: cardsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(DeleteCardTheme.forestDark),
                ),
              );
            }

            if (snapshot.hasError) {
              return Center(
                child: Text(
                  "Error: ${snapshot.error}",
                  style: GoogleFonts.karla(color: DeleteCardTheme.textMuted, fontSize: 15),
                ),
              );
            }

            final cards = snapshot.data ?? [];

            if (cards.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: DeleteCardTheme.forestDark.withValues(alpha: 0.06),
                          border: Border.all(
                            color: DeleteCardTheme.forestDark.withValues(alpha: 0.1),
                            width: 1.5,
                          ),
                        ),
                        child: const FaIcon(
                          FontAwesomeIcons.creditCard,
                          color: DeleteCardTheme.textMuted,
                          size: 42,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        "No Cards Found",
                        style: GoogleFonts.fraunces(
                          color: DeleteCardTheme.darkText,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "You don't have any saved credit cards to delete.",
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          color: DeleteCardTheme.textMuted,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView.separated(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              itemCount: cards.length,
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemBuilder: (context, index) {
                final card = cards[index];
                final bankName = card['bankName'] ?? 'Unknown Bank';
                final last4 = card['last4digits'] ?? '0000';

                return Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: DeleteCardTheme.cardBg,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.08),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Card Icon
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: DeleteCardTheme.forestDark.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const FaIcon(
                          FontAwesomeIcons.wallet,
                          color: DeleteCardTheme.darkText,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 16),

                      // Card Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              bankName,
                              style: GoogleFonts.inter(
                                color: DeleteCardTheme.darkText,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "•••• •••• •••• $last4",
                              style: GoogleFonts.ibmPlexMono(
                                color: DeleteCardTheme.textMuted,
                                fontSize: 13,
                                letterSpacing: 1.1,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Delete Button
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _confirmDelete(context, card, index, cards),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: DeleteCardTheme.terracotta.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: DeleteCardTheme.terracotta.withValues(alpha: 0.2),
                                width: 1,
                              ),
                            ),
                            child: const Icon(
                              Icons.delete_outline_rounded,
                              color: DeleteCardTheme.terracotta,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext ctx, dynamic card, int index, List<dynamic> cards) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      isScrollControlled: true,
      builder: (sheetContext) {
        return Container(
          decoration: const BoxDecoration(
            color: DeleteCardTheme.creamSheet,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(28),
              topRight: Radius.circular(28),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle Bar
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: DeleteCardTheme.darkText.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Warning Icon
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: DeleteCardTheme.terracotta.withValues(alpha: 0.1),
                      border: Border.all(
                        color: DeleteCardTheme.terracotta.withValues(alpha: 0.2),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.delete_forever_rounded,
                      color: DeleteCardTheme.terracotta,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Title
                  Text(
                    "Delete Credit Card",
                    style: GoogleFonts.fraunces(
                      color: DeleteCardTheme.darkText,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Subtitle
                  Text(
                    "Are you sure you want to permanently delete this credit card from ${card['bankName'] ?? 'this bank'}? This action cannot be undone.",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: DeleteCardTheme.textMuted,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Card Preview
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: DeleteCardTheme.cardBg,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.08),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: DeleteCardTheme.forestDark.withValues(alpha: 0.08),
                          ),
                          child: const FaIcon(
                            FontAwesomeIcons.wallet,
                            color: DeleteCardTheme.darkText,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                card['bankName'] ?? 'Unknown Bank',
                                style: GoogleFonts.inter(
                                  color: DeleteCardTheme.darkText,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "•••• •••• •••• ${card['last4digits'] ?? '0000'}",
                                style: GoogleFonts.ibmPlexMono(
                                  color: DeleteCardTheme.textMuted,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),

                  // Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: DeleteCardTheme.darkText.withValues(alpha: 0.2),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: () => Navigator.pop(sheetContext),
                          child: Text(
                            "Cancel",
                            style: GoogleFonts.inter(
                              color: DeleteCardTheme.darkText,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: DeleteCardTheme.terracotta,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: () async {
                            Navigator.pop(sheetContext);
                            
                            final res = await CardService.deleteCard(
                              card['_id'],
                              widget.userId,
                            );

                            if (!ctx.mounted) return;

                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                behavior: SnackBarBehavior.floating,
                                backgroundColor: DeleteCardTheme.forestDark,
                                content: Text(
                                  res['message'] ?? 'Deleted',
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            );

                            setState(() {
                              cards.removeAt(index);
                            });
                            refreshCards();
                          },
                          child: Text(
                            "Delete",
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}