import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/question_provider.dart';
import '../providers/exam_provider.dart';
import 'question_bank_screen.dart';
import 'question_editor_screen.dart';
import 'exam_builder_screen.dart';
import 'widgets/export_dialog.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final questionProvider = Provider.of<QuestionProvider>(context);
    final examProvider = Provider.of<ExamProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('صانع ومحرر الأسئلة الاحترافي'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome & Statistics Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [theme.colorScheme.primary, theme.colorScheme.secondary],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'لوحة التحكم وإدارة الاختبارات',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'أنشئ أسئلتك، صمم نماذج الاختبارات، وصدرها لملفات Word منسقة للطباعة أو جداول Excel لمنصات التعليم.',
                    style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      _buildStatBox('الأسئلة بالبنك', '${questionProvider.questions.length}', Icons.quiz),
                      const SizedBox(width: 12),
                      _buildStatBox('الاختبارات الجاهزة', '${examProvider.exams.length}', Icons.assignment),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            const Text(
              'الإجراءات السريعة',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // Quick Actions Grid
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.3,
              children: [
                _buildActionCard(
                  context,
                  title: 'إضافة سؤال جديد',
                  subtitle: 'خيارات، صح/خطأ، مقالي',
                  icon: Icons.add_circle_outline,
                  color: Colors.blue.shade700,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const QuestionEditorScreen()),
                    );
                  },
                ),
                _buildActionCard(
                  context,
                  title: 'بنك الأسئلة',
                  subtitle: 'استعراض وفلترة وتعديل',
                  icon: Icons.inventory_2_outlined,
                  color: Colors.indigo.shade700,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const QuestionBankScreen()),
                    );
                  },
                ),
                _buildActionCard(
                  context,
                  title: 'بناء اختبار جديد',
                  subtitle: 'تخصيص الترويسة والأسئلة',
                  icon: Icons.post_add,
                  color: Colors.teal.shade700,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ExamBuilderScreen()),
                    );
                  },
                ),
                _buildActionCard(
                  context,
                  title: 'تصدير سريع',
                  subtitle: 'تصدير Word و Excel',
                  icon: Icons.file_download_outlined,
                  color: Colors.deepOrange.shade700,
                  onTap: () {
                    if (questionProvider.questions.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('لا توجد أسئلة لتصديرها')),
                      );
                      return;
                    }
                    showDialog(
                      context: context,
                      builder: (ctx) => ExportDialog(questions: questionProvider.questions),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'الاختبارات المحفوظة',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ExamBuilderScreen()),
                    );
                  },
                  child: const Text('اختبار جديد'),
                ),
              ],
            ),

            if (examProvider.exams.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.assignment_outlined, size: 40, color: Colors.grey),
                    SizedBox(height: 8),
                    Text('لم تقم بإنشاء اختبارات مخصصة بعد.', style: TextStyle(color: Colors.grey)),
                    SizedBox(height: 4),
                    Text('انقر على "بناء اختبار جديد" لتجميع أسئلة بنموذج موحد.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: examProvider.exams.length,
                itemBuilder: (ctx, index) {
                  final exam = examProvider.exams[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.description),
                      ),
                      title: Text(exam.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${exam.questions.length} سؤال • ${exam.totalMarks} درجة • ${exam.header.subject}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.ios_share, color: Colors.blue),
                            tooltip: 'تصدير',
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (_) => ExportDialog(exam: exam),
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            tooltip: 'حذف',
                            onPressed: () => examProvider.deleteExam(exam.id),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatBox(String title, String count, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.18),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(count, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                Text(title, style: const TextStyle(color: Colors.white70, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                backgroundColor: color.withOpacity(0.12),
                radius: 18,
                child: Icon(icon, color: color, size: 20),
              ),
              const Spacer(),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
