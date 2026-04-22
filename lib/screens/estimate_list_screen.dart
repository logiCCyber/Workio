import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/client_model.dart';
import '../models/estimate_model.dart';
import '../models/property_model.dart';
import '../services/client_service.dart';
import '../services/estimate_service.dart';
import '../services/property_service.dart';
import '../utils/estimate_formatters.dart';
import 'create_estimate_screen.dart';
import 'estimate_details_screen.dart';

class EstimateListScreen extends StatefulWidget {
  const EstimateListScreen({super.key});

  @override
  State<EstimateListScreen> createState() => _EstimateListScreenState();
}

class _EstimateListScreenState extends State<EstimateListScreen> {
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String? _errorMessage;

  List<EstimateModel> _allEstimates = [];
  List<EstimateModel> _filteredEstimates = [];

  final Map<String, ClientModel> _clientsById = {};
  final Map<String, PropertyModel> _propertiesById = {};

  String _selectedStatus = 'all';
  String _groupMode = 'year_month';

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchController.removeListener(_applyFilters);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        EstimateService.getEstimates(),
        ClientService.getClients(),
        PropertyService.getProperties(),
      ]);

      final estimates = results[0] as List<EstimateModel>;
      final clients = results[1] as List<ClientModel>;
      final properties = results[2] as List<PropertyModel>;

      _clientsById
        ..clear()
        ..addEntries(clients.map((e) => MapEntry(e.id, e)));

      _propertiesById
        ..clear()
        ..addEntries(properties.map((e) => MapEntry(e.id, e)));

      _allEstimates = estimates;
      _applyFilters();

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load estimates';
      });
    }
  }

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();

    final filtered = _allEstimates.where((estimate) {
      final client = _clientsById[estimate.clientId];
      final property = _propertiesById[estimate.propertyId];

      final clientName = (client?.fullName ?? '').toLowerCase();
      final companyName = (client?.companyName ?? '').toLowerCase();
      final estimateNumber = estimate.estimateNumber.toLowerCase();
      final title = estimate.title.toLowerCase();
      final address = (property?.fullAddress ?? '').toLowerCase();

      final matchesStatus =
          _selectedStatus == 'all' || estimate.status == _selectedStatus;

      final matchesQuery = query.isEmpty ||
          clientName.contains(query) ||
          companyName.contains(query) ||
          estimateNumber.contains(query) ||
          title.contains(query) ||
          address.contains(query);

      return matchesStatus && matchesQuery;
    }).toList();

    if (!mounted) return;

    setState(() {
      _filteredEstimates = filtered;
    });
  }

  void _setStatusFilter(String status) {
    setState(() {
      _selectedStatus = status;
    });
    _applyFilters();
  }

  DateTime _estimateDate(EstimateModel estimate) {
    return estimate.createdAt ?? estimate.updatedAt ?? DateTime.now();
  }

  String get _groupModeLabel {
    switch (_groupMode) {
      case 'year_month':
        return 'Year / Month';
      default:
        return 'None';
    }
  }

  String _monthLabel(int year, int month) {
    return DateFormat('MMMM').format(DateTime(year, month));
  }

  Future<void> _pickGroupMode() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF15161C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Group',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _GroupOptionTile(
                  label: 'None',
                  selected: _groupMode == 'none',
                  onTap: () => Navigator.pop(context, 'none'),
                ),
                const SizedBox(height: 10),
                _GroupOptionTile(
                  label: 'Year / Month',
                  selected: _groupMode == 'year_month',
                  onTap: () => Navigator.pop(context, 'year_month'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null) return;

    setState(() {
      _groupMode = selected;
    });
  }

  List<_EstimateGroupedRow> _buildEstimateGroupedRows() {
    final sorted = [..._filteredEstimates]
      ..sort((a, b) => _estimateDate(b).compareTo(_estimateDate(a)));

    final grouped = <int, Map<int, List<EstimateModel>>>{};

    for (final estimate in sorted) {
      final date = _estimateDate(estimate);

      grouped.putIfAbsent(date.year, () => <int, List<EstimateModel>>{});
      grouped[date.year]!.putIfAbsent(date.month, () => <EstimateModel>[]);
      grouped[date.year]![date.month]!.add(estimate);
    }

    final rows = <_EstimateGroupedRow>[];

    final years = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    for (final year in years) {
      rows.add(_EstimateGroupedRow.year(year));

      final months = grouped[year]!.keys.toList()
        ..sort((a, b) => b.compareTo(a));

      for (final month in months) {
        rows.add(_EstimateGroupedRow.month(year, month));

        final items = grouped[year]![month]!;
        for (final estimate in items) {
          rows.add(_EstimateGroupedRow.item(estimate));
        }
      }
    }

    return rows;
  }

  Future<void> _duplicateEstimate(String estimateId) async {
    try {
      await EstimateService.duplicateEstimate(estimateId);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Estimate duplicated successfully'),
        ),
      );

      await _loadData();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to duplicate estimate'),
        ),
      );
    }
  }

  Future<void> _archiveEstimateFromList(EstimateModel estimate) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Archive estimate?'),
        content: Text(
          'Estimate "${estimate.title}" will be moved to archived.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await EstimateService.archiveEstimate(estimate.id);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Estimate archived')),
      );

      await _loadData();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to archive estimate')),
      );
    }
  }

  Future<void> _deleteEstimateFromList(EstimateModel estimate) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: Text('Delete permanently?'),
        content: Text(
          'Only mistaken draft estimates should be deleted permanently. This action cannot be undone.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await EstimateService.deleteEstimate(estimate.id);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Estimate deleted')),
      );

      await _loadData();
    } catch (e) {
      if (!mounted) return;

      final text = e.toString().replaceFirst('Exception: ', '');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            text.isEmpty ? 'Failed to delete estimate' : text,
          ),
        ),
      );
    }
  }

  Future<void> _showEstimateActions(EstimateModel estimate) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(
          EstimateFormatters.safeText(
            estimate.title,
            fallback: 'Estimate',
          ),
        ),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(context);
              await _archiveEstimateFromList(estimate);
            },
            child: const Text('Archive'),
          ),
          if (estimate.status == 'draft')
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () async {
                Navigator.pop(context);
                await _deleteEstimateFromList(estimate);
              },
              child: const Text('Delete permanently'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Future<void> _openCreateEstimateScreen() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const CreateEstimateScreen(),
      ),
    );

    if (created == true) {
      await _loadData();
    }
  }

  Future<void> _openEstimateDetails(String estimateId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EstimateDetailsScreen(estimateId: estimateId),
      ),
    );

    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF0B0B0F);
    const cardColor = Color(0xFF15161C);
    const borderColor = Color(0xFF262832);
    const mutedText = Color(0xFF8E93A6);
    const primaryText = Colors.white;
    const accent = Color(0xFF5B8CFF);
    final groupedRows = _groupMode == 'year_month'
        ? _buildEstimateGroupedRows()
        : <_EstimateGroupedRow>[];

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 20,
        title: const Text(
          'Estimates',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _loadData,
            icon: const Icon(CupertinoIcons.refresh, color: primaryText),
          ),
          const SizedBox(width: 6),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateEstimateScreen,
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        icon: const Icon(CupertinoIcons.add),
        label: const Text(
          'New Estimate',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _loadData,
          color: accent,
          backgroundColor: cardColor,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Column(
                    children: [
                      _PremiumSearchField(
                        controller: _searchController,
                        hintText: 'Search by client, address, or number...',
                      ),
                      const SizedBox(height: 14),
                      _StatusFilterRow(
                        selectedStatus: _selectedStatus,
                        onSelected: _setStatusFilter,
                      ),
                      const SizedBox(height: 18),
                      _SummaryHeader(
                        totalCount: _filteredEstimates.length,
                        draftCount: _allEstimates.where((e) => e.isDraft).length,
                        approvedCount:
                        _allEstimates.where((e) => e.isApproved).length,
                      ),
                      const SizedBox(height: 18),
                      Align(
                        alignment: Alignment.centerRight,
                        child: _GroupModeButton(
                          label: _groupModeLabel,
                          onTap: _pickGroupMode,
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                  ),
                ),
              ),
              if (_isLoading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _LoadingState(),
                )
              else if (_errorMessage != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _ErrorState(
                    message: _errorMessage!,
                    onRetry: _loadData,
                  ),
                )
              else if (_filteredEstimates.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(
                      onCreatePressed: _openCreateEstimateScreen,
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                    sliver: _groupMode == 'year_month'
                        ? SliverList.separated(
                      itemCount: groupedRows.length,
                      itemBuilder: (context, index) {
                        final row = groupedRows[index];

                        if (row.isYearHeader) {
                          return _YearSectionHeader(
                            title: row.year!.toString(),
                          );
                        }

                        if (row.isMonthHeader) {
                          return _MonthSectionHeader(
                            title: _monthLabel(row.year!, row.month!),
                          );
                        }

                        final estimate = row.estimate!;
                        final client = _clientsById[estimate.clientId];
                        final property = _propertiesById[estimate.propertyId];

                        return _EstimateCard(
                          estimate: estimate,
                          clientName: client?.fullName ?? 'No client',
                          companyName: client?.companyName,
                          address: property?.fullAddress ?? 'No address',
                          onOpen: () => _openEstimateDetails(estimate.id),
                          onDuplicate: () => _duplicateEstimate(estimate.id),
                          onMore: () => _showEstimateActions(estimate),
                        );
                      },
                      separatorBuilder: (_, __) =>
                      const SizedBox(height: 12),
                    )
                        : SliverList.separated(
                      itemCount: _filteredEstimates.length,
                      itemBuilder: (context, index) {
                        final estimate = _filteredEstimates[index];
                        final client = _clientsById[estimate.clientId];
                        final property = _propertiesById[estimate.propertyId];

                        return _EstimateCard(
                          estimate: estimate,
                          clientName: client?.fullName ?? 'No client',
                          companyName: client?.companyName,
                          address: property?.fullAddress ?? 'No address',
                          onOpen: () => _openEstimateDetails(estimate.id),
                          onDuplicate: () => _duplicateEstimate(estimate.id),
                          onMore: () => _showEstimateActions(estimate),
                        );
                      },
                      separatorBuilder: (_, __) =>
                      const SizedBox(height: 12),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PremiumSearchField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;

  const _PremiumSearchField({
    required this.controller,
    required this.hintText,
  });

  @override
  State<_PremiumSearchField> createState() => _PremiumSearchFieldState();
}

class _PremiumSearchFieldState extends State<_PremiumSearchField> {
  late final FocusNode _focusNode;

  bool get _showClearButton =>
      _focusNode.hasFocus && widget.controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_refresh);
    widget.controller.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant _PremiumSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_refresh);
      widget.controller.addListener(_refresh);
    }
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  void _clearText() {
    widget.controller.clear();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    _focusNode.removeListener(_refresh);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: const Color(0xFF15161C),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF262832),
          width: 1,
        ),
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        cursorColor: const Color(0xFF5B8CFF),
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: const TextStyle(
            color: Color(0xFF8E93A6),
            fontSize: 15,
            fontWeight: FontWeight.w400,
          ),
          prefixIcon: const Icon(
            CupertinoIcons.search,
            color: Color(0xFF8E93A6),
            size: 20,
          ),
          suffixIcon: _showClearButton
              ? GestureDetector(
            onTap: _clearText,
            child: const Icon(
              CupertinoIcons.xmark_circle_fill,
              color: Color(0xFF8E93A6),
              size: 18,
            ),
          )
              : null,
          suffixIconConstraints: const BoxConstraints(
            minWidth: 24,
            minHeight: 24,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }
}

