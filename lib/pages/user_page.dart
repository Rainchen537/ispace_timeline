import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/portal_account_profile.dart';
import '../services/moodle_api_client.dart';
import '../state/app_session_controller.dart';

class UserPage extends StatefulWidget {
  const UserPage({super.key, required this.controller});

  final AppSessionController controller;

  @override
  State<UserPage> createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {
  PackageInfo? _packageInfo;
  String _versionLabel = '--';
  bool _isLoadingVersion = true;

  @override
  void initState() {
    super.initState();
    _loadVersionInfo();
  }

  Future<void> _loadVersionInfo() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final version = packageInfo.version.trim();
      final buildNumber = packageInfo.buildNumber.trim();
      final label = buildNumber.isEmpty ? version : '$version+$buildNumber';
      if (!mounted) {
        return;
      }
      setState(() {
        _packageInfo = packageInfo;
        _versionLabel = label.isEmpty ? '--' : label;
        _isLoadingVersion = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingVersion = false;
      });
    }
  }

  Future<void> _handleRefreshTimeline() async {
    final controller = widget.controller;
    if (controller.isBusy || controller.session == null) {
      return;
    }

    controller.clearError();
    await controller.refreshTimeline();
    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          controller.error == null ? 'Timeline 已刷新。' : controller.error!,
        ),
      ),
    );
  }

  void _handleLogout() {
    final controller = widget.controller;
    if (controller.isBusy) {
      return;
    }

    controller.logout();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('已退出当前登录状态。')));
  }

  void _openPlaceholderPage({
    required String title,
    required String description,
    required IconData icon,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _UserPlaceholderPage(
          title: title,
          description: description,
          icon: icon,
        ),
      ),
    );
  }

  void _showVersionSheet() {
    final packageInfo = _packageInfo;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF12324F).withValues(alpha: 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Version detection',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF16324F),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    packageInfo == null ? '当前版本信息暂时不可用。' : '运行时读取到的版本信息如下。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF5D6B7A),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _InfoRow(
                    label: 'app name',
                    value: packageInfo?.appName ?? 'Unavailable',
                  ),
                  const SizedBox(height: 12),
                  _InfoRow(
                    label: 'package',
                    value: packageInfo?.packageName ?? 'Unavailable',
                  ),
                  const SizedBox(height: 12),
                  _InfoRow(label: 'version', value: _versionLabel),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final session = controller.session;
        final username = controller.username?.trim();
        final portalProfile = controller.portalProfile;
        final hasSession = session != null;

        return Scaffold(
          backgroundColor: Colors.white,
          body: ListView(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).padding.bottom + 24,
            ),
            children: [
              _UserHero(
                session: session,
                username: username,
                portalProfile: portalProfile,
                isLoadingPortalProfile: controller.isLoadingPortalProfile,
              ),
              if (controller.error != null) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                  child: _InlineNotice(message: controller.error!),
                ),
                const SizedBox(height: 16),
              ] else
                const SizedBox(height: 18),
              _ActionPanel(
                children: [
                  _ActionTile(
                    icon: Icons.badge_outlined,
                    title: 'ecard',
                    subtitle: '校园电子卡能力入口',
                    onTap: () => _openPlaceholderPage(
                      title: 'ecard',
                      description: 'ecard 页面已预留，后续可以在这里接入校园卡展示、二维码和账户信息。',
                      icon: Icons.badge_outlined,
                    ),
                  ),
                  _ActionTile(
                    icon: Icons.language_rounded,
                    title: 'language',
                    subtitle: '多语言切换即将接入',
                    onTap: () => _openPlaceholderPage(
                      title: 'language',
                      description: '当前版本先保留入口，后续可以在这里接入语言切换与本地化设置。',
                      icon: Icons.language_rounded,
                    ),
                  ),
                  _ActionTile(
                    icon: Icons.verified_outlined,
                    title: 'version detection',
                    subtitle: '运行时版本检测',
                    value: _versionLabel,
                    isValueLoading: _isLoadingVersion,
                    onTap: _showVersionSheet,
                  ),
                  _ActionTile(
                    icon: Icons.refresh_rounded,
                    title: '刷新 timeline',
                    subtitle: hasSession ? '重新同步当前时间线数据' : '当前未登录，无法执行刷新',
                    onTap: hasSession ? _handleRefreshTimeline : null,
                    isBusy: controller.isLoadingTimeline,
                  ),
                  _ActionTile(
                    icon: Icons.logout_rounded,
                    title: 'logout',
                    subtitle: hasSession ? '退出当前 iSpace 会话' : '清理残留会话状态',
                    onTap: controller.isBusy ? null : _handleLogout,
                    isDanger: true,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _UserHero extends StatelessWidget {
  const _UserHero({
    required this.session,
    required this.username,
    required this.portalProfile,
    required this.isLoadingPortalProfile,
  });

  final AuthSession? session;
  final String? username;
  final PortalAccountProfile? portalProfile;
  final bool isLoadingPortalProfile;

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final bannerHeight = (screenHeight * 0.44).clamp(320.0, 430.0).toDouble();

    return SizedBox(
      height: bannerHeight,
      child: Stack(
        children: [
          Positioned.fill(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  'assets/user/user_header.jpeg',
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF0E2841).withValues(alpha: 0.16),
                        const Color(0xFF173E66).withValues(alpha: 0.34),
                        const Color(0xFF113355).withValues(alpha: 0.62),
                        Colors.white.withValues(alpha: 0.12),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'User',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'iSpace account center',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.82),
                              ),
                        ),
                      ],
                    ),
                  ),
                  Opacity(
                    opacity: 0.6,
                    child: SvgPicture.asset(
                      'assets/user/user_logo.svg',
                      width: 54,
                      height: 54,
                      colorFilter: const ColorFilter.mode(
                        Colors.white,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: const Alignment(0, 0.34),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _AcrylicProfileCard(
                session: session,
                username: username,
                portalProfile: portalProfile,
                isLoadingPortalProfile: isLoadingPortalProfile,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AcrylicProfileCard extends StatelessWidget {
  const _AcrylicProfileCard({
    required this.session,
    required this.username,
    required this.portalProfile,
    required this.isLoadingPortalProfile,
  });

  final AuthSession? session;
  final String? username;
  final PortalAccountProfile? portalProfile;
  final bool isLoadingPortalProfile;

  @override
  Widget build(BuildContext context) {
    final fullName = portalProfile?.fullName.trim();
    final displayName = (fullName != null && fullName.isNotEmpty)
        ? fullName
        : (session?.fullName.trim().isNotEmpty ?? false)
        ? session!.fullName.trim()
        : '未登录 iSpace';
    final majorName = portalProfile?.majorName.trim() ?? '';
    final emailAddress = _resolveStudentEmail(username);
    final majorLine = majorName.isNotEmpty
        ? majorName
        : session == null
        ? '登录后可同步身份和组织专业信息'
        : isLoadingPortalProfile
        ? '请稍候片刻'
        : '专业信息同步中';
    final emailLine = emailAddress.isNotEmpty
        ? emailAddress
        : session == null
        ? '登录后可显示学生邮箱'
        : '邮箱信息同步中';

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400, minHeight: 132),
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.16),
                const Color(0xFFE7F1FB).withValues(alpha: 0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF113355).withValues(alpha: 0.10),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 20,
                                  color: const Color(0xFFF8FBFF),
                                ),
                          ),
                        ),
                        if (isLoadingPortalProfile)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 1.8),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _ProfileMetaRow(
                      icon: Icons.school_rounded,
                      text: majorLine,
                      maxLines: 2,
                      textStyle: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(
                            fontSize: 15,
                            color: const Color(0xFFF6FAFF),
                            fontWeight: FontWeight.w700,
                            height: 1.4,
                          ),
                    ),
                    const SizedBox(height: 9),
                    _ProfileMetaRow(
                      icon: Icons.mail_outline_rounded,
                      text: emailLine,
                      maxLines: 1,
                      textStyle: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(
                            fontSize: 14.5,
                            color: const Color(0xFFE7F1FF),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _resolveStudentEmail(String? username) {
    final normalized = (username ?? '').trim().split('@').first.toLowerCase();
    if (normalized.isEmpty) {
      return '';
    }
    return '$normalized@mail.bnbu.edu.cn';
  }
}

class _ProfileMetaRow extends StatelessWidget {
  const _ProfileMetaRow({
    required this.icon,
    required this.text,
    required this.maxLines,
    this.textStyle,
  });

  final IconData icon;
  final String text;
  final int maxLines;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 16, color: const Color(0xFFF5FAFF)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: textStyle,
          ),
        ),
      ],
    );
  }
}

