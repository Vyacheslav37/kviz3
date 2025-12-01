import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const QuizApp());
}

class QuizApp extends StatelessWidget {
  const QuizApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Смешной Квиз',
    theme: ThemeData(useMaterial3: true),
    home: const QuizLoaderPage(),
  );
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
    question: json['question'],
    background: json['background'],
    options: List<String>.from(json['options']),
    correctIndex: json['correctIndex'],
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
  Widget build(BuildContext context) => Scaffold(
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

class QuizPage extends StatefulWidget {
  final List<QuizQuestion> questions;
  const QuizPage({super.key, required this.questions});

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  int? index;
  int? score;
  int? selectedOption;
  Color? selectedColor;
  bool _isProcessing = false; // Защита от быстрых тапов

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    final prefs = await SharedPreferences.getInstance();
    int savedIndex = prefs.getInt('quiz_index') ?? 0;
    int savedScore = prefs.getInt('quiz_score') ?? 0;

    if (savedIndex >= widget.questions.length) {
      savedIndex = 0;
      savedScore = 0;
      await prefs.setInt('quiz_index', 0);
      await prefs.setInt('quiz_score', 0);
    }

    if (mounted) {
      setState(() {
        index = savedIndex;
        score = savedScore;
        selectedOption = null;
        selectedColor = null;
        _isProcessing = false;
      });
    }
  }

  Future<void> _saveProgress() async {
    if (index != null && score != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('quiz_index', index!);
      await prefs.setInt('quiz_score', score!);
    }
  }

  void answer(int selected) {
    if (_isProcessing || index == null) return;

    final correctIndex = widget.questions[index!].correctIndex;

    if (selected == correctIndex) {
      // ✅ Правильный ответ
      _isProcessing = true;
      setState(() {
        selectedOption = selected;
        selectedColor = Colors.green;
        score = (score ?? 0) + 1;
      });
      _saveProgress();

      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          if (index! < widget.questions.length - 1) {
            setState(() {
              index = index! + 1;
              selectedOption = null;
              selectedColor = null;
              _isProcessing = false;
            });
            _saveProgress();
          } else {
            _showCompletionDialog();
          }
        }
      });
    } else {
      // ❌ Неверный ответ — подсветка, но остаёмся на том же вопросе
      setState(() {
        selectedOption = selected;
        selectedColor = Colors.red;
      });
      // Не блокируем повторные попытки (только один тап за раз)
      // Защита от спама: сбрасываем через 300 мс
      _isProcessing = true;
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() {
            _isProcessing = false;
          });
        }
      });
    }
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text('Квиз завершён!', textAlign: TextAlign.center),
        content: Text(
          'Счёт: $score из ${widget.questions.length}',
          textAlign: TextAlign.center,
        ),
        actions: [
          Center(
            child: FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                final prefs = await SharedPreferences.getInstance();
                await prefs.setInt('quiz_index', 0);
                await prefs.setInt('quiz_score', 0);
                if (mounted) {
                  setState(() {
                    index = 0;
                    score = 0;
                    selectedOption = null;
                    selectedColor = null;
                    _isProcessing = false;
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
  Widget build(BuildContext context) {
    if (index == null || score == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final q = widget.questions[index!];

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              q.background,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: Colors.grey[800]),
            ),
          ),
          Container(color: Colors.black.withOpacity(0.35)),

          SafeArea(
            child: Column(
              children: [
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
                        child: Text(
                          '${index! + 1}/${widget.questions.length}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.amber,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star, color: Colors.orange, size: 20),
                            const SizedBox(width: 6),
                            Text(
                              score.toString(),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: List.generate(3, (i) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: GestureDetector(
                            onTap: _isProcessing ? null : () => answer(i), // 🔒 защита
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(28),
                                boxShadow: const [
                                  BoxShadow(color: Colors.black54, blurRadius: 16, offset: Offset(0, 8)),
                                ],
                                border: selectedOption == i
                                    ? Border.all(
                                  color: selectedColor ?? Colors.transparent,
                                  width: 4,
                                )
                                    : null,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(28),
                                child: AspectRatio(
                                  aspectRatio: 1.0,
                                  child: Image.asset(
                                    q.options[i],
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: Colors.grey[600],
                                      alignment: Alignment.center,
                                      child: const Icon(Icons.broken_image, color: Colors.grey),
                                    ),
                                  ),
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

                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(color: Colors.black38, blurRadius: 12, offset: Offset(0, 4)),
                    ],
                  ),
                  child: Text(
                    q.question,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      height: 1.3,
                    ),
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