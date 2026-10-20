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
/// 1. نظام اللغة (العربية & English) + نظام المظهر الفاتح والداكن الاحترافي
/// ============================================================================
class S {
  static String lang = 'ar';
  static bool dark = true;

  static bool get isAr => lang == 'ar';
  static TextDirection get dir => isAr ? TextDirection.rtl : TextDirection.ltr;

  static String t(String ar, String en) => isAr ? ar : en;
}

class AppColors {
  static Color get bg => S.dark ? const Color(0xFF0B0F17) : const Color(0xFFF4F6F9);
  static Color get surface => S.dark ? const Color(0xFF141C27) : const Color(0xFFFFFFFF);
  static Color get surfaceAlt => S.dark ? const Color(0xFF1D2738) : const Color(0xFFEEF2F7);
  static Color get editorBg => S.dark ? const Color(0xFF0D1117) : const Color(0xFFFAFBFC);
  static Color get border => S.dark ? const Color(0xFF2B384E) : const Color(0xFFD5DCE6);
  static Color get textPrimary => S.dark ? const Color(0xFFE6EDF3) : const Color(0xFF1C232B);
  static Color get textMuted => S.dark ? const Color(0xFF8B949E) : const Color(0xFF59636E);

  static const Color primary = Color(0xFF2F81F7);
  static const Color mango = Color(0xFFFF9100);
  static const Color mangoDark = Color(0xFFE65100);
  static const Color success = Color(0xFF2EA043);
  static const Color danger = Color(0xFFF85149);
  static const Color warning = Color(0xFFD29922);
  static const Color purple = Color(0xFFA371F7);
}

/// ============================================================================
/// 2. مخزن آمن مزدوج (SharedPreferences + ملف احتياطي مباشر عبر dart:io)
/// ============================================================================
class SafeStorage {
  static final Map<String, String> _memoryCache = {};
  static File get _backupFile => File('${Directory.systemTemp.path}/mango_studio_v8.json');

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
/// 3. النماذج الأساسية (Models)
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
        IdeProjectType.flutter => S.t('تطبيق Flutter متعدد المنصات (Dart)', 'Multi-platform Flutter app (Dart)'),
        IdeProjectType.androidJava => S.t('تطبيق Android أصلي بلغة Java', 'Native Android app in Java'),
        IdeProjectType.androidKotlin => S.t('تطبيق Android أصلي بلغة Kotlin', 'Native Android app in Kotlin'),
        IdeProjectType.reactNative => S.t('تطبيق React Native (TypeScript)', 'React Native app (TypeScript)'),
      };

  Color get badgeColor => switch (this) {
        IdeProjectType.flutter => const Color(0xFF2F81F7),
        IdeProjectType.androidJava => const Color(0xFFD29922),
        IdeProjectType.androidKotlin => const Color(0xFFA371F7),
        IdeProjectType.reactNative => const Color(0xFF00ACC1),
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
  String buildMode; // 'release', 'playstore_aab', 'debug'
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
        'iconBase64': iconBase64,
        'githubRepo': githubRepo,
        'updatedAt': updatedAt.toIso8601String(),
        'nodes': nodes.map((n) => n.toJson()).toList(),
      };

  factory IdeProject.fromJson(Map<String, dynamic> json) => IdeProject(
        id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
        name: json['name'] as String? ?? 'Mango App',
        packageName: json['packageName'] as String? ?? 'com.mango.app',
        versionName: json['versionName'] as String? ?? '1.0.0',
        versionCode: (json['versionCode'] as num?)?.toInt() ?? 1,
        type: IdeProjectType.fromName(json['type'] as String?),
        buildMode: json['buildMode'] as String? ?? 'release',
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
  final String directApkReleaseUrl;
  final String directAabReleaseUrl;
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
    required this.directApkReleaseUrl,
    required this.directAabReleaseUrl,
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
        'directApkReleaseUrl': directApkReleaseUrl,
        'directAabReleaseUrl': directAabReleaseUrl,
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
        directApkReleaseUrl: json['directApkReleaseUrl'] as String? ?? '',
        directAabReleaseUrl: json['directAabReleaseUrl'] as String? ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        logs: ((json['logs'] as List?) ?? []).map((e) => e.toString()).toList(),
      );
}

