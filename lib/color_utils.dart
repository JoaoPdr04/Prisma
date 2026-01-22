import 'package:flutter/material.dart';

class ColorUtils {
  /// Converte uma string de cor Hex (ex: "#FF0000" ou "FF0000") para um objeto Color.
  static Color fromHex(String hexString) {
    try {
      final buffer = StringBuffer();
      if (hexString.length == 6 || hexString.length == 7) {
        buffer.write('ff'); // Adiciona o canal alfa (opacidade total)
      }
      buffer.write(hexString.replaceFirst('#', ''));
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (e) {
      // Retorna uma cor padrão (cinza) se a conversão falhar
      return Colors.grey;
    }
  }
}
