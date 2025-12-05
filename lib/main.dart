import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yandex_mobileads/mobile_ads.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MobileAds.initialize();
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

class _QuizPageState extends State<QuizPage> with TickerProviderStateMixin {
  int index = 0;
  int score = 0;
  int? selectedOption;
  bool _isProcessing = false;
  bool _hasInternet = true;
  bool _adIsShowing = false; // ← НОВОЕ: защита от дублирования рекламы

  late final Future<InterstitialAdLoader> _adLoader;
  InterstitialAd? _ad;

  // КЛЮЧИ ДЛЯ ТОЧНОЙ АНИМАЦИИ
  final GlobalKey _scoreKey = GlobalKey();
  final List<GlobalKey> _cardKeys = List.generate(3, (_) => GlobalKey());

  Offset? _starStart;
  Offset? _starEnd;
  bool _showStar = false;

  late AnimationController _starController;
  late Animation<Offset> _starAnimation;

  @override
  void initState() {
    super.initState();
    _adLoader = _createInterstitialAdLoader();
    _loadInterstitialAd();

    _starController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _starController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _showStar = false);
        _starController.reset();
      }
    });
  }

  @override
  void dispose() {
    _starController.dispose();
    _ad?.destroy();
    super.dispose();
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
          adUnitId: 'demo-interstitial-yandex',
        ),
      );
    } catch (e) {
      debugPrint('Ошибка загрузки рекламы: $e');
    }
  }

  Future<void> _showInterstitial() async {
    if (_ad == null || _adIsShowing) return;

    _adIsShowing = true;
    setState(() {
      _isProcessing = true;
    });

    _ad!.setAdEventListener(
      eventListener: InterstitialAdEventListener(
        onAdShown: () => debugPrint('Реклама показана'),
        onAdFailedToShow: (error) {
          debugPrint('Не удалось показать: $error');
          _onAdClosed();
        },
        onAdDismissed: () {
          debugPrint('Реклама закрыта');
          _onAdClosed();
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
    } finally {
      _onAdClosed();
    }
  }

  void _onAdClosed() {
    if (!_adIsShowing) return;
    _adIsShowing = false;

    _ad?.destroy();
    _ad = null;
    _loadInterstitialAd();

    if (mounted) {
      setState(() {
        _isProcessing = false;
        // Этот setState "перерисовывает" UI и снимает зависание
      });
    }
  }

  Future<void> _saveProgress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('quiz_index', index);
    await prefs.setInt('quiz_score', score);
  }

  void answer(int selected) async {
    if (_isProcessing || _adIsShowing) return;

    _isProcessing = true;
    final correct = widget.questions[index].correctIndex;
    setState(() => selectedOption = selected);

    if (selected == correct) {
      score++;
      _startStarAnimation(selected);
      await _saveProgress();
      await Future.delayed(const Duration(milliseconds: 800));

      if (index < widget.questions.length - 1) {
        setState(() {
          index++;
          selectedOption = null;
        });

        if (index % 5 == 0) {
          await _showInterstitial();
          // _isProcessing сбросится в _onAdClosed()
        } else {
          if (mounted) {
            setState(() {
              _isProcessing = false;
            });
          }
        }
      } else {
        _showCompletionDialog();
        if (mounted) {
          setState(() {
            _isProcessing = false;
          });
        }
      }
    } else {
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        setState(() {
          selectedOption = null;
          _isProcessing = false; // ← ИСПРАВЛЕНО: раньше не было!
        });
      }
    }
  }

  void _startStarAnimation(int cardIndex) {
    final cardContext = _cardKeys[cardIndex].currentContext;
    final scoreContext = _scoreKey.currentContext;

    if (cardContext == null || scoreContext == null) return;

    final cardBox = cardContext.findRenderObject() as RenderBox;
    final scoreBox = scoreContext.findRenderObject() as RenderBox;

    final start = cardBox.localToGlobal(cardBox.size.center(Offset.zero));
    final end = scoreBox.localToGlobal(scoreBox.size.center(Offset.zero));

    setState(() {
      _starStart = start;
      _starEnd = end;
      _showStar = true;
      _starAnimation = Tween<Offset>(begin: start, end: end).animate(
        CurvedAnimation(parent: _starController, curve: Curves.easeOutBack),
      );
    });

    _starController.forward();
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

  void _restartApp() {
    exit(0);
  }

  Color _getBorderColor(int optionIndex) {
    if (selectedOption == null) return Colors.transparent;
    if (optionIndex == selectedOption) {
      return widget.questions[index].correctIndex == optionIndex
          ? Colors.green.shade700
          : Colors.red.shade700;
    }
    return Colors.transparent;
  }

  Widget _buildImageWithErrorHandling(String url, {bool isBackground = false}) {
    return Image.network(
      url,
      fit: isBackground ? BoxFit.cover : BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        bool hasInternet = false;
        try {
          InternetAddress.lookup('8.8.8.8')
              .then((_) => hasInternet = true)
              .catchError((_) => hasInternet = false);
        } on SocketException {
          hasInternet = false;
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!hasInternet && mounted) {
            setState(() {
              _hasInternet = false;
            });
          }
        });

        if (!hasInternet) {
          return Container();
        }

        return Container(
          color: isBackground ? Colors.grey[800] : Colors.grey[600],
          alignment: Alignment.center,
          child: const Icon(Icons.error, color: Colors.white54, size: 48),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.questions[index];

    if (!_hasInternet) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                const Text(
                  'Нет подключения к интернету',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Проверьте соединение и перезапустите приложение',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _restartApp,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Перезапустить'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: _buildImageWithErrorHandling(q.background, isBackground: true),
          ),
          Container(color: Colors.black.withOpacity(0.35)),

          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.95),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text('${index + 1}/${widget.questions.length}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                      Container(
                        key: _scoreKey,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.amber,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star, color: Colors.orange, size: 18),
                            const SizedBox(width: 4),
                            Text(score.toString(),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 0),

                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: List.generate(3, (i) {
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: GestureDetector(
                              onTap: _isProcessing ? null : () => answer(i),
                              child: Container(
                                key: _cardKeys[i],
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: _getBorderColor(i),
                                    width: 5.0,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 6))
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(24),
                                  child: AspectRatio(
                                    aspectRatio: 1.0,
                                    child: _buildImageWithErrorHandling(q.options[i]),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
                const SizedBox(height: 0),

                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.97),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 3))
                    ],
                  ),
                  child: Text(
                    q.question,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, height: 1.3),
                  ),
                ),
                const SizedBox(height: 18),
              ],
            ),
          ),

          if (_showStar)
            AnimatedBuilder(
              animation: _starAnimation,
              builder: (_, __) {
                return Positioned(
                  left: _starAnimation.value.dx - 18,
                  top: _starAnimation.value.dy - 18,
                  child: const Icon(Icons.star, color: Colors.yellow, size: 48),
                );
              },
            ),
        ],
      ),
    );
  }
}