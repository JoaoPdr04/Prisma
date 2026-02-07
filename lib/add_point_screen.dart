import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'color_utils.dart'; 

class AddPointScreen extends StatefulWidget {
  final LatLng initialCenter;

  const AddPointScreen({
    super.key,
    required this.initialCenter,
  });

  @override
  State<AddPointScreen> createState() => _AddPointScreenState();
}

class _AddPointScreenState extends State<AddPointScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final MapController _mapController = MapController();

  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  String? _selectedDescriptor; 
  String? _selectedSubDescriptor; 
  Color _descriptorColor = Colors.red; 
  
  // Otimização: Carregamos as listas aqui para não travar a tela
  List<QueryDocumentSnapshot> _cachedDocs = [];
  bool _isLoadingCategories = true;

  LatLng? _selectedPoint;
  String _selectedType = 'normal';

  // Mapa para guardar as cores dos pontos vizinhos
  Map<String, String> _categoryColorsMap = {};

  @override
  void initState() {
    super.initState();
    _selectedPoint = widget.initialCenter; 
    _loadAllData();
    
    // REMOVI A ABERTURA AUTOMÁTICA DO DRAWER.
    // Agora o mapa inicia limpo para você selecionar o local primeiro.
  }

  // Busca Descritores e Vizinhos de uma vez só
  void _loadAllData() {
    FirebaseFirestore.instance.collection('descritores').snapshots().listen((snapshot) {
      if (!mounted) return;
      
      var docs = snapshot.docs;
      docs.sort((a, b) => (a['nome'] as String).compareTo(b['nome'] as String));

      setState(() {
        _cachedDocs = docs;
        _isLoadingCategories = false;
        
        Map<String, String> tempMap = {};
        for (var doc in docs) {
          tempMap[doc['nome']] = doc['cor'];
        }
        _categoryColorsMap = tempMap;
      });
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

  Future<void> _savePoint() async {
    final name = _nameController.text.trim();
    final description = _descriptionController.text.trim();

    if (name.isEmpty ||
        description.isEmpty ||
        _selectedDescriptor == null ||
        _selectedSubDescriptor == null || 
        _selectedPoint == null) {
      Navigator.of(context).pop(); // Fecha o drawer para ver o aviso
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preencha todos os campos e selecione os descritores!'),
          backgroundColor: Colors.red,
        ),
      );
      // Reabre o drawer para corrigir
      _scaffoldKey.currentState?.openEndDrawer();
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('pontos_interesse')
          .add({
        'nome': name,
        'descricao': description,
        'categoria': _selectedDescriptor, 
        'subcategoria': _selectedSubDescriptor, 
        'tipo': _selectedType, 
        'coordenadas': GeoPoint(_selectedPoint!.latitude, _selectedPoint!.longitude),
        'data_criacao': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.of(context).pop(); // Fecha a tela de adicionar
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ponto salvo com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Erro ao salvar ponto: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(

      resizeToAvoidBottomInset: false,

      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('Defina o Local'),
        // O botão de voltar padrão (seta) serve como "Cancelar"
      ),
      endDrawer: Drawer(
        width: MediaQuery.of(context).size.width > 500 ? 400 : MediaQuery.of(context).size.width * 0.85,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              color: Colors.blue,
              width: double.infinity,
              child: const SafeArea(
                child: Text("Preencher Dados", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
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
                        label: const Text('Pontos Críticos'),
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
                  
                  if (_isLoadingCategories)
                    const LinearProgressIndicator()
                  else
                    Container(
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
                            items: _cachedDocs.map((doc) {
                              return DropdownMenuItem<String>(
                                value: doc['nome'] as String,
                                child: Text(doc['nome'] as String, overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                            onChanged: (String? newValue) {
                              setState(() {
                                _selectedDescriptor = newValue;
                                _selectedSubDescriptor = null;
                                
                                var selectedDoc = _cachedDocs.firstWhere((d) => d['nome'] == newValue);
                                String colorHex = selectedDoc['cor'] ?? '#FF0000';
                                _descriptorColor = ColorUtils.fromHex(colorHex);
                              });
                            },
                          ),

                          if (_selectedDescriptor != null) ...[
                            const Divider(),
                            const Padding(
                              padding: EdgeInsets.only(left: 12.0, bottom: 8.0, top: 4.0),
                              child: Text("Selecione o detalhe:", style: TextStyle(fontSize: 12, color: Colors.grey)),
                            ),
                            // Busca os subitens diretamente do documento cacheado
                            Builder(
                              builder: (context) {
                                var selectedDoc = _cachedDocs.firstWhere((d) => d['nome'] == _selectedDescriptor);
                                List<dynamic> subs = selectedDoc['subdescritores'] ?? [];
                                List<String> sortedSubs = subs.map((e) => e.toString()).toList()..sort();

                                return Container(
                                  margin: const EdgeInsets.only(left: 10),
                                  decoration: BoxDecoration(
                                    border: Border(left: BorderSide(color: Colors.grey.shade300, width: 2))
                                  ),
                                  padding: const EdgeInsets.only(left: 10),
                                  child: Column(
                                    children: sortedSubs.map((subItem) {
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
                                );
                              }
                            ),
                          ],
                        ],
                      ),
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
                  icon: const Icon(Icons.check),
                  label: const Text("SALVAR PONTO", style: TextStyle(fontSize: 18)),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                  onPressed: _savePoint,
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
              initialCenter: widget.initialCenter,
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
              
              // Vizinhos
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('pontos_interesse').snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox(); 

                  final existingMarkers = snapshot.data!.docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final geoPoint = data['coordenadas'] as GeoPoint;
                    final tipo = data['tipo'] ?? 'normal';
                    
                    String colorHex = _categoryColorsMap[data['categoria']] ?? '#808080';
                    Color markerColor = ColorUtils.fromHex(colorHex).withOpacity(0.6); 

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

              // Ponto Novo
              MarkerLayer(
                markers: [
                  if (_selectedPoint != null)
                    Marker(
                      point: _selectedPoint!,
                      width: 40,
                      height: 40,

                      rotate: false,

                      child: Transform.translate(
                        offset: const Offset(0, -20), 
                        child: Icon(
                          _selectedType == 'Ponto Crítico' ? Icons.location_on : Icons.location_on,
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
                  'Toque no mapa para posicionar.',
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
                  heroTag: "zoomInAdd",
                  mini: true,
                  onPressed: _zoomIn,
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 10),
                FloatingActionButton(
                  heroTag: "zoomOutAdd",
                  mini: true,
                  onPressed: _zoomOut,
                  child: const Icon(Icons.remove),
                ),
                const SizedBox(height: 20),
                FloatingActionButton.extended(
                  heroTag: "openForm",
                  onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                  label: const Text("Preencher Dados"),
                  icon: const Icon(Icons.edit_note),
                  backgroundColor: Colors.blue,
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