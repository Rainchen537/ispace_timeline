import 'package:flutter/material.dart';

import '../services/moodle_api_client.dart';
import '../state/app_session_controller.dart';

class UserPage extends StatelessWidget {
  const UserPage({super.key, required this.controller});

  final AppSessionController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final session = controller.session;
        return Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF082032), Color(0xFF2C394B)],
              ),
            ),
            child: SafeArea(
              minimum: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'User',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '账号登录与会话管理',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: session == null
                          ? _buildLoggedOutHint(context)
                          : _buildProfileCard(context, session),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoggedOutHint(BuildContext context) {
    return Center(
      child: Text(
        '登录状态已失效，正在返回登录页。',
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(color: const Color(0xFF5E6472)),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildProfileCard(BuildContext context, AuthSession session) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '已登录',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF4FF),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('姓名：${session.fullName}'),
              const SizedBox(height: 6),
              Text('用户 ID：${session.userId}'),
              const SizedBox(height: 6),
              Text('Token：${_maskToken(session.token)}'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (controller.error != null)
          Text(
            controller.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const Spacer(),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: controller.isBusy
                    ? null
                    : controller.refreshTimeline,
                child: const Text('刷新 Timeline'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.tonal(
                onPressed: controller.isBusy ? null : controller.logout,
                child: const Text('退出登录'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _maskToken(String token) {
    if (token.length <= 10) {
      return '*' * token.length;
    }
    return '${token.substring(0, 4)}****${token.substring(token.length - 4)}';
  }
}
