import 'dart:convert';
import 'package:flutter/material.dart';

void main() {
  runApp(const QuizApp());
}

class QuizApp extends StatelessWidget {
  const QuizApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Смешной Квиз',
      theme: ThemeData(
        fontFamily: 'Roboto', // можно подключить любой шрифт
        useMaterial3: true,
        primarySwatch: Colors.deepPurple,
      ),
      home: const QuizLoaderPage(),
    );
  }
}

class QuizQuestion {
  final String question;
  final String background; // фон вопроса
  final List<String> options; // пути к картинкам-ответам
  final int correctIndex;

  QuizQuestion({
    required this.question,
    required this.background,
    required this.options,
    required this.correctIndex,
  });

  factory QuizQuestion.fromJson(Map<String, dynamic> json) {
    return QuizQuestion(
      question: json['question'] as String,
      background: json['background'] as String,
      options: List<String>.from(json['options'] as List),
      correctIndex: json['correctIndex'] as int,
    );
  }
}

class QuizLoaderPage extends StatefulWidget {
  const QuizLoaderPage({super.key});

  @override
  State<QuizLoaderPage> createState() => _QuizLoaderPageState();
}

class _QuizLoaderPageState extends State<QuizLoaderPage> {
  late Future<List<QuizQuestion>> _futureQuestions;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _futureQuestions = _loadQuestions();
  }

  Future<List<QuizQuestion>> _loadQuestions() async {
    final String data = await DefaultAssetBundle.of(context)
        .loadString('assets/questions.json');
    final List<dynamic> parsed = jsonDecode(data);
    return parsed
        .map((e) => QuizQuestion.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<QuizQuestion>>(
        future: _futureQuestions,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(strokeWidth: 6),
                  SizedBox(height: 30),
                  Text(
                    'Готовим мемы...',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            );
          }

          if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.sentiment_very_dissatisfied, size: 80, color: Colors.grey),
                  const SizedBox(height: 20),
                  const Text('Мемы не загрузились :(', style: TextStyle(fontSize: 20)),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => setState(() {}),
                    child: const Text('Попробовать снова'),
                  ),
                ],
              ),
            );
          }

          return QuizPage(questions: snapshot.data!);
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
  int currentIndex = 0;
  int score = 0;

  void answer(int selectedIndex) {
    if (selectedIndex == widget.questions[currentIndex].correctIndex) {
      score++;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('😂 Верно!', style: TextStyle(fontSize: 18)),
          backgroundColor: Colors.green,
          duration: Duration(milliseconds: 800),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🤦‍♂️ Не-а!', style: TextStyle(fontSize: 18)),
          backgroundColor: Colors.red,
          duration: Duration(milliseconds: 800),
        ),
      );
    }

    if (currentIndex < widget.questions.length - 1) {
      setState(() => currentIndex++);
    } else {
      // Финал
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('🏆 Квиз пройден!', textAlign: TextAlign.center),
          content: Text(
            'Ты набрал $score из ${widget.questions.length}\n\nТы — настоящий мемный эксперт! 🔥',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18),
          ),
          actions: [
            Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  setState(() {
                    currentIndex = 0;
                    score = 0;
                  });
                },
                child: const Text('Играть снова', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final question = widget.questions[currentIndex];

    return Scaffold(
      body: Stack(
        children: [
          // Фон вопроса
          Image.asset(
            question.background,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          ),

          // Тёмная подложка для читаемости
          Container(color: Colors.black.withOpacity(0.4)),

          SafeArea(
            child: Column(
              children: [
                // Прогресс и счёт
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Chip(
                        backgroundColor: Colors.white.withOpacity(0.9),
                        label: Text(
                          '${currentIndex + 1}/${widget.questions.length}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Chip(
                        backgroundColor: Colors.amber,
                        avatar: const Icon(Icons.star, color: Colors.orange),
                        label: Text(
                          'Счёт: $score',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Вопрос
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Card(
                    color: Colors.white.withOpacity(0.95),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        question.question,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                // Варианты ответов — КАРТИНКИ
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 1,
                    ),
                    itemCount: question.options.length,
                    itemBuilder: (context, i) {
                      return GestureDetector(
                        onTap: () => answer(i),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.asset(
                              question.options[i],
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      );
                    },
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