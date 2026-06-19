import 'package:flutter/material.dart';
import '../services/card_service.dart';

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
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Delete Card"),
        backgroundColor: Colors.red,
      ),

      body: FutureBuilder<List<dynamic>>(
        future: cardsFuture,

        builder: (context, snapshot) {
          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                "Error: ${snapshot.error}",
                style: const TextStyle(color: Colors.white),
              ),
            );
          }

          final cards = snapshot.data ?? [];

          if (cards.isEmpty) {
            return const Center(
              child: Text(
                "No Cards Found",
                style: TextStyle(color: Colors.white),
              ),
            );
          }

          return ListView.builder(
            itemCount: cards.length,

            itemBuilder: (context, index) {
              final card = cards[index];

              return Card(
                color: Colors.grey[900],
                margin: const EdgeInsets.all(10),

                child: ListTile(
                  leading: const Icon(
                    Icons.credit_card,
                    color: Colors.white,
                  ),

                  title: Text(
                    card['bankName'] ?? '',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  subtitle: Text(
                    "**** ${card['last4digits']}",
                    style: const TextStyle(
                      color: Colors.white70,
                    ),
                  ),

                  trailing: IconButton(
                    icon: const Icon(
                      Icons.delete,
                      color: Colors.red,
                    ),

                    onPressed: () {
                      showDialog(
                        context: context,

                        builder: (_) => AlertDialog(
                          title: const Text("Delete Card"),

                          content: const Text(
                            "Are you sure you want to delete this card?",
                          ),

                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                              },

                              child: const Text("Cancel"),
                            ),

                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                              ),

                              onPressed: () async {
                                Navigator.pop(context);

                                final res =
                                await CardService.deleteCard(
                                  card['_id'],
                                  widget.userId,
                                );

                                if (!context.mounted) {
                                  return;
                                }

                                ScaffoldMessenger.of(context)
                                    .showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      res['message'] ??
                                          'Deleted',
                                    ),
                                  ),
                                );


                                setState(() {
                                  cards.removeAt(index);
                                });
                                refreshCards();

                              },

                              child: const Text("Delete"),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}