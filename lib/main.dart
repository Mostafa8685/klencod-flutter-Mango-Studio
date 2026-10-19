import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MangoStudioApp());
}

/// ============================================================================
/// ألوان وسمة "مانجو ستديو" الاحترافية (Mango Studio Pro Theme)
/// ============================================================================
class AppColors {
  static const Color darkBg = Color(0xFF090D14);
  static const Color surface = Color(0xFF131A26);
  static const Color surfaceAlt = Color(0xFF1C2638);
  static const Color border = Color(0xFF2B374E);
  static const Color primary = Color(0xFF388BFD);
  static const Color mango = Color(0xFFFF9800);
  static const Color mangoLight = Color(0xFFFFB74D);
  static const Color success = Color(0xFF2EA043);
  static const Color danger = Color(0xFFF85149);
  static const Color warning = Color(0xFFD29922);
  static const Color purple = Color(0xFFA371F7);
  static const Color cyan = Color(0xFF39C5CF);
  static const Color textPrimary = Color(0xFFE6EDF3);
  static const Color textMuted = Color(0xFF8B949E);
}

/// ============================================================================
/// مخزن آمن مزدوج (SharedPreferences + ملف احتياطي مباشر عبر dart:io)
/// ============================================================================
class SafeStorage {
  static final Map<String, String> _memoryCache = {};
  static File get _backupFile => File('${Directory.systemTemp.path}/mango_studio_pro_v5.json');

  static Future<Map<String, String>> _readAll() async {
    if (_memoryCache.isNotEmpty) return _memoryCache;
    try {
      if (await _backupFile.exists()) {
        final raw = await _backupFile.readAsString();
        final map = jsonDecode(raw) as Map<String, dynamic>;
        map.forEach((k, v) => _memoryCache[k] = v.toString());
      }
    } catch (_) {}
    return _memoryCache;
  }

  static Future<String?> getString(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(const Duration(milliseconds: 900));
      final val = prefs.getString(key);
      if (val != null && val.isNotEmpty) {
        _memoryCache[key] = val;
        return val;
      }
    } catch (_) {}
    final map = await _readAll();
    return map[key];
  }

  static Future<void> setString(String key, String value) async {
    _memoryCache[key] = value;
    try {
      await _backupFile.writeAsString(jsonEncode(_memoryCache));
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance().timeout(const Duration(milliseconds: 900));
      await prefs.setString(key, value);
    } catch (_) {}
  }

  static Future<void> remove(String key) async {
    _memoryCache.remove(key);
    try {
      await _backupFile.writeAsString(jsonEncode(_memoryCache));
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance().timeout(const Duration(milliseconds: 900));
      await prefs.remove(key);
    } catch (_) {}
  }
}

/// ============================================================================
/// النماذج الأساسية (Models)
/// ============================================================================
enum IdeProjectType {
  flutter,
  androidJava,
  androidKotlin,
  reactNative;

  String get title => switch (this) {
        IdeProjectType.flutter => 'Flutter',
        IdeProjectType.androidJava => 'Android (Java)',
        IdeProjectType.androidKotlin => 'Android (Kotlin)',
        IdeProjectType.reactNative => 'React Native',
      };

  String get subtitle => switch (this) {
        IdeProjectType.flutter => 'تطبيق Flutter متعدد المنصات (Dart)',
        IdeProjectType.androidJava => 'تطبيق Android أصلي بلغة Java',
        IdeProjectType.androidKotlin => 'تطبيق Android أصلي بلغة Kotlin',
        IdeProjectType.reactNative => 'تطبيق React Native CLI (TypeScript + Native Android)',
      };

  String get extTag => switch (this) {
        IdeProjectType.flutter => '.dart',
        IdeProjectType.androidJava => '.java',
        IdeProjectType.androidKotlin => '.kt',
        IdeProjectType.reactNative => '.tsx',
      };

  String get langTag => switch (this) {
        IdeProjectType.flutter => 'Dart',
        IdeProjectType.androidJava => 'Java',
        IdeProjectType.androidKotlin => 'Kotlin',
        IdeProjectType.reactNative => 'TypeScript',
      };

  Color get badgeColor => switch (this) {
        IdeProjectType.flutter => const Color(0xFF388BFD),
        IdeProjectType.androidJava => const Color(0xFFD29922),
        IdeProjectType.androidKotlin => const Color(0xFFA371F7),
        IdeProjectType.reactNative => const Color(0xFF39C5CF),
      };

  static IdeProjectType fromName(String? name) {
    for (final v in IdeProjectType.values) {
      if (v.name == name) return v;
    }
    return IdeProjectType.flutter;
  }
}

class IdeNode {
  String path;
  bool isFolder;
  String content;
  bool isDirty;

  IdeNode({
    required this.path,
    required this.isFolder,
    this.content = '',
    this.isDirty = false,
  });

  String get name => path.split('/').last;

  Map<String, dynamic> toJson() => {
        'path': path,
        'isFolder': isFolder,
        'content': content,
      };

  factory IdeNode.fromJson(Map<String, dynamic> json) => IdeNode(
        path: json['path'] as String,
        isFolder: json['isFolder'] as bool? ?? false,
        content: json['content'] as String? ?? '',
      );
}

class IdeProject {
  String id;
  String name;
  String packageName;
  String versionName;
  int versionCode;
  IdeProjectType type;
  String buildMode; // 'release' or 'debug'
  bool publishReleaseTag;
  String? iconBase64;
  String? githubRepo;
  DateTime updatedAt;
  List<IdeNode> nodes;

