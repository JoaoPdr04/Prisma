import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart'; 
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'login_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'add_point_screen.dart';
import 'category_manager_screen.dart';
import 'color_utils.dart';
import 'edit_point_screen.dart';
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

void main() async {
  print('--- APLICATIVO INICIADO ---');
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Prisma',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  bool _isAdmin = false;
  final MapController _mapController = MapController();
  
  LatLng? _userCurrentLocation;
  final LatLng _biriguiCenter = const LatLng(-21.2897, -50.3406);
  late LatLng _lastMapPosition;
  double _lastMapZoom = 15.0;   

  bool _showNormalPoints = true;
  bool _showWarningPoints = true;

  Map<String, Map<String, dynamic>> _descriptorsData = {};
  Map<String, Set<String>> _activeSubFilters = {};

  List<QueryDocumentSnapshot> _allLoadedPoints = [];

  StreamSubscription<Position>? _positionStreamSubscription;

  @override
  void initState() {
    super.initState();
    _lastMapPosition = _biriguiCenter;
    _verificarPapelAdmin();
    _listenToDescriptors();
    _startLocationUpdates();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    super.dispose();
  }

  Future<void> _startLocationUpdates() async {
    bool serviceEnabled;
    LocationPermission permission;

    // 1. Verificações de Permissão (Igual antes)
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    // 2. Configurações de "Economia Inteligente"
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high, // Alta precisão
      distanceFilter: 10, // Só atualiza se andar 10 metros (O SEGREDO DA PERFORMANCE)
    );

    // 3. Inicia o Stream (A "Torneira" de dados)
    _positionStreamSubscription = Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen((Position position) {
      
      // Essa parte roda toda vez que você anda 10 metros
      if (mounted) {
        setState(() {
          _userCurrentLocation = LatLng(position.latitude, position.longitude);
        });

        // Opcional: Se for a PRIMEIRA vez que pega a localização (o mapa acabou de abrir),
        // centraliza no usuário. Depois, deixa o usuário livre.
        if (_lastMapPosition == _biriguiCenter) {
           _mapController.move(_userCurrentLocation!, 15.0);
        }
      }
    });
  }

