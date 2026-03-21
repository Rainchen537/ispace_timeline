import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/ta_course_entry.dart';

class TaCourseManagerPage extends StatefulWidget {
  const TaCourseManagerPage({
    super.key,
    required this.initialEntries,
    required this.onChanged,
  });

  final List<TaCourseEntry> initialEntries;
  final ValueChanged<List<TaCourseEntry>> onChanged;

  @override
  State<TaCourseManagerPage> createState() => _TaCourseManagerPageState();
}

class _TaCourseManagerPageState extends State<TaCourseManagerPage> {
  final DateFormat _weekFormatter = DateFormat('M月d日');
  late List<TaCourseEntry> _entries;

  @override
  void initState() {
    super.initState();
    _entries = _sortedEntries(widget.initialEntries);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('管理TA课'),
        actions: [
          IconButton(
            onPressed: _entries.isEmpty ? null : _exportEntries,
            tooltip: '导出',
            icon: const Icon(Icons.upload_file_rounded),
          ),
          IconButton(
            onPressed: _importEntries,
            tooltip: '导入',
            icon: const Icon(Icons.download_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addEntry,
        child: const Icon(Icons.add_rounded),
      ),
      body: _entries.isEmpty
          ? _buildEmptyState(context)
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: _entries.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final entry = _entries[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F3FB),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.schedule_rounded,
                      color: Color(0xFF185B89),
                    ),
                  ),
                  title: Text(
                    entry.displayTitle,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      [
                        '${_weekdayLabel(entry.weekday)} ${entry.timeRangeLabel}',
                        if (entry.displayLocation.isNotEmpty)
                          entry.displayLocation,
                        _repeatLabel(entry),
                      ].join('  ·  '),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF5B6472),
                        height: 1.45,
                      ),
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () => _editEntry(entry),
                        tooltip: '编辑',
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        onPressed: () => _deleteEntry(entry),
                        tooltip: '删除',
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F3FB),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.edit_calendar_rounded,
                size: 30,
                color: Color(0xFF185B89),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '还没有 TA 课配置',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              '点击右下角新增。支持设置每周重复或只在某一周出现，也可以导入已有配置。',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF5B6472)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addEntry() async {
    final created = await _openEditor();
    if (created == null) {
      return;
    }
    _commitEntries(<TaCourseEntry>[..._entries, created]);
  }

  Future<void> _editEntry(TaCourseEntry entry) async {
    final updated = await _openEditor(initialEntry: entry);
    if (updated == null) {
      return;
    }
    final nextEntries = _entries
        .map((item) => item.id == updated.id ? updated : item)
        .toList();
    _commitEntries(nextEntries);
  }

  Future<void> _deleteEntry(TaCourseEntry entry) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除 TA 课'),
          content: Text('确定删除「${entry.displayTitle}」吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (shouldDelete != true) {
      return;
    }
    _commitEntries(
      _entries.where((item) => item.id != entry.id).toList(growable: false),
    );
  }

  Future<void> _exportEntries() async {
    try {
      final payload = jsonEncode(<String, dynamic>{
        'version': 1,
        'entries': _entries.map((entry) => entry.toJson()).toList(),
      });
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: '导出 TA 课配置',
        fileName: 'ta_courses.json',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: Uint8List.fromList(utf8.encode(payload)),
      );
      if (!mounted || savedPath == null) {
        return;
      }
      _showSnackBar('已导出 TA 课配置');
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showSnackBar('导出失败，请稍后重试');
    }
  }

  Future<void> _importEntries() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: '导入 TA 课配置',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      if (!mounted || result == null || result.files.isEmpty) {
        return;
      }
      final file = result.files.single;
      final bytes =
          file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null) {
        throw const FormatException('未能读取导入文件');
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      final rawEntries = decoded is Map<String, dynamic>
          ? decoded['entries']
          : decoded;
      if (rawEntries is! List) {
        throw const FormatException('导入文件格式不正确');
      }
      final importedEntries = rawEntries
          .map(
            (item) =>
                TaCourseEntry.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList();
      _commitEntries(importedEntries);
      _showSnackBar('已导入 ${importedEntries.length} 条 TA 课');
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showSnackBar('导入失败，请确认文件格式正确');
    }
  }

  Future<TaCourseEntry?> _openEditor({TaCourseEntry? initialEntry}) {
    return showModalBottomSheet<TaCourseEntry>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return _TaCourseEditorSheet(initialEntry: initialEntry);
      },
    );
  }

  void _commitEntries(List<TaCourseEntry> nextEntries) {
    final sorted = _sortedEntries(nextEntries);
    setState(() {
      _entries = sorted;
    });
    widget.onChanged(List<TaCourseEntry>.unmodifiable(sorted));
  }

  List<TaCourseEntry> _sortedEntries(List<TaCourseEntry> entries) {
    final sorted = List<TaCourseEntry>.from(entries);
    sorted.sort((left, right) {
      final leftRank = left.repeatType == TaCourseRepeatType.weekly ? 0 : 1;
      final rightRank = right.repeatType == TaCourseRepeatType.weekly ? 0 : 1;
      final repeatCompare = leftRank.compareTo(rightRank);
      if (repeatCompare != 0) {
        return repeatCompare;
      }
      final weekCompare = (left.weekStart?.millisecondsSinceEpoch ?? 0)
          .compareTo(right.weekStart?.millisecondsSinceEpoch ?? 0);
      if (weekCompare != 0) {
        return weekCompare;
      }
      final weekdayCompare = left.weekday.compareTo(right.weekday);
      if (weekdayCompare != 0) {
        return weekdayCompare;
      }
      return left.startMinutes.compareTo(right.startMinutes);
    });
    return sorted;
  }

  String _repeatLabel(TaCourseEntry entry) {
    if (entry.repeatType == TaCourseRepeatType.weekly) {
      return '每周重复';
    }
    final weekStart = entry.weekStart;
    if (weekStart == null) {
      return '单独周';
    }
    return '${_weekFormatter.format(weekStart)} 所在周';
  }

  String _weekdayLabel(int weekday) {
    const labels = <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return labels[(weekday - 1).clamp(0, 6)];
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _TaCourseEditorSheet extends StatefulWidget {
  const _TaCourseEditorSheet({this.initialEntry});

  final TaCourseEntry? initialEntry;

  @override
  State<_TaCourseEditorSheet> createState() => _TaCourseEditorSheetState();
}

class _TaCourseEditorSheetState extends State<_TaCourseEditorSheet> {
  final DateFormat _weekFormatter = DateFormat('yyyy年M月d日');
  late final TextEditingController _titleController;
  late final TextEditingController _locationController;
  late int _weekday;
  late int _startMinutes;
  late int _endMinutes;
  late TaCourseRepeatType _repeatType;
  DateTime? _weekStart;

  @override
  void initState() {
    super.initState();
    final entry = widget.initialEntry;
    _titleController = TextEditingController(text: entry?.title ?? '');
    _locationController = TextEditingController(text: entry?.location ?? '');
    _weekday = entry?.weekday ?? 1;
    _startMinutes = entry?.startMinutes ?? 8 * 60;
    _endMinutes = entry?.endMinutes ?? 8 * 60 + 50;
    _repeatType = entry?.repeatType ?? TaCourseRepeatType.weekly;
    _weekStart = entry?.weekStart;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.initialEntry == null ? '新增 TA 课' : '编辑 TA 课',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: '名称',
                  hintText: '例如：TA Workshop',
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _locationController,
                decoration: const InputDecoration(
                  labelText: '地点',
                  hintText: '例如：B201 / Zoom',
                ),
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: _weekday,
                decoration: const InputDecoration(labelText: '星期'),
                items: List<DropdownMenuItem<int>>.generate(7, (index) {
                  final weekday = index + 1;
                  return DropdownMenuItem<int>(
                    value: weekday,
                    child: Text(_weekdayLabel(weekday)),
                  );
                }),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _weekday = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildTimeButton(
                      context,
                      label: '开始时间',
                      value: TaCourseEntry.formatMinutes(_startMinutes),
                      onTap: () => _pickTime(isStart: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildTimeButton(
                      context,
                      label: '结束时间',
                      value: TaCourseEntry.formatMinutes(_endMinutes),
                      onTap: () => _pickTime(isStart: false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '重复方式',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              SegmentedButton<TaCourseRepeatType>(
                segments: const [
                  ButtonSegment<TaCourseRepeatType>(
                    value: TaCourseRepeatType.weekly,
                    label: Text('每周'),
                  ),
                  ButtonSegment<TaCourseRepeatType>(
                    value: TaCourseRepeatType.singleWeek,
                    label: Text('单独一周'),
                  ),
                ],
                selected: <TaCourseRepeatType>{_repeatType},
                onSelectionChanged: (selection) {
                  final nextType = selection.first;
                  setState(() {
                    _repeatType = nextType;
                    if (_repeatType == TaCourseRepeatType.weekly) {
                      _weekStart = null;
                    } else {
                      _weekStart ??= TaCourseEntry.normalizeWeekStart(
                        DateTime.now(),
                      );
                    }
                  });
                },
              ),
              if (_repeatType == TaCourseRepeatType.singleWeek) ...[
                const SizedBox(height: 16),
                _buildTimeButton(
                  context,
                  label: '适用周',
                  value: _weekStart == null
                      ? '选择一周'
                      : '${_weekFormatter.format(_weekStart!)} 所在周',
                  onTap: _pickWeek,
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submit,
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeButton(
    BuildContext context, {
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFD0D5DD)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: const Color(0xFF667085),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickTime({required bool isStart}) async {
    final sourceMinutes = isStart ? _startMinutes : _endMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: sourceMinutes ~/ 60,
        minute: sourceMinutes % 60,
      ),
      helpText: isStart ? '选择开始时间' : '选择结束时间',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (picked == null) {
      return;
    }
    final nextMinutes = picked.hour * 60 + picked.minute;
    setState(() {
      if (isStart) {
        _startMinutes = nextMinutes;
        if (_endMinutes <= _startMinutes) {
          _endMinutes = _startMinutes + 50;
        }
      } else {
        _endMinutes = nextMinutes;
        if (_endMinutes <= _startMinutes) {
          _startMinutes = (_endMinutes - 50).clamp(0, 24 * 60 - 1);
        }
      }
    });
  }

  Future<void> _pickWeek() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _weekStart ?? DateTime.now(),
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2035, 12, 31),
      helpText: '选择适用周',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _weekStart = TaCourseEntry.normalizeWeekStart(picked);
    });
  }

  void _submit() {
    if (_endMinutes <= _startMinutes) {
      _showSnackBar('结束时间必须晚于开始时间');
      return;
    }
    if (_repeatType == TaCourseRepeatType.singleWeek && _weekStart == null) {
      _showSnackBar('请选择适用周');
      return;
    }
    final entry = TaCourseEntry(
      id:
          widget.initialEntry?.id ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      title: _titleController.text.trim(),
      location: _locationController.text.trim(),
      weekday: _weekday,
      startMinutes: _startMinutes,
      endMinutes: _endMinutes,
      repeatType: _repeatType,
      weekStart: _repeatType == TaCourseRepeatType.singleWeek
          ? TaCourseEntry.normalizeWeekStart(_weekStart!)
          : null,
    );
    Navigator.of(context).pop(entry);
  }

  String _weekdayLabel(int weekday) {
    const labels = <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return labels[(weekday - 1).clamp(0, 6)];
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
