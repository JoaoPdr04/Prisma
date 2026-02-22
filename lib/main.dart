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
import 'package:url_launcher/url_launcher.dart';
import 'admin_requests_screen.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'notifications_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'dart:convert'; // Para ler o JSON da resposta
import 'package:package_info_plus/package_info_plus.dart';

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

    localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('pt', 'BR'), // Português do Brasil
      ],

      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: StreamBuilder<User?>(
  stream: FirebaseAuth.instance.authStateChanges(), // O "Ouvido" do Firebase
  builder: (context, snapshot) {
    
    // 1. Se estiver carregando (verificando), mostra uma bolinha girando
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }

    // 2. Se tem dados (usuário logado), vai direto para o Mapa
    if (snapshot.hasData) {
      return const MapScreen(); 
    }

    // 3. Se não tem dados (ninguém logado), manda para o Login
    return const LoginScreen(); 
  },
),
    );
  }  
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {

  String? userName = "Carregando...";
  String? userEmail = "";
  String? userPhotoUrl;
  String userRole = "leitor"; // Define o padrão como leitor
  bool isVisitante = false;

  String _userRole = 'leitor'; // <--- O INIMIGO ESTÁ AQUI (DUPLICADO)
  bool get _isAdmin => _userRole == 'admin';
  bool get _canAdd => _userRole == 'admin' || _userRole == 'colaborador';

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

  Future<void> _checkUpdate() async {
    // IMPORTANTE: Use o seu link RAW do GitHub aqui
    final url = Uri.parse("https://raw.githubusercontent.com/JoaoPdr04/Prisma/main/version.json");

try {
      // 1. Descobre a versão instalada no celular agora
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String localVersion = packageInfo.version; // Ex: "1.0.0"
      String buildNumber = packageInfo.buildNumber; // Ex: "1"

      print("Versão instalada: $localVersion (Build $buildNumber)");

      // 2. Busca a versão nova na internet
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        String remoteVersion = data['latest_version'];
        
        // 3. Compara: Se a versão da internet for diferente da local
        if (remoteVersion != localVersion) {
           print("Nova versão encontrada: $remoteVersion");
          _showUpdateDialog(remoteVersion, data['download_url']);
        } else {
           print("O App já está atualizado.");
        }
      }
    } catch (e) {
      debugPrint("Erro ao verificar atualização: $e");
    }
  }

  // Função que busca o endereço na internet
  Future<void> _buscarEnderecoOnline(String query) async {
    if (query.isEmpty) return;

    // URL do Nominatim (OpenStreetMap)
    final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=$query&format=json&limit=1&addressdetails=1');

    try {
      final response = await http.get(
        url,
        // O Nominatim exige um User-Agent para não bloquear
        headers: {'User-Agent': 'com.exemplo.prisma'}, 
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data is List && data.isNotEmpty) {
          // Pegamos o primeiro resultado
          final resultado = data[0];
          final double lat = double.parse(resultado['lat']);
          final double lon = double.parse(resultado['lon']);
          final String nomeEncontrado = resultado['display_name'];

          // Move o mapa para lá
          _mapController.move(LatLng(lat, lon), 16.0); // Zoom 16 é bom para ruas

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Indo para: $nomeEncontrado')),
          );
          
          // Opcional: Limpar a barra de pesquisa ou fechar o teclado
          FocusScope.of(context).unfocus();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Endereço não encontrado.')),
          );
        }
      }
    } catch (e) {
      print("Erro na busca: $e");
    }
  }

  void _showUpdateDialog(String newVersion, String url) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Nova Atualização! 🚀"),
        content: Text("Uma nova versão ($newVersion) do Prisma está disponível. Deseja baixar agora?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Depois"),
          ),
          ElevatedButton(
            onPressed: () async {
              final uri = Uri.parse(url);
              if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                  debugPrint("Não foi possível abrir o link: $url");
              }
            },
            child: const Text("Atualizar"),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _lastMapPosition = _biriguiCenter;
    _loadUserData();
    _listenToDescriptors();
    _startLocationUpdates();
    _checkUpdate();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    super.dispose();
  }

  Future<void> _abrirLink(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
       // Se der erro, avisa no console ou ignora
       debugPrint('Não foi possível abrir o link: $url');
    }
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

  void _showSobreApp() {
  showAboutDialog(
    context: context,
    applicationName: 'Prisma - Mapeador de Qualidade de Vida',
    applicationVersion: '1.2.0',
    applicationIcon: Image.asset(
      'assets/icon/app_icon.png', 
      width: 50, 
      height: 50, 
      errorBuilder: (c, e, s) => const Icon(Icons.map, size: 40, color: Colors.blue)
    ),
    children: [
      const Padding(
        padding: EdgeInsets.only(top: 15),
        child: Text(
          'O Prisma é uma ferramenta colaborativa desenvolvida por alunos e docentes do Intituto Federal de São Paulo, campus Birigui, com a finalidade de catalogar através de um mapa, os indicadores de Qualidade de Vida e Direitos Humanos da cidade de Birigui-SP e região. '
          '\n\nNosso objetivo é dar voz aos cidadãos, indentificando pontos positivos e críticos na cidade.'
          '\n\nRecomendamos que todos os usuarios estejam cientes de nossos Termos de Uso e Políticas de Privacidade a fim de otimizar e potencializar o uso do aplicativo',
          style: TextStyle(fontSize: 14),
          textAlign: TextAlign.justify,
        ),
      ),
      const Divider(),
      ListTile(
        leading: const Icon(Icons.description, color: Colors.blue),
        title: const Text('Termos de Uso'),
        subtitle: const Text('Leia nossos termos de uso'),
        onTap: () => _abrirLink('https://raw.githubusercontent.com/JoaoPdr04/Prisma/refs/heads/main/docs/TERMOS.md'),
      ),
      ListTile(
        leading: const Icon(Icons.privacy_tip, color: Colors.blue),
        title: const Text('Política de Privacidade'),
        subtitle: const Text('Leia nossa Política de Privacidade'),
        onTap: () => _abrirLink('https://raw.githubusercontent.com/JoaoPdr04/Prisma/refs/heads/main/docs/PRIVACIDADE.md'),
      ),
      ListTile(
        leading: const Icon(Icons.email, color: Colors.orange),
        title: const Text('Entrar em Contato/Relatar Problema'),
        subtitle: const Text('jpfdo24@gmail.com'),
        onTap: () => _abrirLink('mailto:jpfdo24@gmail.com'),
      ),
      ListTile(
        leading: const Icon(Icons.email, color: Color.fromARGB(255, 255, 0, 0)),
        title: const Text('Entrar em Contato/Relatar Problema'),
        subtitle: const Text('ferreira.joao2@aluno.ifsp.edu.br'),
        onTap: () => _abrirLink('mailto:ferreira.joao2@aluno.ifsp.edu.br'),
      ),

    ],
  );
}

  void _zoomIn() {
    final currentZoom = _mapController.camera.zoom;
    _mapController.move(_mapController.camera.center, currentZoom + 1);
  }

  void _zoomOut() {
    final currentZoom = _mapController.camera.zoom;
    _mapController.move(_mapController.camera.center, currentZoom - 1);
  }