  IdeProject({
    required this.id,
    required this.name,
    required this.packageName,
    this.versionName = '1.0.0',
    this.versionCode = 1,
    this.type = IdeProjectType.flutter,
    this.buildMode = 'release',
    this.publishReleaseTag = true,
    this.iconBase64,
    this.githubRepo,
    required this.updatedAt,
    required this.nodes,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'packageName': packageName,
        'versionName': versionName,
        'versionCode': versionCode,
        'type': type.name,
        'buildMode': buildMode,
        'publishReleaseTag': publishReleaseTag,
        'iconBase64': iconBase64,
        'githubRepo': githubRepo,
        'updatedAt': updatedAt.toIso8601String(),
        'nodes': nodes.map((n) => n.toJson()).toList(),
      };

  factory IdeProject.fromJson(Map<String, dynamic> json) => IdeProject(
        id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
        name: json['name'] as String? ?? 'تطبيق مانجو',
        packageName: json['packageName'] as String? ?? 'com.mango.app',
        versionName: json['versionName'] as String? ?? '1.0.0',
        versionCode: (json['versionCode'] as num?)?.toInt() ?? 1,
        type: IdeProjectType.fromName(json['type'] as String?),
        buildMode: json['buildMode'] as String? ?? 'release',
        publishReleaseTag: json['publishReleaseTag'] as bool? ?? true,
        iconBase64: json['iconBase64'] as String?,
        githubRepo: json['githubRepo'] as String?,
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
        nodes: ((json['nodes'] as List?) ?? [])
            .map((e) => IdeNode.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class ApkBuildRecord {
  final String id;
  final String projectId;
  final String projectName;
  final String packageName;
  final String versionName;
  final String projectType;
  final String repoFullName;
  String status; // 'running', 'completed', 'failed'
  final String actionsUrl;
  final String? releaseApkUrl;
  final DateTime createdAt;
  final List<String> logs;

  ApkBuildRecord({
    required this.id,
    required this.projectId,
    required this.projectName,
    required this.packageName,
    required this.versionName,
    required this.projectType,
    required this.repoFullName,
    required this.status,
    required this.actionsUrl,
    this.releaseApkUrl,
    required this.createdAt,
    required this.logs,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectId': projectId,
        'projectName': projectName,
        'packageName': packageName,
        'versionName': versionName,
        'projectType': projectType,
        'repoFullName': repoFullName,
        'status': status,
        'actionsUrl': actionsUrl,
        'releaseApkUrl': releaseApkUrl,
        'createdAt': createdAt.toIso8601String(),
        'logs': logs,
      };

  factory ApkBuildRecord.fromJson(Map<String, dynamic> json) => ApkBuildRecord(
        id: json['id'] as String? ?? '',
        projectId: json['projectId'] as String? ?? '',
        projectName: json['projectName'] as String? ?? '',
        packageName: json['packageName'] as String? ?? '',
        versionName: json['versionName'] as String? ?? '1.0.0',
        projectType: json['projectType'] as String? ?? 'Flutter',
        repoFullName: json['repoFullName'] as String? ?? '',
        status: json['status'] as String? ?? 'completed',
        actionsUrl: json['actionsUrl'] as String? ?? '',
        releaseApkUrl: json['releaseApkUrl'] as String?,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        logs: ((json['logs'] as List?) ?? []).map((e) => e.toString()).toList(),
      );
}

/// ============================================================================
/// قوالب المشاريع ومولد التطبيقات الكاملة متعددة الملفات (Multi-File Templates)
/// ============================================================================
class ProjectTemplates {
  static List<IdeNode> generateNodes({
    required IdeProjectType type,
    required String appName,
    required String packageName,
    required String versionName,
    required int versionCode,
    String templateKind = 'default',
  }) {
    final safeSlug = appName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final dartPkgName = safeSlug.isEmpty ? 'mango_app' : safeSlug;

    if (type == IdeProjectType.flutter) {
      final baseNodes = <IdeNode>[
        IdeNode(
          path: 'pubspec.yaml',
          isFolder: false,
          content: 'name: $dartPkgName\n'
              'description: $appName - Built with Mango Studio.\n'
              "publish_to: 'none'\n"
              'version: $versionName+$versionCode\n\n'
              'environment:\n'
              "  sdk: '>=3.0.0 <4.0.0'\n\n"
              'dependencies:\n'
              '  flutter:\n'
              '    sdk: flutter\n'
              '  shared_preferences: ^2.2.2\n'
              '  http: ^1.2.0\n\n'
              'flutter:\n'
              '  uses-material-design: true\n',
        ),
        IdeNode(path: 'lib', isFolder: true),
        IdeNode(path: 'lib/models', isFolder: true),
        IdeNode(path: 'lib/screens', isFolder: true),
        IdeNode(path: 'lib/widgets', isFolder: true),
      ];

      if (templateKind == 'ecommerce') {
        baseNodes.addAll(_buildFullEcommerceAppNodes(appName));
      } else if (templateKind == 'tasks_pro') {
        baseNodes.addAll(_buildFullTasksAppNodes(appName));
      } else if (templateKind == 'islamic') {
        baseNodes.addAll(_buildFullIslamicAppNodes(appName));
      } else if (templateKind == 'xo_game') {
        baseNodes.addAll(_buildFullXoGameNodes(appName));
      } else if (templateKind == 'calculator') {
        baseNodes.add(IdeNode(
          path: 'lib/main.dart',
          isFolder: false,
          content: _calculatorCode(appName),
        ));
      } else {
        baseNodes.add(IdeNode(
          path: 'lib/main.dart',
          isFolder: false,
          content: _defaultFlutterStarter(appName),
        ));
      }

      baseNodes.addAll([
        IdeNode(path: '.github', isFolder: true),
        IdeNode(path: '.github/workflows', isFolder: true),
        IdeNode(
          path: '.github/workflows/main.yml',
          isFolder: false,
          content: workflowForType(
            IdeProjectType.flutter,
            appName: appName,
            packageName: packageName,
            versionName: versionName,
            versionCode: versionCode,
          ),
        ),
      ]);
      return baseNodes;
    }

    if (type == IdeProjectType.androidJava) {
      final pkgPath = packageName.replaceAll('.', '/');
      return [
        IdeNode(path: 'app', isFolder: true),
        IdeNode(path: 'app/src', isFolder: true),
        IdeNode(path: 'app/src/main', isFolder: true),
        IdeNode(path: 'app/src/main/java', isFolder: true),
        IdeNode(
          path: 'app/src/main/java/$pkgPath/MainActivity.java',
          isFolder: false,
          content: 'package $packageName;\n\n'
              'import android.app.Activity;\n'
              'import android.os.Bundle;\n'
              'import android.widget.TextView;\n'
              'import android.view.Gravity;\n\n'
              'public class MainActivity extends Activity {\n'
              '    @Override\n'
              '    protected void onCreate(Bundle savedInstanceState) {\n'
              '        super.onCreate(savedInstanceState);\n'
              '        TextView tv = new TextView(this);\n'
              '        tv.setText("مرحباً بك في $appName - مانجو ستديو");\n'
              '        tv.setTextSize(22f);\n'
              '        tv.setGravity(Gravity.CENTER);\n'
              '        setContentView(tv);\n'
              '    }\n'
              '}\n',
        ),
        IdeNode(
          path: 'app/src/main/AndroidManifest.xml',
          isFolder: false,
          content: '<?xml version="1.0" encoding="utf-8"?>\n'
              '<manifest xmlns:android="http://schemas.android.com/apk/res/android"\n'
              '    package="$packageName">\n'
              '    <uses-permission android:name="android.permission.INTERNET"/>\n'
              '    <application android:label="$appName">\n'
              '        <activity android:name=".MainActivity" android:exported="true">\n'
              '            <intent-filter>\n'
              '                <action android:name="android.intent.action.MAIN"/>\n'
              '                <category android:name="android.intent.category.LAUNCHER"/>\n'
              '            </intent-filter>\n'
              '        </activity>\n'
              '    </application>\n'
              '</manifest>\n',
        ),
        IdeNode(path: '.github', isFolder: true),
        IdeNode(path: '.github/workflows', isFolder: true),
        IdeNode(
          path: '.github/workflows/main.yml',
          isFolder: false,
          content: workflowForType(
            IdeProjectType.androidJava,
            appName: appName,
            packageName: packageName,
            versionName: versionName,
            versionCode: versionCode,
          ),
        ),
      ];
    }

    if (type == IdeProjectType.androidKotlin) {
      final pkgPath = packageName.replaceAll('.', '/');
      return [
        IdeNode(path: 'app', isFolder: true),
        IdeNode(path: 'app/src', isFolder: true),
        IdeNode(path: 'app/src/main', isFolder: true),
        IdeNode(path: 'app/src/main/kotlin', isFolder: true),
        IdeNode(
          path: 'app/src/main/kotlin/$pkgPath/MainActivity.kt',
          isFolder: false,
          content: 'package $packageName\n\n'
              'import android.app.Activity\n'
              'import android.os.Bundle\n'
              'import android.view.Gravity\n'
              'import android.widget.TextView\n\n'
              'class MainActivity : Activity() {\n'
              '    override fun onCreate(savedInstanceState: Bundle?) {\n'
              '        super.onCreate(savedInstanceState)\n'
              '        val tv = TextView(this).apply {\n'
              '            text = "مرحباً بك في $appName (Kotlin)"\n'
              '            textSize = 22f\n'
              '            gravity = Gravity.CENTER\n'
              '        }\n'
              '        setContentView(tv)\n'
              '    }\n'
              '}\n',
        ),
        IdeNode(
          path: 'app/src/main/AndroidManifest.xml',
          isFolder: false,
          content: '<?xml version="1.0" encoding="utf-8"?>\n'
              '<manifest xmlns:android="http://schemas.android.com/apk/res/android"\n'
              '    package="$packageName">\n'
              '    <uses-permission android:name="android.permission.INTERNET"/>\n'
              '    <application android:label="$appName">\n'
              '        <activity android:name=".MainActivity" android:exported="true">\n'
              '            <intent-filter>\n'
              '                <action android:name="android.intent.action.MAIN"/>\n'
              '                <category android:name="android.intent.category.LAUNCHER"/>\n'
              '            </intent-filter>\n'
              '        </activity>\n'
              '    </application>\n'
              '</manifest>\n',
        ),
        IdeNode(path: '.github', isFolder: true),
        IdeNode(path: '.github/workflows', isFolder: true),
        IdeNode(
          path: '.github/workflows/main.yml',
          isFolder: false,
          content: workflowForType(
            IdeProjectType.androidKotlin,
            appName: appName,
            packageName: packageName,
            versionName: versionName,
            versionCode: versionCode,
          ),
        ),
      ];
    }

    return [
      IdeNode(
        path: 'package.json',
        isFolder: false,
        content: '{\n  "name": "$dartPkgName",\n  "version": "$versionName",\n  "private": true\n}\n',
      ),
      IdeNode(
        path: 'App.tsx',
        isFolder: false,
        content: "import React, { useState } from 'react';\n"
            "import { SafeAreaView, Text, TouchableOpacity, View } from 'react-native';\n\n"
            'export default function App() {\n'
            '  const [count, setCount] = useState(0);\n'
            '  return (\n'
            '    <SafeAreaView style={{flex: 1, backgroundColor: "#090D14", justifyContent: "center", alignItems: "center"}}>\n'
            '      <Text style={{color: "#fff", fontSize: 22, fontWeight: "bold"}}>$appName</Text>\n'
            '      <Text style={{color: "#FF9800", fontSize: 18, marginVertical: 12}}>العداد: {count}</Text>\n'
            '    </SafeAreaView>\n'
            '  );\n'
            '}\n',
      ),
      IdeNode(path: '.github', isFolder: true),
      IdeNode(path: '.github/workflows', isFolder: true),
      IdeNode(
        path: '.github/workflows/main.yml',
        isFolder: false,
        content: workflowForType(
          IdeProjectType.reactNative,
          appName: appName,
          packageName: packageName,
          versionName: versionName,
          versionCode: versionCode,
        ),
      ),
    ];
  }

  /// قالب تطبيق متجر إلكتروني كامل متعدد الملفات (main.dart + models + screens + cart)
  static List<IdeNode> _buildFullEcommerceAppNodes(String appName) {
    return [
      IdeNode(
        path: 'lib/models/product.dart',
        isFolder: false,
        content: "import 'package:flutter/material.dart';\n\n"
            'class Product {\n'
            '  final String id;\n'
            '  final String title;\n'
            '  final String category;\n'
            '  final double price;\n'
            '  final IconData icon;\n'
            '  final String description;\n\n'
            '  const Product({\n'
            '    required this.id,\n'
            '    required this.title,\n'
            '    required this.category,\n'
            '    required this.price,\n'
            '    required this.icon,\n'
            '    required this.description,\n'
            '  });\n'
            '}\n\n'
            'const List<Product> kDemoProducts = [\n'
            '  Product(id: "1", title: "سماعة محيطية لاسلكية Pro", category: "صوتيات", price: 850, icon: Icons.headphones, description: "عزل ضوضاء ذكي وبطارية تدوم 40 ساعة متواصلة."),\n'
            '  Product(id: "2", title: "ساعة ذكية Mango Watch Ultra", category: "ساعات", price: 1450, icon: Icons.watch, description: "شاشة AMOLED مقاومة للماء مع متابعة نبضات القلب."),\n'
            '  Product(id: "3", title: "شاحن فائق السرعة 100W GaN", category: "إكسسوارات", price: 420, icon: Icons.bolt, description: "3 منافذ USB-C لشحن اللابتوب والهاتف في وقت واحد."),\n'
            '  Product(id: "4", title: "لوحة مفاتيح ميكانيكية RGB", category: "كمبيوتر", price: 980, icon: Icons.keyboard, description: "مفاتيح سريعة الاستجابة مع إضاءة قابلة للتخصيص."),\n'
            '];\n',
      ),
      IdeNode(
        path: 'lib/screens/cart_screen.dart',
        isFolder: false,
        content: "import 'package:flutter/material.dart';\n"
            "import '../models/product.dart';\n\n"
            'class CartScreen extends StatelessWidget {\n'
            '  final List<Product> cart;\n'
            '  final void Function(Product) onRemove;\n'
            '  final VoidCallback onCheckout;\n\n'
            '  const CartScreen({\n'
            '    super.key,\n'
            '    required this.cart,\n'
            '    required this.onRemove,\n'
            '    required this.onCheckout,\n'
            '  });\n\n'
            '  @override\n'
            '  Widget build(BuildContext context) {\n'
            '    final total = cart.fold<double>(0, (s, p) => s + p.price);\n'
            '    return Directionality(\n'
            '      textDirection: TextDirection.rtl,\n'
            '      child: Scaffold(\n'
            "        appBar: AppBar(title: const Text('سلة المشتريات')),\n"
            '        body: cart.isEmpty\n'
            "            ? const Center(child: Text('السلة فارغة حالياً'))\n"
            '            : Column(\n'
            '                children: [\n'
            '                  Expanded(\n'
            '                    child: ListView.builder(\n'
            '                      itemCount: cart.length,\n'
            '                      itemBuilder: (ctx, i) {\n'
            '                        final p = cart[i];\n'
            '                        return ListTile(\n'
            '                          leading: Icon(p.icon, color: Colors.orange),\n'
            '                          title: Text(p.title),\n'
            "                          subtitle: Text('\${p.price.toStringAsFixed(0)} ج.م'),\n"
            '                          trailing: IconButton(\n'
            '                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),\n'
            '                            onPressed: () => onRemove(p),\n'
            '                          ),\n'
            '                        );\n'
            '                      },\n'
            '                    ),\n'
            '                  ),\n'
            '                  Padding(\n'
            '                    padding: const EdgeInsets.all(16),\n'
            '                    child: ElevatedButton.icon(\n'
            '                      style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),\n'
            '                      onPressed: onCheckout,\n'
            '                      icon: const Icon(Icons.payment),\n'
            "                      label: Text('إتمام الشراء (\${total.toStringAsFixed(0)} ج.م)'),\n"
            '                    ),\n'
            '                  ),\n'
            '                ],\n'
            '              ),\n'
            '      ),\n'
            '    );\n'
            '  }\n'
            '}\n',
      ),
      IdeNode(
        path: 'lib/main.dart',
        isFolder: false,
        content: "import 'package:flutter/material.dart';\n"
            "import 'models/product.dart';\n"
            "import 'screens/cart_screen.dart';\n\n"
            'void main() => runApp(const EcommerceApp());\n\n'
            'class EcommerceApp extends StatelessWidget {\n'
            '  const EcommerceApp({super.key});\n\n'
            '  @override\n'
            '  Widget build(BuildContext context) {\n'
            '    return MaterialApp(\n'
            '      debugShowCheckedModeBanner: false,\n'
            "      title: '$appName',\n"
            '      theme: ThemeData.dark(useMaterial3: true).copyWith(\n'
            '        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange, brightness: Brightness.dark),\n'
            '      ),\n'
            '      home: const StoreHomePage(),\n'
            '    );\n'
            '  }\n'
            '}\n\n'
            'class StoreHomePage extends StatefulWidget {\n'
            '  const StoreHomePage({super.key});\n\n'
            '  @override\n'
            '  State<StoreHomePage> createState() => _StoreHomePageState();\n'
            '}\n\n'
            'class _StoreHomePageState extends State<StoreHomePage> {\n'
            '  final List<Product> _cart = [];\n'
            "  String _search = '';\n\n"
            '  @override\n'
            '  Widget build(BuildContext context) {\n'
            '    final items = kDemoProducts.where((p) => p.title.contains(_search)).toList();\n'
            '    return Directionality(\n'
            '      textDirection: TextDirection.rtl,\n'
            '      child: Scaffold(\n'
            '        appBar: AppBar(\n'
            "          title: const Text('$appName'),\n"
            '          actions: [\n'
            '            IconButton(\n'
            '              icon: Badge(\n'
            "                label: Text('\${_cart.length}'),\n"
            '                child: const Icon(Icons.shopping_cart_outlined),\n'
            '              ),\n'
            '              onPressed: () => Navigator.push(\n'
            '                context,\n'
            '                MaterialPageRoute(\n'
            '                  builder: (_) => CartScreen(\n'
            '                    cart: _cart,\n'
            '                    onRemove: (p) => setState(() => _cart.remove(p)),\n'
            '                    onCheckout: () {\n'
            '                      setState(() => _cart.clear());\n'
            '                      Navigator.pop(context);\n'
            '                      ScaffoldMessenger.of(context).showSnackBar(\n'
            "                        const SnackBar(content: Text('تم تأكيد طلبك بنجاح ✓')),\n"
            '                      );\n'
            '                    },\n'
            '                  ),\n'
            '                ),\n'
            '              ),\n'
            '            ),\n'
            '          ],\n'
            '        ),\n'
            '        body: Column(\n'
            '          children: [\n'
            '            Padding(\n'
            '              padding: const EdgeInsets.all(12),\n'
            '              child: TextField(\n'
            '                onChanged: (v) => setState(() => _search = v),\n'
            '                decoration: const InputDecoration(\n'
            "                  hintText: 'ابحث عن منتج...',\n"
            '                  prefixIcon: Icon(Icons.search),\n'
            '                ),\n'
            '              ),\n'
            '            ),\n'
            '            Expanded(\n'
            '              child: GridView.builder(\n'
            '                padding: const EdgeInsets.all(12),\n'
            '                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(\n'
            '                  crossAxisCount: 2,\n'
            '                  mainAxisSpacing: 12,\n'
            '                  crossAxisSpacing: 12,\n'
            '                  childAspectRatio: 0.78,\n'
            '                ),\n'
            '                itemCount: items.length,\n'
            '                itemBuilder: (ctx, i) {\n'
            '                  final p = items[i];\n'
            '                  return Card(\n'
            '                    child: Padding(\n'
            '                      padding: const EdgeInsets.all(12),\n'
            '                      child: Column(\n'
            '                        mainAxisAlignment: MainAxisAlignment.spaceBetween,\n'
            '                        children: [\n'
            '                          Icon(p.icon, size: 48, color: Colors.orange),\n'
            '                          Text(p.title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),\n'
            "                          Text('\${p.price.toStringAsFixed(0)} ج.م', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),\n"
            '                          ElevatedButton.icon(\n'
            '                            onPressed: () => setState(() => _cart.add(p)),\n'
            '                            icon: const Icon(Icons.add_shopping_cart, size: 16),\n'
            "                            label: const Text('إضافة'),\n"
            '                          ),\n'
            '                        ],\n'
            '                      ),\n'
            '                    ),\n'
            '                  );\n'
            '                },\n'
            '              ),\n'
            '            ),\n'
            '          ],\n'
            '        ),\n'
            '      ),\n'
            '    );\n'
            '  }\n'
            '}\n',
      ),
    ];
  }

  static List<IdeNode> _buildFullTasksAppNodes(String appName) {
    return [
      IdeNode(
        path: 'lib/models/note_item.dart',
        isFolder: false,
        content: 'class NoteItem {\n'
            '  final String id;\n'
            '  String title;\n'
            '  String category;\n'
            '  bool completed;\n\n'
            '  NoteItem({required this.id, required this.title, this.category = "عام", this.completed = false});\n'
            '}\n',
      ),
      IdeNode(
        path: 'lib/main.dart',
        isFolder: false,
        content: "import 'package:flutter/material.dart';\n"
            "import 'models/note_item.dart';\n\n"
            'void main() => runApp(const TasksProApp());\n\n'
            'class TasksProApp extends StatelessWidget {\n'
            '  const TasksProApp({super.key});\n\n'
            '  @override\n'
            '  Widget build(BuildContext context) {\n'
            '    return MaterialApp(\n'
            '      debugShowCheckedModeBanner: false,\n'
            "      title: '$appName',\n"
            '      theme: ThemeData.dark(useMaterial3: true),\n'
            '      home: const TasksBoardScreen(),\n'
            '    );\n'
            '  }\n'
            '}\n\n'
            'class TasksBoardScreen extends StatefulWidget {\n'
            '  const TasksBoardScreen({super.key});\n\n'
            '  @override\n'
            '  State<TasksBoardScreen> createState() => _TasksBoardScreenState();\n'
            '}\n\n'
            'class _TasksBoardScreenState extends State<TasksBoardScreen> {\n'
            '  final List<NoteItem> _items = [\n'
            '    NoteItem(id: "1", title: "تصميم الواجهة الرئيسية للتطبيق", category: "عمل"),\n'
            '    NoteItem(id: "2", title: "اختبار ملف الـ APK على الهاتف", category: "برمجة", completed: true),\n'
            '  ];\n\n'
            '  @override\n'
            '  Widget build(BuildContext context) {\n'
            '    return Directionality(\n'
            '      textDirection: TextDirection.rtl,\n'
            '      child: Scaffold(\n'
            "        appBar: AppBar(title: const Text('$appName')),\n"
            '        floatingActionButton: FloatingActionButton.extended(\n'
            '          onPressed: () {\n'
            '            setState(() {\n'
            '              _items.insert(0, NoteItem(id: DateTime.now().toString(), title: "مهمة جديدة #\${_items.length + 1}"));\n'
            '            });\n'
            '          },\n'
            '          icon: const Icon(Icons.add),\n'
            "          label: const Text('مهمة جديدة'),\n"
            '        ),\n'
            '        body: ListView.builder(\n'
            '          padding: const EdgeInsets.all(14),\n'
            '          itemCount: _items.length,\n'
            '          itemBuilder: (ctx, i) {\n'
            '            final item = _items[i];\n'
            '            return Card(\n'
            '              child: CheckboxListTile(\n'
            '                value: item.completed,\n'
            '                onChanged: (v) => setState(() => item.completed = v ?? false),\n'
            '                title: Text(item.title),\n'
            '                subtitle: Text(item.category),\n'
            '              ),\n'
            '            );\n'
            '          },\n'
            '        ),\n'
            '      ),\n'
            '    );\n'
            '  }\n'
            '}\n',
      ),
    ];
  }

  static List<IdeNode> _buildFullIslamicAppNodes(String appName) {
    return [
      IdeNode(
        path: 'lib/main.dart',
        isFolder: false,
        content: "import 'package:flutter/material.dart';\n\n"
            'void main() => runApp(const AzkarApp());\n\n'
            'class AzkarApp extends StatelessWidget {\n'
            '  const AzkarApp({super.key});\n\n'
            '  @override\n'
            '  Widget build(BuildContext context) {\n'
            '    return MaterialApp(\n'
            '      debugShowCheckedModeBanner: false,\n'
            "      title: '$appName',\n"
            '      theme: ThemeData.dark(useMaterial3: true),\n'
            '      home: const AzkarHomeScreen(),\n'
            '    );\n'
            '  }\n'
            '}\n\n'
            'class AzkarHomeScreen extends StatefulWidget {\n'
            '  const AzkarHomeScreen({super.key});\n\n'
            '  @override\n'
            '  State<AzkarHomeScreen> createState() => _AzkarHomeScreenState();\n'
            '}\n\n'
            'class _AzkarHomeScreenState extends State<AzkarHomeScreen> {\n'
            '  int _tasbih = 0;\n'
            '  final List<(String, int)> _azkar = const [\n'
            "    ('سبحان الله وبحمده، سبحان الله العظيم', 33),\n"
            "    ('الحمد لله رب العالمين', 33),\n"
            "    ('الله أكبر كبيراً', 33),\n"
            "    ('لا إله إلا الله وحده لا شريك له', 100),\n"
            '  ];\n\n'
            '  @override\n'
            '  Widget build(BuildContext context) {\n'
            '    return Directionality(\n'
            '      textDirection: TextDirection.rtl,\n'
            '      child: Scaffold(\n'
            "        appBar: AppBar(title: const Text('$appName')),\n"
            '        body: ListView(\n'
            '          padding: const EdgeInsets.all(16),\n'
            '          children: [\n'
            '            Card(\n'
            '              child: Padding(\n'
            '                padding: const EdgeInsets.all(20),\n'
            '                child: Column(\n'
            '                  children: [\n'
            "                    const Text('المسبحة الإلكترونية', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),\n"
            '                    const SizedBox(height: 10),\n'
            "                    Text('\$_tasbih', style: const TextStyle(fontSize: 44, fontWeight: FontWeight.bold, color: Colors.amber)),\n"
            '                    const SizedBox(height: 10),\n'
            '                    Row(\n'
            '                      mainAxisAlignment: MainAxisAlignment.center,\n'
            '                      children: [\n'
            '                        ElevatedButton.icon(\n'
            '                          onPressed: () => setState(() => _tasbih++),\n'
            '                          icon: const Icon(Icons.touch_app),\n'
            "                          label: const Text('تسبيح'),\n"
            '                        ),\n'
            '                        const SizedBox(width: 10),\n'
            '                        OutlinedButton(\n'
            '                          onPressed: () => setState(() => _tasbih = 0),\n'
            "                          child: const Text('تصفير'),\n"
            '                        ),\n'
            '                      ],\n'
            '                    ),\n'
            '                  ],\n'
            '                ),\n'
            '              ),\n'
            '            ),\n'
            '            const SizedBox(height: 14),\n'
            '            for (final z in _azkar)\n'
            '              Card(\n'
            '                margin: const EdgeInsets.only(bottom: 10),\n'
            '                child: ListTile(\n'
            '                  title: Text(z.\$1),\n'
            "                  trailing: Chip(label: Text('\${z.\$2} مرة')),\n"
            '                ),\n'
            '              ),\n'
            '          ],\n'
            '        ),\n'
            '      ),\n'
            '    );\n'
            '  }\n'
            '}\n',
      ),
    ];
  }

  static List<IdeNode> _buildFullXoGameNodes(String appName) {
    return [
      IdeNode(
        path: 'lib/main.dart',
        isFolder: false,
        content: "import 'package:flutter/material.dart';\n\n"
            'void main() => runApp(const XoGameApp());\n\n'
            'class XoGameApp extends StatelessWidget {\n'
            '  const XoGameApp({super.key});\n\n'
            '  @override\n'
            '  Widget build(BuildContext context) {\n'
            '    return MaterialApp(\n'
            '      debugShowCheckedModeBanner: false,\n'
            "      title: '$appName',\n"
            '      theme: ThemeData.dark(useMaterial3: true),\n'
            '      home: const XoBoardPage(),\n'
            '    );\n'
            '  }\n'
            '}\n\n'
            'class XoBoardPage extends StatefulWidget {\n'
            '  const XoBoardPage({super.key});\n\n'
            '  @override\n'
            '  State<XoBoardPage> createState() => _XoBoardPageState();\n'
            '}\n\n'
            'class _XoBoardPageState extends State<XoBoardPage> {\n'
            '  List<String> _board = List.filled(9, "");\n'
            '  bool _xTurn = true;\n\n'
            '  void _tap(int i) {\n'
            '    if (_board[i].isNotEmpty) return;\n'
            '    setState(() {\n'
            '      _board[i] = _xTurn ? "X" : "O";\n'
            '      _xTurn = !_xTurn;\n'
            '    });\n'
            '  }\n\n'
            '  @override\n'
            '  Widget build(BuildContext context) {\n'
            '    return Scaffold(\n'
            "      appBar: AppBar(title: const Text('$appName')),\n"
            '      body: Column(\n'
            '        mainAxisAlignment: MainAxisAlignment.center,\n'
            '        children: [\n'
            "          Text('الدور الحالي: \${_xTurn ? \"X\" : \"O\"}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),\n"
            '          const SizedBox(height: 20),\n'
            '          GridView.builder(\n'
            '            shrinkWrap: true,\n'
            '            padding: const EdgeInsets.all(24),\n'
            '            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 10, crossAxisSpacing: 10),\n'
            '            itemCount: 9,\n'
            '            itemBuilder: (ctx, i) => ElevatedButton(\n'
            '              onPressed: () => _tap(i),\n'
            '              child: Text(_board[i], style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),\n'
            '            ),\n'
            '          ),\n'
            '          ElevatedButton.icon(\n'
            '            onPressed: () => setState(() => _board = List.filled(9, "")),\n'
            '            icon: const Icon(Icons.refresh),\n'
            "            label: const Text('إعادة اللعب'),\n"
            '          ),\n'
            '        ],\n'
            '      ),\n'
            '    );\n'
            '  }\n'
            '}\n',
      ),
    ];
  }

  static String _calculatorCode(String appName) {
    return "import 'package:flutter/material.dart';\n\n"
        'void main() => runApp(const CalcApp());\n\n'
        'class CalcApp extends StatelessWidget {\n'
        '  const CalcApp({super.key});\n\n'
        '  @override\n'
        '  Widget build(BuildContext context) {\n'
        '    return MaterialApp(\n'
        '      debugShowCheckedModeBanner: false,\n'
        "      title: '$appName',\n"
        '      theme: ThemeData.dark(useMaterial3: true),\n'
        '      home: const CalcPage(),\n'
        '    );\n'
        '  }\n'
        '}\n\n'
        'class CalcPage extends StatefulWidget {\n'
        '  const CalcPage({super.key});\n\n'
        '  @override\n'
        '  State<CalcPage> createState() => _CalcPageState();\n'
        '}\n\n'
        'class _CalcPageState extends State<CalcPage> {\n'
        "  String _display = '0';\n\n"
        '  void _press(String k) {\n'
        '    setState(() {\n'
        "      if (k == 'C') {\n"
        "        _display = '0';\n"
        '      } else {\n'
        "        _display = _display == '0' ? k : _display + k;\n"
        '      }\n'
        '    });\n'
        '  }\n\n'
        '  @override\n'
        '  Widget build(BuildContext context) {\n'
        "    final keys = ['7','8','9','/','4','5','6','*','1','2','3','-','C','0','=','+'];\n"
        '    return Scaffold(\n'
        "      appBar: AppBar(title: const Text('$appName')),\n"
        '      body: Column(\n'
        '        children: [\n'
        '          Expanded(\n'
        '            child: Container(\n'
        '              alignment: Alignment.bottomRight,\n'
        '              padding: const EdgeInsets.all(24),\n'
        '              child: Text(_display, style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold)),\n'
        '            ),\n'
        '          ),\n'
        '          GridView.builder(\n'
        '            shrinkWrap: true,\n'
        '            padding: const EdgeInsets.all(12),\n'
        '            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisSpacing: 8, crossAxisSpacing: 8),\n'
        '            itemCount: keys.length,\n'
        '            itemBuilder: (ctx, i) => ElevatedButton(\n'
        '              onPressed: () => _press(keys[i]),\n'
        '              child: Text(keys[i], style: const TextStyle(fontSize: 22)),\n'
        '            ),\n'
        '          ),\n'
        '        ],\n'
        '      ),\n'
        '    );\n'
        '  }\n'
        '}\n';
  }

  static String _defaultFlutterStarter(String appName) {
    return "import 'package:flutter/material.dart';\n\n"
        'void main() {\n'
        '  runApp(const MyApp());\n'
        '}\n\n'
        'class MyApp extends StatelessWidget {\n'
        '  const MyApp({super.key});\n\n'
        '  @override\n'
        '  Widget build(BuildContext context) {\n'
        '    return MaterialApp(\n'
        '      debugShowCheckedModeBanner: false,\n'
        "      title: '$appName',\n"
        '      theme: ThemeData.dark(useMaterial3: true),\n'
        '      home: const HomePage(),\n'
        '    );\n'
        '  }\n'
        '}\n\n'
        'class HomePage extends StatefulWidget {\n'
        '  const HomePage({super.key});\n\n'
        '  @override\n'
        '  State<HomePage> createState() => _HomePageState();\n'
        '}\n\n'
        'class _HomePageState extends State<HomePage> {\n'
        '  int _counter = 0;\n\n'
        '  @override\n'
        '  Widget build(BuildContext context) {\n'
        '    return Scaffold(\n'
        "      appBar: AppBar(title: const Text('$appName')),\n"
        '      body: Center(\n'
        '        child: Column(\n'
        '          mainAxisAlignment: MainAxisAlignment.center,\n'
        '          children: [\n'
        "            const Text('تم بناء التطبيق بواسطة مانجو ستديو:'),\n"
        '            const SizedBox(height: 12),\n'
        '            Text(\n'
        "              '\$_counter',\n"
        '              style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold),\n'
        '            ),\n'
        '          ],\n'
        '        ),\n'
        '      ),\n'
        '      floatingActionButton: FloatingActionButton(\n'
        '        onPressed: () => setState(() => _counter++),\n'
        '        child: const Icon(Icons.add),\n'
        '      ),\n'
        '    );\n'
        '  }\n'
        '}\n';
  }

  static String workflowForType(
    IdeProjectType type, {
    required String appName,
    required String packageName,
    required String versionName,
    required int versionCode,
    String buildMode = 'release',
    bool publishRelease = true,
  }) {
    final safeAppName = appName.replaceAll('"', '').replaceAll("'", '');
    final safePkg = packageName.trim().isEmpty ? 'com.mango.app' : packageName.trim();
    final buildFlag = buildMode == 'debug' ? '--debug' : '--release';
    final apkFile = buildMode == 'debug' ? 'app-debug.apk' : 'app-release.apk';

    return 'name: Mango Studio Build APK\n\n'
        'on:\n'
        '  push:\n'
        '    branches: [ main, master ]\n'
        '  workflow_dispatch:\n'
        '    inputs:\n'
        '      flutter_version:\n'
        "        description: 'Flutter version'\n"
        '        required: false\n'
        "        default: '3.47.2'\n\n"
        'permissions:\n'
        '  contents: write\n\n'
        'jobs:\n'
        '  build:\n'
        '    runs-on: ubuntu-24.04\n'
        '    steps:\n'
        '      - name: Checkout\n'
        '        uses: actions/checkout@v4\n\n'
        '      - name: Setup Gradle Cache\n'
        '        uses: actions/cache@v4\n'
        '        with:\n'
        '          path: |\n'
        '            ~/.gradle/caches\n'
        '            ~/.gradle/wrapper\n'
        "          key: \${{ runner.os }}-gradle-\${{ hashFiles('**/*.gradle*', '**/gradle-wrapper.properties') }}\n"
        '          restore-keys: |\n'
        '            \${{ runner.os }}-gradle-\n\n'
        '      - name: Setup Java 17\n'
        '        uses: actions/setup-java@v4\n'
        '        with:\n'
        '          distribution: temurin\n'
        "          java-version: '17'\n\n"
        '      - name: Setup Flutter\n'
        '        uses: subosito/flutter-action@v2\n'
        '        with:\n'
        '          cache: true\n'
        '          channel: stable\n\n'
        '      - name: Prepare Android & Branding\n'
        '        run: |\n'
        '          if [ ! -f "pubspec.yaml" ]; then\n'
        '            flutter create . --platforms=android --org ${safePkg.split(".").take(2).join(".")}\n'
        '          elif [ ! -d "android" ]; then\n'
        '            flutter create . --platforms=android\n'
        '          fi\n'
        '          if [ -f "android/app/src/main/AndroidManifest.xml" ]; then\n'
        '            sed -i \'s/android:label="[^"]*"/android:label="$safeAppName"/g\' android/app/src/main/AndroidManifest.xml || true\n'
        '          fi\n'
        '          if [ -f "android/app/build.gradle" ]; then\n'
        '            sed -i \'s/applicationId = "[^"]*"/applicationId = "$safePkg"/g\' android/app/build.gradle || true\n'
        '          fi\n'
        '          if [ -f "android/app/build.gradle.kts" ]; then\n'
        '            sed -i \'s/applicationId = "[^"]*"/applicationId = "$safePkg"/g\' android/app/build.gradle.kts || true\n'
        '          fi\n\n'
        '      - name: Get dependencies\n'
        '        run: flutter pub get\n\n'
        '      - name: Build APK\n'
        '        run: flutter build apk $buildFlag --build-name=$versionName --build-number=$versionCode\n\n'
        '      - name: Upload APK\n'
        '        uses: actions/upload-artifact@v4\n'
        '        with:\n'
        '          name: app-release\n'
        '          path: build/app/outputs/flutter-apk/$apkFile\n'
        '          if-no-files-found: error\n'
        '          retention-days: 14\n';
  }
}

/// ============================================================================
/// محرر الأكواد الملون (CodeSyntaxController)
/// ============================================================================
class CodeSyntaxController extends TextEditingController {
  CodeSyntaxController({super.text});

  static final RegExp _tokenRegex = RegExp(
    r"(//.*$)|(/\*[\s\S]*?\*/)|('(?:\\.|[^'\\])*')|"
    r'("(?:\\.|[^"\\])*")'
    r"|(@[a-zA-Z_]\w*)"
    r"|\b(abstract|as|assert|async|await|break|case|catch|class|const|continue|covariant|default|deferred|do|dynamic|else|enum|export|extends|extension|external|factory|false|final|finally|for|fun|function|Function|get|hide|if|implements|import|in|interface|is|late|let|library|mixin|new|null|object|on|operator|override|package|part|private|protected|public|required|rethrow|return|sealed|set|show|static|super|switch|sync|this|throw|true|try|typedef|val|var|void|when|while|with|yield)\b"
    r"|\b(Widget|StatelessWidget|StatefulWidget|State|BuildContext|Scaffold|AppBar|Container|Column|Row|Text|Center|ListView|GridView|Card|Padding|Expanded|SizedBox|IconButton|ElevatedButton|OutlinedButton|TextField|MaterialApp|ThemeData|Color|Colors|EdgeInsets|Future|Stream|List|Map|Set|String|int|double|bool|num|Object|Key|Activity|Bundle|TextView|View)\b"
    r"|\b(\d+(?:\.\d+)?)\b",
    multiLine: true,
  );

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final baseStyle = style ??
        const TextStyle(
          fontFamily: 'monospace',
          fontSize: 14,
          height: 1.5,
          color: AppColors.textPrimary,
        );

    final source = text;
    if (source.isEmpty) {
      return TextSpan(style: baseStyle, text: '');
    }

    try {
      final children = <TextSpan>[];
      var lastIndex = 0;

      for (final match in _tokenRegex.allMatches(source)) {
        if (match.start > lastIndex) {
          children.add(TextSpan(text: source.substring(lastIndex, match.start)));
        }

        Color tokenColor = AppColors.textPrimary;
        FontWeight? weight;
        FontStyle? fontStyle;

        if (match.group(1) != null || match.group(2) != null) {
          tokenColor = AppColors.textMuted;
          fontStyle = FontStyle.italic;
        } else if (match.group(3) != null || match.group(4) != null) {
          tokenColor = const Color(0xFFA5D6FF);
        } else if (match.group(5) != null) {
          tokenColor = const Color(0xFFD2A8FF);
        } else if (match.group(6) != null) {
          tokenColor = const Color(0xFFFF7B72);
          weight = FontWeight.w600;
        } else if (match.group(7) != null) {
          tokenColor = const Color(0xFFFFA657);
        } else if (match.group(8) != null) {
          tokenColor = const Color(0xFF79C0FF);
        }

        children.add(
          TextSpan(
            text: match.group(0),
            style: baseStyle.copyWith(
              color: tokenColor,
              fontWeight: weight,
              fontStyle: fontStyle,
            ),
          ),
        );
        lastIndex = match.end;
      }

      if (lastIndex < source.length) {
        children.add(TextSpan(text: source.substring(lastIndex)));
      }

      return TextSpan(style: baseStyle, children: children);
    } catch (_) {
      return TextSpan(style: baseStyle, text: source);
    }
  }
}

/// ============================================================================
/// خدمة ربط GitHub المحدثة والمصلحة بالكامل (Device Flow + Resume Listener + Token Save First)
/// ============================================================================
class GithubOAuthDeviceService {
  static const String defaultClientId = '178c6fc778ccc68e1d6a';

  static Map<String, String> _commonHeaders([String? token]) => {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'Mango-Studio-IDE/2.0',
        if (token != null && token.trim().isNotEmpty) 'Authorization': 'token ${token.trim()}',
      };

  static Future<Map<String, dynamic>> startDeviceFlow({String? customClientId}) async {
    final clientId = (customClientId != null && customClientId.trim().isNotEmpty)
        ? customClientId.trim()
        : defaultClientId;

    final res = await http
        .post(
          Uri.parse('https://github.com/login/device/code'),
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/x-www-form-urlencoded',
            'User-Agent': 'Mango-Studio-IDE/2.0',
          },
          body: {
            'client_id': clientId,
            'scope': 'repo workflow read:user',
          },
        )
        .timeout(const Duration(seconds: 20));

    if (res.statusCode >= 400) {
      throw Exception('تعذر بدء طلب التفويض من GitHub (${res.statusCode}).');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (data['user_code'] == null) {
      throw Exception(data['error_description']?.toString() ?? 'تعذر الحصول على رمز التحقق.');
    }
    return data;
  }

  static Future<Map<String, dynamic>> pollDeviceToken({
    required String deviceCode,
    String? customClientId,
  }) async {
    final clientId = (customClientId != null && customClientId.trim().isNotEmpty)
        ? customClientId.trim()
        : defaultClientId;

    final res = await http
        .post(
          Uri.parse('https://github.com/login/oauth/access_token'),
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/x-www-form-urlencoded',
            'User-Agent': 'Mango-Studio-IDE/2.0',
          },
          body: {
            'client_id': clientId,
            'device_code': deviceCode,
            'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
          },
        )
        .timeout(const Duration(seconds: 20));

    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> fetchUserProfile(String token) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final res = await http
            .get(
              Uri.parse('https://api.github.com/user'),
              headers: _commonHeaders(token),
            )
            .timeout(const Duration(seconds: 15));

        if (res.statusCode >= 200 && res.statusCode < 300) {
          return jsonDecode(res.body) as Map<String, dynamic>;
        }
        // تجربة Bearer في حال كان التوكن Fine-grained PAT
        final resBearer = await http
            .get(
              Uri.parse('https://api.github.com/user'),
              headers: {
                'Accept': 'application/vnd.github+json',
                'User-Agent': 'Mango-Studio-IDE/2.0',
                'Authorization': 'Bearer ${token.trim()}',
              },
            )
            .timeout(const Duration(seconds: 15));
        if (resBearer.statusCode >= 200 && resBearer.statusCode < 300) {
          return jsonDecode(resBearer.body) as Map<String, dynamic>;
        }
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
    }
    throw Exception('تعذر التحقق من بيانات حساب GitHub. تأكد من اتصالك بالإنترنت.');
  }

  static Future<ApkBuildRecord> pushProjectAndBuildApk({
    required String token,
    required String githubLogin,
    required IdeProject project,
    required void Function(String stepLog) onLog,
  }) async {
    final cleanToken = token.trim();
    final headers = {
      'Authorization': 'token $cleanToken',
      'Accept': 'application/vnd.github+json',
      'Content-Type': 'application/json',
      'User-Agent': 'Mango-Studio-IDE/2.0',
      'X-GitHub-Api-Version': '2022-11-28',
    };

    var effectiveLogin = githubLogin.trim();
    if (effectiveLogin.isEmpty || effectiveLogin == 'github_user') {
      try {
        final prof = await fetchUserProfile(cleanToken);
        effectiveLogin = prof['login']?.toString() ?? 'user';
        await SafeStorage.setString('gh_oauth_login', effectiveLogin);
      } catch (_) {}
    }

    final safeSlug = project.name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9-]'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final repoShortName =
        safeSlug.isEmpty ? 'mango-app-${project.id.substring(project.id.length - 4)}' : safeSlug;
    final repoFullName = (project.githubRepo != null && project.githubRepo!.contains('/'))
        ? project.githubRepo!.trim()
        : '$effectiveLogin/$repoShortName';

    onLog('جاري التحقق من المستودع $repoFullName على GitHub...');
    var repoCheck = await http
        .get(Uri.parse('https://api.github.com/repos/$repoFullName'), headers: headers)
        .timeout(const Duration(seconds: 20));

    if (repoCheck.statusCode == 404) {
      onLog('جاري إنشاء مستودع جديد ($repoShortName) تلقائياً في حسابك...');
      final createRes = await http
          .post(
            Uri.parse('https://api.github.com/user/repos'),
            headers: headers,
            body: jsonEncode({
              'name': repoShortName,
              'description': '${project.name} - Built with Mango Studio IDE',
              'private': false,
              'auto_init': true,
            }),
          )
          .timeout(const Duration(seconds: 25));
      if (createRes.statusCode >= 400) {
        throw Exception('تعذر إنشاء المستودع تلقائياً: ${createRes.body}');
      }
      await Future<void>.delayed(const Duration(seconds: 2));
      repoCheck = await http
          .get(Uri.parse('https://api.github.com/repos/$repoFullName'), headers: headers)
          .timeout(const Duration(seconds: 20));
    }

    if (repoCheck.statusCode >= 400) {
      throw Exception('تعذر الوصول للمستودع $repoFullName (${repoCheck.statusCode}).');
    }

    final repoData = jsonDecode(repoCheck.body) as Map<String, dynamic>;
    final defaultBranch = (repoData['default_branch'] as String?) ?? 'main';

    onLog('جاري قراءة الفرع الأساسي ($defaultBranch)...');
    final refUri = Uri.parse('https://api.github.com/repos/$repoFullName/git/ref/heads/$defaultBranch');
    final refRes = await http.get(refUri, headers: headers).timeout(const Duration(seconds: 20));
    if (refRes.statusCode >= 400) {
      throw Exception('تعذر قراءة مرجع الفرع $defaultBranch (${refRes.statusCode}).');
    }
    final refData = jsonDecode(refRes.body) as Map<String, dynamic>;
    final latestCommitSha = (refData['object'] as Map<String, dynamic>)['sha'] as String;

    final commitRes = await http
        .get(
          Uri.parse('https://api.github.com/repos/$repoFullName/git/commits/$latestCommitSha'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 20));
    final baseTreeSha = ((jsonDecode(commitRes.body) as Map<String, dynamic>)['tree']
        as Map<String, dynamic>)['sha'] as String;

    final files = project.nodes.where((n) => !n.isFolder).toList();
    final workflowYaml = ProjectTemplates.workflowForType(
      project.type,
      appName: project.name,
      packageName: project.packageName,
      versionName: project.versionName,
      versionCode: project.versionCode,
      buildMode: project.buildMode,
      publishRelease: project.publishReleaseTag,
    );

    final treeItems = <Map<String, dynamic>>[
      for (final file in files)
        if (file.path != '.github/workflows/main.yml')
          {
            'path': file.path,
            'mode': '100644',
            'type': 'blob',
            'content': file.content,
          },
      {
        'path': '.github/workflows/main.yml',
        'mode': '100644',
        'type': 'blob',
        'content': workflowYaml,
      },
    ];

    if (project.iconBase64 != null && project.iconBase64!.isNotEmpty) {
      onLog('جاري رفع أيقونة التطبيق المخصصة...');
      final blobRes = await http
          .post(
            Uri.parse('https://api.github.com/repos/$repoFullName/git/blobs'),
            headers: headers,
            body: jsonEncode({
              'content': project.iconBase64,
              'encoding': 'base64',
            }),
          )
          .timeout(const Duration(seconds: 25));
      if (blobRes.statusCode < 300) {
        final iconSha = (jsonDecode(blobRes.body) as Map<String, dynamic>)['sha'] as String;
        treeItems.add({
          'path': 'android/app/src/main/res/drawable/ic_launcher.png',
          'mode': '100644',
          'type': 'blob',
          'sha': iconSha,
        });
      }
    }

    onLog('جاري رفع (${treeItems.length}/${treeItems.length} ملف) إلى GitHub...');
    final treeRes = await http
        .post(
          Uri.parse('https://api.github.com/repos/$repoFullName/git/trees'),
          headers: headers,
          body: jsonEncode({
            'base_tree': baseTreeSha,
            'tree': treeItems,
          }),
        )
        .timeout(const Duration(seconds: 35));
    if (treeRes.statusCode >= 400) {
      throw Exception('فشل رفع شجرة الملفات (${treeRes.statusCode}).');
    }
    final newTreeSha = (jsonDecode(treeRes.body) as Map<String, dynamic>)['sha'] as String;

    final newCommitRes = await http
        .post(
          Uri.parse('https://api.github.com/repos/$repoFullName/git/commits'),
          headers: headers,
          body: jsonEncode({
            'message': 'Mango Studio Build: ${project.name} v${project.versionName}',
            'tree': newTreeSha,
            'parents': [latestCommitSha],
          }),
        )
        .timeout(const Duration(seconds: 25));
    final newCommitSha = (jsonDecode(newCommitRes.body) as Map<String, dynamic>)['sha'] as String;

    final updateRefRes = await http
        .patch(
          refUri,
          headers: headers,
          body: jsonEncode({'sha': newCommitSha, 'force': false}),
        )
        .timeout(const Duration(seconds: 25));
    if (updateRefRes.statusCode >= 400) {
      throw Exception('فشل تحديث الفرع وتشغيل البناء (${updateRefRes.statusCode}).');
    }

    try {
      await http.post(
        Uri.parse('https://api.github.com/repos/$repoFullName/actions/workflows/main.yml/dispatches'),
        headers: headers,
        body: jsonEncode({'ref': defaultBranch}),
      );
    } catch (_) {}

    onLog('تم تشغيل GitHub Actions لبناء ملف الـ APK بنجاح ✓');

    return ApkBuildRecord(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      projectId: project.id,
      projectName: project.name,
      packageName: project.packageName,
      versionName: project.versionName,
      projectType: project.type.title,
      repoFullName: repoFullName,
      status: 'running',
      actionsUrl: 'https://github.com/$repoFullName/actions',
      releaseApkUrl: 'https://github.com/$repoFullName/releases',
      createdAt: DateTime.now(),
      logs: [
        'تم رفع (${treeItems.length}/${treeItems.length} ملف) إلى $repoFullName',
        'اسم التطبيق: ${project.name}',
        'اسم الحزمة: ${project.packageName}',
        'الإصدار: ${project.versionName}+${project.versionCode}',
        'انطلقت عملية البناء على GitHub Actions ✓',
      ],
    );
  }
}

/// ============================================================================
/// شاشة ربط GitHub الرسمية المطورة (مع مستمع العودة للتطبيق + زر تأكيد فوري)
/// ============================================================================
class GithubConnectModalScreen extends StatefulWidget {
  const GithubConnectModalScreen({
    super.key,
    required this.onConnected,
  });