/// ============================================================================
/// 4. قوالب المشاريع وملف البناء المجهز لـ Google Play (APK + AAB Release)
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

    final baseNodes = <IdeNode>[
      IdeNode(
        path: 'pubspec.yaml',
        isFolder: false,
        content: 'name: $dartPkgName\n'
            'description: $appName - Built with Mango Studio IDE.\n'
            "publish_to: 'none'\n"
            'version: $versionName+$versionCode\n\n'
            'environment:\n'
            "  sdk: '>=3.0.0 <4.0.0'\n\n"
            'dependencies:\n'
            '  flutter:\n'
            '    sdk: flutter\n\n'
            'flutter:\n'
            '  uses-material-design: true\n',
      ),
      IdeNode(path: 'lib', isFolder: true),
    ];

    if (templateKind == 'ecommerce') {
      baseNodes.add(IdeNode(path: 'lib/main.dart', isFolder: false, content: _ecommerceCode(appName)));
    } else if (templateKind == 'tasks_pro') {
      baseNodes.add(IdeNode(path: 'lib/main.dart', isFolder: false, content: _tasksCode(appName)));
    } else if (templateKind == 'islamic') {
      baseNodes.add(IdeNode(path: 'lib/main.dart', isFolder: false, content: _islamicCode(appName)));
    } else if (templateKind == 'calculator') {
      baseNodes.add(IdeNode(path: 'lib/main.dart', isFolder: false, content: _calculatorCode(appName)));
    } else {
      baseNodes.add(IdeNode(path: 'lib/main.dart', isFolder: false, content: _starterFlutterCode(appName)));
    }

    baseNodes.addAll([
      IdeNode(path: '.github', isFolder: true),
      IdeNode(path: '.github/workflows', isFolder: true),
      IdeNode(
        path: '.github/workflows/main.yml',
        isFolder: false,
        content: workflowForType(
          type,
          appName: appName,
          packageName: packageName,
          versionName: versionName,
          versionCode: versionCode,
        ),
      ),
    ]);
    return baseNodes;
  }

  static String _ecommerceCode(String appName) =>
      "import 'package:flutter/material.dart';\n\n"
      'void main() => runApp(const StoreApp());\n\n'
      'class StoreApp extends StatelessWidget {\n'
      '  const StoreApp({super.key});\n\n'
      '  @override\n'
      '  Widget build(BuildContext context) {\n'
      '    return MaterialApp(\n'
      '      debugShowCheckedModeBanner: false,\n'
      "      title: '$appName',\n"
      '      theme: ThemeData.dark(useMaterial3: true).copyWith(\n'
      '        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange, brightness: Brightness.dark),\n'
      '      ),\n'
      '      home: const StoreHomeScreen(),\n'
      '    );\n'
      '  }\n'
      '}\n\n'
      'class StoreHomeScreen extends StatefulWidget {\n'
      '  const StoreHomeScreen({super.key});\n\n'
      '  @override\n'
      '  State<StoreHomeScreen> createState() => _StoreHomeScreenState();\n'
      '}\n\n'
      'class _StoreHomeScreenState extends State<StoreHomeScreen> {\n'
      '  final List<(String, int, IconData)> _products = const [\n'
      "    ('سماعة محيطية Pro', 850, Icons.headphones),\n"
      "    ('ساعة ذكية Ultra', 1450, Icons.watch),\n"
      "    ('شاحن سريع 100W', 420, Icons.bolt),\n"
      "    ('كيبورد ميكانيكي RGB', 980, Icons.keyboard),\n"
      '  ];\n'
      '  final List<(String, int)> _cart = [];\n\n'
      '  @override\n'
      '  Widget build(BuildContext context) {\n'
      '    return Directionality(\n'
      '      textDirection: TextDirection.rtl,\n'
      '      child: Scaffold(\n'
      '        appBar: AppBar(\n'
      "          title: const Text('$appName'),\n"
      '          actions: [\n'
      '            Padding(\n'
      '              padding: const EdgeInsets.symmetric(horizontal: 12),\n'
      '              child: Center(child: Text("السلة (\${_cart.length})")),\n'
      '            ),\n'
      '          ],\n'
      '        ),\n'
      '        body: GridView.builder(\n'
      '          padding: const EdgeInsets.all(14),\n'
      '          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(\n'
      '            crossAxisCount: 2,\n'
      '            mainAxisSpacing: 12,\n'
      '            crossAxisSpacing: 12,\n'
      '            childAspectRatio: 0.8,\n'
      '          ),\n'
      '          itemCount: _products.length,\n'
      '          itemBuilder: (ctx, i) {\n'
      '            final item = _products[i];\n'
      '            return Card(\n'
      '              child: Padding(\n'
      '                padding: const EdgeInsets.all(12),\n'
      '                child: Column(\n'
      '                  mainAxisAlignment: MainAxisAlignment.spaceBetween,\n'
      '                  children: [\n'
      '                    Icon(item.\$3, size: 46, color: Colors.orange),\n'
      '                    Text(item.\$1, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),\n'
      '                    Text("\${item.\$2} ج.م", style: const TextStyle(color: Colors.greenAccent)),\n'
      '                    ElevatedButton(\n'
      '                      onPressed: () => setState(() => _cart.add((item.\$1, item.\$2))),\n'
      '                      child: const Text("إضافة للسلة"),\n'
      '                    ),\n'
      '                  ],\n'
      '                ),\n'
      '              ),\n'
      '            );\n'
      '          },\n'
      '        ),\n'
      '      ),\n'
      '    );\n'
      '  }\n'
      '}\n';

  static String _tasksCode(String appName) =>
      "import 'package:flutter/material.dart';\n\n"
      'void main() => runApp(const TasksApp());\n\n'
      'class TasksApp extends StatelessWidget {\n'
      '  const TasksApp({super.key});\n\n'
      '  @override\n'
      '  Widget build(BuildContext context) {\n'
      '    return MaterialApp(\n'
      '      debugShowCheckedModeBanner: false,\n'
      "      title: '$appName',\n"
      '      theme: ThemeData.dark(useMaterial3: true),\n'
      '      home: const TasksScreen(),\n'
      '    );\n'
      '  }\n'
      '}\n\n'
      'class TasksScreen extends StatefulWidget {\n'
      '  const TasksScreen({super.key});\n\n'
      '  @override\n'
      '  State<TasksScreen> createState() => _TasksScreenState();\n'
      '}\n\n'
      'class _TasksScreenState extends State<TasksScreen> {\n'
      '  final List<(String, bool)> _tasks = [\n'
      "    ('تصميم واجهة التطبيق', false),\n"
      "    ('بناء ملف APK وتجربته', true),\n"
      '  ];\n\n'
      '  @override\n'
      '  Widget build(BuildContext context) {\n'
      '    return Directionality(\n'
      '      textDirection: TextDirection.rtl,\n'
      '      child: Scaffold(\n'
      "        appBar: AppBar(title: const Text('$appName')),\n"
      '        floatingActionButton: FloatingActionButton(\n'
      '          onPressed: () => setState(() => _tasks.add(("مهمة جديدة #\${_tasks.length + 1}", false))),\n'
      '          child: const Icon(Icons.add),\n'
      '        ),\n'
      '        body: ListView.builder(\n'
      '          padding: const EdgeInsets.all(14),\n'
      '          itemCount: _tasks.length,\n'
      '          itemBuilder: (ctx, i) => Card(\n'
      '            child: CheckboxListTile(\n'
      '              value: _tasks[i].\$2,\n'
      '              onChanged: (v) => setState(() => _tasks[i] = (_tasks[i].\$1, v ?? false)),\n'
      '              title: Text(_tasks[i].\$1),\n'
      '            ),\n'
      '          ),\n'
      '        ),\n'
      '      ),\n'
      '    );\n'
      '  }\n'
      '}\n';

  static String _islamicCode(String appName) =>
      "import 'package:flutter/material.dart';\n\n"
      'void main() => runApp(const AzkarApp());\n\n'
      'class AzkarApp extends StatelessWidget {\n'
      '  const AzkarApp({super.key});\n\n'
      '  @override\n'
      '  Widget build(BuildContext context) {\n'
      '    return MaterialApp(\n'
      '      debugShowCheckedModeBanner: false,\n'
      "      title: '$appName',\n"
      '      theme: ThemeData.dark(useMaterial3: true),\n'
      '      home: const AzkarHome(),\n'
      '    );\n'
      '  }\n'
      '}\n\n'
      'class AzkarHome extends StatefulWidget {\n'
      '  const AzkarHome({super.key});\n\n'
      '  @override\n'
      '  State<AzkarHome> createState() => _AzkarHomeState();\n'
      '}\n\n'
      'class _AzkarHomeState extends State<AzkarHome> {\n'
      '  int _count = 0;\n\n'
      '  @override\n'
      '  Widget build(BuildContext context) {\n'
      '    return Directionality(\n'
      '      textDirection: TextDirection.rtl,\n'
      '      child: Scaffold(\n'
      "        appBar: AppBar(title: const Text('$appName')),\n"
      '        body: Center(\n'
      '          child: Column(\n'
      '            mainAxisAlignment: MainAxisAlignment.center,\n'
      '            children: [\n'
      '              const Text("سبحان الله وبحمده، سبحان الله العظيم", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),\n'
      '              const SizedBox(height: 18),\n'
      '              Text("\$_count", style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.amber)),\n'
      '              const SizedBox(height: 18),\n'
      '              ElevatedButton.icon(\n'
      '                onPressed: () => setState(() => _count++),\n'
      '                icon: const Icon(Icons.touch_app),\n'
      '                label: const Text("تسبيح"),\n'
      '              ),\n'
      '            ],\n'
      '          ),\n'
      '        ),\n'
      '      ),\n'
      '    );\n'
      '  }\n'
      '}\n';

  static String _calculatorCode(String appName) =>
      "import 'package:flutter/material.dart';\n\n"
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

  static String _starterFlutterCode(String appName) =>
      "import 'package:flutter/material.dart';\n\n"
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

  /// يبني كلاً من APK وحزمة Google Play (AAB) عند اختيار وضع النشر ويرفعهما في GitHub Releases
  static String workflowForType(
    IdeProjectType type, {
    required String appName,
    required String packageName,
    required String versionName,
    required int versionCode,
    String buildMode = 'release',
  }) {
    final safeAppName = appName.replaceAll('"', '').replaceAll("'", '');
    final safePkg = packageName.trim().isEmpty ? 'com.mango.app' : packageName.trim();
    final isDebug = buildMode == 'debug';
    final buildAabToo = buildMode == 'playstore_aab';
    final apkFlag = isDebug ? '--debug' : '--release';
    final apkFile = isDebug ? 'app-debug.apk' : 'app-release.apk';

    return 'name: Mango Studio Build APK & Play Bundle\n\n'
        'on:\n'
        '  push:\n'
        '    branches: [ main, master ]\n'
        '  workflow_dispatch:\n\n'
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
        '      - name: Prepare Android & Google Play Branding\n'
        '        run: |\n'
        '          if [ ! -f "pubspec.yaml" ]; then\n'
        '            flutter create . --platforms=android --org ${safePkg.split(".").take(2).join(".")}\n'
        '          elif [ ! -d "android" ]; then\n'
        '            flutter create . --platforms=android\n'
        '          fi\n'
        '          if [ -f "CustomAppIcon.png" ]; then\n'
        '            for d in android/app/src/main/res/mipmap-* android/app/src/main/res/drawable*; do\n'
        '              if [ -d "\$d" ] && [ -f "\$d/ic_launcher.png" ]; then\n'
        '                cp CustomAppIcon.png "\$d/ic_launcher.png" || true\n'
        '              fi\n'
        '            done\n'
        '          fi\n'
        '          if [ -f "android/app/src/main/AndroidManifest.xml" ]; then\n'
        '            sed -i \'s/android:label="[^"]*"/android:label="$safeAppName"/g\' android/app/src/main/AndroidManifest.xml || true\n'
        '          fi\n'
        '          if [ -f "android/app/build.gradle" ]; then\n'
        '            sed -i \'s/applicationId = "[^"]*"/applicationId = "$safePkg"/g\' android/app/build.gradle || true\n'
        '            sed -i \'s/applicationId "[^"]*"/applicationId "$safePkg"/g\' android/app/build.gradle || true\n'
        '          fi\n'
        '          if [ -f "android/app/build.gradle.kts" ]; then\n'
        '            sed -i \'s/applicationId = "[^"]*"/applicationId = "$safePkg"/g\' android/app/build.gradle.kts || true\n'
        '          fi\n\n'
        '      - name: Get dependencies\n'
        '        run: flutter pub get\n\n'
        '      - name: Build APK\n'
        '        run: flutter build apk $apkFlag --build-name=$versionName --build-number=$versionCode\n\n'
        '${buildAabToo ? "      - name: Build Google Play Bundle (AAB)\n        run: flutter build appbundle --release --build-name=$versionName --build-number=$versionCode || true\n\n" : ""}'
        '      - name: Upload APK Artifact\n'
        '        uses: actions/upload-artifact@v4\n'
        '        with:\n'
        '          name: app-release\n'
        '          path: build/app/outputs/flutter-apk/$apkFile\n'
        '          if-no-files-found: error\n'
        '          retention-days: 14\n\n'
        '      - name: Publish Direct Download Release\n'
        '        env:\n'
        '          GH_TOKEN: \${{ github.token }}\n'
        '        run: |\n'
        '          cp "build/app/outputs/flutter-apk/$apkFile" app-release.apk\n'
        '          ASSETS="app-release.apk"\n'
        '          if [ -f "build/app/outputs/bundle/release/app-release.aab" ]; then\n'
        '            cp "build/app/outputs/bundle/release/app-release.aab" app-release.aab\n'
        '            ASSETS="app-release.apk app-release.aab"\n'
        '          fi\n'
        '          gh release delete latest-apk --yes || true\n'
        '          git tag -f latest-apk\n'
        '          git push origin -f latest-apk\n'
        '          gh release create latest-apk \$ASSETS --title "$safeAppName v$versionName" --notes "Built by Mango Studio IDE"\n';
  }
}

