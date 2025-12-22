import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yandex_mobileads/mobile_ads.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:url_launcher/url_launcher.dart';

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
  late Future<QuizData> future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    future = _loadQuizData();
  }

  Future<QuizData> _loadQuizData() async {
    debugPrint('[LOG] Загрузка данных квиза начата');
    final prefs = await SharedPreferences.getInstance();
    final jsonString = await DefaultAssetBundle.of(context).loadString('assets/questions.json');
    final List<dynamic> jsonList = jsonDecode(jsonString);
    final questions = jsonList.map((e) => QuizQuestion.fromJson(e)).toList();
    debugPrint('[LOG] Вопросов загружено: ${questions.length}');

    int savedIndex = prefs.getInt('quiz_index') ?? 0;
    int savedScore = prefs.getInt('quiz_score') ?? 0;

    if (savedIndex < 0 || savedIndex >= questions.length) {
      debugPrint('[LOG] Некорректный сохранённый индекс: $savedIndex, сброс к 0');
      savedIndex = 0;
      savedScore = 0;
      await prefs.setInt('quiz_index', 0);
      await prefs.setInt('quiz_score', 0);
    }

    debugPrint('[LOG] Загружено: index=$savedIndex, score=$savedScore');
    return QuizData(questions: questions, startIndex: savedIndex, startScore: savedScore);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<QuizData>(
        future: future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData || snap.data!.questions.isEmpty) {
            return const Center(child: Text('Ошибка загрузки вопросов'));
          }
          final data = snap.data!;
          debugPrint('[LOG] Переход к QuizPage: index=${data.startIndex}, score=${data.startScore}');
          return QuizPage(
            questions: data.questions,
            startIndex: data.startIndex,
            startScore: data.startScore,
          );
        },
      ),
    );
  }
}

class QuizData {
  final List<QuizQuestion> questions;
  final int startIndex;
  final int startScore;

  QuizData({required this.questions, required this.startIndex, required this.startScore});
}

class QuizPage extends StatefulWidget {
  final List<QuizQuestion> questions;
  final int startIndex;
  final int startScore;