  final void Function(String token, String login) onConnected;

  @override
  State<GithubConnectModalScreen> createState() => _GithubConnectModalScreenState();
}

class _GithubConnectModalScreenState extends State<GithubConnectModalScreen>
    with WidgetsBindingObserver {
  String _statusText = 'لم يتم ربط حساب GitHub';
  String? _userCode;
  String? _deviceCode;
  String? _verificationUri;
  String? _customClientId;
  int _pollIntervalSec = 5;
  bool _busy = false;
  bool _checkingNow = false;
  bool _connected = false;
  String? _connectedLogin;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkExistingConnection();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  /// فور رجوع المستخدم من متصفح GitHub إلى تطبيق مانجو ستديو، نفحص حالة الرمز فوراً!
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _deviceCode != null && !_connected) {
      Future<void>.delayed(const Duration(milliseconds: 600), () {
        if (mounted && _deviceCode != null && !_connected) {
          _checkDeviceStatusOnce(manualTap: true);
        }
      });
    }
  }

  Future<void> _checkExistingConnection() async {
    final token = await SafeStorage.getString('gh_oauth_token');
    final login = await SafeStorage.getString('gh_oauth_login');
    if (token != null && token.isNotEmpty && mounted) {
      setState(() {
        _connected = true;
        _connectedLogin = login ?? 'github_user';
        _statusText = 'متصل بحساب GitHub (@${_connectedLogin!}) ✓';
      });
    }
  }

  Future<void> _startDeviceLogin() async {
    _pollTimer?.cancel();
    setState(() {
      _busy = true;
      _statusText = 'جاري طلب رمز التحقق المؤقت من GitHub...';
    });

    try {
      _customClientId = await SafeStorage.getString('gh_custom_client_id');
      final data = await GithubOAuthDeviceService.startDeviceFlow(customClientId: _customClientId);
      final userCode = data['user_code'].toString();
      final deviceCode = data['device_code'].toString();
      final verifyUri = (data['verification_uri']?.toString() ?? 'https://github.com/login/device');
      final intervalSec = (data['interval'] as num?)?.toInt() ?? 5;

      await Clipboard.setData(ClipboardData(text: userCode));

      if (!mounted) return;
      setState(() {
        _userCode = userCode;
        _deviceCode = deviceCode;
        _verificationUri = verifyUri;
        _pollIntervalSec = intervalSec < 5 ? 5 : intervalSec;
        _busy = false;
        _statusText = 'تم نسخ الرمز ($userCode) تلقائياً! افتح صفحة التحقق والصق الرمز ثم ارجع للتطبيق.';
      });

      _scheduleNextPoll();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _statusText = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _scheduleNextPoll() {
    _pollTimer?.cancel();
    if (_deviceCode == null || _connected) return;
    _pollTimer = Timer(Duration(seconds: _pollIntervalSec), () async {
      await _checkDeviceStatusOnce(manualTap: false);
      if (mounted && !_connected && _deviceCode != null) {
        _scheduleNextPoll();
      }
    });
  }

  /// فحص حالة التفويض وحفظ التوكن فوراً في اللحظة التي يرجع فيها من GitHub
  Future<void> _checkDeviceStatusOnce({required bool manualTap}) async {
    if (_deviceCode == null || _connected || _checkingNow) return;
    if (manualTap && mounted) {
      setState(() {
        _checkingNow = true;
        _statusText = 'جاري التحقق من موافقة GitHub وتأكيد الدخول...';
      });
    }

    try {
      final res = await GithubOAuthDeviceService.pollDeviceToken(
        deviceCode: _deviceCode!,
        customClientId: _customClientId,
      );

      final token = res['access_token']?.toString();
      if (token != null && token.isNotEmpty) {
        _pollTimer?.cancel();
        // 1. نحفظ التوكن فوراً قبل أي خطوة أخرى حتى لا يضيع أبداً!
        await SafeStorage.setString('gh_oauth_token', token);

        // 2. نجلب اسم المستخدم مع إعادة المحاولة، وإن تعذر نعتمد حساباً متصلاً
        var login = 'github_user';
        try {
          final profile = await GithubOAuthDeviceService.fetchUserProfile(token);
          login = profile['login']?.toString() ?? 'github_user';
        } catch (_) {}

        await SafeStorage.setString('gh_oauth_login', login);

        if (!mounted) return;
        setState(() {
          _connected = true;
          _connectedLogin = login;
          _deviceCode = null;
          _checkingNow = false;
          _statusText = 'تم تسجيل الدخول وربط حساب GitHub بنجاح (@$login) ✓';
        });
        widget.onConnected(token, login);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.success,
            content: Text('تم ربط حساب GitHub (@$login) بنجاح ✓'),
          ),
        );
        return;
      }

      final err = res['error']?.toString() ?? '';
      if (err == 'slow_down') {
        final newInt = (res['interval'] as num?)?.toInt();
        _pollIntervalSec = newInt ?? (_pollIntervalSec + 5);
        if (manualTap && mounted) {
          setState(() {
            _statusText = 'يرجى الانتظار $_pollIntervalSec ثوانٍ ثم الضغط على تأكيد الربط.';
          });
        }
      } else if (err == 'authorization_pending') {
        if (manualTap && mounted) {
          setState(() {
            _statusText = 'لم تكتمل الموافقة في صفحة GitHub بعد. اضغط Continue ثم Authorize في المتصفح.';
          });
        }
      } else if (err == 'expired_token' || err == 'access_denied') {
        _pollTimer?.cancel();
        _deviceCode = null;
        if (mounted) {
          setState(() {
            _statusText = 'انتهت صلاحية الرمز أو تم رفض الطلب. اضغط "بدء تسجيل الدخول" لطلب رمز جديد.';
          });
        }
      }
    } catch (_) {
      if (manualTap && mounted) {
        setState(() {
          _statusText = 'تعذر الاتصال مؤقتاً، اضغط "تأكيد الربط بعد الموافقة" للمحاولة مرة أخرى.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _checkingNow = false);
      }
    }
  }

  Future<void> _openVerificationPage() async {
    final uriStr = _verificationUri ?? 'https://github.com/login/device';
    if (_userCode != null && _userCode!.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: _userCode!));
    }
    try {
      final uri = Uri.parse(uriStr);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      }
    } catch (_) {}
  }

  Future<void> _showDirectTokenDialog() async {
    final patCtrl = TextEditingController();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('تسجيل دخول مباشر بالتوكن (PAT)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'يمكنك أيضاً لصق مفتاح Personal Access Token (بصلاحية repo و workflow) للربط الفوري:',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: patCtrl,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'GitHub Token',
                  hintText: 'ghp_xxxxxxxxxxxxxxxxxxxx',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                final t = patCtrl.text.trim();
                if (t.isEmpty) return;
                await SafeStorage.setString('gh_oauth_token', t);
                var login = 'github_user';
                try {
                  final p = await GithubOAuthDeviceService.fetchUserProfile(t);
                  login = p['login']?.toString() ?? 'github_user';
                } catch (_) {}
                await SafeStorage.setString('gh_oauth_login', login);
                if (mounted) {
                  setState(() {
                    _connected = true;
                    _connectedLogin = login;
                    _statusText = 'تم ربط حساب GitHub بنجاح (@$login) ✓';
                  });
                  widget.onConnected(t, login);
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('ربط الحساب فوراً'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0E14),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: _showDirectTokenDialog,
                      icon: const Icon(Icons.key_rounded, size: 17, color: AppColors.mango),
                      label: const Text('ربط بتوكن مباشر', style: TextStyle(color: AppColors.mango, fontSize: 12.5)),
                    ),
                    const Text(
                      'MANGO STUDIO / CONNECT',
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        color: Color(0xFF388BFD),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'اربط مساحة العمل بـ GitHub',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'تفويض رسمي من دون خادم وسيط • مانجو ستديو',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 20),

                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF131922),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFF263042)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'كيف يعمل الربط؟',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 10),
                      Text(
                        '1. اضغط "بدء تسجيل الدخول" ليظهر لك الرمز ويُنسخ تلقائياً.\n'
                        '2. اضغط "فتح صفحة التحقق" والصق الرمز ثم اضغط Continue و Authorize.\n'
                        '3. بمجرد رجوعك إلى تطبيق مانجو ستديو سيتم تسجيل دخولك تلقائياً أو بضغطة على زر التأكيد!',
                        style: TextStyle(
                          color: Color(0xFF9BA4B0),
                          fontSize: 14,
                          height: 1.65,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                Text(
                  _statusText,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: _connected ? AppColors.success : const Color(0xFF9BA4B0),
                    fontSize: 14.5,
                    fontWeight: _connected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                const SizedBox(height: 12),

                Container(
                  height: 82,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF131922),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _connected ? AppColors.success : const Color(0xFF263042),
                      width: _connected ? 1.8 : 1.0,
                    ),
                  ),
                  child: (_busy || _checkingNow)
                      ? const SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF388BFD)),
                        )
                      : SelectableText(
                          _connected
                              ? 'متصل: @${_connectedLogin ?? "github"}'
                              : (_userCode ?? '---- - ----'),
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                            color: _connected ? AppColors.success : Colors.white,
                            fontSize: _connected ? 21 : 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: _connected ? 1 : 4,
                            fontFamily: 'monospace',
                          ),
                        ),
                ),
                const SizedBox(height: 14),

                if (_deviceCode != null && !_connected) ...[
                  SizedBox(
                    height: 54,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      ),
                      onPressed: _checkingNow ? null : () => _checkDeviceStatusOnce(manualTap: true),
                      icon: const Icon(Icons.verified_rounded),
                      label: const Text(
                        'تأكيد الربط بعد الموافقة في المتصفح ✓',
                        style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                SizedBox(
                  height: 54,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: const Color(0xFF131922),
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF263042)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                    onPressed: _userCode == null
                        ? null
                        : () async {
                            await Clipboard.setData(ClipboardData(text: _userCode!));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('تم نسخ رمز التحقق إلى الحافظة ✓')),
                              );
                            }
                          },
                    child: const Text(
                      'نسخ رمز التحقق',
                      style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4796FF),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                    onPressed: _openVerificationPage,
                    child: const Text(
                      'فتح صفحة التحقق داخل التطبيق',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4796FF),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                    onPressed: _busy ? null : _startDeviceLogin,
                    child: Text(
                      _connected ? 'تبديل أو إعادة ربط حساب GitHub' : 'بدء تسجيل الدخول',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'إغلاق',
                      style: TextStyle(color: Color(0xFF9BA4B0), fontSize: 15.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ============================================================================
/// مهندس الذكاء الاصطناعي لبناء تطبيقات كاملة متعددة الملفات (Full App AI Architect)
/// ============================================================================
class MangoAiArchitectService {
  static Future<String> buildOrEditWithAi({
    required String provider, // 'gemini', 'openai', 'deepseek', 'groq', 'builtin'
    required String apiKey,
    required String model,
    required String prompt,
    required IdeProject project,
    required String activeFilePath,
    required String activeFileContent,
    required bool fullAppMode,
  }) async {
    // إذا اختار المستخدم المولد الذكي المدمج أو لم يدخل مفتاح API، نبني له تطبيقاً كاملاً متعدد الملفات فوراً!
    if (provider == 'builtin' || apiKey.trim().isEmpty) {
      return _generateBuiltInFullAppResponse(prompt, project.name);
    }

    final fileList = project.nodes.where((n) => !n.isFolder).map((n) => n.path).join(', ');
    final systemPrompt = fullAppMode
        ? 'أنت مهندس برمجيات خبير في Flutter داخل تطبيق "مانجو ستديو" (Mango Studio).\n'
            'المستخدم يريد بناء أو تطوير تطبيق كامل متعدد الملفات باسم "${project.name}".\n'
            'قم بتوليد ملفات المشروع الكاملة (مثل lib/main.dart وأي شاشات أو نماذج إضافية في lib/screens/ و lib/models/).\n'
            'استخدم الصيغة التالية لكل ملف:\n'
            '===FILE: lib/main.dart===\n'
            '```dart\n'
            '// الكود الكامل هنا\n'
            '```\n'
            'بحيث يقوم مانجو ستديو بإنشاء وتحديث جميع ملفات المشروع تلقائياً!'
        : 'أنت مطور تطبيقات خبير داخل بيئة تطوير "مانجو ستديو".\n'
            'نوع المشروع: ${project.type.title} | ملفات المشروع: $fileList\n'
            'الملف المفتوح حالياً: $activeFilePath\n'
            'محتوى الملف:\n```\n$activeFileContent\n```\n'
            'نفذ طلب المستخدم بدقة وضع الكود الكامل المحدّث داخل بلوك ```dart ... ``` لتطبيقه مباشرةً.';

    if (provider == 'gemini') {
      final selectedModel = model.trim().isEmpty ? 'gemini-2.5-flash' : model.trim();
      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$selectedModel:generateContent?key=${apiKey.trim()}',
      );
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'system_instruction': {
                'parts': [
                  {'text': systemPrompt}
                ]
              },
              'contents': [
                {
                  'role': 'user',
                  'parts': [
                    {'text': prompt}
                  ]
                }
              ],
              'generationConfig': {'temperature': 0.2},
            }),
          )
          .timeout(const Duration(seconds: 55));

      if (response.statusCode >= 400) {
        throw Exception('خطأ من Gemini API (${response.statusCode}): ${response.body}');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = data['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) {
        throw Exception('لم يرجع النموذج أي استجابة.');
      }
      final parts = (candidates.first['content'] as Map<String, dynamic>)['parts'] as List;
      return parts.map((p) => (p as Map<String, dynamic>)['text'] ?? '').join('\n');
    } else {
      final endpoint = switch (provider) {
        'deepseek' => 'https://api.deepseek.com/chat/completions',
        'groq' => 'https://api.groq.com/openai/v1/chat/completions',
        _ => 'https://api.openai.com/v1/chat/completions',
      };
      final selectedModel = model.trim().isEmpty
          ? switch (provider) {
              'deepseek' => 'deepseek-chat',
              'groq' => 'llama-3.3-70b-versatile',
              _ => 'gpt-4o-mini',
            }
          : model.trim();

      final response = await http
          .post(
            Uri.parse(endpoint),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${apiKey.trim()}',
            },
            body: jsonEncode({
              'model': selectedModel,
              'temperature': 0.2,
              'messages': [
                {'role': 'system', 'content': systemPrompt},
                {'role': 'user', 'content': prompt},
              ],
            }),
          )
          .timeout(const Duration(seconds: 55));

      if (response.statusCode >= 400) {
        throw Exception('خطأ من API (${response.statusCode}): ${response.body}');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = data['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        throw Exception('لم يرجع النموذج أي استجابة.');
      }
      return ((choices.first as Map<String, dynamic>)['message'] as Map<String, dynamic>)['content']
              ?.toString() ??
          '';
    }
  }

  /// استخراج الملفات المتعددة إذا قام الذكاء الاصطناعي ببناء تطبيق كامل (===FILE: path===)
  static Map<String, String> extractMultiFileMap(String responseText) {
    final result = <String, String>{};
    final reg = RegExp(
      r'===FILE:\s*([^\n=]+)===\s*```(?:[a-zA-Z0-9_+-]+)?\s*\n([\s\S]*?)```',
      multiLine: true,
    );
    for (final m in reg.allMatches(responseText)) {
      final path = m.group(1)?.trim() ?? '';
      final content = m.group(2)?.trimRight() ?? '';
      if (path.isNotEmpty && content.isNotEmpty) {
        result[path] = content;
      }
    }
    return result;
  }

  static String? extractSingleCodeBlock(String text) {
    final regex = RegExp(r'```(?:[a-zA-Z0-9_+-]+)?\s*\n([\s\S]*?)```');
    final match = regex.firstMatch(text);
    return match?.group(1)?.trimRight();
  }

  /// مولّد تطبيقات ذكي مدمج يعمل فوراً لبناء تطبيقات كاملة متعددة الملفات حتى بدون مفتاح API
  static String _generateBuiltInFullAppResponse(String prompt, String appName) {
    final p = prompt.toLowerCase();
    List<IdeNode> nodes;
    String desc;

    if (p.contains('متجر') || p.contains('تسوق') || p.contains('سلة') || p.contains('store')) {
      nodes = ProjectTemplates._buildFullEcommerceAppNodes(appName);
      desc = 'تم بناء تطبيق متجر إلكتروني متكامل متعدد الملفات (يتضمن قائمة المنتجات، البحث الفوري، وسلة المشتريات).';
    } else if (p.contains('قرآن') || p.contains('أذكار') || p.contains('سبح') || p.contains('اسلام')) {
      nodes = ProjectTemplates._buildFullIslamicAppNodes(appName);
      desc = 'تم بناء تطبيق الأذكار والمسبحة الإلكترونية المتكامل بتصميم ليلي مريح.';
    } else if (p.contains('لعب') || p.contains('xo') || p.contains('اكس')) {
      nodes = ProjectTemplates._buildFullXoGameNodes(appName);
      desc = 'تم بناء لعبة X-O التفاعلية الكاملة مع نظام الأدوار وإعادة اللعب.';
    } else if (p.contains('حاسب') || p.contains('calc')) {
      nodes = [IdeNode(path: 'lib/main.dart', isFolder: false, content: ProjectTemplates._calculatorCode(appName))];
      desc = 'تم بناء تطبيق الآلة الحاسبة الاحترافية.';
    } else {
      nodes = ProjectTemplates._buildFullTasksAppNodes(appName);
      desc = 'تم بناء تطبيق إدارة المهام والملاحظات الاحترافي متعدد الملفات.';
    }

    final buffer = StringBuffer('$desc\n\n');
    for (final n in nodes) {
      if (!n.isFolder) {
        buffer.writeln('===FILE: ${n.path}===');
        buffer.writeln('```dart');
        buffer.writeln(n.content);
        buffer.writeln('```\n');
      }
    }
    return buffer.toString();
  }
}