/// ============================================================================
/// 5. محرر الأكواد الملون المتكيف مع الوضع الفاتح والداكن (Light & Dark Syntax)
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
    final isDark = S.dark;
    final baseStyle = style ??
        TextStyle(
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
          tokenColor = isDark ? const Color(0xFF8B949E) : const Color(0xFF6E7781);
          fontStyle = FontStyle.italic;
        } else if (match.group(3) != null || match.group(4) != null) {
          tokenColor = isDark ? const Color(0xFFA5D6FF) : const Color(0xFF0A3069);
        } else if (match.group(5) != null) {
          tokenColor = isDark ? const Color(0xFFD2A8FF) : const Color(0xFF8250DF);
        } else if (match.group(6) != null) {
          tokenColor = isDark ? const Color(0xFFFF7B72) : const Color(0xFFCF222E);
          weight = FontWeight.w600;
        } else if (match.group(7) != null) {
          tokenColor = isDark ? const Color(0xFFFFA657) : const Color(0xFF953800);
        } else if (match.group(8) != null) {
          tokenColor = isDark ? const Color(0xFF79C0FF) : const Color(0xFF0550AE);
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
/// 6. خدمة GitHub الرسمية المصلحة 100% (Device Flow + Contents API Fallback + Live Jobs)
/// ============================================================================
class GithubOAuthDeviceService {
  static const String defaultClientId = '178c6fc778ccc68e1d6a';

  static Map<String, String> _headers(String token) => {
        'Authorization': 'token ${token.trim()}',
        'Accept': 'application/vnd.github+json',
        'Content-Type': 'application/json',
        'User-Agent': 'Mango-Studio-IDE/8.0',
        'X-GitHub-Api-Version': '2022-11-28',
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
            'User-Agent': 'Mango-Studio-IDE/8.0',
          },
          body: {
            'client_id': clientId,
            'scope': 'repo workflow read:user',
          },
        )
        .timeout(const Duration(seconds: 20));

    if (res.statusCode >= 400) {
      throw Exception('GitHub Error (${res.statusCode})');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
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
            'User-Agent': 'Mango-Studio-IDE/8.0',
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
            .get(Uri.parse('https://api.github.com/user'), headers: _headers(token))
            .timeout(const Duration(seconds: 15));
        if (res.statusCode >= 200 && res.statusCode < 300) {
          return jsonDecode(res.body) as Map<String, dynamic>;
        }
        final resBearer = await http
            .get(
              Uri.parse('https://api.github.com/user'),
              headers: {
                ..._headers(token),
                'Authorization': 'Bearer ${token.trim()}',
              },
            )
            .timeout(const Duration(seconds: 15));
        if (resBearer.statusCode >= 200 && resBearer.statusCode < 300) {
          return jsonDecode(resBearer.body) as Map<String, dynamic>;
        }
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }
    }
    throw Exception('تعذر جلب بيانات المستخدم من GitHub');
  }

  static Future<void> _putSingleFileViaContentsApi({
    required String repoFullName,
    required String branch,
    required String path,
    required List<int> bytes,
    required Map<String, String> headers,
    required String message,
  }) async {
    final uri = Uri.parse('https://api.github.com/repos/$repoFullName/contents/$path?ref=$branch');
    String? existingSha;
    try {
      final getRes = await http.get(uri, headers: headers).timeout(const Duration(seconds: 15));
      if (getRes.statusCode == 200) {
        final data = jsonDecode(getRes.body) as Map<String, dynamic>;
        existingSha = data['sha'] as String?;
      }
    } catch (_) {}

    final putUri = Uri.parse('https://api.github.com/repos/$repoFullName/contents/$path');
    final bodyMap = <String, dynamic>{
      'message': message,
      'content': base64Encode(bytes),
      'branch': branch,
      if (existingSha != null) 'sha': existingSha,
    };

    final putRes = await http
        .put(putUri, headers: headers, body: jsonEncode(bodyMap))
        .timeout(const Duration(seconds: 25));
    if (putRes.statusCode >= 400) {
      throw Exception('فشل رفع الملف $path (${putRes.statusCode})');
    }
  }

  static Future<ApkBuildRecord> pushProjectAndBuildApk({
    required String token,
    required String githubLogin,
    required IdeProject project,
    required void Function(String stepLog) onLog,
  }) async {
    final cleanToken = token.trim();
    final headers = _headers(cleanToken);

    var effectiveLogin = githubLogin.trim();
    if (effectiveLogin.isEmpty || effectiveLogin == 'github_user' || effectiveLogin == 'user') {
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
    final suffix = project.id.length > 4 ? project.id.substring(project.id.length - 4) : project.id;
    final repoShortName = safeSlug.isEmpty ? 'mango-app-$suffix' : '$safeSlug-$suffix';
    final repoFullName = (project.githubRepo != null && project.githubRepo!.contains('/'))
        ? project.githubRepo!.trim()
        : '$effectiveLogin/$repoShortName';

    onLog(S.t('جاري التحقق من المستودع $repoFullName...', 'Checking repository $repoFullName...'));
    var repoCheck = await http
        .get(Uri.parse('https://api.github.com/repos/$repoFullName'), headers: headers)
        .timeout(const Duration(seconds: 20));

    if (repoCheck.statusCode == 404) {
      onLog(S.t('جاري إنشاء مستودع جديد ($repoShortName)...', 'Creating repository ($repoShortName)...'));
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
        throw Exception('تعذر إنشاء المستودع (${createRes.statusCode}): ${createRes.body}');
      }
      project.githubRepo = repoFullName;
      await Future<void>.delayed(const Duration(seconds: 3));
      repoCheck = await http
          .get(Uri.parse('https://api.github.com/repos/$repoFullName'), headers: headers)
          .timeout(const Duration(seconds: 20));
    }

    if (repoCheck.statusCode >= 400) {
      throw Exception('تعذر الوصول للمستودع $repoFullName (${repoCheck.statusCode}).');
    }

    final repoData = jsonDecode(repoCheck.body) as Map<String, dynamic>;
    final defaultBranch = (repoData['default_branch'] as String?) ?? 'main';

    final files = project.nodes.where((n) => !n.isFolder).toList();
    final workflowYaml = ProjectTemplates.workflowForType(
      project.type,
      appName: project.name,
      packageName: project.packageName,
      versionName: project.versionName,
      versionCode: project.versionCode,
      buildMode: project.buildMode,
    );

    bool pushedViaGitTree = false;
    try {
      onLog(S.t('جاري قراءة الفرع الأساسي ($defaultBranch)...', 'Reading branch ($defaultBranch)...'));
      final getRefUri = Uri.parse('https://api.github.com/repos/$repoFullName/git/ref/heads/$defaultBranch');
      final updateRefsUri = Uri.parse('https://api.github.com/repos/$repoFullName/git/refs/heads/$defaultBranch');

      final refRes = await http.get(getRefUri, headers: headers).timeout(const Duration(seconds: 20));
      if (refRes.statusCode == 200) {
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
          onLog(S.t('جاري تجهيز أيقونة التطبيق المخصصة...', 'Uploading custom app icon...'));
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
              'path': 'CustomAppIcon.png',
              'mode': '100644',
              'type': 'blob',
              'sha': iconSha,
            });
          }
        }

        onLog(S.t('جاري رفع (${treeItems.length} ملفات) إلى GitHub...', 'Uploading ${treeItems.length} files...'));
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

        if (treeRes.statusCode < 300) {
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

          if (newCommitRes.statusCode < 300) {
            final newCommitSha = (jsonDecode(newCommitRes.body) as Map<String, dynamic>)['sha'] as String;
            final updateRefRes = await http
                .patch(
                  updateRefsUri,
                  headers: headers,
                  body: jsonEncode({'sha': newCommitSha, 'force': true}),
                )
                .timeout(const Duration(seconds: 25));

            if (updateRefRes.statusCode < 300) {
              pushedViaGitTree = true;
            }
          }
        }
      }
    } catch (_) {}

    if (!pushedViaGitTree) {
      onLog(S.t('جاري رفع الملفات عبر المسار المباشر المضمون...', 'Uploading via Contents API...'));
      if (project.iconBase64 != null && project.iconBase64!.isNotEmpty) {
        await _putSingleFileViaContentsApi(
          repoFullName: repoFullName,
          branch: defaultBranch,
          path: 'CustomAppIcon.png',
          bytes: base64Decode(project.iconBase64!),
          headers: headers,
          message: 'Upload CustomAppIcon.png',
        );
      }
      for (final file in files) {
        if (file.path == '.github/workflows/main.yml') continue;
        await _putSingleFileViaContentsApi(
          repoFullName: repoFullName,
          branch: defaultBranch,
          path: file.path,
          bytes: utf8.encode(file.content),
          headers: headers,
          message: 'Update ${file.path}',
        );
      }
      await _putSingleFileViaContentsApi(
        repoFullName: repoFullName,
        branch: defaultBranch,
        path: '.github/workflows/main.yml',
        bytes: utf8.encode(workflowYaml),
        headers: headers,
        message: 'Setup Mango Studio APK Build Workflow',
      );
    }

    onLog(S.t('تم رفع جميع الملفات بنجاح! جاري تشغيل البناء السحابي...', 'Files uploaded! Starting Cloud Build...'));
    try {
      await http.post(
        Uri.parse('https://api.github.com/repos/$repoFullName/actions/workflows/main.yml/dispatches'),
        headers: headers,
        body: jsonEncode({'ref': defaultBranch}),
      );
    } catch (_) {}

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
      directApkReleaseUrl: 'https://github.com/$repoFullName/releases/download/latest-apk/app-release.apk',
      directAabReleaseUrl: 'https://github.com/$repoFullName/releases/download/latest-apk/app-release.aab',
      createdAt: DateTime.now(),
      logs: [
        'تم رفع المشروع إلى $repoFullName بنجاح ✓',
        'الحزمة: ${project.packageName} • الإصدار: ${project.versionName}',
        'بدأ البناء السحابي على GitHub Actions...',
      ],
    );
  }

  static Future<Map<String, dynamic>?> fetchLatestWorkflowLiveStatus({
    required String token,
    required String repoFullName,
  }) async {
    try {
      final headers = _headers(token);
      final runsRes = await http
          .get(
            Uri.parse('https://api.github.com/repos/$repoFullName/actions/runs?per_page=1'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));
      if (runsRes.statusCode != 200) return null;

      final runsData = jsonDecode(runsRes.body) as Map<String, dynamic>;
      final runs = runsData['workflow_runs'] as List?;
      if (runs == null || runs.isEmpty) return null;

      final latestRun = runs.first as Map<String, dynamic>;
      final runId = latestRun['id'];
      final runStatus = latestRun['status']?.toString() ?? 'queued';
      final runConclusion = latestRun['conclusion']?.toString();

      final jobsRes = await http
          .get(
            Uri.parse('https://api.github.com/repos/$repoFullName/actions/runs/$runId/jobs'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));

      List<Map<String, dynamic>> stepsList = [];
      if (jobsRes.statusCode == 200) {
        final jobsData = jsonDecode(jobsRes.body) as Map<String, dynamic>;
        final jobs = jobsData['jobs'] as List?;
        if (jobs != null && jobs.isNotEmpty) {
          final rawSteps = (jobs.first as Map<String, dynamic>)['steps'] as List?;
          if (rawSteps != null) {
            stepsList = rawSteps.map((e) => e as Map<String, dynamic>).toList();
          }
        }
      }

      return {
        'status': runStatus,
        'conclusion': runConclusion,
        'steps': stepsList,
      };
    } catch (_) {
      return null;
    }
  }
}

/// ============================================================================
/// 7. شاشة ربط GitHub الرسمية (متوافقة مع الوضع الفاتح والداكن)
/// ============================================================================
class GithubConnectModalScreen extends StatefulWidget {
  const GithubConnectModalScreen({super.key, required this.onConnected});
  final void Function(String token, String login) onConnected;

  @override
  State<GithubConnectModalScreen> createState() => _GithubConnectModalScreenState();
}

