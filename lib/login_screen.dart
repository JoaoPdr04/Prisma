import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/gestures.dart'; // Para links clicáveis
import 'package:url_launcher/url_launcher.dart'; // Para abrir navegador

// Importe suas telas aqui
import 'main.dart'; // Para MapScreen (ou HomeScreen)
import 'signup_screen.dart'; // Tela de cadastro

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Controladores
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  
  // Variáveis de Estado
  bool _concordouComTermos = false;
  bool _isLoading = false; // Loading geral (Email/Google)
  bool _isLoadingVisitante = false; // Loading específico do Visitante

  // Links dos Termos (RAW)
  final String _urlTermos = 'https://raw.githubusercontent.com/JoaoPdr04/Prisma/refs/heads/main/docs/TERMOS.md';
  final String _urlPrivacidade = 'https://raw.githubusercontent.com/JoaoPdr04/Prisma/refs/heads/main/docs/PRIVACIDADE.md';

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // --- FUNÇÕES AUXILIARES ---

  Future<void> _abrirLink(String url) async {
    final Uri uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // Verifica/Cria usuário no Firestore (para Google)
  Future<void> _checkAndCreateUserInFirestore(User user) async {
    final userDocRef = FirebaseFirestore.instance.collection('usuarios').doc(user.uid);
    final docSnapshot = await userDocRef.get();

    if (!docSnapshot.exists) {
      await userDocRef.set({
        'uid': user.uid,
        'email': user.email,
        'nome': user.displayName ?? 'Usuário Google',
        'foto_url': user.photoURL ?? '',
        'cargo': 'leitor',
        'criado_em': FieldValue.serverTimestamp(),
      });
    }
  }

  // --- LOGIN COM GOOGLE ---
  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      // 1. Abre a janelinha do Google
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return; // Usuário cancelou
      }

      // 2. Autenticação
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // 3. Login no Firebase
      final UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);

      // 4. Salva no Banco e Navega
      if (userCredential.user != null) {
        await _checkAndCreateUserInFirestore(userCredential.user!);
        
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const MapScreen())
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro Google: $e'), backgroundColor: Colors.red)
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- LOGIN COM EMAIL ---
  Future<void> _signInWithEmail() async {
    // 1. Validações básicas
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha email e senha.'), backgroundColor: Colors.orange)
      );
      return;
    }

    if (!_concordouComTermos) {
       ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aceite os termos para continuar.'), backgroundColor: Colors.red)
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final user = credential.user;

      if (user != null) {
        // 2. Verifica se validou o email
        if (!user.emailVerified) {
          await FirebaseAuth.instance.signOut();
          if (mounted) {
            _mostrarDialogoEmailNaoVerificado(user);
          }
          setState(() => _isLoading = false);
          return;
        }

        // 3. Sucesso
        await _checkAndCreateUserInFirestore(user);
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const MapScreen())
          );
        }
      }
    } catch (e) {
      String msg = 'Erro ao entrar.';
      if (e.toString().contains('user-not-found') || 
          e.toString().contains('wrong-password') || 
          e.toString().contains('invalid-credential')) {
        msg = 'Email ou senha incorretos.';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red)
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _mostrarDialogoEmailNaoVerificado(User user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Email não verificado'),
        content: const Text('Você precisa clicar no link enviado ao seu email antes de entrar.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
          TextButton(
            onPressed: () async {
              await user.sendEmailVerification();
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Email reenviado!'))
                );
              }
            },
            child: const Text('Reenviar Email'),
          ),
        ],
      ),
    );
  }

  // --- INTERFACE (BUILD) ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Image.asset(
                'assets/icon/app_icon.png', 
                height: 120, 
                width: 120, 
                errorBuilder: (c,e,s) => const Icon(Icons.map, size: 100, color: Colors.blue)
              ),
              const SizedBox(height: 20),
              const Text('Bem-vindo ao Prisma', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 40),

              // Inputs de Texto
              TextField(
                controller: _emailController, 
                decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder(), prefixIcon: Icon(Icons.email)), 
                keyboardType: TextInputType.emailAddress
              ),
              const SizedBox(height: 16),
              
              TextField(
                controller: _passwordController, 
                decoration: const InputDecoration(labelText: 'Senha', border: OutlineInputBorder(), prefixIcon: Icon(Icons.lock)), 
                obscureText: true
              ),
              const SizedBox(height: 20),

              // Checkbox de Termos (Vem antes dos botões de ação)
              Row(
                children: [
                  SizedBox(
                    height: 24, 
                    width: 24,
                    child: Checkbox(
                      value: _concordouComTermos,
                      activeColor: Colors.blue,
                      onChanged: (bool? valor) {
                        setState(() {
                          _concordouComTermos = valor ?? false;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(color: Colors.black, fontSize: 12),
                        children: [
                          const TextSpan(text: 'Li e aceito os '),
                          TextSpan(
                            text: 'Termos de Uso',
                            style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                            recognizer: TapGestureRecognizer()..onTap = () => _abrirLink(_urlTermos),
                          ),
                          const TextSpan(text: ' e '),
                          TextSpan(
                            text: 'Política de Privacidade',
                            style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                            recognizer: TapGestureRecognizer()..onTap = () => _abrirLink(_urlPrivacidade),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Se estiver carregando (Login ou Google), mostra spinner
              if (_isLoading) 
                const CircularProgressIndicator() 
              else ...[
                // Botão Entrar (Email)
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _signInWithEmail,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                    child: const Text('Entrar', style: TextStyle(fontSize: 16)),
                  ),
                ),
                
                const SizedBox(height: 20),
                const Row(children: [Expanded(child: Divider()), Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text("OU")), Expanded(child: Divider())]),
                const SizedBox(height: 20),

                // Botão Google
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    icon: Image.network('https://cdn1.iconfinder.com/data/icons/google-s-logo/150/Google_Icons-09-512.png', height: 24, errorBuilder: (c,e,s) => const Icon(Icons.login)), 
                    label: const Text('Entrar com Google', style: TextStyle(fontSize: 16)),
                    onPressed: () async {
                      // 1. A TRAVA
                      if (!_concordouComTermos) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Para continuar, aceite os Termos de Uso.'), backgroundColor: Colors.red),
                        );
                        return;
                      }
                      // 2. A AÇÃO
                      await _signInWithGoogle();
                    },
                  ),
                ),
              ],

              const SizedBox(height: 20),
              
              // Link para criar conta
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Não tem conta?'),
                  TextButton(
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const SignUpScreen()));
                    },
                    child: const Text('Criar conta agora', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              
              const SizedBox(height: 10),

              // Botão Visitante Inteligente
              ElevatedButton(
                onPressed: _isLoadingVisitante ? null : () async {
                  setState(() { _isLoadingVisitante = true; });

                  try {
                    // Verifica se já tem user (Logado ou Visitante anterior)
                    final userAtual = FirebaseAuth.instance.currentUser;

                    if (userAtual != null) {
                      print("Usuário detectado: ${userAtual.uid}. Redirecionando...");
                      if (mounted) {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (context) => const MapScreen()), 
                        );
                      }
                      return; 
                    }

                    // Se não tem, cria visitante novo
                    print("Criando novo visitante...");
                    await FirebaseAuth.instance.signInAnonymously();
                    
                    if (mounted) {
                       Navigator.of(context).pushReplacement(
                         MaterialPageRoute(builder: (context) => const MapScreen()), 
                       );
                    }
                  } catch (e) {
                    if (mounted) {
                      setState(() { _isLoadingVisitante = false; });
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
                    }
                  }
                },
                child: _isLoadingVisitante 
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text("Entrar como Visitante"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}