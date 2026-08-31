import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../providers/engagement_provider.dart';

class FeatureIdeasScreen extends StatefulWidget {
  const FeatureIdeasScreen({super.key});

  @override
  State<FeatureIdeasScreen> createState() => _FeatureIdeasScreenState();
}

class _FeatureIdeasScreenState extends State<FeatureIdeasScreen> {
  // حالات الميزات التجريبية المحلية
  bool _focusModeEnabled = false;
  bool _cinemaModeEnabled = true;

  // دالة التعامل مع التصويت في الفايربيس
  Future<void> _toggleVote(String docId, List<dynamic> votedUsers, String currentUserId) async {
    final docRef = FirebaseFirestore.instance.collection('feature_ideas').doc(docId);
    final hasVoted = votedUsers.contains(currentUserId);

    if (hasVoted) {
      // إلغاء التصويت
      await docRef.update({
        'votes': FieldValue.increment(-1),
        'votedUsers': FieldValue.arrayRemove([currentUserId]),
      });
    } else {
      // إضافة التصويت
      await docRef.update({
        'votes': FieldValue.increment(1),
        'votedUsers': FieldValue.arrayUnion([currentUserId]),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final engagement = context.watch<EngagementProvider>();
    final currentUser = context.watch<AuthProvider>().currentUser;
    final double progress = (engagement.points / 500.0).clamp(0.0, 1.0);
    final l10n = AppLocalizations.of(context);

    if (l10n == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    final isLoggedIn = currentUser != null;

    return Directionality(
      textDirection: l10n.localeName == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0xFF5B6CFF), Color(0xFF7B61FF)],
              ),
            ),
            child: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: Text(l10n.featureIdeasTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
              centerTitle: true,
            ),
          ),
        ),
        body: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          children: [
            // أيقونة ترحيبية
            Center(
              child: Column(
                children: [
                  const Icon(Icons.science_rounded, size: 48, color: Color(0xFF5B6CFF)),
                  const SizedBox(height: 8),
                  Text(l10n.featureIdeasSubtitle, style: const TextStyle(color: Colors.grey, fontSize: 14)),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 1. قسم الميزات التجريبية (Beta)
            Text(l10n.featureIdeasBeta, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    title: Text(l10n.featureIdeasFocusMode, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(l10n.featureIdeasFocusModeSubtitle),
                    activeThumbColor: Colors.white,
                    activeTrackColor: const Color(0xFF5B6CFF),
                    secondary: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: const Color(0xFF5B6CFF).withValues(alpha: 0.1), shape: BoxShape.circle),
                      child: const Icon(Icons.do_not_disturb_on_rounded, color: Color(0xFF5B6CFF)),
                    ),
                    value: _focusModeEnabled,
                    onChanged: (val) => setState(() => _focusModeEnabled = val),
                  ),
                  Divider(height: 1, color: Colors.grey[200]),
                  SwitchListTile(
                    title: Text(l10n.featureIdeasCinemaMode, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(l10n.featureIdeasCinemaModeSubtitle),
                    activeThumbColor: Colors.white,
                    activeTrackColor: const Color(0xFF5B6CFF),
                    secondary: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: const Color(0xFF5B6CFF).withValues(alpha: 0.1), shape: BoxShape.circle),
                      child: const Icon(Icons.theaters_rounded, color: Color(0xFF5B6CFF)),
                    ),
                    value: _cinemaModeEnabled,
                    onChanged: (val) => setState(() => _cinemaModeEnabled = val),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // 2. قسم مكافآت التفاعل
            Text(l10n.featureIdeasRewards, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2EC7A5), Color(0xFF1DA1F2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: const Color(0xFF1DA1F2).withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: Colors.white,
                        child: Icon(Icons.verified, color: Color(0xFF1DA1F2)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l10n.featureIdeasVerifyBadge, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                            Text(l10n.featureIdeasVerifyBadgeSubtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF1DA1F2),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        onPressed: engagement.points >= 500 ? () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l10n.featureIdeasRequestSent))
                          );
                        } : null,
                        child: Text(engagement.points >= 500 ? l10n.featureIdeasActivateNow : l10n.featureIdeasNeedPoints),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text('${engagement.points} / 500', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 8,
                            backgroundColor: Colors.white.withValues(alpha: 0.3),
                            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // 3. قسم التصويت التفاعلي المربوط بـ Firestore
            Text(l10n.featureIdeasVoteTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),

            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('feature_ideas').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(l10n.featureIdeasNoIdeas, textAlign: TextAlign.center),
                    ),
                  );
                }

                final docs = snapshot.data!.docs;

                return Column(
                  children: docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final title = data['title'] ?? l10n.featureIdeasNewFeature;
                    final votes = data['votes'] ?? 0;
                    final votedUsers = List<String>.from(data['votedUsers'] ?? []);
                    final currentUserId = currentUser?.id;
                    final isVoted = currentUserId != null && votedUsers.contains(currentUserId);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text('$votes مستخدم يطالبون بهذه الميزة', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                        ),
                        trailing: InkWell(
                          onTap: !isLoggedIn || currentUserId == null
                              ? null
                              : () => _toggleVote(doc.id, votedUsers, currentUserId),
                          borderRadius: BorderRadius.circular(20),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              gradient: isVoted
                                  ? const LinearGradient(colors: [Color(0xFFE94057), Color(0xFFF27121)])
                                  : LinearGradient(colors: [Colors.grey[200]!, Colors.grey[200]!]),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: isVoted
                                  ? [BoxShadow(color: const Color(0xFFE94057).withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))]
                                  : [],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isVoted ? Icons.local_fire_department_rounded : Icons.local_fire_department_outlined,
                                  color: isVoted ? Colors.white : Colors.grey[600],
                                  size: 18,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isVoted ? l10n.featureIdeasVoted : l10n.featureIdeasVote,
                                  style: TextStyle(
                                    color: isVoted ? Colors.white : Colors.grey[700],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}