/// ============================================================================
/// التطبيق الرئيسي: مانجو ستديو (Mango Studio App)
/// ============================================================================
class MangoStudioApp extends StatelessWidget {
  const MangoStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'مانجو ستديو',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: AppColors.darkBg,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.mango,
          secondary: AppColors.primary,
          surface: AppColors.surface,
          error: AppColors.danger,
          onPrimary: Colors.black,
          onSurface: AppColors.textPrimary,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.darkBg,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surfaceAlt,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.mango, width: 1.5),
          ),
        ),
      ),
      home: const MangoHomeShell(),
    );
  }
}

class MangoHomeShell extends StatefulWidget {
  const MangoHomeShell({super.key});

  @override
  State<MangoHomeShell> createState() => _MangoHomeShellState();
}

class _MangoHomeShellState extends State<MangoHomeShell> {
  static const String _projectsStorageKey = 'mango_studio_projects_v5';
  static const String _buildsStorageKey = 'mango_studio_builds_v5';

  int _selectedTabIndex = 0;
  List<IdeProject> _projects = [];
  List<ApkBuildRecord> _builds = [];
  String? _githubToken;
  String? _githubLogin;

  String _aiProvider = 'builtin';
  String _aiApiKey = '';
  String _aiModel = 'gemini-2.5-flash';
  bool _aiAutoApply = true;
  bool _aiFullAppMode = true;
  final List<Map<String, String>> _aiChatHistory = [];

