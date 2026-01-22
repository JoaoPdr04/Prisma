import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'color_utils.dart'; 

class CategoryManagerScreen extends StatefulWidget {
  const CategoryManagerScreen({super.key});

  @override
  State<CategoryManagerScreen> createState() => _CategoryManagerScreenState();
}

class _CategoryManagerScreenState extends State<CategoryManagerScreen> {
  final CollectionReference _descriptorsCollection =
      FirebaseFirestore.instance.collection('descritores');

  // --- DIÁLOGO PARA ADICIONAR NOVO DESCRITOR ---
  Future<void> _showAddDescriptorDialog() async {
    final nameController = TextEditingController();
    final colorController = TextEditingController();
    final subItemController = TextEditingController();
    
    // Lista temporária para guardar os subitens enquanto cria
    List<String> tempSubItems = [];

    await showDialog<void>(
      context: context,
      barrierDismissible: false, // Obriga a clicar em Cancelar ou Salvar
      builder: (BuildContext context) {
        return StatefulBuilder( // Necessário para atualizar a lista DENTRO do diálogo
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Novo Descritor'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    // 1. Nome e Cor
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nome do Descritor',
                        hintText: 'Ex: Saúde, Educação...',
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
                    
                    // 2. Área de Subdescritores
                    const Text("Subdescritores (Detalhes):", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: subItemController,
                            decoration: const InputDecoration(
                              hintText: 'Ex: Hospital, UBS...',
                              isDense: true,
                            ),
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
                    
                    // 3. Lista dos Subitens adicionados
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8.0,
                      children: tempSubItems.map((sub) {
                        return Chip(
                          label: Text(sub),
                          deleteIcon: const Icon(Icons.close, size: 18),
                          onDeleted: () {
                            setStateDialog(() {
                              tempSubItems.remove(sub);
                            });
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
                  onPressed: () {
                    final String name = nameController.text.trim();
                    final String color = colorController.text.trim();

                    if (name.isNotEmpty && color.isNotEmpty) {
                      // Salva no Firebase com a estrutura nova
                      _descriptorsCollection.add({
                        "nome": name,
                        "cor": color,
                        "subdescritores": tempSubItems, // Salva o Array
                      });
                      Navigator.of(context).pop();
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
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Excluir Descritor'),
                          content: Text('Tem certeza que deseja excluir "${data['nome']}" e todos os seus subitens?'),
                          actions: [
                            TextButton(
                              child: const Text('Não'),
                              onPressed: () => Navigator.of(ctx).pop(),
                            ),
                            TextButton(
                              child: const Text('Sim, Excluir'),
                              onPressed: () {
                                _descriptorsCollection.doc(document.id).delete();
                                Navigator.of(ctx).pop();
                              },
                            ),
                          ],
                        ),
                      );
                    },
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
        onPressed: _showAddDescriptorDialog,
        backgroundColor: Colors.blue,
        child: const Icon(Icons.add),
      ),
    );
  }
}