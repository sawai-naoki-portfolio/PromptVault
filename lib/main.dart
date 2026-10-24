import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/prompt_repository.dart';
import 'providers/app_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 完全ローカル管理。ここで開く Hive の box が唯一の保存先で、
  // プロンプト本文がネットワークに出る経路はアプリ内に存在しない。
  await Hive.initFlutter();
  final box = await PromptRepository.openBox();
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        promptRepositoryProvider.overrideWithValue(PromptRepository(box)),
      ],
      child: const PromptVaultApp(),
    ),
  );
}