Future<void> _setupInitialLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    try {
      // 1. Verifica se o GPS está ligado
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      // 2. Verifica e pede permissão
      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      // 3. Pega a posição atual
      Position position = await Geolocator.getCurrentPosition();

      if (mounted) {
        setState(() {
          _userCurrentLocation = LatLng(position.latitude, position.longitude);
        });
        // Move o mapa para o usuário (apenas na inicialização)
        _mapController.move(_userCurrentLocation!, 15.0);
      }
    } catch (e) {
      print('Erro ao obter localização: $e');
    }
  }

  void _moveToCurrentLocation() {
    if (_userCurrentLocation != null) {
      _mapController.move(_userCurrentLocation!, 16.0);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Buscando sua localização...')),
      );
      _setupInitialLocation();
    }
  }

  void _zoomIn() {
    final currentZoom = _mapController.camera.zoom;
    _mapController.move(_mapController.camera.center, currentZoom + 1);
  }

  void _zoomOut() {
    final currentZoom = _mapController.camera.zoom;
    _mapController.move(_mapController.camera.center, currentZoom - 1);
  }

  Future<void> _verificarPapelAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('usuarios').doc(user.uid).get();
      if (doc.exists && doc.data()?['papel'] == 'admin') {
        if (mounted) setState(() => _isAdmin = true);
      }
    } catch (e) {
      print('Erro admin: $e');
    }
  }

  void _listenToDescriptors() {
    FirebaseFirestore.instance.collection('descritores').snapshots().listen((snapshot) {
      Map<String, Map<String, dynamic>> tempData = {};
      Map<String, Set<String>> tempActive = {};

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final name = data['nome'] as String;
        final color = data['cor'] as String;
        List<String> subs = (data['subdescritores'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
        subs.sort(); 

        tempData[name] = {
          'cor': color,
          'subs': subs,
        };

        if (_activeSubFilters.containsKey(name)) {
          tempActive[name] = _activeSubFilters[name]!.intersection(subs.toSet());
        } else {
          tempActive[name] = subs.toSet();
        }
      }

      if (mounted) {
        setState(() {
          _descriptorsData = tempData;
          _activeSubFilters = tempActive;
        });
      }
    });
  }

  // --- MOSTRAR DETALHES (CORRIGIDO O TEXTO CORTADO) ---
  void _showPointDetails(Map<String, dynamic> data, String docId) {
    final String colorHex = _descriptorsData[data['categoria']]?['cor'] ?? '#808080';
    final Color categoryColor = ColorUtils.fromHex(colorHex);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext bc) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.45,
          maxChildSize: 0.8,
          minChildSize: 0.3,
          builder: (context, scrollController) {
            return Container(
              padding: const EdgeInsets.all(24.0),
              child: ListView(
                controller: scrollController,
                children: <Widget>[
                  Center(child: Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
                  const SizedBox(height: 20),
                  
                  // TÍTULO
                  Text(
                    data['nome'] ?? 'Nome não disponível',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  
                  // CATEGORIA E SUBCATEGORIA (Com quebra de linha automática)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: CircleAvatar(backgroundColor: categoryColor, radius: 8),
                      ),
                      const SizedBox(width: 10),
                      // Flexible obriga o texto a quebrar se bater na borda
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data['categoria'] ?? 'Descritor não disponível',
                              style: const TextStyle(fontSize: 16, fontStyle: FontStyle.italic, color: Colors.grey),
                              softWrap: true, // Quebra linha
                            ),
                            if (data['subcategoria'] != null)
                              Text(
                                "(${data['subcategoria']})",
                                style: const TextStyle(fontSize: 14, color: Colors.blueGrey),
                                softWrap: true, // Quebra linha
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 20),
                  const Text("Descrição:", style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(
                    data['descricao'] ?? 'Sem descrição',
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  
                  if (_isAdmin) 
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.edit),
                          label: const Text('Editar'),
                          onPressed: () {
                            Navigator.pop(context);
                            Navigator.push(context, MaterialPageRoute(builder: (context) => EditPointScreen(docId: docId, initialData: data)));
                          },
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                          icon: const Icon(Icons.delete),
                          label: const Text('Excluir'),
                          onPressed: () {
                            Navigator.pop(context);
                            _showDeleteConfirmDialog(docId, data['nome']);
                          },
                        ),
                      ],
                    )
                ],
              ),
            );
          }
        );
      },
    );
  }

  Future<void> _showDeleteConfirmDialog(String docId, String pointName) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirmar Exclusão'),
          content: Text('Excluir "$pointName"?'),
          actions: <Widget>[
            TextButton(child: const Text('Cancelar'), onPressed: () => Navigator.pop(context)),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Excluir'),
              onPressed: () {
                FirebaseFirestore.instance.collection('pontos_interesse').doc(docId).delete();
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  void _openAdvancedSearch() async {
    // CORREÇÃO: Prepara o mapa de cores antes de enviar para a pesquisa
    Map<String, String> simpleColors = {};
    _descriptorsData.forEach((key, value) {
      simpleColors[key] = value['cor'];
    });

    final result = await showSearch(
      context: context,
      delegate: MapSearchDelegate(
        points: _allLoadedPoints,
        categoriesAndColors: simpleColors, // Passamos o mapa corrigido
      ),
    );

    if (result != null) {
      if (result is LatLng) {
        _mapController.move(result, 17.0);
      } else if (result is QueryDocumentSnapshot) {
        final data = result.data() as Map<String, dynamic>;
        final geoPoint = data['coordenadas'] as GeoPoint;
        final latLng = LatLng(geoPoint.latitude, geoPoint.longitude);
        
        _mapController.move(latLng, 17.0);
        _showPointDetails(data, result.id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Query pointsQuery = FirebaseFirestore.instance.collection('pontos_interesse');
    var sortedDescriptorKeys = _descriptorsData.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prisma'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _openAdvancedSearch,
            tooltip: 'Pesquisar Local ou Ponto',
          ),
        ],
      ),
      drawer: Drawer(
        child: Column(
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.blue),
              child: Center(child: Text('Menu', style: TextStyle(color: Colors.white, fontSize: 24))),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text('Exibir no Mapa', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                  ),
                  SwitchListTile(
                    title: const Text('Locais'),
                    secondary: const Icon(Icons.location_pin, color: Colors.red),
                    value: _showNormalPoints,
                    onChanged: (v) => setState(() => _showNormalPoints = v),
                  ),
                  SwitchListTile(
                    title: const Text('Pontos Críticos'),
                    secondary: const Icon(Icons.warning_rounded, color: Colors.orange),
                    value: _showWarningPoints,
                    onChanged: (v) => setState(() => _showWarningPoints = v),
                  ),
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Text('Filtrar Descritores', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                  ),
                  
                 Builder(
                    builder: (context) {
                      // 1. Verifica se TUDO está marcado
                      bool isAllSelected = _descriptorsData.isNotEmpty && _descriptorsData.entries.every((entry) {
                        final catName = entry.key;
                        final List<String> allSubs = (entry.value['subs'] as List<dynamic>).map((e) => e.toString()).toList();
                        final Set<String>? active = _activeSubFilters[catName];
                        // Retorna true só se a lista ativa for igual à lista total
                        return active != null && active.length == allSubs.length;
                      });

                      // 2. Verifica se NADA está marcado (para visual)
                      bool isNoneSelected = _activeSubFilters.isEmpty || _activeSubFilters.values.every((set) => set.isEmpty);

                      // Lógica visual do botão:
                      // True (Check) = Tudo marcado
                      // False (Vazio) = Nada marcado
                      // Null (Tracinho) = Alguns marcados
                      bool? checkboxState;
                      if (isAllSelected) {
                        checkboxState = true;
                      } else if (isNoneSelected) {
                        checkboxState = false;
                      } else {
                        checkboxState = null; // Mostra o "tracinho" (estado misto)
                      }

                      return CheckboxListTile(
                        title: const Text("Selecionar Todos", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                        value: checkboxState,
                        tristate: true, // Permite o estado "meio termo" (tracinho)
                        activeColor: Colors.blue,
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                        
                        onChanged: (bool? value) {
                          setState(() {
                            // AQUI ESTÁ A CORREÇÃO DO BUG:
                            // Se já estava tudo selecionado, a gente LIMPA.
                            // Qualquer outro caso (vazio ou misto), a gente ENCHE TUDO.
                            if (isAllSelected) {
                              _activeSubFilters = {};
                            } else {
                              Map<String, Set<String>> tempAll = {};
                              _descriptorsData.forEach((key, val) {
                                tempAll[key] = (val['subs'] as List<dynamic>).map((e) => e.toString()).toSet();
                              });
                              _activeSubFilters = tempAll;
                            }
                          });
                        },
                      );
                    }
                  ),
                  const Divider(height: 1),

                  ...sortedDescriptorKeys.map((descName) {
                    final descData = _descriptorsData[descName]!;
                    final List<String> allSubs = descData['subs'];
                    final Set<String> activeSubs = _activeSubFilters[descName] ?? {};
                    final Color color = ColorUtils.fromHex(descData['cor']);

                    // Lógica para saber o estado atual
                    bool allSelected = activeSubs.length == allSubs.length && allSubs.isNotEmpty;
                    bool noneSelected = activeSubs.isEmpty;

                    return ExpansionTile(
                      leading: Checkbox(
                        // Define o visual: Cheio, Vazio ou Tracinho (-)
                        value: allSelected ? true : (noneSelected ? false : null),
                        tristate: true, // Importante para mostrar o "tracinho" quando parcial
                        activeColor: color,
                        
                        // --- CORREÇÃO AQUI ---
                        onChanged: (bool? value) {
                          setState(() {
                            // Lógica baseada no ESTADO ATUAL, não no clique
                            if (allSelected) {
                              // Se já estava tudo marcado, LIMPA
                              _activeSubFilters[descName] = {};
                            } else {
                              // Se estava vazio ou parcial, ENCHE TUDO
                              _activeSubFilters[descName] = allSubs.toSet();
                            }
                          });
                        },
                      ),
                      title: Text(descName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      childrenPadding: const EdgeInsets.only(left: 20),
                      children: allSubs.map((subName) {
                        return CheckboxListTile(
                          title: Text(subName, style: const TextStyle(fontSize: 13)),
                          value: activeSubs.contains(subName),
                          dense: true,
                          activeColor: color,
                          onChanged: (bool? value) {
                            setState(() {
                              if (value == true) {
                                _activeSubFilters[descName]!.add(subName);
                              } else {
                                _activeSubFilters[descName]!.remove(subName);
                              }
                            });
                          },
                        );
                      }).toList(),
                    );
                  }).toList(),

                  const Divider(),
                  if (_isAdmin) ...[
                    ListTile(
                      leading: const Icon(Icons.add_location_alt),
                      title: const Text('Adicionar Ponto'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (context) => AddPointScreen(initialCenter: _userCurrentLocation ?? _biriguiCenter)));
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.category),
                      title: const Text('Gerenciar Descritores'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const CategoryManagerScreen()));
                      },
                    ),
                  ],
                  ListTile(
                    leading: Icon(_isAdmin ? Icons.logout : Icons.admin_panel_settings),
                    title: Text(_isAdmin ? 'Sair (Logout)' : 'Login de Administrador'),
                    onTap: () async {
                      if (_isAdmin) await FirebaseAuth.instance.signOut();
                      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => _isAdmin ? const MapScreen() : LoginScreen()));
                    },
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: pointsQuery.snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final allDocs = snapshot.data!.docs;
          _allLoadedPoints = allDocs;

          final filteredPoints = allDocs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final tipo = data['tipo'] ?? 'normal';
            final cat = data['categoria'] ?? '';
            final sub = data['subcategoria'] ?? '';
            
            if (tipo == 'normal' && !_showNormalPoints) return false;
            if (tipo == 'aviso' && !_showWarningPoints) return false;
            
            if (!_activeSubFilters.containsKey(cat)) return false;
            Set<String> activeSubs = _activeSubFilters[cat]!;
            if (sub.isNotEmpty) {
              if (!activeSubs.contains(sub)) return false;
            } else {
              if (activeSubs.isEmpty) return false;
            }
            return true;
          }).toList();

         // 4. CRIAÇÃO DOS MARCADORES (LÓGICA HIERÁRQUICA: SUB > CATEGORIA)
          final markers = filteredPoints.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final geoPoint = data['coordenadas'] as GeoPoint;
            final latLng = LatLng(geoPoint.latitude, geoPoint.longitude);
            final colorHex = _descriptorsData[data['categoria']]?['cor'] ?? '#808080';
            final markerColor = ColorUtils.fromHex(colorHex);
            
            final tipo = data['tipo'] ?? 'normal';
            // Importante: Tratamento de nulos e espaços
            final categoria = (data['categoria'] ?? '').toString().trim();
            final subcategoria = (data['subcategoria'] ?? '').toString().trim();
            
            bool showLabel = _lastMapZoom > 16.0;

            // --- SEU DICIONÁRIO DE ÍCONES ---
            // Adicione aqui TODOS os nomes exatos (do Firebase) e os sufixos dos arquivos
            final Map<String, String> iconMap = {
              // Exemplo Assistência Social
              'Assistência Social e Direitos Humanos': 'social', // Genérico
              'CRAS': 'cras',   // Específico
              'CREAS': 'creas', // Específico
              'ONGs': 'ongs',   // Específico
              
              'Acessibilidade e Inclusão': 'acessibilidade',

              'Bibliotecas': 'bibliotecas',
              'Educação Infantil': 'educacao_infantil',
              'Ensino Fundamental': 'ensino_fundamental',
              'Ensino Médio': 'ensino_medio',
              'Ensino Superior': 'ensino_superior',
              'Centros de Pesquisa': 'centros_de_pesquisa',

              'Campos, Centros Esportivos, Ginásios...': 'campos_centros_esportivos_ginasios',
              'Centros Culturais': 'centros_culturais',
              'Cinemas, Teatros...': 'cinemas_teatros',
              'Praças, Parques...': 'praças_parques',
              
              'Ruas': 'ruas',
              'Iluminação e Semáforos': 'iluminacao_semaforos',
              'Obras': 'obras',
              'Saneamento Básico': 'saneamento_basico',

              'Parques': 'parques',
              'Pontos de Coleta Seletiva': 'pontos_de_coleta_seletiva',
              
              'Ciclovias': 'ciclovias',
              'Pontos de Ônibus': 'pontos_de_onibus',
              'Rodoviárias': 'rodoviarias',

              'Participação Social': 'participacao_social',

              'Conselho Tutelar, Delegacias...': 'conselho_tutelar_delegacias',
              'Hospitais, Postos de vacinação, UBS...': 'hospitais_postos_de_vacinacao',

              // ... adicione os outros aqui ...
            };

            Widget markerWidget;
            String? iconSuffix;

            // 1. Tenta achar ícone pelo SUBDESCRITOR (Prioridade Alta)
            if (subcategoria.isNotEmpty && iconMap.containsKey(subcategoria)) {
              iconSuffix = iconMap[subcategoria];
            } 
            // 2. Se não achou, tenta pelo DESCRITOR PRINCIPAL (Prioridade Média)
            else if (iconMap.containsKey(categoria)) {
              iconSuffix = iconMap[categoria];
            }

            // SE ENCONTROU ALGUM ÍCONE NO MAPA:
            if (iconSuffix != null) {
              String prefix = (tipo == 'aviso') ? 'aviso_' : 'icone_';
              String fileName = 'assets/icons/$prefix$iconSuffix.png';

              markerWidget = Image.asset(
                fileName,
                width: 40, 
                height: 40,
                filterQuality: FilterQuality.high,
                isAntiAlias: true,
                // Fallback: Se você esqueceu de criar o arquivo PNG, usa o ícone padrão
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    tipo == 'aviso' ? Icons.location_on : Icons.location_on,
                    color: tipo == 'aviso' ? Colors.orange : markerColor,
                    size: 45,
                    shadows: [const Shadow(blurRadius: 2, color: Colors.black54, offset: Offset(0, 1))],
                  );
                },
              );
            } 
            // SE NÃO ESTÁ NO MAPA, USA O PADRÃO COLORIDO
            else {
              markerWidget = Icon(
                tipo == 'aviso' ? Icons.location_on : Icons.location_on,
                color: tipo == 'aviso' ? Colors.orange : markerColor,
                size: 45,
                shadows: [const Shadow(blurRadius: 2, color: Colors.black54, offset: Offset(0, 1))],
              );
            }

            return Marker(
              point: latLng,
              width: 50, 
              height: 50,
              alignment: Alignment.center,
              
              child: GestureDetector(
                onTap: () => _showPointDetails(data, doc.id),
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none, 
                  children: [
                    // O ÍCONE (Centralizado e Ajustado)
                    Transform.translate(
                      offset: const Offset(0, -22), 
                      child: Tooltip(
                        message: data['nome'] ?? 'Sem nome',
                        preferBelow: false,
                        child: markerWidget,
                      ),
                    ),

                    // O TEXTO
                    if (showLabel)
                      Positioned(
                        top: -50, 
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 200), 
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                            boxShadow: [const BoxShadow(blurRadius: 2, color: Colors.black26)]
                          ),
                          child: Text(
                            data['nome'] ?? '',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }).toList();

          return _buildMap(markers);
        },
      ),
      
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "zoomIn",
            mini: true,
            onPressed: _zoomIn,
            child: const Icon(Icons.add),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: "zoomOut",
            mini: true,
            onPressed: _zoomOut,
            child: const Icon(Icons.remove),
          ),
          const SizedBox(height: 20),
          
          if (_isAdmin) ...[
            FloatingActionButton(
              heroTag: "btnAdd",
              onPressed: () {
                final LatLng center = _mapController.camera.center;
                Navigator.push(context, MaterialPageRoute(builder: (context) => AddPointScreen(initialCenter: center)));
              },
              backgroundColor: Colors.green,
              child: const Icon(Icons.add_location_alt),
            ),
            const SizedBox(height: 10),
          ],
          FloatingActionButton(
            heroTag: "btnLoc",
            onPressed: _moveToCurrentLocation,
            child: const Icon(Icons.my_location),
          ),
        ],
      ),
    );
  }

  Widget _buildMap(List<Marker> markers) {
    List<Marker> allMarkers = [...markers];
    if (_userCurrentLocation != null) {
      allMarkers.add(Marker(
        point: _userCurrentLocation!, width: 40, height: 40,
        child: const Icon(Icons.person_pin_circle, color: Colors.blue, size: 40),
      ));
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _biriguiCenter,
        initialZoom: 15.0,
        onPositionChanged: (pos, hasGesture) {
          if (pos.center != null) _lastMapPosition = pos.center!;
          if (pos.zoom != null) {
            if (pos.zoom!.floor() != _lastMapZoom.floor()) {
              setState(() => _lastMapZoom = pos.zoom!);
            } else {
              _lastMapZoom = pos.zoom!;
            }
          }
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.mapa_birigui_final',
          panBuffer: 2,
          keepBuffer: 5,
        ),
        MarkerLayer(markers: allMarkers),
      ],
    );
  }
}