class _StatusFilterRow extends StatelessWidget {
  final String selectedStatus;
  final ValueChanged<String> onSelected;

  const _StatusFilterRow({
    required this.selectedStatus,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final items = <Map<String, String>>[
      {'value': 'all', 'label': 'All'},
      {'value': 'draft', 'label': 'Draft'},
      {'value': 'sent', 'label': 'Sent'},
      {'value': 'approved', 'label': 'Approved'},
      {'value': 'rejected', 'label': 'Rejected'},
      {'value': 'archived', 'label': 'Archived'}
    ];

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = items[index];
          final value = item['value']!;
          final label = item['label']!;
          final isSelected = selectedStatus == value;

          return GestureDetector(
            onTap: () => onSelected(value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF5B8CFF)
                    : const Color(0xFF15161C),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF5B8CFF)
                      : const Color(0xFF262832),
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color:
                  isSelected ? Colors.white : const Color(0xFFB4B8C7),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  final int totalCount;
  final int draftCount;
  final int approvedCount;

  const _SummaryHeader({
    required this.totalCount,
    required this.draftCount,
    required this.approvedCount,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MiniStatCard(
            title: 'Total',
            value: totalCount.toString(),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MiniStatCard(
            title: 'Draft',
            value: draftCount.toString(),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MiniStatCard(
            title: 'Approved',
            value: approvedCount.toString(),
          ),
        ),
      ],
    );
  }
}

class _MiniStatCard extends StatelessWidget {
  final String title;
  final String value;

  const _MiniStatCard({
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 84,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF15161C),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF262832)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _EstimateCard extends StatelessWidget {
  final EstimateModel estimate;
  final String clientName;
  final String? companyName;
  final String address;
  final VoidCallback onOpen;
  final VoidCallback onDuplicate;
  final VoidCallback onMore;

  const _EstimateCard({
    required this.estimate,
    required this.clientName,
    required this.companyName,
    required this.address,
    required this.onOpen,
    required this.onDuplicate,
    required this.onMore,
  });

  Color _statusColor(String status) {
    switch (status) {
      case 'draft':
        return const Color(0xFF8F96AB);
      case 'sent':
        return const Color(0xFF4A90E2);
      case 'approved':
        return const Color(0xFF33C27F);
      case 'rejected':
        return const Color(0xFFE05A5A);
      case 'archived':
        return const Color(0xFF6C7283);
      default:
        return const Color(0xFF8F96AB);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(estimate.status);
    final isArchived = estimate.status == 'archived';

    return GestureDetector(
        onTap: onOpen,
        child: Opacity(
          opacity: isArchived ? 0.60 : 1,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF15161C),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF262832)),
            ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    EstimateFormatters.safeText(
                      estimate.title,
                      fallback: 'Untitled Estimate',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _StatusBadge(
                  label: EstimateFormatters.formatStatus(estimate.status),
                  color: statusColor,
                ),
                const SizedBox(width: 8),
                _CardMoreButton(
                  onTap: onMore,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              EstimateFormatters.estimateSubtitle(
                estimateNumber: estimate.estimateNumber,
                createdAt: estimate.createdAt,
              ),
              style: const TextStyle(
                color: Color(0xFF8E93A6),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            _InfoRow(
              icon: CupertinoIcons.person,
              text: clientName,
              secondary: companyName,
            ),
            const SizedBox(height: 10),
            _InfoRow(
              icon: CupertinoIcons.location,
              text: address,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _AmountBlock(
                    label: 'Total',
                    value: EstimateFormatters.formatCurrency(estimate.total),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _AmountBlock(
                    label: 'Valid Until',
                    value: EstimateFormatters.formatDate(estimate.validUntil),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    icon: CupertinoIcons.doc_text,
                    label: 'Open',
                    onTap: onOpen,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionButton(
                    icon: CupertinoIcons.doc_on_doc,
                    label: 'Duplicate',
                    onTap: onDuplicate,
                  ),
                ),
              ],
            ),
          ],
        ),
          ),
        ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withOpacity(0.35),
        ),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _CardMoreButton extends StatelessWidget {
  final VoidCallback onTap;

  const _CardMoreButton({
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF101117),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF23252E)),
          ),
          child: const Icon(
            CupertinoIcons.ellipsis,
            color: Color(0xFFB6BCD0),
            size: 18,
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? secondary;

  const _InfoRow({
    required this.icon,
    required this.text,
    this.secondary,
  });

  @override
  Widget build(BuildContext context) {
    final secondaryText = (secondary ?? '').trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFF1B1D25),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: const Color(0xFFB6BCD0),
            size: 18,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
              if (secondaryText.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  secondaryText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF8E93A6),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _AmountBlock extends StatelessWidget {
  final String label;
  final String value;

  const _AmountBlock({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF23252E),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF101117),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF23252E)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: const Color(0xFFB6BCD0), size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CupertinoActivityIndicator(radius: 16),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF15161C),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF262832)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                CupertinoIcons.exclamationmark_triangle,
                color: Color(0xFFE6A23C),
                size: 34,
              ),
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                color: const Color(0xFF5B8CFF),
                borderRadius: BorderRadius.circular(14),
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreatePressed;