class _ActionPanel extends StatelessWidget {
  const _ActionPanel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: Column(
        children: children
            .expand(
              (child) => [
                child,
                if (child != children.last)
                  const Divider(
                    height: 1,
                    indent: 72,
                    endIndent: 20,
                    color: Color(0xFFE9EEF5),
                  ),
              ],
            )
            .toList(),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.value,
    this.isValueLoading = false,
    this.isBusy = false,
    this.isDanger = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? value;
  final bool isValueLoading;
  final bool isBusy;
  final bool isDanger;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final iconColor = isDanger
        ? const Color(0xFFBC3A3A)
        : const Color(0xFF235789);
    final iconBackground = isDanger
        ? const Color(0xFFFFF0F1)
        : const Color(0xFFEAF2FB);
    final titleColor = isDanger
        ? const Color(0xFF8F232E)
        : const Color(0xFF15314D);
    final enabled = onTap != null;

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: enabled
                            ? titleColor
                            : titleColor.withValues(alpha: 0.45),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF6B7887),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (isBusy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                )
              else if (isValueLoading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                )
              else if (value != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Text(
                    value!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isDanger
                          ? const Color(0xFF8F232E)
                          : const Color(0xFF4A5E74),
                    ),
                  ),
                ),
              if (enabled) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  color: const Color(0xFF98A5B4).withValues(alpha: 0.95),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFFD69A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.info_outline_rounded, color: Color(0xFFB66A00)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF8A5A11),
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF718096),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF17324D),
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _UserPlaceholderPage extends StatelessWidget {
  const _UserPlaceholderPage({
    required this.title,
    required this.description,
    required this.icon,
  });

  final String title;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF16324F).withValues(alpha: 0.08),
                blurRadius: 22,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2FB),
                  borderRadius: BorderRadius.circular(22),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 34, color: const Color(0xFF235789)),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF16324F),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                description,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: const Color(0xFF617080),
                  height: 1.55,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