// Função unificada que carrega TUDO (Auth + Firestore)
  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      setState(() {
        // 1. Carrega dados básicos do Google Auth
        isVisitante = user.isAnonymous;
        userName = user.displayName ?? "Usuário";
        userEmail = user.email ?? "Sem email";
        userPhotoUrl = user.photoURL;
      });

      // 2. Se não for visitante, busca o cargo no Firestore
      if (!isVisitante) {
        try {
          final doc = await FirebaseFirestore.instance
              .collection('usuarios')
              .doc(user.uid)
              .get();

          if (doc.exists && mounted) {
            setState(() {
              // Atualiza a variável correta 'userRole'
              userRole = doc.data()?['cargo'] ?? 'leitor';
            });
            print("Cargo carregado: $userRole"); // Debug
          }
        } catch (e) {
          print("Erro ao buscar cargo: $e");
        }
      }
    } else {
      // Se não tiver usuário, reseta tudo
      setState(() {
        userRole = 'leitor';
        userName = null;
      });
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
void _showPointDetails(Map<String, dynamic> data, String docId,LatLng point) {
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
                  
                  // CATEGORIA
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: CircleAvatar(backgroundColor: categoryColor, radius: 8),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data['categoria'] ?? 'Descritor não disponível',
                              style: const TextStyle(fontSize: 16, fontStyle: FontStyle.italic, color: Colors.grey),
                              softWrap: true,
                            ),
                            if (data['subcategoria'] != null)
                              Text(
                                "(${data['subcategoria']})",
                                style: const TextStyle(fontSize: 14, color: Colors.blueGrey),
                                softWrap: true,
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

                  // --- 1. BOTÃO DE ROTA (PARA TODO MUNDO) ---
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.directions, color: Colors.white),
                      label: const Text('Traçar Rota até aqui', style: TextStyle(color: Colors.white, fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    onPressed: () {
                        _abrirRotaNoGoogleMaps(point.latitude, point.longitude);
                      }
                    ),
                  ),
                  
                  const SizedBox(height: 15),

                  // --- 2. BOTÕES DE ADMIN (SÓ SE TIVER PERMISSÃO) ---
                  if (_canAdd) 
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
                    ),
                    
                   // Fim dos botões
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
        categoriesAndColors: simpleColors,
        onSearchOnline: (String query) {
           _buscarEnderecoOnline(query);
         } // Passamos o mapa corrigido
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
        _showPointDetails(data, result.id, latLng);
      }
    }
  }

  Future<void> _abrirRotaNoGoogleMaps(double lat, double long) async {
    // O parâmetro "dir" diz ao Google que queremos direções (rota)
    // O parâmetro "destination" é para onde vamos
    // Se não passamos a origem, ele assume que é a "Minha Localização Atual"
    final Uri url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$long');

    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o mapa.')),
      );
    }
  }

  // --- FUNÇÃO PARA PEDIR ACESSO (COM DIAGNÓSTICO) ---
  void _showRequestAccessDialog() {
    final TextEditingController reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) { // Mudei o nome para não confundir com o context principal
        return AlertDialog(
          title: const Text('Solicitar Acesso'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Por que você precisa de acesso?'),
              const SizedBox(height: 10),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  hintText: 'Digite o motivo aqui...',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                print("1. Botão Enviar clicado");

                final reason = reasonController.text.trim();
                print("2. Texto digitado: '$reason'");

                if (reason.isEmpty) {
                  print("ERRO: O texto está vazio. O envio foi cancelado.");
                  return; 
                }

                final user = FirebaseAuth.instance.currentUser;
                print("3. Usuário atual: ${user?.uid}");

                if (user == null) {
                  print("ERRO: Usuário não está logado.");
                  return;
                }

                // Fecha o diálogo visualmente
                Navigator.pop(dialogContext);
                print("4. Diálogo fechado, tentando enviar para o Firebase...");

                try {
                  await FirebaseFirestore.instance.collection('solicitacoes').add({
                    'uid': user.uid,
                    'nome': user.displayName ?? 'Sem Nome',
                    'email': user.email ?? 'Sem Email',
                    'motivo': reason,
                    'status': 'pendente',
                    'data': FieldValue.serverTimestamp(),
                  });
                  
                  print("5. SUCESSO! Documento criado no Firebase.");

                  try {
                    // 1. Procura quem são os administradores no banco
                    final adminsQuery = await FirebaseFirestore.instance
                        .collection('usuarios')
                        .where('cargo', isEqualTo: 'admin')
                        .get();

                    // 2. Manda uma notificação para CADA admin encontrado
                    for (var adminDoc in adminsQuery.docs) {
                      await FirebaseFirestore.instance.collection('notificacoes').add({
                        'destinatarioId': adminDoc.id, // O ID do Admin
                        'titulo': 'Nova Solicitação! 🔔',
                        'mensagem': '${user.displayName} pediu acesso de Colaborador.',
                        'data': FieldValue.serverTimestamp(),
                        'lida': false,
                      });
                    }
                    print("6. Admins notificados.");
                  } catch (e) {
                    print("Erro ao notificar admins (não impede o fluxo): $e");
                  }

                  // Mostra mensagem de sucesso
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Solicitação enviada com sucesso!'), backgroundColor: Colors.green),
                    );
                  }
                } catch (e) {
                  print("ERRO CRÍTICO NO FIREBASE: $e");
                  
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('Enviar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    Query pointsQuery = FirebaseFirestore.instance.collection('pontos_interesse');
    var sortedDescriptorKeys = _descriptorsData.keys.toList()..sort();

    final user = FirebaseAuth.instance.currentUser;
    final bool isVisitante = user?.isAnonymous ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prisma'),
        centerTitle: true,
        actions: [

          IconButton(
            icon: const Icon(Icons.notifications),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const NotificationsScreen()),
              );
            },
          ),

          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recarregar Informações',
            onPressed: () async {
              // Recarrega o cargo do usuário
              await _loadUserData();           
              setState(() {}); // Força a tela a redesenhar
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Informações atualizadas!'), duration: Duration(seconds: 1)),
              );
            },
          ),

          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _openAdvancedSearch,
            tooltip: 'Pesquisar Local ou Ponto',
          ),
        ],
      ),
      
