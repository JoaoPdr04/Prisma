import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; // Adicione intl no pubspec.yaml se quiser datas bonitas, senão use toString()

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return const Scaffold(body: Center(child: Text("Faça login para ver avisos.")));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificações'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('notificacoes')
            .where('destinatarioId', isEqualTo: user.uid) // Filtra só as minhas
            .orderBy('data', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_off, size: 60, color: Colors.grey),
                  SizedBox(height: 10),
                  Text('Nenhuma notificação.', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final titulo = data['titulo'] ?? 'Aviso';
              final mensagem = data['mensagem'] ?? '';
              final lida = data['lida'] ?? false;

              return Card(
                color: lida ? Colors.white : Colors.blue[50], // Destaca não lidas
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: ListTile(
                  leading: Icon(
                    lida ? Icons.mark_email_read : Icons.mark_email_unread,
                    color: lida ? Colors.grey : Colors.blue,
                  ),
                  title: Text(titulo, style: TextStyle(fontWeight: lida ? FontWeight.normal : FontWeight.bold)),
                  subtitle: Text(mensagem),
                  onTap: () {
                    // Marca como lida ao clicar
                    if (!lida) {
                      FirebaseFirestore.instance
                          .collection('notificacoes')
                          .doc(docs[index].id)
                          .update({'lida': true});
                    }
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, size: 20, color: Colors.grey),
                    onPressed: () {
                      FirebaseFirestore.instance
                          .collection('notificacoes')
                          .doc(docs[index].id)
                          .delete();
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