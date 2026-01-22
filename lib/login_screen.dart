import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'main.dart';

// Usamos um StatefulWidget porque os campos de texto precisam de "controladores"
// que guardam o que o usuário digita, e isso envolve gerenciar um estado.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Controladores para ler o texto dos campos de Email e Senha
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

 Future<void> _fazerLogin() async {
    // Usamos .trim() para remover espaços em branco acidentais
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    // Bloco try-catch para lidar com possíveis erros (senha errada, etc.)
    try {
      // Usa o pacote do Firebase Auth para fazer o login
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      print('DEBUG: Login bem-sucedido! Navegando para a MapScreen...');

      // Se o login for bem-sucedido, navega para a tela do mapa
      // Usamos pushReplacement para que o usuário не possa voltar para a tela de login
      if (mounted) { // Verificação de segurança
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const MapScreen()),
        );
      }
    } on FirebaseAuthException catch (e) {
      // Se der erro, mostra uma mensagem para o usuário
      if (mounted) { // Verificação de segurança
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Falha no login: ${e.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login de Administrador'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [

            Image.asset(
              'assets/icon/app_icon.png', // Caminho da imagem
              height: 120, // Tamanho da logo
              width: 120,
            ),
            const SizedBox(height: 30),

            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16.0),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Senha',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 24.0),
            ElevatedButton(
              onPressed: _fazerLogin,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              child: const Text('Entrar'),
            ),

            // --- NOVO BOTÃO ADICIONADO AQUI ---
            const SizedBox(height: 16.0),
            TextButton(
              onPressed: () {
                // Navega para o mapa sem fazer login
                // O MapScreen vai identificar que não há usuário e
                // automaticamente entrará em modo "visitante" (isAdmin = false)
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (context) => const MapScreen()),
                );
              },
              child: const Text('Continuar como Visitante'),
            ),
            // --- FIM DO NOVO BOTÃO ---
          ],
        ),
      ),
    );
  }
}