  const QuizPage({
    super.key,
    required this.questions,
    this.startIndex = 0,
    this.startScore = 0,
  });

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> with TickerProviderStateMixin {
  late int index;
  late int score;
  int? selectedOption;
  bool _isProcessing = false;
  bool _hasInternet = true;
  bool _adIsShowing = false;

  late final Future<InterstitialAdLoader> _adLoader;
  InterstitialAd? _ad;

  final GlobalKey _scoreKey = GlobalKey();
  late List<GlobalKey> _cardKeys;

  Offset? _starStart;
  Offset? _starEnd;
  bool _showStar = false;

  late AnimationController _starController;
  late Animation<Offset> _starAnimation;

  late AudioPlayer _audioPlayer;
  bool _isSoundPlaying = false; // ← ДОБАВЛЕНО: защита от задвоения

  final Set<int> _firstAttemptedQuestions = {};

  @override
  void initState() {
    super.initState();
    index = widget.startIndex;
    score = widget.startScore;

    final optionCount = widget.questions.isNotEmpty ? widget.questions.first.options.length : 3;
    _cardKeys = List.generate(optionCount, (_) => GlobalKey());

    _checkInternetConnection();
    _audioPlayer = AudioPlayer();
    _adLoader = _createInterstitialAdLoader();
    _loadInterstitialAd();

    _starController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _starController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (mounted) {
          setState(() => _showStar = false);
          debugPrint('[LOG] Анимация звезды завершена, _showStar=false');
        }
        _starController.reset();
      }
    });
  }

  Future<void> _checkInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('8.8.8.8').timeout(const Duration(seconds: 3));
      _hasInternet = result.isNotEmpty;
    } catch (_) {
      _hasInternet = false;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    debugPrint('[LOG] dispose вызван');
    _starController.dispose();
    _audioPlayer.dispose();
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
          adUnitId: 'R-M-18100341-1',
        ),
      );
    } catch (e) {
      debugPrint('Ошибка загрузки рекламы: $e');
    }
  }

  Future<void> _showInterstitial() async {
    if (_ad == null || _adIsShowing) return;

    _adIsShowing = true;
    if (mounted) setState(() {});

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
      });
      debugPrint('[LOG] Реклама закрыта, _isProcessing=false (setState)');
    } else {
      _isProcessing = false;
      debugPrint('[LOG] Реклама закрыта, _isProcessing=false (mounted=false)');
    }
  }

  Future<void> _saveProgress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('quiz_index', index);
    await prefs.setInt('quiz_score', score);
    debugPrint('[LOG] Прогресс сохранён: index=$index, score=$score');
  }

  // 🔥 ИСПРАВЛЕНО: защита от задвоения звука
  Future<void> _playSound(String asset) async {
    if (_isSoundPlaying) {
      debugPrint('[LOG] Звук уже играет — пропускаем $asset');
      return;
    }

    _isSoundPlaying = true;
    debugPrint('[LOG] Начало проигрывания $asset');

    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource(asset));
      // Оба звука длятся ~1 секунду — ждём 1100 мс для надёжности
      await Future.delayed(const Duration(milliseconds: 1100));
    } catch (e) {
      debugPrint('[LOG] Ошибка проигрывания $asset: $e');
    } finally {
      _isSoundPlaying = false;
      debugPrint('[LOG] Завершено проигрывание $asset');
    }
  }

  void _updateCardKeysForCurrentQuestion() {
    if (mounted && widget.questions.isNotEmpty && index < widget.questions.length) {
      final newOptionCount = widget.questions[index].options.length;
      if (_cardKeys.length != newOptionCount) {
        _cardKeys = List.generate(newOptionCount, (_) => GlobalKey());
        debugPrint('[LOG] _cardKeys обновлены для вопроса $index (новое количество: $newOptionCount)');
      }
    }
  }

  void answer(int selected) async {
    final currentOptionsCount = widget.questions[index].options.length;
    debugPrint('[LOG] 🔘 Тап по кнопке $selected (всего вариантов: $currentOptionsCount) на вопросе $index');

    if (selected < 0 || selected >= currentOptionsCount) {
      debugPrint('[LOG] ❌ ИГНОРИРУЕМ: индекс $selected вне диапазона [0, $currentOptionsCount)');
      return;
    }

    debugPrint('\n[LOG] === НАЧАЛО answer($selected) ===');
    debugPrint('[LOG] Состояние: _isProcessing=$_isProcessing, _adIsShowing=$_adIsShowing, mounted=$mounted');
    debugPrint('[LOG] Текущий вопрос: $index, selectedOption=$selectedOption');

    if (_isProcessing || _adIsShowing) {
      debugPrint('[LOG] БЛОКИРОВАНО: _isProcessing=$_isProcessing или реклама показывается');
      return;
    }

    final correct = widget.questions[index].correctIndex;
    final isFirstAttempt = !_firstAttemptedQuestions.contains(index);
    _firstAttemptedQuestions.add(index);
    debugPrint('[LOG] Это первая попытка на вопрос $index: $isFirstAttempt');

    _isProcessing = true;
    debugPrint('[LOG] Установлено _isProcessing = true');

    if (mounted) {
      setState(() => selectedOption = selected);
      debugPrint('[LOG] setState выполнен (mounted=true)');
    } else {
      selectedOption = selected;
      debugPrint('[LOG] setState пропущен (mounted=false)');
    }

    if (selected == correct) {
      debugPrint('[LOG] Ответ ВЕРНЫЙ');
      if (isFirstAttempt) {
        score++;
        _startStarAnimation(selected);
        await _saveProgress();
        debugPrint('[LOG] Звезда начислена! Новый счёт: $score');
      } else {
        debugPrint('[LOG] Верный ответ, но не с первой попытки — звезда НЕ начислена');
      }

      await _playSound('sounds/correct.wav');
      await Future.delayed(const Duration(milliseconds: 800));

      if (index + 1 >= widget.questions.length) {
        _showCompletionDialog();
        _isProcessing = false;
        debugPrint('[LOG] Квиз завершён — последний вопрос');
      } else {
        if (mounted) {
          setState(() {
            index++;
            selectedOption = null;
            _updateCardKeysForCurrentQuestion();
          });
          debugPrint('[LOG] Переход к вопросу $index (setState)');
        } else {
          index++;
          selectedOption = null;
          debugPrint('[LOG] Переход к вопросу $index (mounted=false)');
        }
        await _saveProgress();

        if (index % 5 == 0) {
          debugPrint('[LOG] Планируется показ рекламы после вопроса $index');
          await _showInterstitial();
        } else {
          if (mounted) {
            setState(() => _isProcessing = false);
            debugPrint('[LOG] _isProcessing = false (setState, без рекламы)');
          } else {
            _isProcessing = false;
            debugPrint('[LOG] _isProcessing = false (mounted=false, без рекламы)');
          }
        }
      }
    } else {
      debugPrint('[LOG] Ответ НЕВЕРНЫЙ');
      await _playSound('sounds/wrong.wav');
      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        setState(() {
          selectedOption = null;
          _isProcessing = false;
        });
        debugPrint('[LOG] _isProcessing = false после ошибки (setState)');
      } else {
        selectedOption = null;
        _isProcessing = false;
        debugPrint('[LOG] _isProcessing = false после ошибки (mounted=false)');
      }
    }

    debugPrint('[LOG] === КОНЕЦ answer($selected) ===\n');
  }

  void _startStarAnimation(int cardIndex) {
    if (_showStar || _starController.isAnimating) {
      debugPrint('[LOG] Анимация звезды пропущена: уже запущена');
      return;
    }

    if (cardIndex >= _cardKeys.length) {
      debugPrint('[LOG] Анимация звезды отменена: cardIndex вне диапазона');
      return;
    }

    final cardContext = _cardKeys[cardIndex].currentContext;
    final scoreContext = _scoreKey.currentContext;
    if (cardContext == null || scoreContext == null) {
      debugPrint('[LOG] Анимация звезды отменена: контексты null');
      return;
    }

    final cardBox = cardContext.findRenderObject() as RenderBox?;
    final scoreBox = scoreContext.findRenderObject() as RenderBox?;
    if (cardBox == null || scoreBox == null) {
      debugPrint('[LOG] Анимация звезды отменена: RenderBox null');
      return;
    }

    final start = cardBox.localToGlobal(cardBox.size.center(Offset.zero));
    final end = scoreBox.localToGlobal(scoreBox.size.center(Offset.zero));

    if (mounted) {
      setState(() {
        _starStart = start;
        _starEnd = end;
        _showStar = true;
        _starAnimation = Tween<Offset>(begin: start, end: end).animate(
          CurvedAnimation(parent: _starController, curve: Curves.easeOutBack),
        );
      });
      _starController.forward();
      debugPrint('[LOG] Анимация звезды запущена от $start к $end');
    } else {
      debugPrint('[LOG] Анимация звезды не запущена: mounted=false');
    }
  }

  void _showCompletionDialog() {
    debugPrint('[LOG] Показ диалога завершения');
    final int totalQuestions = widget.questions.length;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Квиз завершён!', textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Счёт: $score из $totalQuestions', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            const Text(
              'Если вам понравилось — пожалуйста, оставьте отзыв в RuStore!\nЭто очень помогает нам развивать приложение 😊',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.icon(
                  onPressed: () async {
                    const appId = 'ru.smekho.tap_quiz'; // ← ЗАМЕНИТЕ НА СВОЙ!
                    final uri = Uri.parse('rustore://details?id=$appId');
                    try {
                      await launchUrl(uri);
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('RuStore не найден. Пожалуйста, установите его.')),
                        );
                      }
                      debugPrint('[LOG] Не удалось открыть RuStore: $e');
                    }
                  },
                  icon: const Icon(Icons.star_rate_outlined),
                  label: const Text('Оставить отзыв'),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () async {
                    debugPrint('[LOG] Нажата кнопка "Играть снова"');
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove('quiz_index');
                    await prefs.remove('quiz_score');
                    Navigator.pop(context);
                    if (mounted) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (context) => const QuizLoaderPage()),
                      );
                    }
                  },
                  child: const Text('Играть снова'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getBorderColor(int optionIndex) {
    if (selectedOption == null) return Colors.transparent;
    if (optionIndex == selectedOption) {
      return widget.questions[index].correctIndex == optionIndex ? Colors.green.shade700 : Colors.red.shade700;
    }
    return Colors.transparent;
  }

  Widget _buildImageWithErrorHandling(String url, {bool isBackground = false}) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          color: isBackground ? Colors.black : Colors.grey[300],
          child: const Center(child: CircularProgressIndicator(color: Colors.white)),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        debugPrint('[LOG] ❌ ОШИБКА ЗАГРУЗКИ ИЗОБРАЖЕНИЯ: $url');
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
    if (index >= widget.questions.length) {
      debugPrint('[LOG] Индекс вышел за границы — показ завершения');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isProcessing) _showCompletionDialog();
      });
      return const Scaffold(body: SizedBox());
    }

    debugPrint('[LOG] build вызван, вопрос: $index');
    final q = widget.questions[index];

    debugPrint('[LOG] 🛑 Состояние блокировки на вопросе $index: _isProcessing=$_isProcessing, mounted=$mounted');

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
                const Text('Нет подключения к интернету', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                const Text('Проверьте соединение и перезапустите приложение', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => SystemNavigator.pop(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Перезапустить'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_cardKeys.length != q.options.length) {
      debugPrint('[LOG] ⚠️ НЕСОВПАДЕНИЕ: _cardKeys.length=${_cardKeys.length}, q.options.length=${q.options.length}');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _updateCardKeysForCurrentQuestion());
      });
    } else {
      debugPrint('[LOG] ✅ Количество кнопок и вариантов совпадает (${_cardKeys.length})');
    }

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: _buildImageWithErrorHandling(q.background, isBackground: true)),
          Container(color: Colors.black.withOpacity(0.35)),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 1),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.95), borderRadius: BorderRadius.circular(16)),
                        child: Text('${index + 1}/${widget.questions.length}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                      Container(
                        key: _scoreKey,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(16)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star, color: Colors.orange, size: 18),
                            const SizedBox(width: 4),
                            Text(score.toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 0),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: List.generate(_cardKeys.length, (i) {
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: GestureDetector(
                              onTap: _isProcessing ? null : () => answer(i),
                              child: Container(
                                key: _cardKeys[i],
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: _getBorderColor(i), width: 5.0),
                                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 6))],
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
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.97),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 3))],
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