drawer: Drawer(
  child: ListView(
    padding: EdgeInsets.zero, // Remove borda branca do topo
    children: [

      UserAccountsDrawerHeader(
        decoration: const BoxDecoration(color: Colors.blue),
        
        // 1. FOTO DO PERFIL
        currentAccountPicture: CircleAvatar(
          backgroundColor: Colors.white,
          backgroundImage: (userPhotoUrl != null && !isVisitante) 
              ? NetworkImage(userPhotoUrl!) 
              : null,
          child: (userPhotoUrl == null || isVisitante)
              ? const Icon(Icons.person, size: 40, color: Colors.blue)
              : null,
        ),

        // 2. NOME
        accountName: Text(
          isVisitante ? "Visitante" : (userName ?? "Usuário"),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),

        // 3. EMAIL E CARGO (CORRIGIDO)
        accountEmail: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isVisitante ? "Modo de visualização" : (userEmail ?? "")),
            
            // Etiqueta amarela do cargo
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black26, 
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                isVisitante ? "VISITANTE" : "CARGO: ${userRole.toUpperCase()}",
                style: const TextStyle(
                    color: Colors.yellowAccent, 
                    fontWeight: FontWeight.bold, 
                    fontSize: 10
                ),
              ),
            ),
          ],
        ),
      ),

      // 2. SWITCHES (Locais e Críticos)
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

      // 3. FILTROS (Lógica complexa)
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Text('Filtrar Descritores', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
      ),

      // Checkbox "Selecionar Todos"
      Builder(
        builder: (context) {
          bool isAllSelected = _descriptorsData.isNotEmpty && _descriptorsData.entries.every((entry) {
            final catName = entry.key;
            final List<String> allSubs = (entry.value['subs'] as List<dynamic>).map((e) => e.toString()).toList();
            final Set<String>? active = _activeSubFilters[catName];
            return active != null && active.length == allSubs.length;
          });

          bool isNoneSelected = _activeSubFilters.isEmpty || _activeSubFilters.values.every((set) => set.isEmpty);

          bool? checkboxState;
          if (isAllSelected) checkboxState = true;
          else if (isNoneSelected) checkboxState = false;
          else checkboxState = null;

          return CheckboxListTile(
            title: const Text("Selecionar Todos", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
            value: checkboxState,
            tristate: true,
            activeColor: Colors.blue,
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            onChanged: (bool? value) {
              setState(() {
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

      // Lista Expansível de Descritores
      // Note que aqui usamos o spread operator (...) direto na lista principal
      ...sortedDescriptorKeys.map((descName) {
        final descData = _descriptorsData[descName]!;
        final List<String> allSubs = (descData['subs'] as List<dynamic>).map((e) => e.toString()).toList();
        final Set<String> activeSubs = _activeSubFilters[descName] ?? {};
        final Color color = ColorUtils.fromHex(descData['cor']);

        bool allSelected = activeSubs.length == allSubs.length && allSubs.isNotEmpty;
        bool noneSelected = activeSubs.isEmpty;

        return ExpansionTile(
          leading: Checkbox(
            value: allSelected ? true : (noneSelected ? false : null),
            tristate: true,
            activeColor: color,
            onChanged: (bool? value) {
              setState(() {
                if (allSelected) {
                  _activeSubFilters[descName] = {};
                } else {
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
                    if (_activeSubFilters[descName] == null) _activeSubFilters[descName] = {};
                    _activeSubFilters[descName]!.add(subName);
                  } else {
                    _activeSubFilters[descName]?.remove(subName);
                  }
                });
              },
            );
          }).toList(),
        );
      }),

      // 4. RODAPÉ (Outras opções e Botões)
      // Eles entram aqui direto, sem Spacer ou Expanded, para rolar junto
      const Divider(thickness: 2),
      const Padding(
        padding: EdgeInsets.only(left: 16, top: 10, bottom: 5),
        child: Text("Outras Opções", style: TextStyle(color: Colors.grey, fontSize: 12)),
      ),

      ListTile(
        leading: const Icon(Icons.info_outline, color: Colors.blueGrey),
        title: const Text('Sobre o App'),
        onTap: () {
          Navigator.pop(context);
          _showSobreApp();
        },
      ),

      if (isVisitante) 
        ListTile(
          leading: const Icon(Icons.login, color: Colors.green),
          title: const Text('Fazer Login'),
          onTap: () {
             Navigator.pop(context);
             Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
          },
        )
      else ...[
        if (userRole == 'leitor')
          ListTile(
            leading: const Icon(Icons.volunteer_activism, color: Colors.orange),
            title: const Text('Quero ser Colaborador'),
            onTap: () {
              Navigator.pop(context); 
                    // 2. Chama a função que estava "desligada" (unused)
                    print("Botão clicado! Abrindo diálogo..."); // Debug pra você ver no console
                    _showRequestAccessDialog();
            },
          ),

          // --- ÁREA DO ADMINISTRADOR ---
              if (userRole == 'admin') ...[
                const Divider(), // Uma linha para separar
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings, color: Colors.purple),
                  title: const Text('Gerenciar Colaboradores'),
                  subtitle: const Text('Aprovar/Rejeitar pedidos'),
                  onTap: () {
                    Navigator.pop(context); // Fecha o menu
                    
                    // Navega para a tela de administração
                    // Certifique-se de importar o arquivo dessa tela lá no topo!
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminRequestsScreen()));
                  },
                ),
              ],


        ListTile(
          leading: const Icon(Icons.exit_to_app, color: Colors.red),
          title: const Text('Sair'),
          onTap: () async {
            await FirebaseAuth.instance.signOut();
            if (mounted) {
               Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
            }
          },
        ),
      ],
      
      const SizedBox(height: 20), // Espaço final
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
            
            // --- O SEGREDO ESTÁ AQUI ---
            rotate: true, // false = Fica em pé (Norte da Tela). true = Gira com o mapa.
            alignment: Alignment.center, // Garante que o ícone gire sobre o próprio eixo
            // ---------------------------

            child: GestureDetector(
              onTap: () => _showPointDetails(data, doc.id, latLng),
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none, 
                children: [
                  // O ÍCONE
                  Transform.translate(
                    offset: const Offset(0, -22), // Levanta o ícone para a ponta tocar no local
                    child: Tooltip(
                      message: data['nome'] ?? 'Sem nome',
                      preferBelow: false,
                      child: markerWidget,
                    ),
                  ),

                  // O TEXTO (BALÃOZINHO)
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
          
          if (_canAdd) ...[
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
        point: _userCurrentLocation!, 
        width: 40, 
        height: 40,
        
        // 👇 ADICIONE ESTA LINHA AQUI 👇
        rotate: true, 
        
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

      nonRotatedChildren: [
    Align(
      alignment: Alignment.bottomLeft, // Fica no canto direito inferior
      child: Container(
        margin: const EdgeInsets.all(5), // Um espacinho da borda
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.7), // Fundo branco meio transparente (igual Leaflet)
          borderRadius: BorderRadius.circular(4),
        ),
        child: GestureDetector(
          // Mantemos o link clicável para cumprir a regra
          onTap: () => launchUrl(Uri.parse('https://openstreetmap.org/copyright')),
          child: const Text(
            '© OpenStreetMap contributors',
            style: TextStyle(
              fontSize: 12, // Letra pequena e discreta
              color: Colors.blue, // Azul para indicar que é um link
              decoration: TextDecoration.underline, // Sublinhado opcional
              ),
            ),
          ),
        ),
      ),
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
  final Function(String) onSearchOnline;

  MapSearchDelegate({required this.onSearchOnline,required this.points, required this.categoriesAndColors});

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
            title: Text('Buscar endereço "$query" na web'),
            onTap: () {
              close(context, null); // 1. Fecha a barra de pesquisa
              onSearchOnline(query);
            }
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