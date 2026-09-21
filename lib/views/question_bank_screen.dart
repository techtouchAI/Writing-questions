import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/question_type.dart';
import '../models/difficulty.dart';
import '../providers/question_provider.dart';
import 'question_editor_screen.dart';
import 'widgets/question_card.dart';
import 'widgets/export_dialog.dart';

class QuestionBankScreen extends StatelessWidget {
  const QuestionBankScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<QuestionProvider>();
    final visibleQuestions = provider.filteredQuestions;

    return Scaffold(
      appBar: AppBar(
        title: const Text('بنك الأسئلة'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'تصدير الأسئلة كملف Excel',
            onPressed: () {
              if (provider.questions.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('لا توجد أسئلة لتصديرها')),
                );
                return;
              }
              showDialog(
                context: context,
                builder: (ctx) => ExportDialog(questions: visibleQuestions),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Search & Filter Bar
          Container(
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: 'ابحث عن سؤال أو موضوع...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: provider.searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => provider.setSearchQuery(''),
                          )
                        : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  onChanged: (val) => provider.setSearchQuery(val),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      // Filter by Type
                      DropdownButton<QuestionType?>(
                        value: provider.selectedTypeFilter,
                        hint: const Text('نوع السؤال'),
                        underline: const SizedBox(),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('جميع الأنواع')),
                          ...QuestionType.values.map(
                            (t) => DropdownMenuItem(value: t, child: Text(t.arabicLabel)),
                          ),
                        ],
                        onChanged: (val) => provider.setTypeFilter(val),
                      ),
                      const SizedBox(width: 16),

                      // Filter by Difficulty
                      DropdownButton<Difficulty?>(
                        value: provider.selectedDifficultyFilter,
                        hint: const Text('مستوى الصعوبة'),
                        underline: const SizedBox(),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('جميع المستويات')),
                          ...Difficulty.values.map(
                            (d) => DropdownMenuItem(value: d, child: Text(d.arabicLabel)),
                          ),
                        ],
                        onChanged: (val) => provider.setDifficultyFilter(val),
                      ),
                      const SizedBox(width: 16),

                      // Filter by Subject
                      DropdownButton<String>(
                        value: provider.selectedSubjectFilter,
                        underline: const SizedBox(),
                        items: provider.availableSubjects.map((s) {
                          return DropdownMenuItem(value: s, child: Text(s));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) provider.setSubjectFilter(val);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Count summary
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'عدد الأسئلة المعروضة: ${visibleQuestions.length}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
                ),
                if (provider.searchQuery.isNotEmpty ||
                    provider.selectedTypeFilter != null ||
                    provider.selectedDifficultyFilter != null ||
                    provider.selectedSubjectFilter != 'الكل')
                  TextButton(
                    onPressed: () => provider.resetFilters(),
                    child: const Text('إعادة تعيين الفلاتر', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),

          // Questions List
          Expanded(
            child: visibleQuestions.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.quiz_outlined, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        const Text('لا توجد أسئلة تطابق البحث أو الفلتر', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: visibleQuestions.length,
                    itemBuilder: (ctx, index) {
                      final q = visibleQuestions[index];
                      return QuestionCard(
                        question: q,
                        onEdit: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => QuestionEditorScreen(existingQuestion: q),
                            ),
                          );
                        },
                        onDelete: () {
                          showDialog(
                            context: context,
                            builder: (dialogCtx) => AlertDialog(
                              title: const Text('تأكيد الحذف'),
                              content: const Text('هل أنت متأكد من حذف هذا السؤال من البنك؟'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(dialogCtx),
                                  child: const Text('إلغاء'),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                  onPressed: () {
                                    provider.deleteQuestion(q.id);
                                    Navigator.pop(dialogCtx);
                                  },
                                  child: const Text('حذف', style: TextStyle(color: Colors.white)),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('سؤال جديد'),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const QuestionEditorScreen()),
          );
        },
      ),
    );
  }
}
