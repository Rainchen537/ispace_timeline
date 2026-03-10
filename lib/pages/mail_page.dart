import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/mail_models.dart';
import '../services/mail_service.dart';
import '../services/mail_service_factory.dart';
import '../state/app_session_controller.dart';
import '../widgets/native_html_mail_view.dart';

class MailPage extends StatefulWidget {
  const MailPage({super.key, required this.controller});

  final AppSessionController controller;

  @override
  State<MailPage> createState() => _MailPageState();
}

class _MailPageState extends State<MailPage> {
  final MailService _mailService = createMailService();
  final TextEditingController _searchController = TextEditingController();
  final DateFormat _detailTimeFormat = DateFormat('yyyy-MM-dd HH:mm');

  MailAccessCredentials? _credentials;
  MailInboxSnapshot? _snapshot;
  String? _errorMessage;
  bool _isLoading = false;
  bool _showUnreadOnly = false;
  int? _openingMessageUid;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _refreshInbox();
  }

  @override
  void dispose() {
    _searchController.dispose();
    unawaited(_mailService.close());
    super.dispose();
  }

  Future<void> _refreshInbox() async {
    if (_isLoading) {
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final credentials = await widget.controller.loadMailAccessCredentials();
      if (credentials == null) {
        throw const MailServiceException('请先登录后再读取邮箱。');
      }
      final snapshot = await _mailService.fetchInbox(credentials: credentials);
      if (!mounted) {
        return;
      }
      setState(() {
        _credentials = credentials;
        _snapshot = snapshot;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openMessage(MailMessageSummary message) async {
    if (_openingMessageUid != null) {
      return;
    }
    setState(() {
      _openingMessageUid = message.uid;
    });

    try {
      final credentials =
          _credentials ?? await widget.controller.loadMailAccessCredentials();
      if (credentials == null) {
        throw const MailServiceException('请先登录后再读取邮箱。');
      }
      final detail = await _mailService.readMessage(
        credentials: credentials,
        uid: message.uid,
      );
      if (!mounted) {
        return;
      }
      _markMessageAsSeen(message.uid);
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => _MailDetailPage(
            detail: detail,
            timeFormat: _detailTimeFormat,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) {
        setState(() {
          _openingMessageUid = null;
        });
      }
    }
  }

  void _markMessageAsSeen(int uid) {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return;
    }
    final updatedMessages = snapshot.messages.map((message) {
      if (message.uid != uid) {
        return message;
      }
      return message.copyWith(isSeen: true);
    }).toList(growable: false);
    setState(() {
      _snapshot = snapshot.copyWith(messages: updatedMessages);
    });
  }

  List<MailMessageSummary> _visibleMessages(List<MailMessageSummary> messages) {
    final normalizedQuery = _searchQuery.trim().toLowerCase();
    return messages.where((message) {
      if (_showUnreadOnly && message.isSeen) {
        return false;
      }
      if (normalizedQuery.isEmpty) {
        return true;
      }
      final searchableText =
          '${message.sender}\n${message.subject}\n${message.preview}'
              .toLowerCase();
      return searchableText.contains(normalizedQuery);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final visibleMessages = _visibleMessages(snapshot?.messages ?? const []);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: const Color(0xFFD8E3F1),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  Expanded(child: _buildSearchBar()),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 34,
                    height: 34,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      onPressed: _isLoading ? null : _refreshInbox,
                      iconSize: 18,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.refresh_rounded,
                              color: Colors.black87,
                            ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: 44,
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: _TopAction(
                      icon: Icons.inbox_outlined,
                      label: '收件箱',
                      selected: true,
                      onTap: () {},
                    ),
                  ),
                  const VerticalDivider(
                    width: 1,
                    indent: 14,
                    endIndent: 14,
                    color: Color(0xFFE5E7EB),
                  ),
                  Expanded(
                    child: _TopAction(
                      icon: _showUnreadOnly
                          ? Icons.mark_email_unread_rounded
                          : Icons.drafts_outlined,
                      label: '未读',
                      selected: _showUnreadOnly,
                      onTap: () {
                        setState(() {
                          _showUnreadOnly = !_showUnreadOnly;
                        });
                      },
                    ),
                  ),
                  const VerticalDivider(
                    width: 1,
                    indent: 14,
                    endIndent: 14,
                    color: Color(0xFFE5E7EB),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        '${visibleMessages.length} 封',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: const Color(0xFF6B7280),
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE5E7EB)),
            Expanded(
              child: Container(
                color: Colors.white,
                child: _buildBody(context, snapshot, visibleMessages),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
        },
        decoration: InputDecoration(
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 9),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: Color(0xFF9CA3AF),
            size: 18,
          ),
          hintText: '搜索',
          hintStyle: const TextStyle(
            color: Color(0xFF9CA3AF),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 36),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Color(0xFF9CA3AF),
                    size: 16,
                  ),
                ),
        ),
        style: const TextStyle(
          fontSize: 13,
          color: Color(0xFF111827),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    MailInboxSnapshot? snapshot,
    List<MailMessageSummary> visibleMessages,
  ) {
    if (_isLoading && snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && snapshot == null) {
      return _buildEmptyState(
        title: '加载失败',
        subtitle: _errorMessage!,
      );
    }

    if (snapshot == null) {
      return _buildEmptyState(
        title: '暂无邮件',
        subtitle: '下拉或点击右上角刷新后读取邮箱。',
      );
    }

    return Column(
      children: [
        if (_errorMessage != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
            color: const Color(0xFFFFFBEB),
            child: Text(
              _errorMessage!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFFB45309),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        Expanded(
          child: RefreshIndicator.adaptive(
            onRefresh: _refreshInbox,
            child: visibleMessages.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: 280,
                        child: _buildEmptyState(
                          title: '没有匹配的邮件',
                          subtitle: _searchQuery.isEmpty && _showUnreadOnly
                              ? '当前没有未读邮件。'
                              : '换个关键词试试。',
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    itemCount: visibleMessages.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 76, endIndent: 16),
                    itemBuilder: (context, index) {
                      final message = visibleMessages[index];
                      return _MailListTile(
                        message: message,
                        timeLabel: _formatMessageTime(message.date),
                        isOpening: _openingMessageUid == message.uid,
                        onTap: () => _openMessage(message),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState({
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.mail_outline_rounded,
              size: 42,
              color: Color(0xFF9CA3AF),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 12,
                height: 1.5,
                color: Color(0xFF6B7280),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _formatMessageTime(DateTime? dateTime) {
    if (dateTime == null) {
      return '';
    }
    final now = DateTime.now();
    final isSameDay =
        dateTime.year == now.year &&
        dateTime.month == now.month &&
        dateTime.day == now.day;
    if (isSameDay) {
      return DateFormat('HH:mm').format(dateTime);
    }
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday =
        dateTime.year == yesterday.year &&
        dateTime.month == yesterday.month &&
        dateTime.day == yesterday.day;
    if (isYesterday) {
      return '昨天';
    }
    return DateFormat('MM-dd').format(dateTime);
  }
}

class _TopAction extends StatelessWidget {
  const _TopAction({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? const Color(0xFF4B5563)
        : const Color(0xFF9CA3AF);
    return InkWell(
      onTap: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _MailListTile extends StatelessWidget {
  const _MailListTile({
    required this.message,
    required this.timeLabel,
    required this.isOpening,
    required this.onTap,
  });

  final MailMessageSummary message;
  final String timeLabel;
  final bool isOpening;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isOpening ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Avatar(text: message.sender),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!message.isSeen)
                        Container(
                          width: 10,
                          height: 10,
                          margin: const EdgeInsets.only(top: 6, right: 8),
                          decoration: const BoxDecoration(
                            color: Color(0xFF2F80ED),
                            shape: BoxShape.circle,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          message.sender,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: message.isSeen
                                ? FontWeight.w600
                                : FontWeight.w700,
                            color: const Color(0xFF111827),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        timeLabel,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFFD1D5DB),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message.subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF111827),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (message.preview.isNotEmpty || message.hasHtmlBody) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            message.preview.isNotEmpty
                                ? message.preview
                                : 'HTML 邮件，点开查看完整内容',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              height: 1.25,
                              color: Color(0xFF9CA3AF),
                            ),
                          ),
                        ),
                        if (isOpening) ...[
                          const SizedBox(width: 10),
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ],
                      ],
                    ),
                  ] else if (isOpening) ...[
                    const SizedBox(height: 4),
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final initials = _initials(text);
    return Container(
      width: 38,
      height: 38,
      decoration: const BoxDecoration(
        color: Color(0xFFF3F4F6),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Color(0xFF2F80ED),
        ),
      ),
    );
  }

  static String _initials(String input) {
    final cleaned = input.trim();
    if (cleaned.isEmpty) {
      return '邮';
    }
    final upper = cleaned.toUpperCase();
    if (upper.length == 1) {
      return upper;
    }
    final words = upper
        .split(RegExp(r'[^A-Z0-9\u4E00-\u9FFF]+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (words.length >= 2) {
      return '${words.first[0]}${words[1][0]}';
    }
    return upper.characters.take(2).toString();
  }
}

class _MailDetailPage extends StatelessWidget {
  const _MailDetailPage({
    required this.detail,
    required this.timeFormat,
  });

  final MailMessageDetail detail;
  final DateFormat timeFormat;

  @override
  Widget build(BuildContext context) {
    final htmlBody = detail.htmlBody?.trim() ?? '';
    final hasHtmlBody = htmlBody.isNotEmpty;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('邮件详情'),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.subject,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 8),
                _DetailLine(label: '发件人', value: detail.sender),
                _DetailLine(label: '收件人', value: detail.recipients),
                if (detail.cc != null) _DetailLine(label: '抄送', value: detail.cc!),
                _DetailLine(
                  label: '时间',
                  value: detail.date == null
                      ? '未知时间'
                      : timeFormat.format(detail.date!),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: hasHtmlBody
                ? NativeHtmlMailView(
                    htmlContent: htmlBody,
                    baseUrl: 'https://mail.bnbu.edu.cn/',
                  )
                : SelectionArea(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      children: [
                        Text(
                          detail.body.isEmpty
                              ? '这封邮件没有可解析的正文内容。'
                              : detail.body,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.65,
                            color: Color(0xFF374151),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 12, color: Color(0xFF374151)),
          children: [
            TextSpan(
              text: '$label：',
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}
