import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ← ВАЖНО! Импорты именно такие в версии 7.17.0+
import 'package:yandex_mobileads/mobile_ads.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MobileAds.initialize(); // ← правильная инициализация
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const QuizApp());
}

class QuizApp extends StatelessWidget {
  const QuizApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Смешной Квиз',
      theme: ThemeData(useMaterial3: true),
      home: const QuizLoaderPage(),
    );
  }
}

class QuizQuestion {
  final String question;
  final String background;
  final List<String> options;
  final int correctIndex;

  QuizQuestion({
    required this.question,
    required this.background,
    required this.options,
    required this.correctIndex,
  });

  factory QuizQuestion.fromJson(Map<String, dynamic> json) => QuizQuestion(
    question: json['question'] as String,
    background: json['background'] as String,
    options: List<String>.from(json['options'] as List),
    correctIndex: json['correctIndex'] as int,
  );
}

class QuizLoaderPage extends StatefulWidget {
  const QuizLoaderPage({super.key});
  @override
  State<QuizLoaderPage> createState() => _QuizLoaderPageState();
}

class _QuizLoaderPageState extends State<QuizLoaderPage> {
  late Future<List<QuizQuestion>> future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    future = DefaultAssetBundle.of(context)
        .loadString('assets/questions.json')
        .then((d) => jsonDecode(d) as List)
        .then((l) => l.map((e) => QuizQuestion.fromJson(e)).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<QuizQuestion>>(
        future: future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData || snap.data!.isEmpty) {
            return const Center(child: Text('Ошибка загрузки вопросов'));
          }
          return QuizPage(questions: snap.data!);
        },
      ),
    );
  }
}

class QuizPage extends StatefulWidget {
  final List<QuizQuestion> questions;
  const QuizPage({super.key, required this.questions});
  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  int index = 0;
  int score = 0;
  int? selectedOption;
  Color? selectedColor;
  bool _isProcessing = false;

  late final Future<InterstitialAdLoader> _adLoader;
  InterstitialAd? _ad;

  @override
  void initState() {
    super.initState();
    _adLoader = _createInterstitialAdLoader();
    _loadProgress();
    _loadInterstitialAd();
  }

  Future<InterstitialAdLoader> _createInterstitialAdLoader() {
    return InterstitialAdLoader.create(
      onAdLoaded: (InterstitialAd ad) {
        _ad = ad;
        debugPrint('Yandex Interstitial: загружен');
      },
      onAdFailedToLoad: (error) {
        debugPrint('Yandex Interstitial ошибка загрузки: $error');
      },
    );
  }

  Future<void> _loadInterstitialAd() async {
    try {
      final loader = await _adLoader;
      await loader.loadAd(
        adRequestConfiguration: const AdRequestConfiguration(
          adUnitId: 'demo-interstitial-yandex', // ← тестовый ID (работает всегда)
          // adUnitId: 'R-M-XXXXXX-X', // ← потом замени на свой настоящий
        ),
      );
    } catch (e) {
      debugPrint('Ошибка загрузки рекламы: $e');
    }
  }

  Future<void> _showInterstitial() async {
    if (_ad == null) return;

    _ad!.setAdEventListener(
      eventListener: InterstitialAdEventListener(
        onAdShown: () => debugPrint('Реклама показана'),
        onAdFailedToShow: (error) => debugPrint('Не удалось показать: $error'),
        onAdDismissed: () {
          debugPrint('Реклама закрыта');
          _ad?.destroy();
          _ad = null;
          _loadInterstitialAd(); // сразу грузим следующую
        },
        onAdClicked: () => debugPrint('Клик по рекламе'),
        onAdImpression: (_) => debugPrint('Impression'),
      ),
    );

    try {
      await _ad!.show();
      await _ad!.waitForDismiss();
    } catch (e) {
      debugPrint('Ошибка показа рекламы: $e');
    }
  }

  Future<void> _loadProgress() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      index = prefs.getInt('quiz_index') ?? 0;
      score = prefs.getInt('quiz_score') ?? 0;
      if (index >= widget.questions.length) index = 0;
    });
  }

  Future<void> _saveProgress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('quiz_index', index);
    await prefs.setInt('quiz_score', score);
  }

  void answer(int selected) async {
    if (_isProcessing) return;
    _isProcessing = true;

    final correct = widget.questions[index].correctIndex;

    setState(() {
      selectedOption = selected;
      selectedColor = selected == correct ? Colors.green : Colors.red;
    });

    if (selected == correct) {
      score++;
      await _saveProgress();
      await Future.delayed(const Duration(milliseconds: 800));

      if (index < widget.questions.length - 1) {
        index++;
        if (index % 5 == 0) await _showInterstitial(); // каждые 5 правильных
        await _saveProgress();
        if (mounted) setState(() => selectedOption = null);
      } else {
        _showCompletionDialog();
      }
    } else {
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) setState(() => selectedOption = null);
    }

    _isProcessing = false;
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Квиз завершён!', textAlign: TextAlign.center),
        content: Text('Счёт: $score из ${widget.questions.length}', textAlign: TextAlign.center),
        actions: [
          Center(
            child: FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('quiz_index');
                await prefs.remove('quiz_score');
                if (mounted) {
                  setState(() {
                    index = 0;
                    score = 0;
                    selectedOption = null;
                  });
                }
              },
              child: const Text('Играть снова'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _ad?.destroy();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.questions[index];

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(q.background, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(color: Colors.grey[800])),
          ),
          Container(color: Colors.black.withOpacity(0.35)),
          SafeArea(
            child: Column(
              children: [
                // Счётчики
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.95),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('${index + 1}/${widget.questions.length}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(20)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star, color: Colors.orange, size: 20),
                            const SizedBox(width: 6),
                            Text(score.toString(),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Три картинки
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: List.generate(3, (i) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: GestureDetector(
                            onTap: _isProcessing ? null : () => answer(i),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(28),
                                border: selectedOption == i
                                    ? Border.all(color: selectedColor ?? Colors.transparent, width: 4)
                                    : null,
                                boxShadow: const [
                                  BoxShadow(color: Colors.black54, blurRadius: 16, offset: Offset(0, 8))
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(28),
                                child: AspectRatio(
                                  aspectRatio: 1.0,
                                  child: Image.asset(q.options[i], fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(color: Colors.grey[600])),
                                ),
                              ),
                            ),
                          ),
                        ),
                      )),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Вопрос
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.97),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(color: Colors.black38, blurRadius: 12, offset: Offset(0, 4))
                    ],
                  ),
                  child: Text(
                    q.question,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, height: 1.3),
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ],
      ),
    );
  }
}