  const _EmptyState({
    required this.onCreatePressed,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF15161C),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFF262832)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: const Color(0xFF1B1D25),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(
                  CupertinoIcons.doc_text_search,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'No estimates yet',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                  'Create your first estimate and it will appear here in the list.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF8E93A6),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                color: const Color(0xFF5B8CFF),
                borderRadius: BorderRadius.circular(16),
                onPressed: onCreatePressed,
                child: const Text(
                  'Create Estimate',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupModeButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _GroupModeButton({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFF15161C),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF262832)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              CupertinoIcons.square_grid_2x2,
              color: Color(0xFF8E93A6),
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              CupertinoIcons.chevron_down,
              color: Color(0xFF8E93A6),
              size: 14,
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupOptionTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _GroupOptionTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF5B8CFF)
              : const Color(0xFF101117),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? const Color(0xFF5B8CFF)
                : const Color(0xFF262832),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFFB4B8C7),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (selected)
              const Icon(
                CupertinoIcons.check_mark,
                color: Colors.white,
                size: 18,
              ),
          ],
        ),
      ),
    );
  }
}

class _YearSectionHeader extends StatelessWidget {
  final String title;

  const _YearSectionHeader({
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
      ),
    );
  }
}

class _MonthSectionHeader extends StatelessWidget {
  final String title;

  const _MonthSectionHeader({
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF8E93A6),
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EstimateGroupedRow {
  final int? year;
  final int? month;
  final EstimateModel? estimate;
  final _EstimateGroupedRowType type;

  const _EstimateGroupedRow._({
    required this.type,
    this.year,
    this.month,
    this.estimate,
  });

  const _EstimateGroupedRow.year(int year)
      : this._(type: _EstimateGroupedRowType.year, year: year);

  const _EstimateGroupedRow.month(int year, int month)
      : this._(
    type: _EstimateGroupedRowType.month,
    year: year,
    month: month,
  );

  const _EstimateGroupedRow.item(EstimateModel estimate)
      : this._(
    type: _EstimateGroupedRowType.item,
    estimate: estimate,
  );

  bool get isYearHeader => type == _EstimateGroupedRowType.year;
  bool get isMonthHeader => type == _EstimateGroupedRowType.month;
  bool get isItem => type == _EstimateGroupedRowType.item;
}

enum _EstimateGroupedRowType {
  year,
  month,
  item,
}