// =============================================================================
//  CLASSE DE PESQUISA (Delegate)
// =============================================================================
class MapSearchDelegate extends SearchDelegate<dynamic> {
  final List<QueryDocumentSnapshot> points;
  final Map<String, String> categoriesAndColors; // Variável corrigida

  MapSearchDelegate({required this.points, required this.categoriesAndColors});

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = '';
          showSuggestions(context); 
        },
      ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => Navigator.pop(context), 
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    if (query.trim().isEmpty) return const SizedBox();
    _addToHistory(query);

    return FutureBuilder<List<dynamic>>(
      future: _searchAll(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('Nenhum resultado encontrado.'));
        }

        final results = snapshot.data!;

        return ListView.builder(
          itemCount: results.length,
          itemBuilder: (context, index) {
            final item = results[index];
            if (item is QueryDocumentSnapshot) {
              final data = item.data() as Map<String, dynamic>;
              // CORREÇÃO: Agora usa a variável local da classe Delegate
              final colorHex = categoriesAndColors[data['categoria']] ?? '#808080';
              return ListTile(
                leading: Icon(Icons.location_pin, color: ColorUtils.fromHex(colorHex)),
                title: Text(data['nome'] ?? 'Sem nome'),
                subtitle: Text(data['categoria'] ?? ''),
                onTap: () => close(context, item),
              );
            } else {
              return ListTile(
                leading: const Icon(Icons.public, color: Colors.blue),
                title: Text(item['display_name'] ?? ''),
                subtitle: const Text('Endereço/Local'),
                onTap: () {
                  final lat = double.parse(item['lat']);
                  final lon = double.parse(item['lon']);
                  close(context, LatLng(lat, lon));
                },
              );
            }
          },
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    // ... (Mantido igual ao anterior, sem dependências de cores) ...
    // Apenas para brevidade, não colei de novo, mas se precisar me avise.
    // O erro estava no buildResults, então o buildSuggestions não precisa mudar.
    // Vou incluir a função completa para não quebrar:
    if (query.isEmpty) {
      return FutureBuilder<List<String>>(
        future: _getHistory(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox();
          final history = snapshot.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (history.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Pesquisas Recentes', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                      TextButton(onPressed: _clearHistory, child: const Text('Limpar'))
                    ],
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  itemCount: history.length,
                  itemBuilder: (context, index) {
                    return ListTile(
                      leading: const Icon(Icons.history),
                      title: Text(history[index]),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () => _removeFromHistory(history[index], context),
                      ),
                      onTap: () {
                        query = history[index];
                        showResults(context);
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      );
    }

    final suggestions = points.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final nome = (data['nome'] as String? ?? '').toLowerCase();
      return nome.contains(query.toLowerCase());
    }).toList();

    return ListView.builder(
      itemCount: suggestions.length + 1,
      itemBuilder: (context, index) {
        if (index == suggestions.length) {
          return ListTile(
            leading: const Icon(Icons.search, color: Colors.blue),
            title: Text('Buscar endereço "$query" no mapa'),
            onTap: () => showResults(context),
          );
        }
        final item = suggestions[index];
        final data = item.data() as Map<String, dynamic>;
        return ListTile(
          leading: const Icon(Icons.location_pin, color: Colors.grey),
          title: Text(data['nome'] ?? ''),
          onTap: () => close(context, item),
        );
      },
    );
  }

  // Métodos auxiliares de busca e histórico (Mantenha igual ao código anterior)
  Future<List<dynamic>> _searchAll(String term) async {
    List<dynamic> results = [];
    final localResults = points.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final nome = (data['nome'] as String? ?? '').toLowerCase();
      return nome.contains(term.toLowerCase());
    }).toList();
    results.addAll(localResults);

    try {
      final url = Uri.parse('https://nominatim.openstreetmap.org/search?q=$term+Birigui&format=json&limit=5&addressdetails=1');
      final response = await http.get(url, headers: {'User-Agent': 'com.example.mapa_birigui_final'});
      if (response.statusCode == 200) {
        final List<dynamic> places = json.decode(response.body);
        results.addAll(places);
      }
    } catch (e) {
      print("Erro na busca online: $e");
    }
    return results;
  }

  Future<List<String>> _getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('search_history') ?? [];
  }

  Future<void> _addToHistory(String term) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> history = prefs.getStringList('search_history') ?? [];
    history.remove(term);
    history.insert(0, term);
    if (history.length > 10) history = history.sublist(0, 10);
    await prefs.setStringList('search_history', history);
  }

  Future<void> _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('search_history');
    query = query; 
  }

  Future<void> _removeFromHistory(String term, BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> history = prefs.getStringList('search_history') ?? [];
    history.remove(term);
    await prefs.setStringList('search_history', history);
    query = query;
    showSuggestions(context);
  }
}