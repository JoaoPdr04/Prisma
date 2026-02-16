import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main.dart'; // Para MapScreen
import 'signup_screen.dart'; // IMPORTANTE: Importe a nova tela de cadastro

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  // Verifica se o usuário existe no Firestore (para login com Google)
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

  // --- LOGIN COM GOOGLE (O Google já verifica o email automaticamente) ---
  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);

      if (userCredential.user != null) {
        await _checkAndCreateUserInFirestore(userCredential.user!);
        if (mounted) {
          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => const MapScreen()));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro Google: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- LOGIN COM EMAIL (Agora verifica se o email foi validado) ---
  Future<void> _signInWithEmail() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preencha email e senha.'), backgroundColor: Colors.orange));
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
        // --- TRAVA DE SEGURANÇA: EMAIL VERIFICADO? ---
        if (!user.emailVerified) {
          await FirebaseAuth.instance.signOut(); // Desloga imediatamente
          if (mounted) {
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
                      await user.sendEmailVerification(); // Reenviar email
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email reenviado!')));
                    },
                    child: const Text('Reenviar Email'),
                  ),
                ],
              ),
            );
          }
          setState(() => _isLoading = false);
          return;
        }

        // Se verificado, entra no app
        await _checkAndCreateUserInFirestore(user); // Garante que tem doc no banco
        if (mounted) {
          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => const MapScreen()));
        }
      }
    } catch (e) {
      String msg = 'Erro ao entrar.';
      if (e.toString().contains('user-not-found') || e.toString().contains('wrong-password') || e.toString().contains('invalid-credential')) {
        msg = 'Email ou senha incorretos.';
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/icon/app_icon.png', height: 120, width: 120, errorBuilder: (c,e,s) => const Icon(Icons.map, size: 100, color: Colors.blue)),
              const SizedBox(height: 20),
              const Text('Bem-vindo ao Mapeador', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 40),

              if (_isLoading) const CircularProgressIndicator() else ...[
                // Botão Google
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    icon: Image.network('https://cdn1.iconfinder.com/data/icons/google-s-logo/150/Google_Icons-09-512.png', height: 24, errorBuilder: (c,e,s) => const Icon(Icons.login)), 
                    label: const Text('Entrar com Google', style: TextStyle(fontSize: 16)),
                    onPressed: _signInWithGoogle,
                  ),
                ),
                
                const SizedBox(height: 20),
                const Row(children: [Expanded(child: Divider()), Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text("OU")), Expanded(child: Divider())]),
                const SizedBox(height: 20),

                TextField(controller: _emailController, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder(), prefixIcon: Icon(Icons.email)), keyboardType: TextInputType.emailAddress),
                const SizedBox(height: 16),
                TextField(controller: _passwordController, decoration: const InputDecoration(labelText: 'Senha', border: OutlineInputBorder(), prefixIcon: Icon(Icons.lock)), obscureText: true),
                const SizedBox(height: 24),
                
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
                
                // MUDANÇA AQUI: Botão leva para a tela nova
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
                
                TextButton(
                  onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => const MapScreen())),
                  child: const Text('Entrar como Visitante (Sem Login)'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}