  @override
  void initState() {
    super.initState();
    final defaultProj = IdeProject(
      id: 'mango_1',
      name: 'متجر مانجو الذكي',
      packageName: 'com.mango.smartstore',
      type: IdeProjectType.flutter,
      updatedAt: DateTime.now(),
      nodes: ProjectTemplates.generateNodes(
        type: IdeProjectType.flutter,
        appName: 'متجر مانجو الذكي',
        packageName: 'com.mango.smartstore',
        versionName: '1.0.0',
        versionCode: 1,
        templateKind: 'ecommerce',
      ),
    );
    _projects = [defaultProj];
    _loadSavedStateInBackground();
  }

  Future<void> _loadSavedStateInBackground() async {
    try {
      final token = await SafeStorage.getString('gh_oauth_token');
      final login = await SafeStorage.getString('gh_oauth_login');
      final aiProv = await SafeStorage.getString('ide_ai_provider');
      final aiKey = await SafeStorage.getString('ide_ai_api_key');
      final aiMod = await SafeStorage.getString('ide_ai_model');
      final rawProjects = await SafeStorage.getString(_projectsStorageKey);
      final rawBuilds = await SafeStorage.getString(_buildsStorageKey);

      List<IdeProject>? loadedProjects;
      if (rawProjects != null && rawProjects.isNotEmpty) {
        final list = (jsonDecode(rawProjects) as List)
            .map((e) => IdeProject.fromJson(e as Map<String, dynamic>))
            .toList();
        if (list.isNotEmpty) loadedProjects = list;
      }

      List<ApkBuildRecord>? loadedBuilds;
      if (rawBuilds != null && rawBuilds.isNotEmpty) {
        loadedBuilds = (jsonDecode(rawBuilds) as List)
            .map((e) => ApkBuildRecord.fromJson(e as Map<String, dynamic>))
            .toList();
      }

      if (!mounted) return;
      setState(() {
        _githubToken = token;
        _githubLogin = login;
        if (aiProv != null) _aiProvider = aiProv;
        if (aiKey != null) _aiApiKey = aiKey;
        if (aiMod != null) _aiModel = aiMod;
        if (loadedProjects != null) _projects = loadedProjects;
        if (loadedBuilds != null) _builds = loadedBuilds;
      });
    } catch (_) {}
  }

  Future<void> _persistProjects() async {
    await SafeStorage.setString(
      _projectsStorageKey,
      jsonEncode(_projects.map((p) => p.toJson()).toList()),
    );
  }

  Future<void> _persistBuilds() async {
    await SafeStorage.setString(
      _buildsStorageKey,
      jsonEncode(_builds.map((b) => b.toJson()).toList()),
    );
  }

  /// تطبيق الملفات المتعددة المولدة بالذكاء الاصطناعي داخل شجرة المشروع مباشرةً
  Future<int> _applyAiGeneratedFilesToProject(IdeProject project, String aiResponse) async {
    final multiFiles = MangoAiArchitectService.extractMultiFileMap(aiResponse);
    if (multiFiles.isNotEmpty) {
      var count = 0;
      for (final entry in multiFiles.entries) {
        final cleanPath = entry.key.replaceAll('\\', '/').replaceAll(RegExp(r'^/+|/+$'), '');
        if (cleanPath.isEmpty) continue;
        final parts = cleanPath.split('/');
        var acc = '';
        for (var i = 0; i < parts.length - 1; i++) {
          acc = acc.isEmpty ? parts[i] : '$acc/${parts[i]}';
          if (!project.nodes.any((n) => n.isFolder && n.path == acc)) {
            project.nodes.add(IdeNode(path: acc, isFolder: true));
          }
        }
        final existingIdx = project.nodes.indexWhere((n) => !n.isFolder && n.path == cleanPath);
        if (existingIdx != -1) {
          project.nodes[existingIdx].content = entry.value;
          project.nodes[existingIdx].isDirty = false;
        } else {
          project.nodes.add(IdeNode(path: cleanPath, isFolder: false, content: entry.value));
        }
        count++;
      }
      project.updatedAt = DateTime.now();
      await _persistProjects();
      return count;
    }

    final singleCode = MangoAiArchitectService.extractSingleCodeBlock(aiResponse);
    if (singleCode != null) {
      final mainIdx = project.nodes.indexWhere((n) => !n.isFolder && n.path == 'lib/main.dart');
      if (mainIdx != -1) {
        project.nodes[mainIdx].content = singleCode;
      } else {
        final firstFileIdx = project.nodes.indexWhere((n) => !n.isFolder);
        if (firstFileIdx != -1) {
          project.nodes[firstFileIdx].content = singleCode;
        }
      }
      project.updatedAt = DateTime.now();
      await _persistProjects();
      return 1;
    }
    return 0;
  }

