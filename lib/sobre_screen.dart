import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class SobreScreen extends StatelessWidget {
  const SobreScreen({super.key});

  // 👇 ATUALIZE COM SEUS LINKS RAW AQUI TAMBÉM
  final String _urlTermos = 'https://raw.githubusercontent.com/JoaoPdr04/Prisma/refs/heads/main/docs/TERMOS.md';
  final String _urlPrivacidade = 'https://raw.githubusercontent.com/JoaoPdr04/Prisma/refs/heads/main/docs/PRIVACIDADE.md';
  final String _urlOSM = 'https://www.openstreetmap.org/copyright';

  Future<void> _abrirLink(String url) async {
    final Uri uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Sobre o Prisma")),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              children: [
                Icon(Icons.map_rounded, size: 80, color: Colors.blue),
                SizedBox(height: 16),
                Text(
                  "Prisma",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                Text("Mapeador de Qualidade de Vida v1.2.0"),
              ],
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text("Termos de Uso"),
            trailing: const Icon(Icons.arrow_forward_ios, size: 14),
            onTap: () => _abrirLink(_urlTermos),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text("Política de Privacidade"),
            trailing: const Icon(Icons.arrow_forward_ios, size: 14),
            onTap: () => _abrirLink(_urlPrivacidade),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.public),
            title: const Text("Dados do Mapa"),
            subtitle: const Text("© Colaboradores do OpenStreetMap"),
            trailing: const Icon(Icons.open_in_new, size: 14),
            onTap: () => _abrirLink(_urlOSM),
          ),
        ],
      ),
    );
  }
}