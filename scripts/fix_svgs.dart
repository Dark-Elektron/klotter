import 'dart:io';

void main() {
  final templatePath = 'assets/imgs/background_classic.svg';
  final templateFile = File(templatePath);

  if (!templateFile.existsSync()) {
    // ignore: avoid_print
    print('Template file not found: $templatePath');
    return;
  }

  final content = templateFile.readAsStringSync();

  final themes = {
    'dark': {
      'bg': 'rgb(0, 0, 0)',
      'sym': 'rgb(34, 34, 34)',
      'sym_hex': '#222222',
    },
    'pink': {
      'bg': 'rgb(45, 36, 38)',
      'sym': 'rgb(94, 75, 78)',
      'sym_hex': '#5E4B4E',
    },
    'soft_pink': {
      'bg': 'rgb(251, 228, 228)',
      'sym': 'rgb(242, 196, 196)',
      'sym_hex': '#F2C4C4',
    },
    'sunset_ember': {
      'bg': 'rgb(45, 27, 27)',
      'sym': 'rgb(93, 64, 55)',
      'sym_hex': '#5D4037',
    },
    'desert_sand': {
      'bg': 'rgb(244, 235, 210)',
      'sym': 'rgb(193, 138, 99)',
      'sym_hex': '#C18A63',
    },
    'digital_amber': {
      'bg': 'rgb(0, 0, 0)',
      'sym': 'rgb(62, 39, 35)',
      'sym_hex': '#3E2723',
    },
    'rose_chic': {
      'bg': 'rgb(44, 44, 44)',
      'sym': 'rgb(96, 32, 42)',
      'sym_hex': '#60202A',
    },
    'honey_mustard': {
      'bg': 'rgb(255, 245, 197)',
      'sym': 'rgb(197, 165, 126)',
      'sym_hex': '#C5A57E',
    },
    'forest_moss': {
      'bg': 'rgb(232, 240, 229)',
      'sym': 'rgb(74, 103, 65)',
      'sym_hex': '#4A6741',
    },
  };

  for (final entry in themes.entries) {
    final name = entry.key;
    final colors = entry.value;

    var newContent = content.replaceAll('rgb(99, 99, 99)', colors['bg']!);
    newContent = newContent.replaceAll('rgb(74, 74, 74)', colors['sym']!);
    newContent = newContent.replaceAll('#4a4a4a', colors['sym_hex']!);

    final outputPath = 'assets/imgs/background_$name.svg';
    File(outputPath).writeAsStringSync(newContent);
    // ignore: avoid_print
    print('Created $outputPath');
  }
}