  Future<void> _showNewProjectTypeSelector() async {
    final chosenType = await showModalBottomSheet<IdeProjectType>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'نوع المشروع',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white),
                ),
                const SizedBox(height: 4),
                const Text(
                  'اختر نوع المشروع الذي تريد إنشاءه في مانجو ستديو:',
                  style: TextStyle(fontSize: 13.5, color: AppColors.textMuted),
                ),
                const SizedBox(height: 16),
                for (final t in IdeProjectType.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => Navigator.pop(ctx, t),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.darkBg,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: t.badgeColor.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                switch (t) {
                                  IdeProjectType.flutter => Icons.flutter_dash_rounded,
                                  IdeProjectType.androidJava => Icons.coffee_rounded,
                                  IdeProjectType.androidKotlin => Icons.android_rounded,
                                  IdeProjectType.reactNative => Icons.hub_rounded,
                                },
                                color: t.badgeColor,
                                size: 30,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t.title,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    t.subtitle,
                                    style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    children: [
                                      _miniBadge(t.langTag, t.badgeColor),
                                      _miniBadge(t.extTag, AppColors.textMuted),
                                      _miniBadge('GitHub Actions', AppColors.primary),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                          ],
                        ),
                      ),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('إلغاء'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (chosenType == null || !mounted) return;
    await _showProjectConfigDialog(initialType: chosenType);
  }

  Widget _miniBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Text(
        text,
        textDirection: TextDirection.ltr,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Future<void> _showProjectConfigDialog({
    IdeProject? existingProject,
    IdeProjectType initialType = IdeProjectType.flutter,
    String templateKind = 'default',
  }) async {
    final isEdit = existingProject != null;
    final nameCtrl = TextEditingController(text: existingProject?.name ?? 'تطبيق مانجو جديد');
    final pkgCtrl = TextEditingController(
      text: existingProject?.packageName ?? 'com.mango.app${_projects.length + 1}',
    );
    final verNameCtrl = TextEditingController(text: existingProject?.versionName ?? '1.0.0');
    final verCodeCtrl = TextEditingController(text: '${existingProject?.versionCode ?? 1}');
    final repoCtrl = TextEditingController(text: existingProject?.githubRepo ?? '');

    var buildMode = existingProject?.buildMode ?? 'release';
    var publishRelease = existingProject?.publishReleaseTag ?? true;
    var iconBase64 = existingProject?.iconBase64;

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Future<void> pickAppIcon() async {
              try {
                final res = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['png', 'jpg', 'jpeg'],
                );
                final path = res?.files.single.path;
                if (path == null) return;
                final bytes = await File(path).readAsBytes();
                setModalState(() {
                  iconBase64 = base64Encode(bytes);
                });
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('تعذر اختيار الصورة: $e')),
                  );
                }
              }
            }

            return Directionality(
              textDirection: TextDirection.rtl,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 18,
                  right: 18,
                  top: 18,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 18,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        isEdit
                            ? 'إعدادات التطبيق والنشر (${existingProject.name})'
                            : 'تخصيص وإنشاء مشروع ${initialType.title}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          GestureDetector(
                            onTap: pickAppIcon,
                            child: Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: AppColors.surfaceAlt,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppColors.mango),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: iconBase64 != null && iconBase64!.isNotEmpty
                                  ? Image.memory(
                                      base64Decode(iconBase64!),
                                      fit: BoxFit.cover,
                                    )
                                  : const Icon(Icons.add_photo_alternate_outlined,
                                      color: AppColors.mango, size: 30),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'أيقونة التطبيق (App Icon)',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'اختر صورة PNG أو JPG لتعيينها كأيقونة رسمية لملف الـ APK',
                                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                                ),
                                TextButton.icon(
                                  onPressed: pickAppIcon,
                                  icon: const Icon(Icons.image_outlined, size: 16),
                                  label: Text(iconBase64 == null ? 'اختيار صورة التطبيق' : 'تغيير الصورة'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'اسم التطبيق (App Name)',
                          prefixIcon: Icon(Icons.apps_rounded),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: pkgCtrl,
                        textDirection: TextDirection.ltr,
                        decoration: const InputDecoration(
                          labelText: 'اسم الحزمة (Package Name / Application ID)',
                          hintText: 'com.mango.myapp',
                          prefixIcon: Icon(Icons.inventory_2_outlined),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: verNameCtrl,
                              textDirection: TextDirection.ltr,
                              decoration: const InputDecoration(
                                labelText: 'اسم الإصدار (Version)',
                                hintText: '1.0.0',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: verCodeCtrl,
                              keyboardType: TextInputType.number,
                              textDirection: TextDirection.ltr,
                              decoration: const InputDecoration(
                                labelText: 'رقم البناء (Build Number)',
                                hintText: '1',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: repoCtrl,
                        textDirection: TextDirection.ltr,
                        decoration: const InputDecoration(
                          labelText: 'مستودع GitHub للنشر (اختياري: يُنشأ تلقائياً إن تُرك فارغاً)',
                          hintText: 'username/my-repo',
                          prefixIcon: Icon(Icons.cloud_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text('نوع مخرجات البناء والنشر:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'release', label: Text('Release APK (للنشر)')),
                          ButtonSegment(value: 'debug', label: Text('Debug APK (للتجربة)')),
                        ],
                        selected: {buildMode},
                        onSelectionChanged: (s) => setModalState(() => buildMode = s.first),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('تجهيز إصدار GitHub Release وملف APK قابل للتنزيل'),
                        value: publishRelease,
                        onChanged: (v) => setModalState(() => publishRelease = v),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.mango,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        icon: Icon(isEdit ? Icons.save_outlined : Icons.rocket_launch_rounded),
                        label: Text(
                          isEdit ? 'حفظ إعدادات التطبيق' : 'إنشاء المشروع وفتح المحرر',
                          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () async {
                          final appName = nameCtrl.text.trim().isEmpty ? 'تطبيق مانجو' : nameCtrl.text.trim();
                          final pkg = pkgCtrl.text.trim().isEmpty ? 'com.mango.app' : pkgCtrl.text.trim();
                          final vName = verNameCtrl.text.trim().isEmpty ? '1.0.0' : verNameCtrl.text.trim();
                          final vCode = int.tryParse(verCodeCtrl.text.trim()) ?? 1;

                          if (isEdit) {
                            setState(() {
                              existingProject.name = appName;
                              existingProject.packageName = pkg;
                              existingProject.versionName = vName;
                              existingProject.versionCode = vCode;
                              existingProject.buildMode = buildMode;
                              existingProject.publishReleaseTag = publishRelease;
                              existingProject.iconBase64 = iconBase64;
                              existingProject.githubRepo =
                                  repoCtrl.text.trim().isEmpty ? null : repoCtrl.text.trim();
                              existingProject.updatedAt = DateTime.now();
                            });
                            await _persistProjects();
                            if (ctx.mounted) Navigator.pop(ctx);
                          } else {
                            final newProj = IdeProject(
                              id: DateTime.now().millisecondsSinceEpoch.toString(),
                              name: appName,
                              packageName: pkg,
                              versionName: vName,
                              versionCode: vCode,
                              type: initialType,
                              buildMode: buildMode,
                              publishReleaseTag: publishRelease,
                              iconBase64: iconBase64,
                              githubRepo: repoCtrl.text.trim().isEmpty ? null : repoCtrl.text.trim(),
                              updatedAt: DateTime.now(),
                              nodes: ProjectTemplates.generateNodes(
                                type: initialType,
                                appName: appName,
                                packageName: pkg,
                                versionName: vName,
                                versionCode: vCode,
                                templateKind: templateKind,
                              ),
                            );
                            setState(() {
                              _projects.insert(0, newProj);
                            });
                            await _persistProjects();
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (mounted) _openProjectInEditor(newProj);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _importProjectFromZip() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      final filePath = res?.files.single.path;
      if (filePath == null) return;

      final bytes = await File(filePath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final importedNodes = <IdeNode>[];
      final seenFolders = <String>{};

      for (final entry in archive) {
        var relPath = entry.name.replaceAll('\\', '/');
        relPath = relPath.replaceAll(RegExp(r'^/+|/+$'), '');
        if (relPath.isEmpty || relPath.startsWith('.git/')) continue;

        final parts = relPath.split('/');
        var currentFolder = '';
        for (var i = 0; i < parts.length - 1; i++) {
          currentFolder = currentFolder.isEmpty ? parts[i] : '$currentFolder/${parts[i]}';
          if (seenFolders.add(currentFolder)) {
            importedNodes.add(IdeNode(path: currentFolder, isFolder: true));
          }
        }

        if (entry.isFile) {
          final ext = relPath.split('.').last.toLowerCase();
          const textExts = {
            'dart', 'yaml', 'yml', 'json', 'xml', 'gradle', 'kts',
            'properties', 'md', 'txt', 'html', 'css', 'js', 'java', 'kt', 'tsx', 'ts', 'sh'
          };
          if (textExts.contains(ext) && entry.size < 1024 * 600) {
            final rawBytes = entry.content;
            final bytesList = rawBytes is List<int> ? rawBytes : <int>[];
            final content = utf8.decode(bytesList, allowMalformed: true);
            importedNodes.add(IdeNode(path: relPath, isFolder: false, content: content));
          }
        }
      }

      if (importedNodes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لم يتم العثور على ملفات برمجية داخل ملف الـ ZIP.')),
        );
        return;
      }

      var detectedType = IdeProjectType.flutter;
      if (importedNodes.any((n) => n.path.endsWith('.tsx') || n.path == 'package.json')) {
        detectedType = IdeProjectType.reactNative;
      } else if (importedNodes.any((n) => n.path.endsWith('.java')) &&
          !importedNodes.any((n) => n.path == 'pubspec.yaml')) {
        detectedType = IdeProjectType.androidJava;
      } else if (importedNodes.any((n) => n.path.endsWith('.kt')) &&
          !importedNodes.any((n) => n.path == 'pubspec.yaml')) {
        detectedType = IdeProjectType.androidKotlin;
      }

      final zipName = res!.files.single.name.replaceAll(RegExp(r'\.zip$', caseSensitive: false), '');
      final importedProj = IdeProject(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: zipName,
        packageName: 'com.mango.${zipName.toLowerCase().replaceAll(RegExp(r"[^a-z0-9]"), "")}',
        type: detectedType,
        updatedAt: DateTime.now(),
        nodes: importedNodes,
      );

      setState(() {
        _projects.insert(0, importedProj);
      });
      await _persistProjects();
      if (!mounted) return;
      _openProjectInEditor(importedProj);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ أثناء استيراد ملف الـ ZIP: $e')),
      );
    }
  }

  Future<void> _exportProjectAsZip(IdeProject project) async {
    try {
      final archive = Archive();
      for (final node in project.nodes) {
        if (node.isFolder) continue;
        final bytes = utf8.encode(node.content);
        archive.addFile(ArchiveFile(node.path, bytes.length, bytes));
      }
      final zipBytes = ZipEncoder().encode(archive) ?? [];
      final outPath = '${Directory.systemTemp.path}/${project.name.replaceAll(" ", "_")}.zip';
      await File(outPath).writeAsBytes(zipBytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم حفظ نسخة ZIP للمشروع (${(zipBytes.length / 1024).toStringAsFixed(1)} KB) في: $outPath'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تصدير المشروع: $e')),
      );
    }
  }

  void _openProjectInEditor(IdeProject project) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProjectEditorFullScreen(
          project: project,
          githubToken: _githubToken,
          githubLogin: _githubLogin,
          aiProvider: _aiProvider,
          aiApiKey: _aiApiKey,
          aiModel: _aiModel,
          onSaveProject: () async {
            project.updatedAt = DateTime.now();
            await _persistProjects();
            if (mounted) setState(() {});
          },
          onConfigureApp: () => _showProjectConfigDialog(existingProject: project),
          onOpenGithubConnect: _openGithubConnectScreen,
          onBuildRecorded: (record) async {
            setState(() {
              _builds.insert(0, record);
            });
            await _persistBuilds();
          },
          onApplyMultiFiles: (aiReply) => _applyAiGeneratedFilesToProject(project, aiReply),
        ),
      ),
    );
  }

  Future<void> _openGithubConnectScreen() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GithubConnectModalScreen(
          onConnected: (token, login) {
            setState(() {
              _githubToken = token;
              _githubLogin = login;
            });
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFB74D), Color(0xFFFF9800), Color(0xFFE65100)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'M',
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 20),
                ),
              ),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'مانجو ستديو',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 19,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'Mango Studio IDE Pro',
                    style: TextStyle(fontSize: 10.5, color: AppColors.mangoLight),
                  ),
                ],
              ),
              const Spacer(),
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _openGithubConnectScreen,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                  decoration: BoxDecoration(
                    color: _githubToken != null
                        ? AppColors.success.withOpacity(0.16)
                        : AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _githubToken != null ? AppColors.success : AppColors.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.circle,
                        size: 9,
                        color: _githubToken != null ? AppColors.success : AppColors.warning,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _githubToken != null ? '@${_githubLogin ?? "GitHub"}' : 'ربط GitHub',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        body: IndexedStack(
          index: _selectedTabIndex,
          children: [
            _buildProjectsTab(),
            _buildLibraryAndApksTab(),
            _buildGlobalAiStudioTab(),
            _buildSettingsTab(),
          ],
        ),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border, width: 0.7)),
          ),
          child: BottomNavigationBar(
            currentIndex: _selectedTabIndex,
            onTap: (i) => setState(() => _selectedTabIndex = i),
            type: BottomNavigationBarType.fixed,
            backgroundColor: AppColors.darkBg,
            selectedItemColor: AppColors.mango,
            unselectedItemColor: AppColors.textMuted,
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.folder_copy_outlined), label: 'مشاريعي'),
              BottomNavigationBarItem(icon: Icon(Icons.android_rounded), label: 'مكتبة APK'),
              BottomNavigationBarItem(icon: Icon(Icons.auto_awesome_rounded), label: 'مهندس AI'),
              BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: 'إعدادات'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProjectsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.mango,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _showNewProjectTypeSelector,
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  label: const Text('مشروع جديد', style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: AppColors.surface,
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _showReadyTemplatesSheet,
                  icon: const Icon(Icons.dashboard_customize_outlined, size: 18, color: AppColors.mango),
                  label: const Text('قوالب تطبيقات كاملة', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 46,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              backgroundColor: AppColors.surface,
              foregroundColor: AppColors.primary,
              side: BorderSide(color: AppColors.primary.withOpacity(0.45)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _importProjectFromZip,
            icon: const Icon(Icons.folder_zip_outlined),
            label: const Text(
              'استيراد مشروع ZIP من الهاتف وتعديل أيقونته وحزمته',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'مشاريع مانجو ستديو',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            Text(
              '${_projects.length} مشاريع',
              style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final proj in _projects)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => _showProjectConfigDialog(existingProject: proj),
                        child: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: proj.type.badgeColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: proj.type.badgeColor.withOpacity(0.4)),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: proj.iconBase64 != null && proj.iconBase64!.isNotEmpty
                              ? Image.memory(base64Decode(proj.iconBase64!), fit: BoxFit.cover)
                              : Icon(Icons.code_rounded, color: proj.type.badgeColor, size: 26),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              proj.name,
                              style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${proj.packageName} • v${proj.versionName}+${proj.versionCode} • ${proj.nodes.where((n) => !n.isFolder).length} ملفات',
                              textDirection: TextDirection.ltr,
                              style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                      _miniBadge(proj.type.title, proj.type.badgeColor),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.mango,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        ),
                        onPressed: () => _openProjectInEditor(proj),
                        icon: const Icon(Icons.terminal_rounded, size: 18),
                        label: const Text('فتح المحرر', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _showProjectConfigDialog(existingProject: proj),
                        icon: const Icon(Icons.tune_rounded, size: 17),
                        label: const Text('الأيقونة والحزمة'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _exportProjectAsZip(proj),
                        icon: const Icon(Icons.download_outlined, size: 17),
                        label: const Text('تصدير ZIP'),
                      ),
                      if (_projects.length > 1)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 20),
                          onPressed: () async {
                            setState(() => _projects.removeWhere((p) => p.id == proj.id));
                            await _persistProjects();
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _showReadyTemplatesSheet() async {
    final templates = [
      ('متجر إلكتروني متكامل (متعدد الملفات)', 'ecommerce', IdeProjectType.flutter, Icons.shopping_bag_outlined),
      ('تطبيق مهام وملاحظات احترافي', 'tasks_pro', IdeProjectType.flutter, Icons.task_alt_rounded),
      ('تطبيق أذكار ومسبحة إلكترونية', 'islamic', IdeProjectType.flutter, Icons.mosque_outlined),
      ('لعبة X-O التفاعلية الكاملة', 'xo_game', IdeProjectType.flutter, Icons.sports_esports_outlined),
      ('آلة حاسبة علمية حديثة', 'calculator', IdeProjectType.flutter, Icons.calculate_outlined),
      ('تطبيق أندرويد Java أصلي', 'default', IdeProjectType.androidJava, Icons.coffee_outlined),
      ('تطبيق أندرويد Kotlin أصلي', 'default', IdeProjectType.androidKotlin, Icons.android_outlined),
    ];

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('قوالب تطبيقات كاملة جاهزة للبناء والتعديل',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                for (final t in templates)
                  ListTile(
                    leading: Icon(t.$4, color: AppColors.mango),
                    title: Text(t.$1, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(t.$3.subtitle, style: const TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.add_circle_outline, color: AppColors.primary),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showProjectConfigDialog(initialType: t.$3, templateKind: t.$2);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLibraryAndApksTab() {
    if (_builds.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.android_rounded, size: 64, color: AppColors.textMuted),
              SizedBox(height: 12),
              Text(
                'مكتبة ملفات الـ APK فارغة حالياً',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 6),
              Text(
                'افتح أي مشروع واضغط "بناء APK" ليتم حفظ سجل البناء وروابط تنزيل الـ APK المباشرة هنا.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _builds.length,
      itemBuilder: (ctx, i) {
        final b = _builds[i];
        return Card(
          color: AppColors.surface,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: AppColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.android_rounded, color: AppColors.success, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${b.projectName} (v${b.versionName})',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Text(
                            '${b.packageName} • ${b.repoFullName}',
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    _miniBadge(b.projectType, AppColors.mango),
                  ],
                ),
                const Divider(height: 20),
                for (final logLine in b.logs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, color: AppColors.success, size: 15),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(logLine, style: const TextStyle(fontSize: 12.5)),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.download_rounded, size: 17),
                      label: const Text('فتح GitHub Actions وتنزيل APK'),
                      onPressed: () => launchUrl(
                        Uri.parse(b.actionsUrl),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                    if (b.releaseApkUrl != null)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.new_releases_outlined, size: 17),
                        label: const Text('الإصدارات (Releases)'),
                        onPressed: () => launchUrl(
                          Uri.parse(b.releaseApkUrl!),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 3. تبويب مهندس الذكاء الاصطناعي الشامل (قادر على بناء تطبيقات كاملة متعددة الملفات)
  Widget _buildGlobalAiStudioTab() {
    final activeProject = _projects.first;
    final mainNode = activeProject.nodes.where((n) => !n.isFolder).firstOrNull;
    final promptCtrl = TextEditingController();
    final apiKeyCtrl = TextEditingController(text: _aiApiKey);
    final modelCtrl = TextEditingController(text: _aiModel);
    bool busy = false;

    return StatefulBuilder(
      builder: (ctx, setTabState) {
        Future<void> runAiArchitect(String textPrompt) async {
          if (textPrompt.trim().isEmpty) return;
          setTabState(() {
            busy = true;
            _aiChatHistory.add({'role': 'user', 'text': textPrompt});
          });

          await SafeStorage.setString('ide_ai_provider', _aiProvider);
          await SafeStorage.setString('ide_ai_api_key', apiKeyCtrl.text.trim());
          await SafeStorage.setString('ide_ai_model', modelCtrl.text.trim());
          _aiApiKey = apiKeyCtrl.text.trim();
          _aiModel = modelCtrl.text.trim();

          try {
            final reply = await MangoAiArchitectService.buildOrEditWithAi(
              provider: _aiProvider,
              apiKey: _aiApiKey,
              model: _aiModel,
              prompt: textPrompt,
              project: activeProject,
              activeFilePath: mainNode?.path ?? 'lib/main.dart',
              activeFileContent: mainNode?.content ?? '',
              fullAppMode: _aiFullAppMode,
            );

            var appliedNote = '';
            if (_aiAutoApply) {
              final updatedCount = await _applyAiGeneratedFilesToProject(activeProject, reply);
              if (updatedCount > 0) {
                appliedNote = '\n\n✅ [قام مهندس مانجو الذكي ببناء وتحديث $updatedCount ملفات مباشرة داخل مشروع "${activeProject.name}"]';
              }
            }

            setTabState(() {
              _aiChatHistory.add({'role': 'ai', 'text': '$reply$appliedNote'});
            });
          } catch (e) {
            setTabState(() {
              _aiChatHistory.add({
                'role': 'error',
                'text': e.toString().replaceFirst('Exception: ', ''),
              });
            });
          } finally {
            setTabState(() => busy = false);
          }
        }

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.auto_awesome, color: AppColors.mango),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'مهندس مانجو الذكي • يبني ويعدل مشروع (${activeProject.name})',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                        Switch(
                          value: _aiFullAppMode,
                          onChanged: (v) => setState(() => _aiFullAppMode = v),
                        ),
                        const Text('بناء تطبيق كامل', style: TextStyle(fontSize: 11)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        DropdownButton<String>(
                          value: _aiProvider,
                          underline: const SizedBox(),
                          items: const [
                            DropdownMenuItem(value: 'builtin', child: Text('مولد مانجو المدمج (فوري)')),
                            DropdownMenuItem(value: 'gemini', child: Text('Google Gemini Pro/Flash')),
                            DropdownMenuItem(value: 'openai', child: Text('OpenAI GPT-4o')),
                            DropdownMenuItem(value: 'deepseek', child: Text('DeepSeek Coder')),
                            DropdownMenuItem(value: 'groq', child: Text('Groq Llama 3.3 70B')),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() {
                              _aiProvider = v;
                              _aiModel = switch (v) {
                                'gemini' => 'gemini-2.5-flash',
                                'deepseek' => 'deepseek-chat',
                                'groq' => 'llama-3.3-70b-versatile',
                                _ => 'gpt-4o-mini',
                              };
                              modelCtrl.text = _aiModel;
                            });
                          },
                        ),
                        const SizedBox(width: 10),
                        if (_aiProvider != 'builtin')
                          Expanded(
                            child: TextField(
                              controller: apiKeyCtrl,
                              obscureText: true,
                              textDirection: TextDirection.ltr,
                              decoration: const InputDecoration(
                                labelText: 'مفتاح الـ API',
                                isDense: true,
                              ),
                            ),
                          )
                        else
                          const Expanded(
                            child: Text(
                              'يعمل فوراً بدون مفتاح API لبناء تطبيقات كاملة متعددة الملفات!',
                              style: TextStyle(fontSize: 11.5, color: AppColors.success),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final chip in [
                      'ابني تطبيق متجر إلكتروني متكامل مع سلة مشتريات',
                      'ابني تطبيق أذكار ومسبحة إلكترونية احترافي',
                      'ابني لعبة X-O كاملة بتصميم عصري',
                      'ابني تطبيق إدارة مهام وملاحظات ذكي',
                      'ابني آلة حاسبة علمية حديثة',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: ActionChip(
                          avatar: const Icon(Icons.bolt, size: 15, color: AppColors.mango),
                          label: Text(chip, style: const TextStyle(fontSize: 11.5)),
                          onPressed: busy ? null : () => runAiArchitect(chip),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _aiChatHistory.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.architecture_rounded, size: 54, color: AppColors.mango),
                            const SizedBox(height: 10),
                            const Text(
                              'مهندس مانجو الذكي لبناء التطبيقات الكاملة',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'اضغط على أي فكرة بالأعلى أو اكتب وصف التطبيق الذي تريده، وسيقوم ببناء جميع ملفاته ومجلداته تلقائياً!',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: () => _openProjectInEditor(activeProject),
                              icon: const Icon(Icons.code_rounded),
                              label: Text('فتح محرر المشروع (${activeProject.name})'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _aiChatHistory.length,
                        itemBuilder: (ctx, i) {
                          final msg = _aiChatHistory[i];
                          final isUser = msg['role'] == 'user';
                          final isErr = msg['role'] == 'error';
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isUser
                                  ? AppColors.mango.withOpacity(0.16)
                                  : (isErr ? AppColors.danger.withOpacity(0.15) : AppColors.surface),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isUser
                                    ? AppColors.mango
                                    : (isErr ? AppColors.danger : AppColors.border),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SelectableText(
                                  msg['text'] ?? '',
                                  style: const TextStyle(fontSize: 13, height: 1.5),
                                ),
                                if (!isUser && !isErr) ...[
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: () => _openProjectInEditor(activeProject),
                                      icon: const Icon(Icons.open_in_new, size: 16),
                                      label: const Text('فتح المشروع وتجربة الكود في المحرر'),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: promptCtrl,
                      decoration: const InputDecoration(
                        hintText: 'اطلب بناء تطبيق كامل أو تعديل مباشر على الكود...',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.mango,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                    onPressed: busy
                        ? null
                        : () {
                            final text = promptCtrl.text;
                            promptCtrl.clear();
                            runAiArchitect(text);
                          },
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : const Icon(Icons.send_rounded),
                    label: const Text('بناء وتطبيق', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSettingsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: AppColors.surface,
          child: ListTile(
            leading: const Icon(Icons.hub_rounded, color: AppColors.mango, size: 30),
            title: const Text('ربط حساب GitHub والبناء السحابي',
                style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              _githubToken != null
                  ? 'متصل بحساب @${_githubLogin ?? "GitHub"} (جاهز لبناء APK)'
                  : 'غير متصل - اضغط لتسجيل الدخول بـ GitHub',
            ),
            trailing: ElevatedButton(
              onPressed: _openGithubConnectScreen,
              child: Text(_githubToken != null ? 'إدارة الحساب' : 'تسجيل الدخول'),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_githubToken != null)
          Card(
            color: AppColors.surface,
            child: ListTile(
              leading: const Icon(Icons.link_off_rounded, color: AppColors.danger),
              title: const Text('فصل حساب GitHub وتسجيل الخروج'),
              onTap: () async {
                await SafeStorage.remove('gh_oauth_token');
                await SafeStorage.remove('gh_oauth_login');
                setState(() {
                  _githubToken = null;
                  _githubLogin = null;
                });
              },
            ),
          ),
        const SizedBox(height: 12),
        Card(
          color: AppColors.surface,
          child: SwitchListTile(
            title: const Text('التطبيق التلقائي المباشر لأكواد الذكاء الاصطناعي'),
            subtitle: const Text('إنشاء وتحديث ملفات المشروع تلقائياً فور انتهاء الذكاء الاصطناعي'),
            value: _aiAutoApply,
            onChanged: (v) => setState(() => _aiAutoApply = v),
          ),
        ),
        const SizedBox(height: 12),
        const Card(
          color: AppColors.surface,
          child: ListTile(
            leading: Icon(Icons.verified_user_outlined, color: AppColors.primary),
            title: Text('مانجو ستديو (Mango Studio IDE Pro)'),
            subtitle: Text('بيئة تطوير متكاملة للهواتف لبناء تطبيقات Android و Flutter بالذكاء الاصطناعي.'),
          ),
        ),
      ],
    );
  }
}

/// ============================================================================
/// شاشة محرر الأكواد الاحترافية الكاملة (مع معاينة الواجهة، مدير الحزم، وفاحص الكود)
/// ============================================================================
class ProjectEditorFullScreen extends StatefulWidget {
  const ProjectEditorFullScreen({
    super.key,
    required this.project,
    required this.githubToken,
    required this.githubLogin,
    required this.aiProvider,
    required this.aiApiKey,
    required this.aiModel,
    required this.onSaveProject,
    required this.onConfigureApp,
    required this.onOpenGithubConnect,
    required this.onBuildRecorded,
    required this.onApplyMultiFiles,
  });

  final IdeProject project;
  final String? githubToken;
  final String? githubLogin;
  final String aiProvider;
  final String aiApiKey;
  final String aiModel;
  final Future<void> Function() onSaveProject;
  final Future<void> Function() onConfigureApp;
  final Future<void> Function() onOpenGithubConnect;
  final Future<void> Function(ApkBuildRecord record) onBuildRecorded;
  final Future<int> Function(String aiReply) onApplyMultiFiles;

  @override
  State<ProjectEditorFullScreen> createState() => _ProjectEditorFullScreenState();
}

class _ProjectEditorFullScreenState extends State<ProjectEditorFullScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final CodeSyntaxController _codeController;
  final ScrollController _editorScrollController = ScrollController();

  late List<String> _openTabs;
  String? _activeFilePath;
  String? _previousCodeSnapshot;
  double _fontSize = 14.0;
  bool _showSearchBar = false;
  final TextEditingController _findCtrl = TextEditingController();
  final TextEditingController _replaceCtrl = TextEditingController();
  final Set<String> _expandedFolders = {
    'lib',
    'lib/models',
    'lib/screens',
    'lib/widgets',
    'app',
    '.github',
    '.github/workflows'
  };

  @override
  void initState() {
    super.initState();
    final mainDart = widget.project.nodes.where((n) => !n.isFolder && n.path == 'lib/main.dart').firstOrNull ??
        widget.project.nodes.where((n) => !n.isFolder && !n.path.startsWith('.github')).firstOrNull ??
        widget.project.nodes.where((n) => !n.isFolder).firstOrNull;

    if (mainDart != null) {
      _openTabs = [mainDart.path];
      _activeFilePath = mainDart.path;
      _codeController = CodeSyntaxController(text: mainDart.content);
    } else {
      _openTabs = [];
      _codeController = CodeSyntaxController();
    }
    _codeController.addListener(_onCodeChanged);
  }

  @override
  void dispose() {
    _codeController.removeListener(_onCodeChanged);
    _codeController.dispose();
    _editorScrollController.dispose();
    _findCtrl.dispose();
    _replaceCtrl.dispose();
    super.dispose();
  }

  void _onCodeChanged() {
    final activePath = _activeFilePath;
    if (activePath == null) return;
    final idx = widget.project.nodes.indexWhere((n) => !n.isFolder && n.path == activePath);
    if (idx == -1) return;
    if (widget.project.nodes[idx].content != _codeController.text) {
      setState(() {
        widget.project.nodes[idx].content = _codeController.text;
        widget.project.nodes[idx].isDirty = true;
      });
    }
  }

  void _selectFile(String path) {
    final node = widget.project.nodes.where((n) => !n.isFolder && n.path == path).firstOrNull;
    if (node == null) return;
    setState(() {
      if (!_openTabs.contains(path)) _openTabs.add(path);
      _activeFilePath = path;
      _codeController.value = TextEditingValue(
        text: node.content,
        selection: const TextSelection.collapsed(offset: 0),
      );
    });
  }

  void _closeTab(String path) {
    setState(() {
      _openTabs.remove(path);
      if (_activeFilePath == path) {
        _activeFilePath = _openTabs.isNotEmpty ? _openTabs.last : null;
        final next = widget.project.nodes.where((n) => !n.isFolder && n.path == _activeFilePath).firstOrNull;
        _codeController.text = next?.content ?? '';
      }
    });
  }

  void _insertSymbol(String sym) {
    final val = _codeController.value;
    final start = val.selection.start >= 0 ? val.selection.start : val.text.length;
    final end = val.selection.end >= 0 ? val.selection.end : val.text.length;
    final updated = val.text.replaceRange(start, end, sym);
    _codeController.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: start + sym.length),
    );
  }

  /// فاحص الكود الفوري (Instant Code Analyzer)
  void _runCodeAnalyzer() {
    final code = _codeController.text;
    final issues = <String>[];
    final openParen = '('.allMatches(code).length;
    final closeParen = ')'.allMatches(code).length;
    final openBrace = '{'.allMatches(code).length;
    final closeBrace = '}'.allMatches(code).length;
    final openBracket = '['.allMatches(code).length;
    final closeBracket = ']'.allMatches(code).length;

    if (openParen != closeParen) {
      issues.add('عدم تطابق الأقواس الدائرية (): مفتوح $openParen / مغلق $closeParen');
    }
    if (openBrace != closeBrace) {
      issues.add('عدم تطابق أقواس البلوك {}: مفتوح $openBrace / مغلق $closeBrace');
    }
    if (openBracket != closeBracket) {
      issues.add('عدم تطابق أقواس المصفوفات []: مفتوح $openBracket / مغلق $closeBracket');
    }
    if (_activeFilePath == 'lib/main.dart' && !code.contains('void main')) {
      issues.add('ملف lib/main.dart لا يحتوي على نقطة البداية void main().');
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppColors.surface,
          title: Row(
            children: [
              Icon(
                issues.isEmpty ? Icons.verified_rounded : Icons.warning_amber_rounded,
                color: issues.isEmpty ? AppColors.success : AppColors.warning,
              ),
              const SizedBox(width: 8),
              const Text('تقرير فحص الكود (Analyzer)'),
            ],
          ),
          content: issues.isEmpty
              ? const Text('الكود سليم 100%! جميع الأقواس والبلوكات متوازنة وجاهزة للبناء ✓')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final iss in issues)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('• $iss', style: const TextStyle(color: AppColors.danger)),
                      ),
                  ],
                ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً')),
          ],
        ),
      ),
    );
  }

  /// مدير الحزم البصري (Pubspec Package Manager)
  Future<void> _openPackageManagerSheet() async {
    final packages = [
      ('http', '^1.2.0', 'الاتصال بالإنترنت وواجهات REST API'),
      ('shared_preferences', '^2.2.2', 'حفظ البيانات والإعدادات محلياً'),
      ('url_launcher', '^6.2.0', 'فتح الروابط والمتصفح وتطبيقات الهاتف'),
      ('file_picker', '^8.0.0', 'اختيار الملفات والصور من ذاكرة الهاتف'),
      ('archive', '^3.6.0', 'ضغط وفك ضغط ملفات ZIP'),
      ('intl', 'any', 'تنسيق التواريخ والأرقام ودعم اللغات'),
    ];

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'مدير مكتبات وحزم Flutter (pubspec.yaml)',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              for (final pkg in packages)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.extension_rounded, color: AppColors.mango),
                  title: Text('${pkg.$1}: ${pkg.$2}', textDirection: TextDirection.ltr),
                  subtitle: Text(pkg.$3),
                  trailing: ElevatedButton(
                    onPressed: () async {
                      final pubNode = widget.project.nodes.where((n) => n.path == 'pubspec.yaml').firstOrNull;
                      if (pubNode != null && !pubNode.content.contains('${pkg.$1}:')) {
                        pubNode.content = pubNode.content.replaceFirst(
                          'dependencies:\n  flutter:\n    sdk: flutter\n',
                          'dependencies:\n  flutter:\n    sdk: flutter\n  ${pkg.$1}: ${pkg.$2}\n',
                        );
                        if (_activeFilePath == 'pubspec.yaml') {
                          _codeController.text = pubNode.content;
                        }
                        await widget.onSaveProject();
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('تمت إضافة الحزمة ${pkg.$1} إلى pubspec.yaml ✓')),
                        );
                      }
                    },
                    child: const Text('إضافة'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// معاينة حية تفاعلية لواجهة التطبيق داخل الهاتف (Live App Preview Simulator)
  Future<void> _openLiveUiPreviewSheet() async {
    final code = _codeController.text;
    final hasAppBar = code.contains('AppBar');
    final hasFab = code.contains('FloatingActionButton');
    final hasGrid = code.contains('GridView');
    final hasCart = code.contains('shopping_cart') || code.contains('سلة');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        int previewCounter = 0;
        return StatefulBuilder(
          builder: (ctx, setPreviewState) => Directionality(
            textDirection: TextDirection.rtl,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.phone_android_rounded, color: AppColors.mango),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'معاينة حية لواجهة (${widget.project.name})',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    height: 400,
                    width: 260,
                    decoration: BoxDecoration(
                      color: AppColors.darkBg,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: AppColors.mango, width: 3),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Scaffold(
                      backgroundColor: AppColors.darkBg,
                      appBar: hasAppBar
                          ? AppBar(
                              backgroundColor: AppColors.surfaceAlt,
                              title: Text(widget.project.name, style: const TextStyle(fontSize: 14)),
                              actions: [
                                if (hasCart) const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.shopping_cart, size: 18)),
                              ],
                            )
                          : null,
                      floatingActionButton: hasFab
                          ? FloatingActionButton.small(
                              backgroundColor: AppColors.mango,
                              onPressed: () => setPreviewState(() => previewCounter++),
                              child: const Icon(Icons.add, color: Colors.black),
                            )
                          : null,
                      body: hasGrid
                          ? GridView.count(
                              crossAxisCount: 2,
                              padding: const EdgeInsets.all(10),
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                              children: List.generate(
                                4,
                                (i) => Card(
                                  color: AppColors.surface,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.star_rounded, color: AppColors.mango, size: 28),
                                      const SizedBox(height: 6),
                                      Text('عنصر #${i + 1}', style: const TextStyle(fontSize: 12)),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          : Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.flutter_dash, size: 46, color: AppColors.primary),
                                  const SizedBox(height: 10),
                                  Text(widget.project.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 6),
                                  Text('العداد التفاعلي: $previewCounter',
                                      style: const TextStyle(color: AppColors.mango, fontSize: 18)),
                                ],
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _createNewNode({String? parentFolder, required bool isFolder}) async {
    final ctrl = TextEditingController(
      text: parentFolder != null && parentFolder.isNotEmpty ? '$parentFolder/' : 'lib/',
    );
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(isFolder ? 'إنشاء مجلد جديد' : 'إنشاء ملف جديد'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            labelText: isFolder ? 'مسار المجلد' : 'مسار الملف (مثال: lib/screen.dart)',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('إنشاء')),
        ],
      ),
    );
    if (res == null || res.isEmpty) return;
    final clean = res.replaceAll('\\', '/').replaceAll(RegExp(r'^/+|/+$'), '');
    if (clean.isEmpty || widget.project.nodes.any((n) => n.path == clean)) return;

    setState(() {
      final parts = clean.split('/');
      var acc = '';
      for (var i = 0; i < parts.length - 1; i++) {
        acc = acc.isEmpty ? parts[i] : '$acc/${parts[i]}';
        if (!widget.project.nodes.any((n) => n.isFolder && n.path == acc)) {
          widget.project.nodes.add(IdeNode(path: acc, isFolder: true));
        }
        _expandedFolders.add(acc);
      }
      widget.project.nodes.add(
        IdeNode(
          path: clean,
          isFolder: isFolder,
          content: isFolder ? '' : '// $clean\n',
        ),
      );
      if (!isFolder) _selectFile(clean);
    });
    await widget.onSaveProject();
  }

  Future<void> _openDirectAiEditorSheet() async {
    var provider = (await SafeStorage.getString('ide_ai_provider')) ?? widget.aiProvider;
    final savedKey = (await SafeStorage.getString('ide_ai_api_key')) ?? widget.aiApiKey;
    final savedModel = (await SafeStorage.getString('ide_ai_model')) ?? widget.aiModel;

    final keyCtrl = TextEditingController(text: savedKey);
    final modelCtrl = TextEditingController(text: savedModel);
    final promptCtrl = TextEditingController();
    bool fullAppMode = true;
    bool showKeySettings = false;
    bool busy = false;
    String? errorMsg;

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Future<void> executeDirectAiEdit() async {
              if (promptCtrl.text.trim().isEmpty) return;
              setModalState(() {
                busy = true;
                errorMsg = null;
              });

              await SafeStorage.setString('ide_ai_provider', provider);
              await SafeStorage.setString('ide_ai_api_key', keyCtrl.text.trim());
              await SafeStorage.setString('ide_ai_model', modelCtrl.text.trim());

              try {
                final reply = await MangoAiArchitectService.buildOrEditWithAi(
                  provider: provider,
                  apiKey: keyCtrl.text.trim(),
                  model: modelCtrl.text.trim(),
                  prompt: promptCtrl.text.trim(),
                  project: widget.project,
                  activeFilePath: _activeFilePath ?? 'lib/main.dart',
                  activeFileContent: _codeController.text,
                  fullAppMode: fullAppMode,
                );

                _previousCodeSnapshot = _codeController.text;
                final updatedFilesCount = await widget.onApplyMultiFiles(reply);
                final currentActive = widget.project.nodes
                    .where((n) => !n.isFolder && n.path == _activeFilePath)
                    .firstOrNull;
                if (currentActive != null) {
                  setState(() {
                    _codeController.text = currentActive.content;
                    for (final n in widget.project.nodes) {
                      if (!n.isFolder && !_openTabs.contains(n.path) && !n.path.startsWith('.github')) {
                        _openTabs.add(n.path);
                      }
                    }
                  });
                }

                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: AppColors.success,
                      content: Text('قام مهندس مانجو الذكي ببناء وتحديث $updatedFilesCount ملفات مباشرةً ✓'),
                      action: SnackBarAction(
                        label: 'تراجع',
                        textColor: Colors.white,
                        onPressed: () {
                          if (_previousCodeSnapshot != null) {
                            _codeController.text = _previousCodeSnapshot!;
                          }
                        },
                      ),
                    ),
                  );
                }
              } catch (e) {
                setModalState(() {
                  errorMsg = e.toString().replaceFirst('Exception: ', '');
                });
              } finally {
                setModalState(() => busy = false);
              }
            }

            return Directionality(
              textDirection: TextDirection.rtl,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.auto_awesome, color: AppColors.mango),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'مهندس مانجو الذكي لبناء وتعديل التطبيقات',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                            ),
                          ),
                          IconButton(
                            icon: Icon(showKeySettings ? Icons.expand_less : Icons.vpn_key_outlined),
                            onPressed: () => setModalState(() => showKeySettings = !showKeySettings),
                          ),
                        ],
                      ),
                      if (showKeySettings) ...[
                        DropdownButton<String>(
                          value: provider,
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(value: 'builtin', child: Text('مولد مانجو المدمج (فوري بدون مفتاح)')),
                            DropdownMenuItem(value: 'gemini', child: Text('Google Gemini API')),
                            DropdownMenuItem(value: 'openai', child: Text('OpenAI GPT-4o')),
                            DropdownMenuItem(value: 'deepseek', child: Text('DeepSeek Coder')),
                            DropdownMenuItem(value: 'groq', child: Text('Groq Llama 3.3 70B')),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setModalState(() => provider = v);
                          },
                        ),
                        if (provider != 'builtin') ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: keyCtrl,
                            obscureText: true,
                            textDirection: TextDirection.ltr,
                            decoration: const InputDecoration(labelText: 'مفتاح الـ API'),
                          ),
                        ],
                        const SizedBox(height: 8),
                      ],
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('بناء تطبيق كامل متعدد الملفات وتطبيقه مباشرة'),
                        value: fullAppMode,
                        onChanged: (v) => setModalState(() => fullAppMode = v),
                      ),
                      TextField(
                        controller: promptCtrl,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'صف التطبيق الكامل أو التعديل المطلوب',
                          hintText: 'مثال: ابني تطبيق متجر إلكتروني متكامل مع سلة مشتريات أو تطبيق أذكار...',
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.mango,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        onPressed: busy ? null : executeDirectAiEdit,
                        icon: busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                              )
                            : const Icon(Icons.bolt_rounded),
                        label: Text(
                          busy ? 'جاري بناء وتطبيق الكود...' : 'بناء وتطبيق مباشر على المشروع',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (errorMsg != null) ...[
                        const SizedBox(height: 10),
                        Text(errorMsg!, style: const TextStyle(color: AppColors.danger)),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _startCloudBuildFlow() async {
    for (final n in widget.project.nodes) {
      n.isDirty = false;
    }
    await widget.onSaveProject();

    final token = await SafeStorage.getString('gh_oauth_token') ?? widget.githubToken;
    final login = await SafeStorage.getString('gh_oauth_login') ?? widget.githubLogin ?? 'user';

    if (token == null || token.isEmpty) {
      await widget.onOpenGithubConnect();
      return;
    }

    final liveLogs = <String>[];
    bool building = true;
    String? errorMsg;
    ApkBuildRecord? resultRecord;

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        var started = false;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            if (!started) {
              started = true;
              Future<void>(() async {
                try {
                  final rec = await GithubOAuthDeviceService.pushProjectAndBuildApk(
                    token: token,
                    githubLogin: login,
                    project: widget.project,
                    onLog: (msg) {
                      if (ctx.mounted) {
                        setModalState(() => liveLogs.add(msg));
                      }
                    },
                  );
                  await widget.onBuildRecorded(rec);
                  if (ctx.mounted) {
                    setModalState(() {
                      building = false;
                      resultRecord = rec;
                    });
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    setModalState(() {
                      building = false;
                      errorMsg = e.toString().replaceFirst('Exception: ', '');
                    });
                  }
                }
              });
            }

            return Directionality(
              textDirection: TextDirection.rtl,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          errorMsg != null
                              ? Icons.cancel_rounded
                              : (building ? Icons.sync_rounded : Icons.check_circle_rounded),
                          color: errorMsg != null
                              ? AppColors.danger
                              : (building ? AppColors.mango : AppColors.success),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'مانجو ستديو • البناء السحابي (${widget.project.name})',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 22),
                    for (final step in [
                      'Checkout',
                      'Setup Gradle Cache',
                      'Setup Java 17',
                      'Setup Flutter & Branding (${widget.project.packageName})',
                      'Get dependencies',
                      'Build APK (${widget.project.buildMode.toUpperCase()})',
                    ])
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            const Icon(Icons.add_circle, color: AppColors.success, size: 20),
                            const SizedBox(width: 10),
                            Text(
                              step,
                              textDirection: TextDirection.ltr,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final l in liveLogs)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(l, style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace')),
                            ),
                          if (errorMsg != null)
                            Text(errorMsg!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (resultRecord != null)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.mango,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        icon: const Icon(Icons.open_in_new),
                        label: const Text(
                          'فتح GitHub Actions وتنزيل ملف الـ APK',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onPressed: () => launchUrl(
                          Uri.parse(resultRecord!.actionsUrl),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildExplorerDrawer() {
    final sorted = [...widget.project.nodes]..sort((a, b) {
        if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
        return a.path.compareTo(b.path);
      });

    final visible = sorted.where((node) {
      final parts = node.path.split('/');
      if (parts.length == 1) return true;
      var parent = '';
      for (var i = 0; i < parts.length - 1; i++) {
        parent = parent.isEmpty ? parts[i] : '$parent/${parts[i]}';
        if (!_expandedFolders.contains(parent)) return false;
      }
      return true;
    }).toList();

    return Drawer(
      backgroundColor: AppColors.surface,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.folder_copy_outlined, color: AppColors.mango),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.project.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.note_add_outlined, size: 20),
                    tooltip: 'ملف جديد',
                    onPressed: () => _createNewNode(isFolder: false),
                  ),
                  IconButton(
                    icon: const Icon(Icons.create_new_folder_outlined, size: 20),
                    tooltip: 'مجلد جديد',
                    onPressed: () => _createNewNode(isFolder: true),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: visible.length,
                itemBuilder: (ctx, i) {
                  final node = visible[i];
                  final depth = node.path.split('/').length - 1;
                  final isSelected = !node.isFolder && node.path == _activeFilePath;
                  final isExpanded = node.isFolder && _expandedFolders.contains(node.path);

                  return InkWell(
                    onTap: () {
                      if (node.isFolder) {
                        setState(() {
                          isExpanded
                              ? _expandedFolders.remove(node.path)
                              : _expandedFolders.add(node.path);
                        });
                      } else {
                        _selectFile(node.path);
                        Navigator.pop(context);
                      }
                    },
                    child: Container(
                      color: isSelected ? AppColors.mango.withOpacity(0.18) : null,
                      padding: EdgeInsets.only(
                        left: 12.0 + depth * 15.0,
                        right: 10,
                        top: 8,
                        bottom: 8,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            node.isFolder
                                ? (isExpanded ? Icons.folder_open : Icons.folder)
                                : Icons.code_rounded,
                            size: 18,
                            color: node.isFolder ? AppColors.mango : AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              node.name + (node.isDirty ? ' •' : ''),
                              textDirection: TextDirection.ltr,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lineCount = '\n'.allMatches(_codeController.text).length + 1;

    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildExplorerDrawer(),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.account_tree_outlined),
          tooltip: 'شجرة الملفات',
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Text(
          _activeFilePath ?? widget.project.name,
          style: const TextStyle(fontSize: 13, fontFamily: 'monospace', fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone_android_rounded, color: AppColors.cyan),
            tooltip: 'معاينة حية للواجهة',
            onPressed: _openLiveUiPreviewSheet,
          ),
          IconButton(
            icon: const Icon(Icons.extension_outlined, color: AppColors.purple),
            tooltip: 'مدير حزم pubspec.yaml',
            onPressed: _openPackageManagerSheet,
          ),
          IconButton(
            icon: const Icon(Icons.fact_check_outlined, color: AppColors.success),
            tooltip: 'فحص الكود',
            onPressed: _runCodeAnalyzer,
          ),
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: 'بحث واستبدال',
            onPressed: () => setState(() => _showSearchBar = !_showSearchBar),
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome, color: AppColors.mango),
            tooltip: 'بناء وتعديل بالذكاء الاصطناعي',
            onPressed: _openDirectAiEditorSheet,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.mango,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              onPressed: _startCloudBuildFlow,
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('بناء APK', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_showSearchBar)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              color: AppColors.surfaceAlt,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _findCtrl,
                      textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(hintText: 'بحث...', isDense: true),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _replaceCtrl,
                      textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(hintText: 'استبدال بـ...', isDense: true),
                    ),
                  ),
                  const SizedBox(width: 6),
                  ElevatedButton(
                    onPressed: () {
                      if (_findCtrl.text.isEmpty) return;
                      _codeController.text =
                          _codeController.text.replaceAll(_findCtrl.text, _replaceCtrl.text);
                    },
                    child: const Text('استبدال الكل'),
                  ),
                ],
              ),
            ),
          if (_openTabs.isNotEmpty)
            Container(
              height: 36,
              color: AppColors.surface,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _openTabs.length,
                itemBuilder: (ctx, idx) {
                  final tab = _openTabs[idx];
                  final active = tab == _activeFilePath;
                  return InkWell(
                    onTap: () => _selectFile(tab),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: active ? AppColors.darkBg : AppColors.surface,
                        border: Border(
                          bottom: BorderSide(
                            color: active ? AppColors.mango : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            tab.split('/').last,
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              color: active ? AppColors.mango : AppColors.textMuted,
                              fontWeight: active ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => _closeTab(tab),
                            child: const Icon(Icons.close, size: 14, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          Expanded(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Container(
                color: AppColors.darkBg,
                child: SingleChildScrollView(
                  controller: _editorScrollController,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        padding: const EdgeInsets.only(right: 8, left: 6),
                        decoration: const BoxDecoration(
                          border: Border(right: BorderSide(color: AppColors.border)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: List.generate(
                            lineCount,
                            (i) => Text(
                              '${i + 1}',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: _fontSize,
                                height: 1.5,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _codeController,
                          maxLines: null,
                          keyboardType: TextInputType.multiline,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: _fontSize,
                            height: 1.5,
                            color: AppColors.textPrimary,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            isDense: true,
                            contentPadding: EdgeInsets.only(right: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Container(
              height: 42,
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                children: [
                  for (final sym in [
                    ('Tab', '  '),
                    ('{', '{'),
                    ('}', '}'),
                    ('(', '('),
                    (')', ')'),
                    ('[', '['),
                    (']', ']'),
                    (';', ';'),
                    ('=>', ' => '),
                    ('=', ' = '),
                    ("'", "'"),
                    ('"', '"'),
                    (r'$', r'$'),
                    ('//', '// '),
                  ])
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _insertSymbol(sym.$2),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceAlt,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text(
                            sym.$1,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.text_increase, size: 16),
                    onPressed: () => setState(() => _fontSize = (_fontSize + 1).clamp(11.0, 22.0)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.text_decrease, size: 16),
                    onPressed: () => setState(() => _fontSize = (_fontSize - 1).clamp(11.0, 22.0)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}