import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/mail_models.dart';
import '../services/mail_service.dart';
import '../services/mail_service_factory.dart';
import '../state/app_session_controller.dart';
import '../widgets/native_html_mail_view.dart';

// ─── MailPage ─────────────────────────────────────────────────────────────────

class MailPage extends StatefulWidget {
  const MailPage({super.key, required this.controller})
      : _mailService = null,
        _testCredentials = null;

  /// Test-only constructor that injects a mock service and fake credentials.
  @visibleForTesting
  const MailPage.withService({
    super.key,
    required this.controller,
    required MailService mailService,
    required MailAccessCredentials? testCredentials,
  })  : _mailService = mailService,
        _testCredentials = testCredentials;

  final AppSessionController? controller;
  final MailService? _mailService;
  final MailAccessCredentials? _testCredentials;

  @override
  State<MailPage> createState() => _MailPageState();
}

class _MailPageState extends State<MailPage> {
  late final MailService _mailService =
      widget._mailService ?? createMailService();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _senderController = TextEditingController();
  final TextEditingController _recipientController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final DateFormat _detailTimeFormat = DateFormat('yyyy-MM-dd HH:mm');

  MailAccessCredentials? _credentials;
  MailFolderSnapshot? _snapshot;
  String? _errorMessage;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _showUnreadOnly = false;
  int? _openingMessageUid;
  String _searchQuery = '';
  MailFolder _currentFolder = MailFolder.inbox;
  MailSearchScope _searchScope = MailSearchScope.allText;
  bool _isSearching = false;
  List<MailMessageSummary>? _searchResults;
  Timer? _searchDebounce;
  bool _isMultiSelectMode = false;
  final Set<int> _selectedUids = {};
  bool _isDeleting = false;

  bool get _showScopeArea =>
      _searchQuery.isNotEmpty ||
      _searchScope == MailSearchScope.from ||
      _searchScope == MailSearchScope.to;

  @override
  void initState() {
    super.initState();
    // Inject test credentials if provided
    _credentials = widget._testCredentials;
    _scrollController.addListener(_onScroll);
    _refreshFolder();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _senderController.dispose();
    _recipientController.dispose();
    _scrollController.dispose();
    _searchDebounce?.cancel();
    unawaited(_mailService.close());
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<MailAccessCredentials?> _getCredentials() async {
    if (_credentials != null) return _credentials;
    final creds = await widget.controller?.loadMailAccessCredentials();
    _credentials = creds;
    return creds;
  }

  Future<void> _refreshFolder() async {
    if (_isLoading) return;
    _searchDebounce?.cancel();
    _senderController.clear();
    _recipientController.clear();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _searchResults = null;
      _searchScope = MailSearchScope.allText;
      _isMultiSelectMode = false;
      _selectedUids.clear();
    });

