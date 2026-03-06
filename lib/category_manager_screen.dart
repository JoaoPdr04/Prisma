import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'color_utils.dart'; 

class CategoryManagerScreen extends StatefulWidget {
  const CategoryManagerScreen({super.key});

  @override
  State<CategoryManagerScreen> createState() => CategoryManagerScreenState();
}

class CategoryManagerScreenState extends State<CategoryManagerScreen> {
  final CollectionReference _descriptorsCollection =
      FirebaseFirestore.instance.collection('descritores');

  // --- DIÁLOGO PARA ADICIONAR NOVO DESCRITOR ---
  // Agora a função aceita um DocumentSnapshot opcional
Future<void> _showDescriptorDialog([DocumentSnapshot? doc]) async {
  final isEditing = doc != null;
  
  // Se estiver editando, carrega os dados atuais; se não, começa vazio
  final nameController = TextEditingController(text: isEditing ? doc['nome'] : '');
  final colorController = TextEditingController(text: isEditing ? doc['cor'] : '');
  final subItemController = TextEditingController();
  
  // Inicializa a lista com os subitens existentes ou vazia
  List<String> tempSubItems = isEditing 
      ? List<String>.from(doc['subdescritores'] ?? []) 
      : [];

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: Text(isEditing ? 'Editar Descritor' : 'Novo Descritor'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nome do Descritor',
                      border: OutlineInputBorder()
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: colorController,
                    decoration: const InputDecoration(
                      labelText: 'Cor Hex (Ex: #FF0000)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.color_lens)
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text("Subdescritores:", style: TextStyle(fontWeight: FontWeight.bold)),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: subItemController,
                          decoration: const InputDecoration(hintText: 'Novo subitem...'),
                          onSubmitted: (value) {
                            if (value.trim().isNotEmpty) {
                              setStateDialog(() {
                                tempSubItems.add(value.trim());
                                subItemController.clear();
                              });
                            }
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle, color: Colors.blue),
                        onPressed: () {
                          if (subItemController.text.trim().isNotEmpty) {
                            setStateDialog(() {
                              tempSubItems.add(subItemController.text.trim());
                              subItemController.clear();
                            });
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8.0,
                    children: tempSubItems.map((sub) {
                      return Chip(
                        label: Text(sub),
                        onDeleted: () {
                          setStateDialog(() => tempSubItems.remove(sub));
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Cancelar'),
                onPressed: () => Navigator.of(context).pop(),
              ),
              ElevatedButton(
                child: const Text('Salvar'),
                onPressed: () async {
                  final String name = nameController.text.trim();
                  final String color = colorController.text.trim();

                  if (name.isNotEmpty && color.isNotEmpty) {
                    // 1. Criamos um Map com os dados, garantindo que a lista seja tratada como List<String>
                    final Map<String, dynamic> data = {
                      "nome": name,
                      "cor": color,
                      "subdescritores": List<String>.from(tempSubItems), // Força a tipagem correta
                    };

                    try {
                      if (isEditing) {
                        // 2. Usamos doc.id para atualizar o documento específico
                        await _descriptorsCollection.doc(doc.id).update(data);
                      } else {
                        // 3. Adiciona um novo
                        await _descriptorsCollection.add(data);
                      }

                      // 4. SÓ FECHA o diálogo se o widget ainda estiver na árvore (evita o erro assíncrono)
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                    } catch (e) {
                      debugPrint("Erro ao salvar no Firestore: $e");
                      // Opcional: mostrar um SnackBar de erro aqui
                    }
                  }
                },
              ),
            ],
          );
        },
      );
    },
  );
}

void _confirmDelete(DocumentSnapshot doc, String nome) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Excluir Descritor'),
      content: Text('Tem certeza que deseja excluir "$nome" e todos os seus subitens?'),
      actions: [
        TextButton(
          child: const Text('Não'),
          onPressed: () => Navigator.of(ctx).pop(),
        ),
        TextButton(
          child: const Text('Sim, Excluir', style: TextStyle(color: Colors.red)),
          onPressed: () {
            _descriptorsCollection.doc(doc.id).delete();
            Navigator.of(ctx).pop();
          },
        ),
      ],
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gerenciar Descritores'),
      ),
      body: StreamBuilder(
        stream: _descriptorsCollection.snapshots(),
        builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (snapshot.hasError) return const Center(child: Text('Erro ao carregar'));
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Nenhum descritor cadastrado.'));
          }

          // Ordena a lista alfabeticamente
          var docs = snapshot.data!.docs;
          docs.sort((a, b) => (a['nome'] as String).compareTo(b['nome'] as String));

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final document = docs[index];
              final data = document.data()! as Map<String, dynamic>;
              final color = ColorUtils.fromHex(data['cor'] ?? '#808080');
              
              // Pega a lista de subitens
              List<dynamic> subs = data['subdescritores'] ?? [];
              subs.sort(); // Ordena subitens visualmente

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: ExpansionTile(
                  leading: CircleAvatar(
                    backgroundColor: color,
                    radius: 15,
                  ),
                  title: Text(
                    data['nome'] ?? 'Sem nome',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text("${subs.length} subdescritores"),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min, // Importante para não quebrar o layout
                    children: [
                      // BOTÃO EDITAR (O QUE ADICIONAMOS)
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _showDescriptorDialog(document), // Chama a função passando o doc
                      ),
                      // BOTÃO EXCLUIR (O QUE JÁ EXISTIA, MAS ORGANIZADO)
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _confirmDelete(document, data['nome']),
                      ),
                    ],
                  ),
                  // O conteúdo expandido mostra a lista de subitens
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8)
                        ),
                        child: subs.isEmpty 
                          ? const Text("Nenhum subitem cadastrado.", style: TextStyle(fontStyle: FontStyle.italic))
                          : Wrap(
                              spacing: 8.0,
                              children: subs.map((sub) => Chip(
                                label: Text(sub.toString(), style: const TextStyle(fontSize: 12)),
                                backgroundColor: Colors.white,
                                padding: EdgeInsets.zero,
                              )).toList(),
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
      floatingActionButton: FloatingActionButton(
        onPressed: _showDescriptorDialog,
        backgroundColor: Colors.blue,
        child: const Icon(Icons.add),
      ),
    );
  }
}