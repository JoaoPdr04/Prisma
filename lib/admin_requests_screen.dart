import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

class AdminRequestsScreen extends StatelessWidget {
  const AdminRequestsScreen({super.key});

  // Função auxiliar para enviar notificação
  Future<void> _sendNotification(String userId, String title, String message) async {
    await FirebaseFirestore.instance.collection('notificacoes').add({
      'destinatarioId': userId,
      'titulo': title,
      'mensagem': message,
      'data': FieldValue.serverTimestamp(),
      'lida': false,
    });
  }

  // Função para APROVAR
  Future<void> _approveUser(BuildContext context, String docId, String userId, String userName, String userEmail) async {
    try {
      // 1. Atualiza o cargo do usuário para 'colaborador'
      await FirebaseFirestore.instance.collection('usuarios').doc(userId).update({
        'cargo': 'colaborador',
      });

      // 2. Atualiza o status do pedido para 'aprovado' (para sair da lista)
      await FirebaseFirestore.instance.collection('solicitacoes').doc(docId).update({
        'status': 'aprovado',
      });

      await _sendNotification(
        userId, 
        'Acesso Aprovado! 🎉', 
        'Parabéns $userName! Agora você é um Colaborador. Você já pode adicionar pontos no mapa.'
      );

      _openEmailApp(userEmail, userName);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$userName agora é Colaborador!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao aprovar: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // Função para REJEITAR (Agora com notificação)
  Future<void> _rejectUser(BuildContext context, String docId, String userId, String userName) async {
    try {
      // 1. Atualiza o status do pedido para 'rejeitado'
      await FirebaseFirestore.instance.collection('solicitacoes').doc(docId).update({
        'status': 'rejeitado',
      });

      // 2. Envia a Notificação para o Usuário
      await _sendNotification(
        userId, 
        'Solicitação Recusada', 
        'Olá $userName. Infelizmente sua solicitação para ser colaborador não foi aceita neste momento. Entre em contato para mais detalhes.'
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Solicitação rejeitada e usuário avisado.'), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao rejeitar: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // Função para abrir o app de e-mail
Future<void> _openEmailApp(String emailDestino, String nomeUsuario) async {
  final String subject = Uri.encodeComponent("Sua solicitação foi Aprovada! 🎉");
  final String body = Uri.encodeComponent(
    "Olá $nomeUsuario,\n\n"
    "Sua solicitação para se tornar um Colaborador no Prisma - Mapeador de Qualidade de Vida foi aprovada!\n\n"
    "Agora você pode acessar o aplicativo e adicionar novos pontos no mapa.\n\n"
    "Atenciosamente,\nEquipe Prisma."
  );

  final Uri mailUri = Uri.parse("mailto:$emailDestino?subject=$subject&body=$body");

  try {
    // Tenta abrir o app de e-mail
    if (!await launchUrl(mailUri)) {
      print("Não foi possível abrir o app de e-mail.");
    }
  } catch (e) {
    print("Erro ao tentar abrir e-mail: $e");
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Solicitações de Acesso'),
        backgroundColor: Colors.blueGrey,
      ),
      body: StreamBuilder<QuerySnapshot>(
        // Ouve apenas os pedidos que estão 'pendente'
        stream: FirebaseFirestore.instance
            .collection('solicitacoes')
            .where('status', isEqualTo: 'pendente')
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final requests = snapshot.data!.docs;

          if (requests.isEmpty) {
            return const Center(
              child: Text(
                'Nenhuma solicitação pendente.',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            );
          }

          return ListView.builder(
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final req = requests[index];
              final data = req.data() as Map<String, dynamic>;
              
              final String nome = data['nome'] ?? 'Sem Nome';
              final String email = data['email'] ?? 'Sem Email';
              final String motivo = data['motivo'] ?? 'Sem Motivo';
              final String uid = data['uid'];

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.person, color: Colors.blue),
                          const SizedBox(width: 8),
                          Text(nome, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                      Text(email, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                      const Divider(),
                      const Text('Motivo:', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(motivo, style: const TextStyle(fontSize: 14)),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton(
                            onPressed: () => _rejectUser(context, req.id, uid, nome),                            
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                            child: const Text('Rejeitar'),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: () => _approveUser(context, req.id, uid, nome, email),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                            child: const Text('Aprovar'),
                          ),
                        ],
                      )
                    ],
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