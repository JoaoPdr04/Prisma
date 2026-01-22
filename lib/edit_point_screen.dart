import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'color_utils.dart';

class EditPointScreen extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> initialData;

  const EditPointScreen({
    super.key,
    required this.docId,
    required this.initialData,
  });

  @override
  State<EditPointScreen> createState() => _EditPointScreenState();
}

class _EditPointScreenState extends State<EditPointScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final MapController _mapController = MapController();

  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  String? _selectedDescriptor;
  String? _selectedSubDescriptor;
  Color _descriptorColor = Colors.red;
  List<String> _currentSubItems = [];

  LatLng? _selectedPoint;
  String _selectedType = 'normal';

  // Mapa para guardar as cores dos pontos vizinhos
  Map<String, String> _categoryColorsMap = {};

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _loadCategoryColors();
    
    // Abre o formulário automaticamente após um breve delay para facilitar a edição
    WidgetsBinding.instance.addPostFrameCallback((_) {
         if (mounted) _scaffoldKey.currentState?.openEndDrawer();
    });
  }

  void _loadInitialData() {
    _nameController.text = widget.initialData['nome'] ?? '';
    _descriptionController.text = widget.initialData['descricao'] ?? '';
    _selectedDescriptor = widget.initialData['categoria'];
    _selectedSubDescriptor = widget.initialData['subcategoria']; // Carrega o subitem
    _selectedType = widget.initialData['tipo'] ?? 'normal';

    final geoPoint = widget.initialData['coordenadas'] as GeoPoint;
    _selectedPoint = LatLng(geoPoint.latitude, geoPoint.longitude);
  }

  void _loadCategoryColors() {
    FirebaseFirestore.instance.collection('descritores').snapshots().listen((snapshot) {
      Map<String, String> tempMap = {};
      for (var doc in snapshot.docs) {
        tempMap[doc['nome']] = doc['cor'];
        
        // Se encontrarmos o descritor atual, já atualizamos a cor e a lista de subs
        if (doc['nome'] == _selectedDescriptor) {
           // Atualiza cor
           if (mounted) {
             setState(() {
               _descriptorColor = ColorUtils.fromHex(doc['cor']);
               // Atualiza subitens
               List<dynamic> subs = doc['subdescritores'] ?? [];
               _currentSubItems = subs.map((e) => e.toString()).toList();
               _currentSubItems.sort();
             });
           }
        }
      }
      if (mounted) {
        setState(() {
          _categoryColorsMap = tempMap;
        });
      }
    });
  }

  void _zoomIn() {
    final currentZoom = _mapController.camera.zoom;
    _mapController.move(_mapController.camera.center, currentZoom + 1);
  }

  void _zoomOut() {
    final currentZoom = _mapController.camera.zoom;
    _mapController.move(_mapController.camera.center, currentZoom - 1);
  }

  Future<void> _updatePoint() async {
    final name = _nameController.text.trim();
    final description = _descriptionController.text.trim();

    if (name.isEmpty ||
        description.isEmpty ||
        _selectedDescriptor == null ||
        _selectedSubDescriptor == null ||
        _selectedPoint == null) {
      Navigator.of(context).pop(); 
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preencha todos os campos e categorias!'),
          backgroundColor: Colors.red,
        ),
      );
      _scaffoldKey.currentState?.openEndDrawer();
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('pontos_interesse')
          .doc(widget.docId) // Atualiza o documento existente
          .update({
        'nome': name,
        'descricao': description,
        'categoria': _selectedDescriptor,
        'subcategoria': _selectedSubDescriptor,
        'tipo': _selectedType,
        'coordenadas': GeoPoint(_selectedPoint!.latitude, _selectedPoint!.longitude),
        // Não atualizamos data_criacao, talvez um data_atualizacao?
        'data_atualizacao': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.of(context).pop(); // Volta para o mapa
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ponto atualizado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Erro ao atualizar ponto: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(

      resizeToAvoidBottomInset: false,

      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('Editar Ponto'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.check, color: Colors.blue),
            label: const Text("CONCLUÍDO", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
            onPressed: () {
              Navigator.of(context).pop(); // Apenas fecha sem salvar
            },
          ),
        ],
      ),
      endDrawer: Drawer(
        width: MediaQuery.of(context).size.width > 500 ? 400 : MediaQuery.of(context).size.width * 0.85,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              color: Colors.orange, // Laranja para diferenciar da Adição (Azul)
              width: double.infinity,
              child: const SafeArea(
                child: Text("Editar Dados", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  const Text("Tipo:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Local'),
                        selected: _selectedType == 'normal',
                        onSelected: (b) => setState(() => _selectedType = 'normal'),
                      ),
                      const SizedBox(width: 10),
                      ChoiceChip(
                        label: const Text('Ponto Crítico'),
                        selected: _selectedType == 'aviso',
                        selectedColor: Colors.orange.withOpacity(0.4),
                        onSelected: (b) => setState(() => _selectedType = 'aviso'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Nome do Ponto', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(labelText: 'Descrição', border: OutlineInputBorder()),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 20),

                  const Text("Categorização:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 5),
                  
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('descritores').snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const LinearProgressIndicator();
                      
                      var docs = snapshot.data!.docs;
                      docs.sort((a, b) => (a['nome'] as String).compareTo(b['nome'] as String));

                      var descriptorItems = docs.map((doc) {
                        return DropdownMenuItem<String>(
                          value: doc['nome'] as String,
                          child: Text(doc['nome'] as String, overflow: TextOverflow.ellipsis),
                        );
                      }).toList();
                      
                      return Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DropdownButtonFormField<String>(
                              value: _selectedDescriptor,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Selecione o Descritor',
                                prefixIcon: Icon(Icons.folder),
                                border: InputBorder.none,
                              ),
                              items: descriptorItems,
                              onChanged: (String? newValue) {
                                setState(() {
                                  _selectedDescriptor = newValue;
                                  _selectedSubDescriptor = null; // Reseta ao trocar a pai
                                  
                                  var selectedDoc = docs.firstWhere((d) => d['nome'] == newValue);
                                  String colorHex = selectedDoc['cor'] ?? '#FF0000';
                                  _descriptorColor = ColorUtils.fromHex(colorHex);

                                  List<dynamic> subs = selectedDoc['subdescritores'] ?? [];
                                  _currentSubItems = subs.map((e) => e.toString()).toList();
                                  _currentSubItems.sort();
                                });
                              },
                            ),

                            // Menu Secundário
                            if (_selectedDescriptor != null) ...[
                              const Divider(),
                              const Padding(
                                padding: EdgeInsets.only(left: 12.0, bottom: 8.0, top: 4.0),
                                child: Text("Selecione o detalhe:", style: TextStyle(fontSize: 12, color: Colors.grey)),
                              ),
                              Container(
                                margin: const EdgeInsets.only(left: 10),
                                decoration: BoxDecoration(
                                  border: Border(left: BorderSide(color: Colors.grey.shade300, width: 2))
                                ),
                                padding: const EdgeInsets.only(left: 10),
                                child: _currentSubItems.isEmpty 
                                  ? const Padding(
                                      padding: EdgeInsets.all(8.0),
                                      child: Text("Nenhum subitem disponível", style: TextStyle(fontStyle: FontStyle.italic)),
                                    )
                                  : Column(
                                      children: _currentSubItems.map((subItem) {
                                        return RadioListTile<String>(
                                          title: Text(subItem, style: const TextStyle(fontSize: 14)),
                                          value: subItem,
                                          groupValue: _selectedSubDescriptor,
                                          dense: true,
                                          contentPadding: EdgeInsets.zero,
                                          activeColor: _descriptorColor,
                                          onChanged: (String? val) {
                                            setState(() {
                                              _selectedSubDescriptor = val;
                                            });
                                          },
                                        );
                                      }).toList(),
                                    ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text("ATUALIZAR", style: TextStyle(fontSize: 18)),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                  onPressed: _updatePoint,
                ),
              ),
            )
          ],
        ),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              // Inicia focado no ponto que está sendo editado
              initialCenter: _selectedPoint ?? const LatLng(0, 0),
              initialZoom: 17.0,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onTap: (tapPosition, point) {
                setState(() {
                  _selectedPoint = point;
                });
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.mapa_birigui_final',
              ),
              
              // CAMADA 1: Vizinhos (Pontos Fantasmas)
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('pontos_interesse').snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox();

                  final existingMarkers = snapshot.data!.docs
                    .where((doc) => doc.id != widget.docId) // Não mostra o ponto atual duplicado
                    .map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final geoPoint = data['coordenadas'] as GeoPoint;
                      final tipo = data['tipo'] ?? 'normal';
                      
                      String colorHex = _categoryColorsMap[data['categoria']] ?? '#808080';
                      Color markerColor = ColorUtils.fromHex(colorHex).withOpacity(0.5); // Transparente

                      return Marker(
                        point: LatLng(geoPoint.latitude, geoPoint.longitude),
                        width: 40,
                        height: 40,
                        child: Transform.translate(
                          offset: const Offset(0, -20),
                          child: Icon(
                            tipo == 'aviso' ? Icons.location_on : Icons.location_on,
                            color: markerColor,
                            size: 40,
                          ),
                        ),
                      );
                    }).toList();

                  return MarkerLayer(markers: existingMarkers);
                },
              ),

              // CAMADA 2: O Ponto em Edição (Forte)
              MarkerLayer(
                markers: [
                  if (_selectedPoint != null)
                    Marker(
                      point: _selectedPoint!,
                      width: 40,
                      height: 40,
                      child: Transform.translate(
                        offset: const Offset(0, -20), 
                        child: Icon(
                          _selectedType == 'aviso' ? Icons.location_on : Icons.location_on,
                          color: _selectedType == 'aviso' ? Colors.orange : _descriptorColor,
                          size: 40,
                          shadows: [const Shadow(blurRadius: 5, color: Colors.black, offset: Offset(0, 2))],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          
          Positioned(
            top: 10, left: 10, right: 10,
            child: Card(
              color: Colors.white.withOpacity(0.9),
              child: const Padding(
                padding: EdgeInsets.all(12.0),
                child: Text(
                  'Arraste o mapa ou clique para ajustar a posição.\nO formulário abre automaticamente.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),

          Positioned(
            bottom: 20,
            right: 20,
            child: Column(
              children: [
                FloatingActionButton(
                  heroTag: "zoomInEdit",
                  mini: true,
                  onPressed: _zoomIn,
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 10),
                FloatingActionButton(
                  heroTag: "zoomOutEdit",
                  mini: true,
                  onPressed: _zoomOut,
                  child: const Icon(Icons.remove),
                ),
                const SizedBox(height: 20),
                FloatingActionButton.extended(
                  heroTag: "openFormEdit",
                  onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                  label: const Text("Editar Dados"),
                  icon: const Icon(Icons.edit),
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}