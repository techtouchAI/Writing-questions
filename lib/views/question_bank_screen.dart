import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/difficulty.dart';
import '../models/main_question.dart';
import '../models/question_type.dart';
import '../providers/question_provider.dart';
import 'question_editor_screen.dart';
import 'widgets/export_dialog.dart';
import 'widgets/question_card.dart';

class QuestionBankScreen extends StatefulWidget {
  const QuestionBankScreen({super.key});

  @override
  State<QuestionBankScreen> createState() => _QuestionBankScreenState();
}

class _QuestionBankScreenState extends State<QuestionBankScreen> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    final provider = context.read<QuestionProvider>();
    _searchController = TextEditingController(text: provider.searchQuery)
      ..addListener(() => provider.setSearchQuery(_searchController.text));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openEditor([MainQuestion? question]) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => QuestionEditorScreen(existingQuestion: question),
      ),
    );
  }

  Future<void> _confirmDelete(MainQuestion question) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل أنت متأكد من حذف هذا السؤال من البنك؟'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (shouldDelete != true || !mounted) {
      return;
    }

    try {
      await context.read<QuestionProvider>().deleteQuestion(question.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حذف السؤال.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('تعذر حذف السؤال. حاول مرة أخرى.'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _showExportDialog(List<MainQuestion> questions) async {
    await showDialog<void>(
      context: context,
      builder: (_) => ExportDialog(questions: questions),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<QuestionProvider>();
    final filteredQuestions = provider.filteredQuestions;
    final hasActiveFilters = provider.searchQuery.isNotEmpty ||
        provider.selectedTypeFilter != null ||
        provider.selectedDifficultyFilter != null ||
        provider.selectedSubjectFilter != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('بنك الأسئلة'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'تصدير الأسئلة المعروضة كملف Excel',
            onPressed: filteredQuestions.isEmpty
                ? null
                : () => _showExportDialog(filteredQuestions),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (provider.errorMessage != null || provider.recoveryMessage != null)
            MaterialBanner(
              content: Text(provider.errorMessage ?? provider.recoveryMessage!),
              backgroundColor: provider.errorMessage == null
                  ? Theme.of(context).colorScheme.secondaryContainer
                  : Theme.of(context).colorScheme.errorContainer,
              actions: <Widget>[
                TextButton(
                  onPressed: provider.clearMessages,
                  child: const Text('إخفاء'),
                ),
              ],
            ),
          Container(
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Column(
              children: <Widget>[
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'ابحث عن سؤال أو موضوع أو مادة...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: provider.searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            tooltip: 'مسح البحث',
                            onPressed: _searchController.clear,
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // تلتفّ الفلاتر بدلاً من التمرير الأفقي حتى تبقى كلّ الأزرار ضمن
                // حدود الشاشة، والإزاحة الإضافية (end = اليسار في RTL) تضمن ظهور
                // القوائم المنبثقة كاملة دون قصّ عند الحافة اليسرى.
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 12),
                  child: Wrap(
                    alignment: WrapAlignment.start,
                    spacing: 16,
                    runSpacing: 8,
                    children: <Widget>[
                      DropdownButton<QuestionType?>(
                        value: provider.selectedTypeFilter,
                        hint: const Text('نوع السؤال'),
                        underline: const SizedBox(),
                        items: <DropdownMenuItem<QuestionType?>>[
                          const DropdownMenuItem<QuestionType?>(
                            value: null,
                            child: Text('جميع الأنواع'),
                          ),
                          ...QuestionType.values.map(
                            (type) => DropdownMenuItem<QuestionType?>(
                              value: type,
                              child: Text(type.arabicLabel),
                            ),
                          ),
                        ],
                        onChanged: provider.setTypeFilter,
                      ),
                      DropdownButton<Difficulty?>(
                        value: provider.selectedDifficultyFilter,
                        hint: const Text('مستوى الصعوبة'),
                        underline: const SizedBox(),
                        items: <DropdownMenuItem<Difficulty?>>[
                          const DropdownMenuItem<Difficulty?>(
                            value: null,
                            child: Text('جميع المستويات'),
                          ),
                          ...Difficulty.values.map(
                            (difficulty) => DropdownMenuItem<Difficulty?>(
                              value: difficulty,
                              child: Text(difficulty.arabicLabel),
                            ),
                          ),
                        ],
                        onChanged: provider.setDifficultyFilter,
                      ),
                      DropdownButton<String?>(
                        value: provider.selectedSubjectFilter,
                        hint: const Text('المادة'),
                        underline: const SizedBox(),
                        items: <DropdownMenuItem<String?>>[
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('جميع المواد'),
                          ),
                          ...provider.availableSubjects.map(
                            (subject) => DropdownMenuItem<String?>(
                              value: subject,
                              child: Text(subject),
                            ),
                          ),
                        ],
                        onChanged: provider.setSubjectFilter,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Expanded(
                  child: Text(
                    'عدد الأسئلة المعروضة: ${filteredQuestions.length}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.grey,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (hasActiveFilters)
                  TextButton(
                    onPressed: () {
                      _searchController.clear();
                      provider.resetFilters();
                    },
                    child: const Text(
                      'إعادة تعيين الفلاتر',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: provider.isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredQuestions.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Icon(
                              Icons.quiz_outlined,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              provider.questions.isEmpty
                                  ? 'لا توجد أسئلة في البنك بعد.'
                                  : 'لا توجد أسئلة تطابق البحث أو الفلتر.',
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: filteredQuestions.length,
                        itemBuilder: (context, index) {
                          final question = filteredQuestions[index];
                          return QuestionCard(
                            question: question,
                            onEdit: () => _openEditor(question),
                            onDelete: () => _confirmDelete(question),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('سؤال جديد'),
        onPressed: _openEditor,
      ),
    );
  }
}
