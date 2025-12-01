import 'dart:convert';
import 'package:flutter/material.dart';

void main() => runApp(const QuizApp());

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
  int index = 0;
  int score = 0;

  void answer(int selected) {
    if (selected == widget.questions[index].correctIndex) {
      score++;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Верно!'), backgroundColor: Colors.green),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не-а!'), backgroundColor: Colors.red),
      );
    }

    if (index < widget.questions.length - 1) {
      setState(() => index++);
    } else {
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
                onPressed: () {
                  Navigator.pop(context);
                  setState(() => index = score = 0);
                },
                child: const Text('Играть снова'),
              ),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.questions[index];

    return Scaffold(
      body: Stack(
        children: [
          // Фон — оставляем как есть (cover)
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
                // Компактные счётчики
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
                          '${index + 1}/${widget.questions.length}',
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

                // ТРИ ВСЕГДА КВАДРАТНЫХ КАРТИНКИ — ИСПРАВЛЕНО!
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: List.generate(3, (i) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: GestureDetector(
                            onTap: () => answer(i),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(28),
                                boxShadow: const [
                                  BoxShadow(color: Colors.black54, blurRadius: 16, offset: Offset(0, 8)),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(28),
                                child: AspectRatio(
                                  aspectRatio: 1.0, // ← ГАРАНТИРОВАННО КВАДРАТ
                                  child: Image.asset(
                                    q.options[i],
                                    fit: BoxFit.contain, // ✅ ИСПРАВЛЕНО: без обрезки
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

                // Компактный вопрос
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.97),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(color: Colors.black38, blurRadius: 12, offset: Offset(0, 4)),
                    ],
                  ),
                  child: Text(
                    q.question,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
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