    try {
      final credentials = await _getCredentials();
      if (credentials == null) {
        throw const MailServiceException('请先登录后再读取邮箱。');
      }
      final snapshot = await _mailService.fetchFolder(
        credentials: credentials,
        folder: _currentFolder,
        page: 1,
      );
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
      });
    } catch (error) {
      if (!mounted) return;
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

  Future<void> _loadMore() async {
    final snapshot = _snapshot;
    if (snapshot == null || _isLoadingMore || _isLoading) return;
    if (snapshot.currentPage * snapshot.pageSize >= snapshot.totalMessages) {
      return;
    }

    setState(() => _isLoadingMore = true);

    try {
      final credentials = await _getCredentials();
      if (credentials == null) return;
      final nextPage = snapshot.currentPage + 1;
      final nextSnapshot = await _mailService.fetchFolder(
        credentials: credentials,
        folder: _currentFolder,
        page: nextPage,
      );
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot.copyWith(
          messages: [...snapshot.messages, ...nextSnapshot.messages],
          currentPage: nextPage,
        );
      });
    } catch (_) {
      // silently ignore load-more failures
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    setState(() {
      _searchQuery = value;
      // Only clear results if we're not in from/to mode (those have their own inputs)
      if (value.isEmpty &&
          _searchScope != MailSearchScope.from &&
          _searchScope != MailSearchScope.to) {
        _searchResults = null;
        _isSearching = false;
      }
    });
    // from/to scopes use the secondary input, not the main bar
    if (_searchScope == MailSearchScope.from ||
        _searchScope == MailSearchScope.to) {
      return;
    }
    if (value.trim().isEmpty) return;
    _searchDebounce = Timer(const Duration(milliseconds: 500), _runSearch);
  }

  void _onSenderChanged(String value) {
    _searchDebounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _searchResults = null;
        _isSearching = false;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 500), _runSearch);
  }

  void _onRecipientChanged(String value) {
    _searchDebounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _searchResults = null;
        _isSearching = false;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 500), _runSearch);
  }

  Future<void> _runSearch() async {
    // Determine which query to use based on current scope
    final String query;
    switch (_searchScope) {
      case MailSearchScope.from:
        query = _senderController.text.trim();
        break;
      case MailSearchScope.to:
        query = _recipientController.text.trim();
        break;
      default:
        query = _searchQuery.trim();
    }
    if (query.isEmpty) {
      setState(() => _searchResults = null);
      return;
    }
    final credentials = await _getCredentials();
    if (credentials == null || !mounted) return;
    setState(() => _isSearching = true);
    try {
      final results = await _mailService.searchFolder(
        credentials: credentials,
        query: query,
        folder: _currentFolder,
        searchScope: _searchScope,
      );
      if (!mounted) return;
      setState(() => _searchResults = results);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('搜索失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _onScopeChanged(MailSearchScope scope) {
    // Tapping an already-selected chip toggles it off (back to allText)
    if (_searchScope == scope) {
      setState(() {
        _searchScope = MailSearchScope.allText;
        _searchResults = null;
      });
      // Re-run text search if main bar has content
      if (_searchQuery.trim().isNotEmpty) _runSearch();
      return;
    }
    setState(() {
      _searchScope = scope;
      _searchResults = null;
    });
    // For from/to, wait for user to type in secondary input
    if (scope == MailSearchScope.from || scope == MailSearchScope.to) return;
    // For subject, re-run if main bar has content
    if (_searchQuery.trim().isNotEmpty) {
      _searchDebounce?.cancel();
      _runSearch();
    }
  }

  Future<void> _openMessage(MailMessageSummary message) async {
    if (_openingMessageUid != null) return;
    setState(() => _openingMessageUid = message.uid);

    try {
      final credentials = await _getCredentials();
      if (credentials == null) {
        throw const MailServiceException('请先登录后再读取邮箱。');
      }
      final detail = await _mailService.readMessage(
        credentials: credentials,
        uid: message.uid,
      );
      if (!mounted) return;

      // Drafts: open in compose for editing instead of read-only view
      if (_currentFolder == MailFolder.drafts) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => ComposeMailPage(
              mailService: _mailService,
              credentials: credentials,
              draftDetail: detail,
            ),
          ),
        );
        // Refresh drafts after editing/sending
        _refreshFolder();
      } else {
        _markMessageAsSeen(message.uid);
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => _MailDetailPage(
              detail: detail,
              timeFormat: _detailTimeFormat,
              onReply: () => _openComposePage(replyTo: detail),
              mailService: _mailService,
              credentials: credentials,
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _openingMessageUid = null);
    }
  }

  void _openComposePage({MailMessageDetail? replyTo}) {
    final credentials = _credentials;
    if (credentials == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ComposeMailPage(
          mailService: _mailService,
          credentials: credentials,
          replyTo: replyTo,
        ),
      ),
    );
  }

  void _markMessageAsSeen(int uid) {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    final updated = snapshot.messages.map((msg) {
      if (msg.uid != uid) return msg;
      return msg.copyWith(isSeen: true);
    }).toList(growable: false);
    setState(() => _snapshot = snapshot.copyWith(messages: updated));
  }

  void _toggleMultiSelect() {
    setState(() {
      _isMultiSelectMode = !_isMultiSelectMode;
      if (!_isMultiSelectMode) _selectedUids.clear();
    });
  }

  void _toggleSelectMessage(int uid) {
    setState(() {
      if (_selectedUids.contains(uid)) {
        _selectedUids.remove(uid);
      } else {
        _selectedUids.add(uid);
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedUids.isEmpty) return;
    final credentials = await _getCredentials();
    if (credentials == null) return;

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('删除已选中的 ${_selectedUids.length} 封邮件？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);
    try {
      final uids = _selectedUids.toList();
      await _mailService.deleteMessages(
        credentials: credentials,
        folder: _currentFolder,
        uids: uids,
      );
      if (!mounted) return;
      final snapshot = _snapshot;
      if (snapshot != null) {
        setState(() {
          _snapshot = snapshot.copyWith(
            messages: snapshot.messages
                .where((m) => !_selectedUids.contains(m.uid))
                .toList(),
          );
          _isMultiSelectMode = false;
          _selectedUids.clear();
        });
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  List<MailMessageSummary> get _visibleMessages {
    final base = _searchResults ?? _snapshot?.messages ?? const [];
    if (!_showUnreadOnly) return base;
    return base.where((m) => !m.isSeen).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleMessages;
    final snapshot = _snapshot;
    final hasMore = !_isSearching &&
        _searchResults == null &&
        snapshot != null &&
        snapshot.currentPage * snapshot.pageSize < snapshot.totalMessages;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      floatingActionButton: _isMultiSelectMode
          ? null
          : FloatingActionButton(
              onPressed:
                  _credentials == null ? null : () => _openComposePage(),
              backgroundColor: const Color(0xFF2F80ED),
              foregroundColor: Colors.white,
              child: const Icon(Icons.edit_outlined),
            ),
      bottomNavigationBar:
          _isMultiSelectMode ? _buildMultiSelectBar() : null,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            if (_showScopeArea) _buildScopeChips(),
            _buildToolbar(),
            const Divider(height: 1, color: Color(0xFFE5E7EB)),
            Expanded(
              child: Container(
                color: Colors.white,
                child: _buildBody(context, visible, hasMore),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
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
              onPressed: _isLoading ? null : _refreshFolder,
              iconSize: 18,
              icon: _isLoading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, color: Colors.black87),
            ),
          ),
        ],
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
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.only(top: 10, bottom: 10, right: 8),
          prefixIcon: _isSearching
              ? const Padding(
                  padding: EdgeInsets.all(10),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : const Icon(
                  Icons.search_rounded,
                  color: Color(0xFF9CA3AF),
                  size: 18,
                ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 40, minHeight: 38),
          hintText: '搜索',
          hintStyle: const TextStyle(
            color: Color(0xFF9CA3AF),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged('');
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

  Widget _buildScopeChips() {
    return Container(
      color: const Color(0xFFD8E3F1),
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ScopeChip(
                label: '仅主题',
                selected: _searchScope == MailSearchScope.subject,
                onTap: () => _onScopeChanged(MailSearchScope.subject),
              ),
              const SizedBox(width: 8),
              _ScopeChip(
                label: '按发件人',
                selected: _searchScope == MailSearchScope.from,
                onTap: () => _onScopeChanged(MailSearchScope.from),
              ),
              const SizedBox(width: 8),
              _ScopeChip(
                label: '按收件人',
                selected: _searchScope == MailSearchScope.to,
                onTap: () => _onScopeChanged(MailSearchScope.to),
              ),
            ],
          ),
          if (_searchScope == MailSearchScope.from)
            _buildSecondaryEmailInput(
              label: '发件人邮箱：',
              controller: _senderController,
              onChanged: _onSenderChanged,
            ),
          if (_searchScope == MailSearchScope.to)
            _buildSecondaryEmailInput(
              label: '收件人邮箱：',
              controller: _recipientController,
              onChanged: _onRecipientChanged,
            ),
        ],
      ),
    );
  }

  Widget _buildSecondaryEmailInput({
    required String label,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w500,
              ),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                autofocus: true,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                  hintText: '输入邮箱地址...',
                  hintStyle: TextStyle(
                    fontSize: 12,
                    color: Color(0xFFD1D5DB),
                  ),
                ),
                style: const TextStyle(fontSize: 12, color: Color(0xFF111827)),
                keyboardType: TextInputType.emailAddress,
              ),
            ),
            if (controller.text.isNotEmpty)
              GestureDetector(
                onTap: () {
                  controller.clear();
                  onChanged('');
                },
                child: const Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: Color(0xFF9CA3AF),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Equal-width 3-section toolbar: [folder▼] | [未读] | [多选]
  Widget _buildToolbar() {
    return Container(
      height: 44,
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: Center(
              child: PopupMenuButton<MailFolder>(
                initialValue: _currentFolder,
                position: PopupMenuPosition.under,
                onSelected: (folder) {
                  if (folder == _currentFolder) return;
                  setState(() {
                    _currentFolder = folder;
                    _searchResults = null;
                    _searchController.clear();
                    _searchQuery = '';
                  });
                  _refreshFolder();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: MailFolder.inbox,
                    child: Text('收件箱'),
                  ),
                  PopupMenuItem(
                    value: MailFolder.drafts,
                    child: Text('草稿箱'),
                  ),
                  PopupMenuItem(
                    value: MailFolder.sent,
                    child: Text('已发送'),
                  ),
                  PopupMenuItem(
                    value: MailFolder.trash,
                    child: Text('已删除'),
                  ),
                ],
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _folderIcon(_currentFolder),
                      size: 16,
                      color: const Color(0xFF374151),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _folderLabel(_currentFolder),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF374151),
                      ),
                    ),
                    const Icon(
                      Icons.arrow_drop_down,
                      size: 16,
                      color: Color(0xFF9CA3AF),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const VerticalDivider(
            width: 1,
            indent: 12,
            endIndent: 12,
            color: Color(0xFFE5E7EB),
          ),
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _showUnreadOnly = !_showUnreadOnly),
              child: Center(
                child: _TopAction(
                  icon: _showUnreadOnly
                      ? Icons.mark_email_unread_rounded
                      : Icons.drafts_outlined,
                  label: '未读',
                  selected: _showUnreadOnly,
                ),
              ),
            ),
          ),
          const VerticalDivider(
            width: 1,
            indent: 12,
            endIndent: 12,
            color: Color(0xFFE5E7EB),
          ),
          Expanded(
            child: InkWell(
              onTap: _toggleMultiSelect,
              child: Center(
                child: _TopAction(
                  icon: _isMultiSelectMode
                      ? Icons.check_box_outlined
                      : Icons.check_box_outline_blank,
                  label: '多选',
                  selected: _isMultiSelectMode,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMultiSelectBar() {
    final isTrash = _currentFolder == MailFolder.trash;
    return SafeArea(
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            Text(
              '已选 ${_selectedUids.length} 封',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF374151),
              ),
            ),
            const Spacer(),
            if (_isDeleting)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (isTrash)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _selectedUids.isEmpty
                      ? Colors.grey
                      : const Color(0xFF2F80ED),
                ),
                onPressed: _selectedUids.isEmpty ? null : _restoreSelected,
                icon: const Icon(Icons.restore, size: 16),
                label: const Text('恢复'),
              )
            else
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor:
                      _selectedUids.isEmpty ? Colors.grey : Colors.red,
                ),
                onPressed: _selectedUids.isEmpty ? null : _deleteSelected,
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('删除'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _restoreSelected() async {
    if (_selectedUids.isEmpty) return;
    final credentials = await _getCredentials();
    if (credentials == null) return;

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认恢复'),
        content: Text('将已选 ${_selectedUids.length} 封邮件恢复到原文件夹？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF2F80ED),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);
    try {
      final uids = _selectedUids.toList();
      await _mailService.restoreMessages(
        credentials: credentials,
        uids: uids,
        userEmailAddress: credentials.emailAddress,
      );
      if (!mounted) return;
      final snapshot = _snapshot;
      if (snapshot != null) {
        setState(() {
          _snapshot = snapshot.copyWith(
            messages: snapshot.messages
                .where((m) => !_selectedUids.contains(m.uid))
                .toList(),
          );
          _isMultiSelectMode = false;
          _selectedUids.clear();
        });
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('恢复失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  Widget _buildBody(
    BuildContext context,
    List<MailMessageSummary> visible,
    bool hasMore,
  ) {
    if (_isLoading && _snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _snapshot == null) {
      return _buildEmptyState(title: '加载失败', subtitle: _errorMessage!);
    }

    if (_snapshot == null) {
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
            onRefresh: _refreshFolder,
            child: visible.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: 280,
                        child: _buildEmptyState(
                          title: '没有匹配的邮件',
                          subtitle: _searchQuery.isNotEmpty
                              ? '换个关键词试试。'
                              : _showUnreadOnly
                                  ? '当前没有未读邮件。'
                                  : '该文件夹没有邮件。',
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    itemCount: visible.length + (hasMore ? 1 : 0),
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 76, endIndent: 16),
                    itemBuilder: (context, index) {
                      if (index == visible.length) {
                        return _buildLoadMoreFooter();
                      }
                      final message = visible[index];
                      return _MailListTile(
                        message: message,
                        timeLabel: _formatMessageTime(message.date),
                        isOpening: _openingMessageUid == message.uid,
                        isMultiSelect: _isMultiSelectMode,
                        isSelected: _selectedUids.contains(message.uid),
                        onTap: _isMultiSelectMode
                            ? () => _toggleSelectMessage(message.uid)
                            : () => _openMessage(message),
                        onLongPress: _isMultiSelectMode
                            ? null
                            : () {
                                setState(() {
                                  _isMultiSelectMode = true;
                                  _selectedUids.add(message.uid);
                                });
                              },
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadMoreFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: _isLoadingMore
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton(
                onPressed: _loadMore,
                child: const Text('加载更多'),
              ),
      ),
    );
  }

  Widget _buildEmptyState({required String title, required String subtitle}) {
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
    if (dateTime == null) return '';
    final now = DateTime.now();
    final isSameDay = dateTime.year == now.year &&
        dateTime.month == now.month &&
        dateTime.day == now.day;
    if (isSameDay) return DateFormat('HH:mm').format(dateTime);
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = dateTime.year == yesterday.year &&
        dateTime.month == yesterday.month &&
        dateTime.day == yesterday.day;
    if (isYesterday) return '昨天';
    return DateFormat('MM-dd').format(dateTime);
  }

  static String _folderLabel(MailFolder folder) {
    switch (folder) {
      case MailFolder.inbox:
        return '收件箱';
      case MailFolder.drafts:
        return '草稿箱';
      case MailFolder.sent:
        return '已发送';
      case MailFolder.trash:
        return '已删除';
    }
  }

  static IconData _folderIcon(MailFolder folder) {
    switch (folder) {
      case MailFolder.inbox:
        return Icons.inbox_outlined;
      case MailFolder.drafts:
        return Icons.drafts_outlined;
      case MailFolder.sent:
        return Icons.send_outlined;
      case MailFolder.trash:
        return Icons.delete_outline;
    }
  }
}

// ─── ComposeMailPage (public) ─────────────────────────────────────────────────

class ComposeMailPage extends StatefulWidget {
  const ComposeMailPage({
    super.key,
    required this.mailService,
    required this.credentials,
    this.replyTo,
    this.draftDetail,
  });

  final MailService mailService;
  final MailAccessCredentials credentials;

  /// Set when replying to an existing message.
  final MailMessageDetail? replyTo;

  /// Set when continuing to edit an existing draft.
  /// Pre-fills all fields and tracks the draft UID for deletion on send.
  final MailMessageDetail? draftDetail;

  @override
  State<ComposeMailPage> createState() => _ComposeMailPageState();
}

class _ComposeMailPageState extends State<ComposeMailPage> {
  late final TextEditingController _toController;
  late final TextEditingController _ccController;
  late final TextEditingController _subjectController;
  late final TextEditingController _bodyController;

  int? _draftUid;
  Timer? _draftTimer;
  late String _lastSavedTo;
  late String _lastSavedCc;
  late String _lastSavedSubject;
  late String _lastSavedBody;
  bool _isSending = false;
  bool _isSavingDraft = false;

  @override
  void initState() {
    super.initState();
    final draft = widget.draftDetail;
    final replyTo = widget.replyTo;

    if (draft != null) {
      // Continue editing an existing draft
      _toController =
          TextEditingController(text: _extractEmail(draft.recipients));
      _ccController = TextEditingController(text: draft.cc ?? '');
      _subjectController = TextEditingController(text: draft.subject);
      _bodyController = TextEditingController(text: draft.body);
      _draftUid = draft.uid;
    } else if (replyTo != null) {
      // Reply
      _toController =
          TextEditingController(text: _extractEmail(replyTo.sender));
      _ccController = TextEditingController();
      _subjectController = TextEditingController(
        text: replyTo.subject.startsWith('Re:')
            ? replyTo.subject
            : 'Re: ${replyTo.subject}',
      );
      _bodyController = TextEditingController();
    } else {
      // New compose
      _toController = TextEditingController();
      _ccController = TextEditingController();
      _subjectController = TextEditingController();
      _bodyController = TextEditingController();
    }

    // Set last-saved baseline so draft timer doesn't fire immediately
    _lastSavedTo = _toController.text;
    _lastSavedCc = _ccController.text;
    _lastSavedSubject = _subjectController.text;
    _lastSavedBody = _bodyController.text;

    _draftTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _autoSaveDraft(),
    );
  }

  @override
  void dispose() {
    _toController.dispose();
    _ccController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    _draftTimer?.cancel();
    super.dispose();
  }

  bool get _hasChanges =>
      _toController.text != _lastSavedTo ||
      _ccController.text != _lastSavedCc ||
      _subjectController.text != _lastSavedSubject ||
      _bodyController.text != _lastSavedBody;

  Future<void> _autoSaveDraft() async {
    if (!_hasChanges || !mounted) return;
    setState(() => _isSavingDraft = true);
    try {
      final newUid = await widget.mailService.saveDraft(
        credentials: widget.credentials,
        composeData: _buildComposeData(),
        existingDraftUid: _draftUid,
      );
      if (!mounted) return;
      setState(() {
        _draftUid = newUid;
        _lastSavedTo = _toController.text;
        _lastSavedCc = _ccController.text;
        _lastSavedSubject = _subjectController.text;
        _lastSavedBody = _bodyController.text;
      });
    } catch (_) {
      // best-effort
    } finally {
      if (mounted) setState(() => _isSavingDraft = false);
    }
  }

  MailComposeData _buildComposeData() {
    final replyTo = widget.replyTo;
    final body = _bodyController.text;
    final htmlBody = replyTo != null ? _buildReplyHtml(replyTo, body) : null;
    return MailComposeData(
      to: _toController.text.trim(),
      cc: _ccController.text.trim().isEmpty ? null : _ccController.text.trim(),
      subject: _subjectController.text.trim(),
      body: body,
      htmlBody: htmlBody,
      inReplyTo: replyTo?.messageId,
      references: replyTo?.messageId,
    );
  }

  static String _buildReplyHtml(MailMessageDetail original, String userText) {
    final dateStr = original.date != null
        ? DateFormat('yyyy-MM-dd HH:mm').format(original.date!)
        : '';
    final escapedText = _escapeHtml(userText).replaceAll('\n', '<br>');
    final originalBody = original.htmlBody != null
        ? original.htmlBody!
        : '<pre>${_escapeHtml(original.body)}</pre>';
    return '''
<div>$escapedText</div>
<hr style="border:none;border-top:1px solid #d0d0d0;margin:16px 0">
<div style="color:#666;font-size:0.9em;margin-bottom:8px;line-height:1.8">
  <b>发件人：</b>${_escapeHtml(original.sender)}<br>
  <b>时 间：</b>$dateStr<br>
  <b>收件人：</b>${_escapeHtml(original.recipients)}<br>
  <b>主 题：</b>${_escapeHtml(original.subject)}
</div>
<blockquote style="margin:0;padding-left:12px;border-left:3px solid #ccc;color:#444">
  $originalBody
</blockquote>
''';
  }

  static String _escapeHtml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static String _truncateBody(String body) {
    final normalized = body.replaceAll('\n', ' ').trim();
    if (normalized.length <= 200) return normalized;
    return '${normalized.substring(0, 200)}...';
  }

  Future<void> _sendEmail() async {
    final to = _toController.text.trim();
    if (to.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写收件人')),
      );
      return;
    }
    _draftTimer?.cancel();
    setState(() => _isSending = true);
    try {
      await widget.mailService.sendEmail(
        credentials: widget.credentials,
        composeData: _buildComposeData(),
      );
      // Delete the draft after sending (both auto-saved and pre-existing)
      final draftUid = _draftUid;
      if (draftUid != null) {
        try {
          await widget.mailService.deleteMessages(
            credentials: widget.credentials,
            folder: MailFolder.drafts,
            uids: [draftUid],
          );
        } catch (_) {}
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('邮件已发送')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送失败：$error')),
      );
    }
  }

  Future<void> _onCancel() async {
    _draftTimer?.cancel();
    final hasContent = _toController.text.isNotEmpty ||
        _subjectController.text.isNotEmpty ||
        _bodyController.text.isNotEmpty;
    if (_hasChanges && hasContent) {
      try {
        await widget.mailService.saveDraft(
          credentials: widget.credentials,
          composeData: _buildComposeData(),
          existingDraftUid: _draftUid,
        );
      } catch (_) {}
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDraft = widget.draftDetail != null;
    final isReply = widget.replyTo != null;
    final title = isDraft ? '继续编辑' : (isReply ? '回复' : '写邮件');

    return Scaffold(
      appBar: AppBar(
        leading: TextButton(
          onPressed: _isSending ? null : _onCancel,
          child: const Text('取消'),
        ),
        leadingWidth: 60,
        title: Text(title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _isSending
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2F80ED),
                    ),
                    onPressed: _sendEmail,
                    child: const Text('发送'),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isSavingDraft) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                // From field: read-only, shows sender email
                Row(
                  children: [
                    const SizedBox(
                      width: 52,
                      child: Text(
                        '发件人：',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Text(
                          widget.credentials.emailAddress,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF374151),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 1),
                _ComposeField(
                  label: '收件人',
                  controller: _toController,
                  autofocus: !isDraft && !isReply,
                ),
                const Divider(height: 1),
                _ComposeField(label: '抄送', controller: _ccController),
                const Divider(height: 1),
                _ComposeField(
                  label: '主题',
                  controller: _subjectController,
                ),
                const Divider(height: 1),
                const SizedBox(height: 12),
                TextField(
                  controller: _bodyController,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: '写点什么...',
                    hintStyle: TextStyle(color: Color(0xFF9CA3AF)),
                  ),
                  style: const TextStyle(fontSize: 14, height: 1.65),
                  maxLines: null,
                  minLines: 12,
                  autofocus: isReply,
                ),
                if (isReply) _buildQuotedBlock(widget.replyTo!),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuotedBlock(MailMessageDetail original) {
    final dateStr = original.date != null
        ? DateFormat('yyyy-MM-dd HH:mm').format(original.date!)
        : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24),
        Container(
          padding: const EdgeInsets.only(left: 12, top: 8, bottom: 8),
          decoration: const BoxDecoration(
            border: Border(
              left: BorderSide(color: Color(0xFFD1D5DB), width: 3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _QuoteInfoLine(label: '发件人', value: original.sender),
              if (dateStr.isNotEmpty)
                _QuoteInfoLine(label: '时　间', value: dateStr),
              _QuoteInfoLine(label: '收件人', value: original.recipients),
              _QuoteInfoLine(label: '主　题', value: original.subject),
              const SizedBox(height: 8),
              Text(
                _truncateBody(original.body),
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: Color(0xFF374151),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  static String _extractEmail(String input) {
    // Extract first email address from "Name <email>, Name2 <email2>" or plain emails
    final emailRegex = RegExp(r'<([^>]+)>');
    final match = emailRegex.firstMatch(input);
    if (match != null) return match.group(1)?.trim() ?? input.trim();
    // plain email or comma-separated
    return input.split(',').first.trim();
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

class _ComposeField extends StatelessWidget {
  const _ComposeField({
    required this.label,
    required this.controller,
    this.autofocus = false,
  });

  final String label;
  final TextEditingController controller;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            '$label：',
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: TextField(
            controller: controller,
            autofocus: autofocus,
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 14),
            ),
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2F80ED) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? const Color(0xFF2F80ED)
                : const Color(0xFFD1D5DB),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: selected ? Colors.white : const Color(0xFF374151),
          ),
        ),
      ),
    );
  }
}

class _TopAction extends StatelessWidget {
  const _TopAction({
    required this.icon,
    required this.label,
    required this.selected,
  });

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color =
        selected ? const Color(0xFF2F80ED) : const Color(0xFF9CA3AF);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _MailListTile extends StatelessWidget {
  const _MailListTile({
    required this.message,
    required this.timeLabel,
    required this.isOpening,
    required this.isMultiSelect,
    required this.isSelected,
    required this.onTap,
    this.onLongPress,
  });

  final MailMessageSummary message;
  final String timeLabel;
  final bool isOpening;
  final bool isMultiSelect;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isOpening ? null : onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isMultiSelect)
              Padding(
                padding: const EdgeInsets.only(right: 10, top: 4),
                child: Icon(
                  isSelected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 24,
                  color: isSelected
                      ? const Color(0xFF2F80ED)
                      : const Color(0xFFD1D5DB),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: _Avatar(text: message.sender),
              ),
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
    if (cleaned.isEmpty) return '邮';
    final upper = cleaned.toUpperCase();
    if (upper.length == 1) return upper;
    final words = upper
        .split(RegExp(r'[^A-Z0-9\u4E00-\u9FFF]+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (words.length >= 2) return '${words.first[0]}${words[1][0]}';
    return upper.characters.take(2).toString();
  }
}

// ─── Mail Detail Page ─────────────────────────────────────────────────────────

class _MailDetailPage extends StatefulWidget {
  const _MailDetailPage({
    required this.detail,
    required this.timeFormat,
    required this.onReply,
    required this.mailService,
    required this.credentials,
  });

  final MailMessageDetail detail;
  final DateFormat timeFormat;
  final VoidCallback onReply;
  final MailService mailService;
  final MailAccessCredentials credentials;

  @override
  State<_MailDetailPage> createState() => _MailDetailPageState();
}

class _MailDetailPageState extends State<_MailDetailPage> {
  final Set<String> _downloadingPartIds = {};
  static const _nativeActions = MethodChannel('ispace/native_actions');

  Future<void> _downloadAndOpen(MailAttachment attachment) async {
    final partId = attachment.partId;
    if (partId == null) return;
    setState(() => _downloadingPartIds.add(partId));
    try {
      final bytes = await widget.mailService.downloadAttachment(
        credentials: widget.credentials,
        uid: widget.detail.uid,
        partId: partId,
      );
      final cacheDirPath =
          await _nativeActions.invokeMethod<String>('getMailAttachmentCacheDir');
      final file = File('$cacheDirPath/${attachment.name}');
      await file.writeAsBytes(bytes);
      final mimeType = attachment.mimeType.split(';').first.trim();
      await _nativeActions.invokeMethod<void>('openFile', {
        'path': file.path,
        'mimeType': mimeType.isEmpty ? '*/*' : mimeType,
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloadingPartIds.remove(partId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;
    final htmlBody = detail.htmlBody?.trim() ?? '';
    final hasHtmlBody = htmlBody.isNotEmpty;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('邮件详情'),
        actions: [
          IconButton(
            onPressed: widget.onReply,
            icon: const Icon(Icons.reply_outlined),
            tooltip: '回复',
          ),
        ],
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
                if (detail.cc != null)
                  _DetailLine(label: '抄送', value: detail.cc!),
                _DetailLine(
                  label: '时间',
                  value: detail.date == null
                      ? '未知时间'
                      : widget.timeFormat.format(detail.date!),
                ),
                if (detail.attachments.isNotEmpty) ...[
                  const Divider(height: 16),
                  const Text(
                    '附件',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: detail.attachments.map((att) {
                      final isLoading =
                          _downloadingPartIds.contains(att.partId);
                      return _AttachmentChip(
                        attachment: att,
                        isLoading: isLoading,
                        onTap:
                            isLoading ? null : () => _downloadAndOpen(att),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 4),
                ],
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

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({
    required this.attachment,
    required this.isLoading,
    required this.onTap,
  });

  final MailAttachment attachment;
  final bool isLoading;
  final VoidCallback? onTap;

  static IconData _iconForName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) { return Icons.picture_as_pdf_outlined; }
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp')) {
      return Icons.image_outlined;
    }
    return Icons.attach_file_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFD1D5DB)),
          borderRadius: BorderRadius.circular(8),
          color: Colors.white,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _iconForName(attachment.name),
              size: 16,
              color: const Color(0xFF6B7280),
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                attachment.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF374151),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 6),
            if (isLoading)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(
                Icons.download_rounded,
                size: 14,
                color: Color(0xFF9CA3AF),
              ),
          ],
        ),
      ),
    );
  }
}

class _QuoteInfoLine extends StatelessWidget {
  const _QuoteInfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
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