class _GithubConnectModalScreenState extends State<GithubConnectModalScreen>
    with WidgetsBindingObserver {
  String _statusText = S.t('لم يتم ربط حساب GitHub', 'GitHub account not connected');
  String? _userCode;
  String? _deviceCode;
  String? _verificationUri;
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _deviceCode != null && !_connected) {
      Future<void>.delayed(const Duration(milliseconds: 500), () {
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
        _statusText = S.t('متصل بحساب GitHub (@$_connectedLogin) ✓', 'Connected to GitHub (@$_connectedLogin) ✓');
      });
    }
  }

  Future<void> _startDeviceLogin() async {
    _pollTimer?.cancel();
    setState(() {
      _busy = true;
      _statusText = S.t('جاري طلب رمز التحقق من GitHub...', 'Requesting verification code...');
    });

    try {
      final data = await GithubOAuthDeviceService.startDeviceFlow();
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
        _statusText = S.t(
          'تم نسخ الرمز ($userCode) تلقائياً! افتح صفحة التحقق والصق الرمز.',
          'Code ($userCode) copied! Open verification page and paste it.',
        );
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

  Future<void> _checkDeviceStatusOnce({required bool manualTap}) async {
    if (_deviceCode == null || _connected || _checkingNow) return;
    if (manualTap && mounted) {
      setState(() {
        _checkingNow = true;
        _statusText = S.t('جاري تأكيد الربط من GitHub...', 'Verifying authorization...');
      });
    }

    try {
      final res = await GithubOAuthDeviceService.pollDeviceToken(deviceCode: _deviceCode!);
      final token = res['access_token']?.toString();
      if (token != null && token.isNotEmpty) {
        _pollTimer?.cancel();
        await SafeStorage.setString('gh_oauth_token', token);

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
          _statusText = S.t('تم ربط حساب GitHub بنجاح (@$login) ✓', 'Connected (@$login) ✓');
        });
        widget.onConnected(token, login);
        return;
      }

      final err = res['error']?.toString() ?? '';
      if (err == 'slow_down') {
        final newInt = (res['interval'] as num?)?.toInt();
        _pollIntervalSec = newInt ?? (_pollIntervalSec + 5);
      } else if (err == 'expired_token' || err == 'access_denied') {
        _pollTimer?.cancel();
        _deviceCode = null;
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _checkingNow = false);
    }
  }

  Future<void> _openVerificationPage() async {
    final uriStr = _verificationUri ?? 'https://github.com/login/device';
    if (_userCode != null && _userCode!.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: _userCode!));
    }
    try {
      await launchUrl(Uri.parse(uriStr), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _showDirectTokenDialog() async {
    final patCtrl = TextEditingController();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: S.dir,
        child: AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(S.t('ربط بتوكن مباشر (PAT)', 'Connect via Personal Access Token')),
          content: TextField(
            controller: patCtrl,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
              labelText: 'GitHub Token (repo + workflow)',
              hintText: 'ghp_xxxxxxxxxxxxxxxxxxxx',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(S.t('إلغاء', 'Cancel'))),
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
                  });
                  widget.onConnected(t, login);
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(S.t('حفظ وربط', 'Save & Connect')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: S.dir,
      child: Scaffold(
        backgroundColor: AppColors.bg,
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
                      label: Text(
                        S.t('ربط بتوكن مباشر', 'Direct Token'),
                        style: const TextStyle(color: AppColors.mango, fontSize: 12.5),
                      ),
                    ),
                    const Text(
                      'MANGO STUDIO / CONNECT',
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  S.t('اربط مساحة العمل بـ GitHub', 'Connect Workspace to GitHub'),
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 26, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  S.t('تفويض رسمي من دون خادم وسيط', 'Official direct OAuth Device Flow'),
                  style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        S.t('كيف يعمل الربط؟', 'How does it work?'),
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        S.t(
                          'يتم طلب رمز مؤقت من GitHub ونسخه تلقائياً. افتح صفحة التحقق والصق الرمز ثم اضغط Continue و Authorize، وعند رجوعك للتطبيق سيتم تسجيل الدخول تلقائياً.',
                          'A temporary code is generated and copied automatically. Open the verification page, paste the code, click Continue & Authorize, then return to the app.',
                        ),
                        style: TextStyle(color: AppColors.textMuted, fontSize: 13.5, height: 1.6),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  _statusText,
                  style: TextStyle(
                    color: _connected ? AppColors.success : AppColors.textMuted,
                    fontSize: 14,
                    fontWeight: _connected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  height: 78,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: _connected ? AppColors.success : AppColors.border,
                    ),
                  ),
                  child: (_busy || _checkingNow)
                      ? const SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary),
                        )
                      : SelectableText(
                          _connected
                              ? '✓ @${_connectedLogin ?? "github"}'
                              : (_userCode ?? '---- - ----'),
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                            color: _connected ? AppColors.success : AppColors.textPrimary,
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
                    height: 52,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: _checkingNow ? null : () => _checkDeviceStatusOnce(manualTap: true),
                      icon: const Icon(Icons.verified_rounded),
                      label: Text(
                        S.t('تأكيد الربط بعد الموافقة ✓', 'Verify Connection Now ✓'),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: AppColors.surface,
                      foregroundColor: AppColors.textPrimary,
                      side: BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: _userCode == null
                        ? null
                        : () async {
                            await Clipboard.setData(ClipboardData(text: _userCode!));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(S.t('تم نسخ الرمز ✓', 'Code copied ✓'))),
                              );
                            }
                          },
                    child: Text(S.t('نسخ رمز التحقق', 'Copy Verification Code')),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: _openVerificationPage,
                    child: Text(
                      S.t('فتح صفحة التحقق داخل التطبيق', 'Open GitHub Verification Page'),
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: _busy ? null : _startDeviceLogin,
                    child: Text(
                      _connected
                          ? S.t('إعادة ربط حساب آخر', 'Reconnect Another Account')
                          : S.t('بدء تسجيل الدخول', 'Start Sign In'),
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(S.t('إغلاق', 'Close'), style: TextStyle(color: AppColors.textMuted)),
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
/// 8. مهندس الذكاء الاصطناعي الحقيقي عبر API المستخدم (Gemini / OpenAI / DeepSeek / Groq)
/// ============================================================================
class MangoAiArchitectService {
  static Future<String> buildOrEditWithUserApi({
    required String provider, // 'gemini', 'openai', 'deepseek', 'groq'
    required String apiKey,
    required String model,
    required String prompt,
    required IdeProject project,
    required String activeFilePath,
    required String activeFileContent,
    required bool buildFromScratchMode,
  }) async {
    final cleanKey = apiKey.trim();
    if (cleanKey.isEmpty) {
      throw Exception(
        S.t(
          'يرجى إدخال مفتاح الـ API الخاص بك أولاً (مثل مفتاح Google Gemini API أو OpenAI) وحفظه لتشغيل الذكاء الاصطناعي.',
          'Please enter and save your API Key first (Google Gemini, OpenAI, DeepSeek, or Groq) to run the AI builder.',
        ),
      );
    }

    final fileList = project.nodes.where((n) => !n.isFolder).map((n) => n.path).join(', ');
    final systemPrompt = buildFromScratchMode
        ? 'You are a senior Flutter & Android application architect inside "Mango Studio IDE".\n'
            'The user wants to build a complete, production-ready application from scratch or overhaul "${project.name}".\n'
            'Rules:\n'
            '1. Write clean, complete, compilable Flutter Dart code with zero placeholders.\n'
            '2. Output each file using this exact header format:\n'
            '===FILE: lib/main.dart===\n'
            '```dart\n'
            '// complete code\n'
            '```\n'
            'You can output multiple files (e.g. lib/main.dart, lib/screens/..., lib/models/...) so Mango Studio creates the entire project structure automatically.\n'
            '3. Start with a brief 2-line summary in the user language.'
        : 'You are an expert mobile code assistant inside "Mango Studio IDE".\n'
            'Project files: $fileList\n'
            'Currently open file: $activeFilePath\n'
            'Current file content:\n'
            '```dart\n$activeFileContent\n```\n'
            'Modify the code according to the user request and return the complete updated file inside a ```dart ... ``` block.';

    if (provider == 'gemini') {
      final selectedModel = model.trim().isEmpty ? 'gemini-2.5-flash' : model.trim();
      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$selectedModel:generateContent?key=$cleanKey',
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
          .timeout(const Duration(seconds: 60));

      if (response.statusCode >= 400) {
        throw Exception('Gemini API Error (${response.statusCode}): ${response.body}');
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
              'Authorization': 'Bearer $cleanKey',
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
          .timeout(const Duration(seconds: 60));

      if (response.statusCode >= 400) {
        throw Exception('API Error (${response.statusCode}): ${response.body}');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = data['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        throw Exception('Empty response from API.');
      }
      return ((choices.first as Map<String, dynamic>)['message'] as Map<String, dynamic>)['content']
              ?.toString() ??
          '';
    }
  }

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
}

/// ============================================================================
/// 9. التطبيق الرئيسي: مانجو ستديو (يدعم الفاتح والداكن + العربي والإنجليزي)
/// ============================================================================
class MangoStudioApp extends StatefulWidget {
  const MangoStudioApp({super.key});

  @override
  State<MangoStudioApp> createState() => _MangoStudioAppState();
}

class _MangoStudioAppState extends State<MangoStudioApp> {
  void _toggleLanguage() {
    setState(() => S.lang = S.isAr ? 'en' : 'ar');
    SafeStorage.setString('mango_lang', S.lang);
  }

  void _toggleTheme() {
    setState(() => S.dark = !S.dark);
    SafeStorage.setString('mango_dark', S.dark ? '1' : '0');
  }

  @override
  void initState() {
    super.initState();
    Future<void>(() async {
      final savedLang = await SafeStorage.getString('mango_lang');
      final savedDark = await SafeStorage.getString('mango_dark');
      if (!mounted) return;
      setState(() {
        if (savedLang == 'ar' || savedLang == 'en') S.lang = savedLang!;
        if (savedDark == '0' || savedDark == '1') S.dark = savedDark == '1';
      });
    });
  }

  ThemeData _buildTheme(bool isDark) {
    final brightness = isDark ? Brightness.dark : Brightness.light;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: AppColors.mango,
        onPrimary: Colors.black,
        secondary: AppColors.primary,
        onSecondary: Colors.white,
        error: AppColors.danger,
        onError: Colors.white,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: AppColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceAlt,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.mango, width: 1.5),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      key: ValueKey('${S.lang}_${S.dark}'),
      title: 'مانجو ستديو',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(S.dark),
      home: MangoHomeShell(
        onToggleLanguage: _toggleLanguage,
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}

class MangoHomeShell extends StatefulWidget {
  const MangoHomeShell({
    super.key,
    required this.onToggleLanguage,
    required this.onToggleTheme,
  });

  final VoidCallback onToggleLanguage;
  final VoidCallback onToggleTheme;

  @override
  State<MangoHomeShell> createState() => _MangoHomeShellState();
}

class _MangoHomeShellState extends State<MangoHomeShell> {
  static const String _projectsStorageKey = 'mango_studio_projects_v8';
  static const String _buildsStorageKey = 'mango_studio_builds_v8';

  int _selectedTabIndex = 0;
  List<IdeProject> _projects = [];
  List<ApkBuildRecord> _builds = [];
  String? _githubToken;
  String? _githubLogin;

  String _aiProvider = 'gemini';
  String _aiApiKey = '';
  String _aiModel = 'gemini-2.5-flash';
  bool _aiBuildNewAppFromScratch = true;
  final List<Map<String, String>> _aiChatHistory = [];

  @override
  void initState() {
    super.initState();
    final defaultProj = IdeProject(
      id: '1001',
      name: 'متجر مانجو',
      packageName: 'com.mango.store',
      type: IdeProjectType.flutter,
      updatedAt: DateTime.now(),
      nodes: ProjectTemplates.generateNodes(
        type: IdeProjectType.flutter,
        appName: 'متجر مانجو',
        packageName: 'com.mango.store',
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
        if (aiProv != null && aiProv != 'builtin') _aiProvider = aiProv;
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

  /// استيراد ملف ZIP مطور ومضمون 100% على أندرويد (مع withData: true وإزالة المجلد الأب واستخراج الحزمة والأيقونة)
  Future<void> _importProjectFromZip() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final picked = res.files.single;

      Uint8List? bytes = picked.bytes;
      if (bytes == null && picked.path != null) {
        bytes = await File(picked.path!).readAsBytes();
      }
      if (bytes == null || bytes.isEmpty) {
        throw Exception(S.t('تعذر قراءة بيانات الملف المختار.', 'Could not read selected file bytes.'));
      }

      final archive = ZipDecoder().decodeBytes(bytes);
      final fileEntries = archive.where((e) => e.isFile).toList();
      if (fileEntries.isEmpty) {
        throw Exception(S.t('ملف الـ ZIP فارغ.', 'ZIP archive is empty.'));
      }

      // إزالة المجلد الجذري المشترك إن كان كل المشروع داخل مجلد واحد (مثل my_app/lib/main.dart)
      String? commonRootPrefix;
      final validPaths = fileEntries
          .map((e) => e.name.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), ''))
          .where((p) => p.isNotEmpty && !p.startsWith('__MACOSX'))
          .toList();
      if (validPaths.isNotEmpty && validPaths.every((p) => p.contains('/'))) {
        final firstFolder = validPaths.first.split('/').first;
        if (validPaths.every((p) => p.startsWith('$firstFolder/'))) {
          commonRootPrefix = '$firstFolder/';
        }
      }

      final importedNodes = <IdeNode>[];
      final seenFolders = <String>{};
      String? extractedIconBase64;
      String? extractedPkgName;
      String? extractedAppName;

      for (final entry in fileEntries) {
        var relPath = entry.name.replaceAll('\\', '/').replaceAll(RegExp(r'^/+|/+$'), '');
        if (relPath.isEmpty || relPath.startsWith('__MACOSX') || relPath.startsWith('.git/')) continue;
        if (commonRootPrefix != null && relPath.startsWith(commonRootPrefix)) {
          relPath = relPath.substring(commonRootPrefix.length);
        }
        if (relPath.isEmpty) continue;

        final parts = relPath.split('/');
        var currentFolder = '';
        for (var i = 0; i < parts.length - 1; i++) {
          currentFolder = currentFolder.isEmpty ? parts[i] : '$currentFolder/${parts[i]}';
          if (seenFolders.add(currentFolder)) {
            importedNodes.add(IdeNode(path: currentFolder, isFolder: true));
          }
        }

        final rawBytes = entry.content;
        final bytesList = rawBytes is List<int> ? rawBytes : <int>[];

        if (relPath.endsWith('ic_launcher.png') && extractedIconBase64 == null && bytesList.isNotEmpty) {
          extractedIconBase64 = base64Encode(bytesList);
        }

        final ext = relPath.split('.').last.toLowerCase();
        const textExts = {
          'dart', 'yaml', 'yml', 'json', 'xml', 'gradle', 'kts',
          'properties', 'md', 'txt', 'html', 'css', 'js', 'java', 'kt', 'tsx', 'ts', 'sh'
        };
        if (textExts.contains(ext) && entry.size < 1024 * 800) {
          final content = utf8.decode(bytesList, allowMalformed: true);
          importedNodes.add(IdeNode(path: relPath, isFolder: false, content: content));

          if (relPath == 'pubspec.yaml') {
            final m = RegExp(r'^name:\s*([a-zA-Z0-9_]+)', multiLine: true).firstMatch(content);
            if (m != null) extractedAppName = m.group(1);
          } else if (relPath.endsWith('build.gradle') || relPath.endsWith('build.gradle.kts')) {
            final m = RegExp(r'applicationId\s*=?\s*["\x27]([^"\x27]+)["\x27]').firstMatch(content);
            if (m != null) extractedPkgName = m.group(1);
          }
        }
      }

      if (importedNodes.isEmpty) {
        throw Exception(S.t('لم يتم العثور على ملفات برمجية داخل الـ ZIP.', 'No source files found in ZIP.'));
      }

      final zipBaseName = picked.name.replaceAll(RegExp(r'\.zip$', caseSensitive: false), '');
      final finalName = extractedAppName ?? zipBaseName;
      final finalPkg = extractedPkgName ??
          'com.mango.${finalName.toLowerCase().replaceAll(RegExp(r"[^a-z0-9]"), "")}';

      final importedProj = IdeProject(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: finalName,
        packageName: finalPkg,
        iconBase64: extractedIconBase64,
        type: IdeProjectType.flutter,
        updatedAt: DateTime.now(),
        nodes: importedNodes,
      );

      setState(() => _projects.insert(0, importedProj));
      await _persistProjects();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.success,
          content: Text(
            S.t(
              'تم استيراد المشروع "$finalName" (${importedNodes.where((n) => !n.isFolder).length} ملف) بنجاح ✓',
              'Imported "$finalName" successfully ✓',
            ),
          ),
        ),
      );
      _openProjectInEditor(importedProj);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(S.t('تعذر استيراد ملف الـ ZIP: $e', 'ZIP Import Failed: $e')),
        ),
      );
    }
  }

  /// فاحص جاهزية النشر على متجر Google Play (Google Play Store Readiness Dialog)
  void _showGooglePlayReadinessDialog(IdeProject proj) {
    final checks = <(String, bool, String)>[
      (
        S.t('معرّف الحزمة الفريد (Package Name)', 'Unique Package ID'),
        !proj.packageName.startsWith('com.example') && proj.packageName.contains('.'),
        proj.packageName,
      ),
      (
        S.t('أيقونة التطبيق المخصصة (App Icon)', 'Custom App Icon'),
        proj.iconBase64 != null && proj.iconBase64!.isNotEmpty,
        proj.iconBase64 != null ? S.t('مضافة ✓', 'Configured ✓') : S.t('الافتراضية (يفضل إضافة صورة)', 'Default icon'),
      ),
      (
        S.t('إصدار التطبيق ورقم البناء (Version & Build #)', 'Version & Build Code'),
        proj.versionCode >= 1 && proj.versionName.isNotEmpty,
        'v${proj.versionName} (+${proj.versionCode})',
      ),
      (
        S.t('دعم حزمة متجر جوجل بلاي (AAB + Release APK)', 'Google Play App Bundle (AAB)'),
        true,
        S.t('مفعّل في البناء السحابي ✓', 'Enabled in Cloud Build ✓'),
      ),
    ];

    showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: S.dir,
        child: AlertDialog(
          backgroundColor: AppColors.surface,
          title: Row(
            children: [
              const Icon(Icons.shop_two_rounded, color: AppColors.success),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  S.t('جاهزية النشر على Google Play', 'Google Play Readiness'),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final c in checks)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    c.$2 ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                    color: c.$2 ? AppColors.success : AppColors.warning,
                  ),
                  title: Text(c.$1, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
                  subtitle: Text(c.$3, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _showProjectConfigDialog(existingProject: proj);
              },
              child: Text(S.t('تعديل الأيقونة والحزمة', 'Edit Icon & Package')),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.mango, foregroundColor: Colors.black),
              onPressed: () => Navigator.pop(ctx),
              child: Text(S.t('تم', 'Done')),
            ),
          ],
        ),
      ),
    );
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
          textDirection: S.dir,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  S.t('نوع المشروع', 'Project Type'),
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 14),
                for (final t in IdeProjectType.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: AppColors.border),
                      ),
                      tileColor: AppColors.bg,
                      leading: Icon(Icons.code_rounded, color: t.badgeColor, size: 28),
                      title: Text(t.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(t.subtitle, style: const TextStyle(fontSize: 12)),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.pop(ctx, t),
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
    final nameCtrl = TextEditingController(
      text: existingProject?.name ?? S.t('تطبيق مانجو', 'Mango App'),
    );
    final pkgCtrl = TextEditingController(
      text: existingProject?.packageName ?? 'com.mango.app${_projects.length + 1}',
    );
    final verNameCtrl = TextEditingController(text: existingProject?.versionName ?? '1.0.0');
    final verCodeCtrl = TextEditingController(text: '${existingProject?.versionCode ?? 1}');

    var buildMode = existingProject?.buildMode ?? 'playstore_aab';
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
                  type: FileType.image,
                  withData: true,
                );
                if (res == null || res.files.isEmpty) return;
                final picked = res.files.single;
                Uint8List? bytes = picked.bytes;
                if (bytes == null && picked.path != null) {
                  bytes = await File(picked.path!).readAsBytes();
                }
                if (bytes != null && bytes.isNotEmpty) {
  final encodedIcon = base64Encode(bytes);
  setModalState(() => iconBase64 = encodedIcon);
}

              } catch (_) {}
            }

            return Directionality(
              textDirection: S.dir,
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
                            ? S.t('إعدادات التطبيق والنشر (${existingProject.name})', 'App & Play Store Config')
                            : S.t('إنشاء مشروع ${initialType.title}', 'Create ${initialType.title} Project'),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          GestureDetector(
                            onTap: pickAppIcon,
                            child: Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: AppColors.surfaceAlt,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppColors.mango),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: iconBase64 != null && iconBase64!.isNotEmpty
                                  ? Image.memory(base64Decode(iconBase64!), fit: BoxFit.cover)
                                  : const Icon(Icons.add_photo_alternate_outlined, color: AppColors.mango, size: 28),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  S.t('أيقونة التطبيق (App Icon)', 'App Icon'),
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                TextButton.icon(
                                  onPressed: pickAppIcon,
                                  icon: const Icon(Icons.image_outlined, size: 16),
                                  label: Text(S.t('اختيار صورة من الهاتف', 'Pick Image')),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: nameCtrl,
                        decoration: InputDecoration(
                          labelText: S.t('اسم التطبيق', 'App Name'),
                          prefixIcon: const Icon(Icons.apps_rounded),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: pkgCtrl,
                        textDirection: TextDirection.ltr,
                        decoration: InputDecoration(
                          labelText: S.t('اسم الحزمة (Package ID)', 'Package Name (e.g. com.mango.app)'),
                          prefixIcon: const Icon(Icons.inventory_2_outlined),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: verNameCtrl,
                              textDirection: TextDirection.ltr,
                              decoration: InputDecoration(labelText: S.t('الإصدار', 'Version')),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: verCodeCtrl,
                              keyboardType: TextInputType.number,
                              textDirection: TextDirection.ltr,
                              decoration: InputDecoration(labelText: S.t('رقم البناء', 'Build #')),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: buildMode,
                        decoration: InputDecoration(
                          labelText: S.t('وضع الخرج والنشر', 'Build & Publish Target'),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'playstore_aab',
                            child: Text(S.t('Google Play Bundle (AAB) + Release APK', 'Google Play (AAB + Release APK)')),
                          ),
                          DropdownMenuItem(
                            value: 'release',
                            child: Text(S.t('Release APK فقط (سريع)', 'Release APK Only')),
                          ),
                          DropdownMenuItem(
                            value: 'debug',
                            child: Text(S.t('Debug APK (للتجربة)', 'Debug APK')),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) setModalState(() => buildMode = v);
                        },
                      ),
                      const SizedBox(height: 14),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.mango,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        icon: Icon(isEdit ? Icons.save_outlined : Icons.rocket_launch_rounded),
                        label: Text(
                          isEdit ? S.t('حفظ التعديلات', 'Save Changes') : S.t('إنشاء وفتح المحرر', 'Create & Open Editor'),
                          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () async {
                          final appName = nameCtrl.text.trim().isEmpty ? 'Mango App' : nameCtrl.text.trim();
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
                              existingProject.iconBase64 = iconBase64;
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
                              iconBase64: iconBase64,
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
                            setState(() => _projects.insert(0, newProj));
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
        SnackBar(content: Text(S.t('تم حفظ نسخة ZIP في: $outPath', 'Saved ZIP to: $outPath'))),
      );
    } catch (_) {}
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
          onCheckPlayStore: () => _showGooglePlayReadinessDialog(project),
          onOpenGithubConnect: _openGithubConnectScreen,
          onBuildRecorded: (record) async {
            setState(() {
              _builds.removeWhere((b) => b.id == record.id);
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
      textDirection: S.dir,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.mango, AppColors.mangoDark]),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'M',
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 19),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  S.t('مانجو ستديو', 'Mango Studio'),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
              ),
              // زر تبديل الوضع الفاتح والداكن
              IconButton(
                icon: Icon(
                  S.dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                  color: AppColors.mango,
                  size: 21,
                ),
                tooltip: S.t('الوضع الفاتح / الداكن', 'Light / Dark Mode'),
                onPressed: widget.onToggleTheme,
              ),
              // زر تبديل اللغة الفوري (AR / EN)
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  side: BorderSide(color: AppColors.border),
                ),
                onPressed: widget.onToggleLanguage,
                child: Text(
                  S.isAr ? 'EN' : 'عربي',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.mango),
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _openGithubConnectScreen,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _githubToken != null ? AppColors.success.withOpacity(0.15) : AppColors.surfaceAlt,
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
                        size: 8,
                        color: _githubToken != null ? AppColors.success : AppColors.warning,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _githubToken != null ? '@${_githubLogin ?? "GitHub"}' : 'GitHub',
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
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
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border, width: 0.8)),
          ),
          child: BottomNavigationBar(
            currentIndex: _selectedTabIndex,
            onTap: (i) => setState(() => _selectedTabIndex = i),
            type: BottomNavigationBarType.fixed,
            backgroundColor: AppColors.surface,
            selectedItemColor: AppColors.mango,
            unselectedItemColor: AppColors.textMuted,
            items: [
              BottomNavigationBarItem(
                icon: const Icon(Icons.folder_copy_outlined),
                label: S.t('مشاريعي', 'Projects'),
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.android_rounded),
                label: S.t('مكتبة APK', 'APK Library'),
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.auto_awesome_rounded),
                label: S.t('مهندس AI', 'AI Studio'),
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.settings_outlined),
                label: S.t('إعدادات', 'Settings'),
              ),
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
                  label: Text(
                    S.t('مشروع جديد', 'New Project'),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
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
                    side: BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _showReadyTemplatesSheet,
                  icon: const Icon(Icons.dashboard_customize_outlined, size: 18, color: AppColors.mango),
                  label: Text(
                    S.t('قوالب جاهزة', 'Templates'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
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
              side: BorderSide(color: AppColors.primary.withOpacity(0.5)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _importProjectFromZip,
            icon: const Icon(Icons.folder_zip_outlined, size: 20),
            label: Text(
              S.t('استيراد مشروع ZIP من الهاتف (مع استخراج الحزمة والأيقونة)', 'Import Project ZIP'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ),
        const SizedBox(height: 18),
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
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                            ),
                            Text(
                              '${proj.packageName} • v${proj.versionName}+${proj.versionCode}',
                              textDirection: TextDirection.ltr,
                              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                      _miniBadge(proj.type.title, proj.type.badgeColor),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.mango,
                            foregroundColor: Colors.black,
                          ),
                          onPressed: () => _openProjectInEditor(proj),
                          icon: const Icon(Icons.edit_note_rounded, size: 18),
                          label: Text(
                            S.t('فتح المحرر', 'Open Editor'),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      OutlinedButton.icon(
                        onPressed: () => _showGooglePlayReadinessDialog(proj),
                        icon: const Icon(Icons.shop_two_outlined, size: 16, color: AppColors.success),
                        label: const Text('Google Play', style: TextStyle(fontSize: 12)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.tune_rounded, size: 20),
                        onPressed: () => _showProjectConfigDialog(existingProject: proj),
                      ),
                      IconButton(
                        icon: const Icon(Icons.download_outlined, size: 20),
                        tooltip: 'ZIP',
                        onPressed: () => _exportProjectAsZip(proj),
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
      (S.t('متجر إلكتروني مع سلة مشتريات', 'E-Commerce Store App'), 'ecommerce', IdeProjectType.flutter, Icons.shopping_bag_outlined),
      (S.t('إدارة مهام وملاحظات ذكية', 'Tasks & Notes Manager'), 'tasks_pro', IdeProjectType.flutter, Icons.task_alt_rounded),
      (S.t('تطبيق أذكار ومسبحة إلكترونية', 'Azkar & Tasbih Counter'), 'islamic', IdeProjectType.flutter, Icons.mosque_outlined),
      (S.t('آلة حاسبة حديثة', 'Calculator App'), 'calculator', IdeProjectType.flutter, Icons.calculate_outlined),
    ];

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Directionality(
        textDirection: S.dir,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                S.t('اختر قالباً جاهزاً', 'Choose a Ready Template'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              for (final t in templates)
                ListTile(
                  leading: Icon(t.$4, color: AppColors.mango),
                  title: Text(t.$1, style: const TextStyle(fontWeight: FontWeight.bold)),
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
    );
  }

  Widget _buildLibraryAndApksTab() {
    if (_builds.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.android_rounded, size: 60, color: AppColors.textMuted),
              const SizedBox(height: 10),
              Text(
                S.t('لا توجد ملفات APK أو AAB بعد', 'No built APKs or AABs yet'),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                S.t(
                  'افتح أي مشروع واضغط "بناء APK" ليظهر هنا رابط تنزيل الـ APK وحزمة Google Play (AAB).',
                  'Open any project and tap "Build APK" to get your direct APK & Google Play AAB links here.',
                ),
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
          margin: const EdgeInsets.only(bottom: 12),
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
                            b.repoFullName,
                            textDirection: TextDirection.ltr,
                            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    _miniBadge(b.status.toUpperCase(), b.status == 'completed' ? AppColors.success : AppColors.mango),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: Text(S.t('تنزيل APK', 'Download APK')),
                      onPressed: () => launchUrl(
                        Uri.parse(b.directApkReleaseUrl),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.shop_two_outlined, size: 17, color: AppColors.mango),
                      label: Text(S.t('حزمة Play Store (AAB)', 'Play Bundle (AAB)')),
                      onPressed: () => launchUrl(
                        Uri.parse(b.directAabReleaseUrl),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.open_in_new, size: 17),
                      label: const Text('Actions'),
                      onPressed: () => launchUrl(
                        Uri.parse(b.actionsUrl),
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

  /// تبويب مهندس الذكاء الاصطناعي المعتمد على مفتاح الـ API الخاص بالمستخدم (يبني تطبيقات جديدة من الصفر أو يعدل الحالية)
  Widget _buildGlobalAiStudioTab() {
    final activeProject = _projects.first;
    final mainNode = activeProject.nodes.where((n) => !n.isFolder).firstOrNull;
    final promptCtrl = TextEditingController();
    final apiKeyCtrl = TextEditingController(text: _aiApiKey);
    final modelCtrl = TextEditingController(text: _aiModel);
    bool busy = false;

    return StatefulBuilder(
      builder: (ctx, setTabState) {
        Future<void> saveKey() async {
          _aiApiKey = apiKeyCtrl.text.trim();
          _aiModel = modelCtrl.text.trim();
          await SafeStorage.setString('ide_ai_provider', _aiProvider);
          await SafeStorage.setString('ide_ai_api_key', _aiApiKey);
          await SafeStorage.setString('ide_ai_model', _aiModel);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: AppColors.success,
                content: Text(S.t('تم حفظ مفتاح الـ API بنجاح ✓', 'API Key saved ✓')),
              ),
            );
          }
        }

        Future<void> runAiArchitect(String textPrompt) async {
          if (textPrompt.trim().isEmpty) return;
          _aiApiKey = apiKeyCtrl.text.trim();
          _aiModel = modelCtrl.text.trim();
          await SafeStorage.setString('ide_ai_provider', _aiProvider);
          await SafeStorage.setString('ide_ai_api_key', _aiApiKey);
          await SafeStorage.setString('ide_ai_model', _aiModel);

          setTabState(() {
            busy = true;
            _aiChatHistory.add({'role': 'user', 'text': textPrompt});
          });

          try {
            IdeProject targetProject = activeProject;
            if (_aiBuildNewAppFromScratch) {
              // إنشاء مشروع جديد من الصفر إذا طلب المستخدم بناء تطبيق كامل جديد
              final shortTitle = textPrompt.trim().split(RegExp(r'\s+')).take(3).join(' ');
              targetProject = IdeProject(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                name: shortTitle.isEmpty ? 'تطبيق AI جديد' : shortTitle,
                packageName: 'com.mango.ai${_projects.length + 1}',
                type: IdeProjectType.flutter,
                updatedAt: DateTime.now(),
                nodes: ProjectTemplates.generateNodes(
                  type: IdeProjectType.flutter,
                  appName: shortTitle.isEmpty ? 'تطبيق AI جديد' : shortTitle,
                  packageName: 'com.mango.ai${_projects.length + 1}',
                  versionName: '1.0.0',
                  versionCode: 1,
                ),
              );
              setState(() => _projects.insert(0, targetProject));
            }

            final reply = await MangoAiArchitectService.buildOrEditWithUserApi(
              provider: _aiProvider,
              apiKey: _aiApiKey,
              model: _aiModel,
              prompt: textPrompt,
              project: targetProject,
              activeFilePath: mainNode?.path ?? 'lib/main.dart',
              activeFileContent: mainNode?.content ?? '',
              buildFromScratchMode: _aiBuildNewAppFromScratch,
            );

            final updatedCount = await _applyAiGeneratedFilesToProject(targetProject, reply);
            final appliedNote = updatedCount > 0
                ? S.t(
                    '\n\n✅ [تم بناء وتحديث $updatedCount ملفات مباشرةً في مشروع "${targetProject.name}"]',
                    '\n\n✅ [Generated and updated $updatedCount files in "${targetProject.name}"]',
                  )
                : '';

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
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.vpn_key_rounded, color: AppColors.mango, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            S.t('إعدادات مفتاح الذكاء الاصطناعي (API Key)', 'User AI API Configuration'),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                        DropdownButton<String>(
                          value: _aiProvider,
                          underline: const SizedBox(),
                          items: const [
                            DropdownMenuItem(value: 'gemini', child: Text('Google Gemini')),
                            DropdownMenuItem(value: 'openai', child: Text('OpenAI GPT')),
                            DropdownMenuItem(value: 'deepseek', child: Text('DeepSeek')),
                            DropdownMenuItem(value: 'groq', child: Text('Groq Llama 3.3')),
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
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: apiKeyCtrl,
                            obscureText: true,
                            textDirection: TextDirection.ltr,
                            decoration: InputDecoration(
                              labelText: S.t('أدخل مفتاح الـ API الخاص بك', 'Enter your API Key'),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: modelCtrl,
                            textDirection: TextDirection.ltr,
                            decoration: InputDecoration(
                              labelText: S.t('النموذج', 'Model'),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton.filled(
                          style: IconButton.styleFrom(backgroundColor: AppColors.mango, foregroundColor: Colors.black),
                          onPressed: saveKey,
                          icon: const Icon(Icons.check_rounded, size: 20),
                          tooltip: S.t('حفظ المفتاح', 'Save Key'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(
                          value: true,
                          icon: const Icon(Icons.add_box_outlined, size: 17),
                          label: Text(S.t('بناء تطبيق جديد من الصفر', 'Build App from Scratch')),
                        ),
                        ButtonSegment(
                          value: false,
                          icon: const Icon(Icons.edit_note_rounded, size: 18),
                          label: Text(S.t('تعديل المشروع الحالي', 'Modify Current Project')),
                        ),
                      ],
                      selected: {_aiBuildNewAppFromScratch},
                      onSelectionChanged: (s) => setState(() => _aiBuildNewAppFromScratch = s.first),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _aiChatHistory.isEmpty
                    ? Center(
                        child: Text(
                          S.t(
                            'أدخل مفتاح الـ API الخاص بك بالأعلى، ثم اطلب بناء أي تطبيق أندرويد/فلاتر من الصفر أو تعديل مشروعك الحالي.',
                            'Enter your API key above, then ask to build any full app from scratch or modify your active project.',
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textMuted),
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
                                  ? AppColors.mango.withOpacity(0.15)
                                  : (isErr ? AppColors.danger.withOpacity(0.12) : AppColors.surface),
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
                                SelectableText(msg['text'] ?? '', style: const TextStyle(fontSize: 13)),
                                if (!isUser && !isErr) ...[
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: () => _openProjectInEditor(_projects.first),
                                      icon: const Icon(Icons.code_rounded, size: 16),
                                      label: Text(S.t('فتح المشروع في المحرر', 'Open in Editor')),
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
                      decoration: InputDecoration(
                        hintText: _aiBuildNewAppFromScratch
                            ? S.t('صف التطبيق الذي تريد بناءه من الصفر...', 'Describe the full app to build from scratch...')
                            : S.t('صف التعديل المطلوب على المشروع...', 'Describe the code changes...'),
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
                    label: Text(S.t('تنفيذ', 'Run'), style: const TextStyle(fontWeight: FontWeight.bold)),
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
          child: SwitchListTile(
            secondary: Icon(
              S.dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
              color: AppColors.mango,
            ),
            title: Text(S.t('الوضع الداكن / الفاتح (Theme)', 'Dark / Light Theme')),
            subtitle: Text(S.dark ? S.t('الوضع الداكن مفعّل', 'Dark Mode') : S.t('الوضع الفاتح مفعّل', 'Light Mode')),
            value: S.dark,
            onChanged: (_) => widget.onToggleTheme(),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: const Icon(Icons.language_rounded, color: AppColors.mango),
            title: Text(S.t('لغة التطبيق (Language)', 'App Language')),
            subtitle: Text(S.isAr ? 'العربية (Arabic)' : 'English'),
            trailing: ElevatedButton(
              onPressed: widget.onToggleLanguage,
              child: Text(S.isAr ? 'English' : 'العربية'),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: const Icon(Icons.hub_rounded, color: AppColors.primary),
            title: Text(S.t('حساب GitHub والبناء السحابي', 'GitHub Account')),
            subtitle: Text(
              _githubToken != null
                  ? '@${_githubLogin ?? "GitHub"}'
                  : S.t('غير متصل', 'Not connected'),
            ),
            trailing: ElevatedButton(
              onPressed: _openGithubConnectScreen,
              child: Text(_githubToken != null ? S.t('إدارة', 'Manage') : S.t('ربط', 'Connect')),
            ),
          ),
        ),
        if (_githubToken != null) ...[
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: const Icon(Icons.link_off_rounded, color: AppColors.danger),
              title: Text(S.t('تسجيل الخروج من GitHub', 'Disconnect GitHub')),
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
        ],
      ],
    );
  }
}

/// ============================================================================
/// 10. شاشة محرر الأكواد الاحترافية (بمستوى Android Studio + لوحة أدوات سفلية ذكية)
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
    required this.onCheckPlayStore,
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
  final VoidCallback onCheckPlayStore;
  final Future<void> Function() onOpenGithubConnect;
  final Future<void> Function(ApkBuildRecord record) onBuildRecorded;
  final Future<int> Function(String aiReply) onApplyMultiFiles;

  @override
  State<ProjectEditorFullScreen> createState() => _ProjectEditorFullScreenState();
}

class _ProjectEditorFullScreenState extends State<ProjectEditorFullScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final CodeSyntaxController _codeController;
  final ScrollController _verticalScrollController = ScrollController();

  late List<String> _openTabs;
  String? _activeFilePath;
  String? _undoSnapshot;
  double _fontSize = 14.0;
  bool _showSearchBar = false;
  bool _showBottomStudioPanel = false;
  int _bottomPanelTab = 0; // 0: Outline, 1: Problems, 2: Packages
  final TextEditingController _findCtrl = TextEditingController();
  final TextEditingController _replaceCtrl = TextEditingController();
  final Set<String> _expandedFolders = {'lib', '.github', '.github/workflows'};

  @override
  void initState() {
    super.initState();
    final mainDart = widget.project.nodes.where((n) => !n.isFolder && n.path == 'lib/main.dart').firstOrNull ??
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
    _verticalScrollController.dispose();
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

  List<String> _getCodeDiagnostics() {
    final code = _codeController.text;
    final issues = <String>[];
    if ('('.allMatches(code).length != ')'.allMatches(code).length) {
      issues.add(S.t('عدم توازن الأقواس الدائرية ()', 'Unbalanced parentheses ()'));
    }
    if ('{'.allMatches(code).length != '}'.allMatches(code).length) {
      issues.add(S.t('عدم توازن أقواس البلوك {}', 'Unbalanced braces {}'));
    }
    if ('['.allMatches(code).length != ']'.allMatches(code).length) {
      issues.add(S.t('عدم توازن أقواس المصفوفات []', 'Unbalanced brackets []'));
    }
    return issues;
  }

  List<String> _getClassAndMethodOutline() {
    final res = <String>[];
    final reg = RegExp(r'\b(class\s+[A-Za-z0-9_]+|void\s+main|Widget\s+build)\b');
    for (final m in reg.allMatches(_codeController.text)) {
      res.add(m.group(0)!);
    }
    return res;
  }

  Future<void> _openDirectAiEditorSheet() async {
    var provider = (await SafeStorage.getString('ide_ai_provider')) ?? widget.aiProvider;
    if (provider == 'builtin') provider = 'gemini';
    final savedKey = (await SafeStorage.getString('ide_ai_api_key')) ?? widget.aiApiKey;
    final savedModel = (await SafeStorage.getString('ide_ai_model')) ?? widget.aiModel;

    final keyCtrl = TextEditingController(text: savedKey);
    final modelCtrl = TextEditingController(text: savedModel);
    final promptCtrl = TextEditingController();
    bool fullAppMode = false;
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
            Future<void> executeAi() async {
              if (promptCtrl.text.trim().isEmpty) return;
              setModalState(() {
                busy = true;
                errorMsg = null;
              });
              await SafeStorage.setString('ide_ai_provider', provider);
              await SafeStorage.setString('ide_ai_api_key', keyCtrl.text.trim());
              await SafeStorage.setString('ide_ai_model', modelCtrl.text.trim());

              try {
                final reply = await MangoAiArchitectService.buildOrEditWithUserApi(
                  provider: provider,
                  apiKey: keyCtrl.text.trim(),
                  model: modelCtrl.text.trim(),
                  prompt: promptCtrl.text.trim(),
                  project: widget.project,
                  activeFilePath: _activeFilePath ?? 'lib/main.dart',
                  activeFileContent: _codeController.text,
                  buildFromScratchMode: fullAppMode,
                );

                _undoSnapshot = _codeController.text;
                final count = await widget.onApplyMultiFiles(reply);
                final currentActive = widget.project.nodes
                    .where((n) => !n.isFolder && n.path == _activeFilePath)
                    .firstOrNull;
                if (currentActive != null) {
                  setState(() => _codeController.text = currentActive.content);
                }
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: AppColors.success,
                      content: Text(S.t('تم تحديث $count ملفات بالذكاء الاصطناعي ✓', 'Updated $count files via AI ✓')),
                      action: SnackBarAction(
                        label: S.t('تراجع', 'Undo'),
                        textColor: Colors.white,
                        onPressed: () {
                          if (_undoSnapshot != null) {
                            _codeController.text = _undoSnapshot!;
                          }
                        },
                      ),
                    ),
                  );
                }
              } catch (e) {
                setModalState(() => errorMsg = e.toString().replaceFirst('Exception: ', ''));
              } finally {
                setModalState(() => busy = false);
              }
            }

            return Directionality(
              textDirection: S.dir,
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
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            S.t('مساعد الذكاء الاصطناعي (API المستخدم)', 'AI Assistant (User API)'),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          DropdownButton<String>(
                            value: provider,
                            underline: const SizedBox(),
                            items: const [
                              DropdownMenuItem(value: 'gemini', child: Text('Google Gemini')),
                              DropdownMenuItem(value: 'openai', child: Text('OpenAI GPT')),
                              DropdownMenuItem(value: 'deepseek', child: Text('DeepSeek')),
                              DropdownMenuItem(value: 'groq', child: Text('Groq Llama 3.3')),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setModalState(() {
                                  provider = v;
                                  modelCtrl.text = switch (v) {
                                    'gemini' => 'gemini-2.5-flash',
                                    'deepseek' => 'deepseek-chat',
                                    'groq' => 'llama-3.3-70b-versatile',
                                    _ => 'gpt-4o-mini',
                                  };
                                });
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: keyCtrl,
                              obscureText: true,
                              textDirection: TextDirection.ltr,
                              decoration: InputDecoration(
                                labelText: S.t('مفتاح الـ API الخاص بك', 'Your API Key'),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: modelCtrl,
                              textDirection: TextDirection.ltr,
                              decoration: InputDecoration(
                                labelText: S.t('النموذج', 'Model'),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          S.t('بناء/إعادة هيكلة التطبيق بالكامل من الصفر', 'Build complete multi-file app from scratch'),
                          style: const TextStyle(fontSize: 13.5),
                        ),
                        value: fullAppMode,
                        onChanged: (v) => setModalState(() => fullAppMode = v),
                      ),
                      TextField(
                        controller: promptCtrl,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: S.t('اكتب وصف التطبيق أو التعديل المطلوب', 'Describe your app or modification'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.mango,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        onPressed: busy ? null : executeAi,
                        icon: busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                              )
                            : const Icon(Icons.bolt_rounded),
                        label: Text(
                          busy ? S.t('جاري التوليد عبر الـ API...', 'Calling API...') : S.t('تنفيذ وتطبيق مباشر', 'Generate & Apply'),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (errorMsg != null) ...[
                        const SizedBox(height: 8),
                        Text(errorMsg!, style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
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
    String phase = 'uploading';
    String? errorMsg;
    ApkBuildRecord? resultRecord;
    List<Map<String, dynamic>> liveSteps = [];
    Timer? livePollTimer;

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg,
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
                  if (!ctx.mounted) return;
                  setModalState(() {
                    phase = 'polling';
                    resultRecord = rec;
                  });

                  livePollTimer = Timer.periodic(const Duration(seconds: 5), (t) async {
                    if (!ctx.mounted) {
                      t.cancel();
                      return;
                    }
                    final statusData = await GithubOAuthDeviceService.fetchLatestWorkflowLiveStatus(
                      token: token,
                      repoFullName: rec.repoFullName,
                    );
                    if (statusData != null && ctx.mounted) {
                      final st = statusData['status']?.toString() ?? 'queued';
                      final conc = statusData['conclusion']?.toString();
                      final steps = (statusData['steps'] as List<Map<String, dynamic>>?) ?? [];
                      setModalState(() {
                        liveSteps = steps;
                        if (st == 'completed') {
                          t.cancel();
                          if (conc == 'success') {
                            phase = 'completed';
                            rec.status = 'completed';
                            widget.onBuildRecorded(rec);
                          } else {
                            phase = 'failed';
                            errorMsg = S.t(
                              'فشلت إحدى خطوات البناء على GitHub Actions. اضغط "فتح سجل GitHub" للتفاصيل.',
                              'A build step failed on GitHub Actions. Open GitHub logs for details.',
                            );
                          }
                        }
                      });
                    }
                  });
                } catch (e) {
                  if (ctx.mounted) {
                    setModalState(() {
                      phase = 'failed';
                      errorMsg = e.toString().replaceFirst('Exception: ', '');
                    });
                  }
                }
              });
            }

            return Directionality(
              textDirection: S.dir,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 26),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          if (phase == 'uploading' || phase == 'polling')
                            const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.mango),
                            )
                          else
                            Icon(
                              phase == 'completed' ? Icons.check_circle_rounded : Icons.cancel_rounded,
                              color: phase == 'completed' ? AppColors.success : AppColors.danger,
                              size: 26,
                            ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              S.t(
                                'مانجو ستديو • البناء السحابي (${widget.project.name})',
                                'Mango Studio • Cloud Build (${widget.project.name})',
                              ),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () {
                              livePollTimer?.cancel();
                              Navigator.pop(ctx);
                            },
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      if (liveSteps.isNotEmpty) ...[
                        for (final step in liveSteps)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                _stepStatusIcon(
                                  step['status']?.toString() ?? 'queued',
                                  step['conclusion']?.toString(),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    step['name']?.toString() ?? '',
                                    textDirection: TextDirection.ltr,
                                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 10),
                      ],
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
                                child: Row(
                                  children: [
                                    const Icon(Icons.check, color: AppColors.success, size: 15),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(l, style: const TextStyle(fontSize: 12.5)),
                                    ),
                                  ],
                                ),
                              ),
                            if (phase == 'polling')
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  S.t(
                                    '⏳ جاري بناء الـ APK وحزمة متجر جوجل بلاي على خوادم GitHub Actions...',
                                    '⏳ Building APK & Google Play Bundle on GitHub Actions...',
                                  ),
                                  style: const TextStyle(color: AppColors.mango, fontSize: 12.5),
                                ),
                              ),
                            if (errorMsg != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(errorMsg!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (resultRecord != null)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (phase == 'completed') ...[
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.success,
                                  foregroundColor: Colors.white,
                                ),
                                icon: const Icon(Icons.download_rounded),
                                label: Text(S.t('تنزيل APK مباشر', 'Download APK')),
                                onPressed: () => launchUrl(
                                  Uri.parse(resultRecord!.directApkReleaseUrl),
                                  mode: LaunchMode.externalApplication,
                                ),
                              ),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.shop_two_outlined, color: AppColors.mango),
                                label: Text(S.t('تنزيل حزمة AAB لمتجر Play', 'Download Play AAB')),
                                onPressed: () => launchUrl(
                                  Uri.parse(resultRecord!.directAabReleaseUrl),
                                  mode: LaunchMode.externalApplication,
                                ),
                              ),
                            ],
                            OutlinedButton.icon(
                              icon: const Icon(Icons.open_in_new, size: 18),
                              label: Text(S.t('سجل GitHub Actions', 'GitHub Actions Log')),
                              onPressed: () => launchUrl(
                                Uri.parse(resultRecord!.actionsUrl),
                                mode: LaunchMode.externalApplication,
                              ),
                            ),
                          ],
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
    livePollTimer?.cancel();
  }

  Widget _stepStatusIcon(String status, String? conclusion) {
    if (status == 'completed') {
      if (conclusion == 'success') {
        return const Icon(Icons.check_circle, color: AppColors.success, size: 19);
      }
      if (conclusion == 'skipped') {
        return Icon(Icons.remove_circle_outline, color: AppColors.textMuted, size: 19);
      }
      return const Icon(Icons.cancel, color: AppColors.danger, size: 19);
    }
    if (status == 'in_progress') {
      return const SizedBox(
        width: 17,
        height: 17,
        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.mango),
      );
    }
    return Icon(Icons.schedule_rounded, color: AppColors.textMuted, size: 18);
  }

  Future<void> _createNewNode({String? parentFolder, required bool isFolder}) async {
    final ctrl = TextEditingController(
      text: parentFolder != null && parentFolder.isNotEmpty ? '$parentFolder/' : 'lib/',
    );
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(isFolder ? S.t('مجلد جديد', 'New Folder') : S.t('ملف جديد', 'New File')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(hintText: 'lib/screen.dart'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(S.t('إلغاء', 'Cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(S.t('إنشاء', 'Create'))),
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
        IdeNode(path: clean, isFolder: isFolder, content: isFolder ? '' : '// $clean\n'),
      );
      if (!isFolder) _selectFile(clean);
    });
    await widget.onSaveProject();
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
                    onPressed: () => _createNewNode(isFolder: false),
                  ),
                  IconButton(
                    icon: const Icon(Icons.create_new_folder_outlined, size: 20),
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

  /// لوحة Android Studio السفلية المبسطة (Structure / Problems / Pubspec Packages)
  Widget _buildBottomAndroidStudioDock() {
    final problems = _getCodeDiagnostics();
    final outline = _getClassAndMethodOutline();
    final packages = [
      ('http', '^1.2.0'),
      ('shared_preferences', '^2.2.2'),
      ('url_launcher', '^6.2.0'),
      ('file_picker', '^8.0.0'),
      ('intl', 'any'),
    ];

    return Container(
      height: 170,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            color: AppColors.surfaceAlt,
            child: Row(
              children: [
                _dockTabBtn(0, Icons.account_tree_outlined, S.t('الهيكل (Structure)', 'Structure')),
                _dockTabBtn(
                  1,
                  Icons.warning_amber_rounded,
                  '${S.t("الأخطاء", "Problems")} (${problems.length})',
                ),
                _dockTabBtn(2, Icons.extension_outlined, S.t('الحزم (Pubspec)', 'Packages')),
                const Spacer(),
                IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                  onPressed: () => setState(() => _showBottomStudioPanel = false),
                ),
              ],
            ),
          ),
          Expanded(
            child: _bottomPanelTab == 0
                ? ListView(
                    padding: const EdgeInsets.all(8),
                    children: [
                      if (outline.isEmpty)
                        Text(S.t('لا توجد كلاسات في هذا الملف', 'No classes found'), style: TextStyle(color: AppColors.textMuted))
                      else
                        for (final item in outline)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                const Icon(Icons.functions_rounded, size: 16, color: AppColors.mango),
                                const SizedBox(width: 6),
                                Text(item, textDirection: TextDirection.ltr, style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
                              ],
                            ),
                          ),
                    ],
                  )
                : _bottomPanelTab == 1
                    ? ListView(
                        padding: const EdgeInsets.all(10),
                        children: [
                          if (problems.isEmpty)
                            Row(
                              children: [
                                const Icon(Icons.check_circle, color: AppColors.success, size: 18),
                                const SizedBox(width: 8),
                                Text(S.t('لا توجد أخطاء برمجية في هذا الملف ✓', 'No syntax issues detected ✓')),
                              ],
                            )
                          else
                            for (final p in problems)
                              Row(
                                children: [
                                  const Icon(Icons.error_outline, color: AppColors.danger, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(p, style: const TextStyle(color: AppColors.danger))),
                                ],
                              ),
                        ],
                      )
                    : ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        children: [
                          for (final pkg in packages)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('${pkg.$1}: ${pkg.$2}', textDirection: TextDirection.ltr, style: const TextStyle(fontFamily: 'monospace')),
                                TextButton(
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
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text(S.t('تمت إضافة ${pkg.$1} ✓', 'Added ${pkg.$1} ✓'))),
                                        );
                                      }
                                    }
                                  },
                                  child: Text(S.t('+ إضافة', '+ Add')),
                                ),
                              ],
                            ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _dockTabBtn(int idx, IconData icon, String label) {
    final active = _bottomPanelTab == idx;
    return InkWell(
      onTap: () => setState(() => _bottomPanelTab = idx),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: active ? AppColors.mango : Colors.transparent, width: 2),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: active ? AppColors.mango : AppColors.textMuted),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
                color: active ? AppColors.mango : AppColors.textMuted,
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
    final minEditorWidth = MediaQuery.of(context).size.width - 54;

    return Directionality(
      textDirection: S.dir,
      child: Scaffold(
        key: _scaffoldKey,
        drawer: _buildExplorerDrawer(),
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.folder_open_rounded, color: AppColors.mango),
            tooltip: S.t('ملفات المشروع', 'Project Files'),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          ),
          titleSpacing: 0,
          title: Text(
            _activeFilePath?.split('/').last ?? widget.project.name,
            textDirection: TextDirection.ltr,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontFamily: 'monospace', fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.auto_awesome, color: AppColors.mango),
              tooltip: 'AI',
              onPressed: _openDirectAiEditorSheet,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.mango,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: _startCloudBuildFlow,
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: Text(
                  S.t('بناء APK', 'Build APK'),
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (val) {
                if (val == 'dock') setState(() => _showBottomStudioPanel = !_showBottomStudioPanel);
                if (val == 'play') widget.onCheckPlayStore();
                if (val == 'config') widget.onConfigureApp();
                if (val == 'find') setState(() => _showSearchBar = !_showSearchBar);
                if (val == 'save') widget.onSaveProject();
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: 'dock',
                  child: Text(S.t('لوحة أدوات Android Studio السفلية', 'Android Studio Bottom Panel')),
                ),
                PopupMenuItem(
                  value: 'play',
                  child: Text(S.t('فحص جاهزية Google Play (AAB)', 'Google Play Store Check')),
                ),
                PopupMenuItem(
                  value: 'config',
                  child: Text(S.t('أيقونة التطبيق والحزمة', 'App Icon & Package ID')),
                ),
                PopupMenuItem(
                  value: 'find',
                  child: Text(S.t('بحث واستبدال', 'Find & Replace')),
                ),
                PopupMenuItem(
                  value: 'save',
                  child: Text(S.t('حفظ الكل', 'Save All')),
                ),
              ],
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
                        decoration: InputDecoration(hintText: S.t('بحث...', 'Find...'), isDense: true),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _replaceCtrl,
                        textDirection: TextDirection.ltr,
                        decoration: InputDecoration(hintText: S.t('استبدال...', 'Replace...'), isDense: true),
                      ),
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton(
                      onPressed: () {
                        if (_findCtrl.text.isEmpty) return;
                        _codeController.text =
                            _codeController.text.replaceAll(_findCtrl.text, _replaceCtrl.text);
                      },
                      child: Text(S.t('تبديل', 'Replace')),
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
                          color: active ? AppColors.editorBg : AppColors.surface,
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
                              textDirection: TextDirection.ltr,
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
                              child: Icon(Icons.close, size: 14, color: AppColors.textMuted),
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
                  color: AppColors.editorBg,
                  child: SingleChildScrollView(
                    controller: _verticalScrollController,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44,
                          padding: const EdgeInsets.only(right: 8, left: 4),
                          decoration: BoxDecoration(
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
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minWidth: minEditorWidth > 200 ? minEditorWidth : 300),
                              child: IntrinsicWidth(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
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
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_showBottomStudioPanel) _buildBottomAndroidStudioDock(),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Container(
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => setState(() => _showBottomStudioPanel = !_showBottomStudioPanel),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _showBottomStudioPanel ? AppColors.mango : AppColors.surfaceAlt,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.dock_rounded,
                            size: 16,
                            color: _showBottomStudioPanel ? Colors.black : AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
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
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: AppColors.textPrimary,
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
      ),
    );
  }
}