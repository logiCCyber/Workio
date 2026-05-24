import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/client_model.dart';
import '../models/estimate_model.dart';
import '../models/property_model.dart';
import '../services/client_service.dart';
import '../services/estimate_service.dart';
import '../services/property_service.dart';
import '../utils/estimate_formatters.dart';
import '../utils/workio_icon_mapper.dart';
import 'create_estimate_screen.dart';
import 'estimate_details_screen.dart';

const _kEstTintTop = Color(0xFF31343B);
const _kEstTintMid = Color(0xFF272A31);
const _kEstTintBot = Color(0xFF1D2027);

const _kEstCardTop = Color(0xFF262A31);
const _kEstCardBot = Color(0xFF1C2027);

const _kEstInnerTop = Color(0xFF242A32);
const _kEstInnerBot = Color(0xFF171C23);

const _kEstTextMain = Color(0xFFF3F6FC);
const _kEstTextSoft = Color(0xFFA0A7B8);
const _kEstTextMute = Color(0xFF8E93A6);
const _kEstAccent = Color(0xFF38BDF8);

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
  final Map<int, bool> _expandedYears = {};
  final Map<String, bool> _expandedMonths = {};

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
      _expandedYears.clear();
      _expandedMonths.clear();
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
      _expandedYears.clear();
      _expandedMonths.clear();
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

  String _monthKey(int year, int month) => '$year-$month';

  List<_EstimateYearGroup> _buildEstimateYearGroups() {
    final sorted = [..._filteredEstimates]
      ..sort((a, b) => _estimateDate(b).compareTo(_estimateDate(a)));

    final grouped = <int, Map<int, List<EstimateModel>>>{};

    for (final estimate in sorted) {
      final date = _estimateDate(estimate);

      grouped.putIfAbsent(date.year, () => <int, List<EstimateModel>>{});
      grouped[date.year]!.putIfAbsent(date.month, () => <EstimateModel>[]);
      grouped[date.year]![date.month]!.add(estimate);
    }

    final years = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return years.map((year) {
      final monthMap = grouped[year]!;
      final monthKeys = monthMap.keys.toList()
        ..sort((a, b) => b.compareTo(a));

      final months = monthKeys.map((month) {
        return _EstimateMonthGroup(
          year: year,
          month: month,
          title: _monthLabel(year, month),
          estimates: monthMap[month]!,
        );
      }).toList();

      return _EstimateYearGroup(
        year: year,
        months: months,
      );
    }).toList();
  }

  int? get _latestVisibleYear {
    final groups = _buildEstimateYearGroups();
    if (groups.isEmpty) return null;
    return groups.first.year;
  }

  String? get _latestVisibleMonthKey {
    final groups = _buildEstimateYearGroups();
    if (groups.isEmpty || groups.first.months.isEmpty) return null;

    final month = groups.first.months.first;
    return _monthKey(month.year, month.month);
  }

  bool _isYearExpanded(int year) {
    if (_expandedYears.containsKey(year)) {
      return _expandedYears[year]!;
    }

    return year == _latestVisibleYear;
  }

  bool _isMonthExpanded(int year, int month) {
    final key = _monthKey(year, month);

    if (_expandedMonths.containsKey(key)) {
      return _expandedMonths[key]!;
    }

    return key == _latestVisibleMonthKey;
  }

  void _toggleYear(int year) {
    setState(() {
      _expandedYears[year] = !_isYearExpanded(year);
    });
  }

  void _toggleMonth(int year, int month) {
    final key = _monthKey(year, month);

    setState(() {
      _expandedMonths[key] = !_isMonthExpanded(year, month);
    });
  }

  Widget _buildEstimateCard(EstimateModel estimate) {
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
  }

  Widget _buildGroupedEstimateContent(List<_EstimateYearGroup> years) {
    return Column(
      children: [
        for (int y = 0; y < years.length; y++) ...[
          _EstimateYearGroupPanel(
            group: years[y],
            expanded: _isYearExpanded(years[y].year),
            onTap: () => _toggleYear(years[y].year),
            isMonthExpanded: (month) =>
                _isMonthExpanded(month.year, month.month),
            onMonthTap: (month) => _toggleMonth(month.year, month.month),
            buildEstimateCard: _buildEstimateCard,
          ),
          if (y != years.length - 1) const SizedBox(height: 14),
        ],
      ],
    );
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

    final yearGroups = _groupMode == 'year_month'
        ? _buildEstimateYearGroups()
        : <_EstimateYearGroup>[];

    final totalCount = _filteredEstimates.length;
    final draftCount = _filteredEstimates.where((e) => e.isDraft).length;
    final sentCount = _filteredEstimates.where((e) => e.status == 'sent').length;
    final approvedCount = _filteredEstimates.where((e) => e.isApproved).length;

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        top: true,
        child: RefreshIndicator(
          onRefresh: _loadData,
          color: _kEstAccent,
          backgroundColor: const Color(0xFF15161C),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                  child: _EstimatesTopPanel(
                    searchController: _searchController,
                    selectedStatus: _selectedStatus,
                    onStatusSelected: _setStatusFilter,
                    onCreate: _openCreateEstimateScreen,
                    totalCount: totalCount,
                    draftCount: draftCount,
                    sentCount: sentCount,
                    approvedCount: approvedCount,
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
                        ? SliverToBoxAdapter(
                      child: _buildGroupedEstimateContent(yearGroups),
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
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EstimatesTopPanel extends StatelessWidget {
  final TextEditingController searchController;
  final String selectedStatus;
  final ValueChanged<String> onStatusSelected;
  final VoidCallback onCreate;

  final int totalCount;
  final int draftCount;
  final int sentCount;
  final int approvedCount;

  const _EstimatesTopPanel({
    required this.searchController,
    required this.selectedStatus,
    required this.onStatusSelected,
    required this.onCreate,
    required this.totalCount,
    required this.draftCount,
    required this.sentCount,
    required this.approvedCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _kEstTintTop,
            _kEstTintMid,
            _kEstTintBot,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.07),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.26),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _EstimateTopIconButton(
                icon: CupertinoIcons.chevron_left,
                onTap: () => Navigator.maybePop(context),
              ),
              const SizedBox(width: 12),

              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Estimates',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Color(0xFFF4F6FB),
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.25,
                        height: 1.05,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Search, filter, and manage estimate totals',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Color(0xFF9DA6B8),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.05,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          _EstimateQuickControls(
            searchController: searchController,
            selectedStatus: selectedStatus,
            onStatusSelected: onStatusSelected,
            onCreate: onCreate,
          ),

          const SizedBox(height: 12),

          _EstimatesSummaryPanel(
            totalCount: totalCount,
            draftCount: draftCount,
            sentCount: sentCount,
            approvedCount: approvedCount,
          ),
        ],
      ),
    );
  }
}

class _EstimateTopIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _EstimateTopIconButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(16);

    return Material(
      color: Colors.transparent,
      borderRadius: borderRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: Ink(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF2F3440),
                Color(0xFF252A34),
              ],
            ),
            borderRadius: borderRadius,
            border: Border.all(
              color: const Color(0xFF3A4150),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.20),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Icon(
            icon,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _EstimateQuickControls extends StatefulWidget {
  final TextEditingController searchController;
  final String selectedStatus;
  final ValueChanged<String> onStatusSelected;
  final VoidCallback onCreate;

  const _EstimateQuickControls({
    required this.searchController,
    required this.selectedStatus,
    required this.onStatusSelected,
    required this.onCreate,
  });

  @override
  State<_EstimateQuickControls> createState() => _EstimateQuickControlsState();
}

class _EstimateQuickControlsState extends State<_EstimateQuickControls> {
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.searchController.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant _EstimateQuickControls oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.searchController != widget.searchController) {
      oldWidget.searchController.removeListener(_refresh);
      widget.searchController.addListener(_refresh);
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _clearSearch() {
    widget.searchController.clear();
    _searchFocusNode.requestFocus();
  }

  @override
  void dispose() {
    widget.searchController.removeListener(_refresh);
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasSearch = widget.searchController.text.trim().isNotEmpty;

    return Container(
      height: 68,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF343941),
            Color(0xFF262B32),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.24),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _kEstInnerTop,
                    _kEstInnerBot,
                  ],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: _searchFocusNode.hasFocus
                      ? const Color(0xFF5B6374)
                      : Colors.white.withOpacity(0.08),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    CupertinoIcons.search,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: widget.searchController,
                      focusNode: _searchFocusNode,
                      textAlignVertical: TextAlignVertical.center,
                      style: const TextStyle(
                        color: Color(0xFFE8EDF6),
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.05,
                      ),
                      cursorColor: _kEstAccent,
                      decoration: const InputDecoration(
                        hintText: 'Search estimate...',
                        hintStyle: TextStyle(
                          color: Color(0xFF8F98AA),
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.05,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if (hasSearch)
                    GestureDetector(
                      onTap: _clearSearch,
                      child: const Icon(
                        CupertinoIcons.xmark_circle_fill,
                        color: Color(0xFF8E93A6),
                        size: 18,
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 8),

          _EstimateFilterIconPopup(
            selectedStatus: widget.selectedStatus,
            onSelected: widget.onStatusSelected,
          ),

          const SizedBox(width: 8),

          _EstimateControlIconButton(
            icon: CupertinoIcons.plus,
            onTap: widget.onCreate,
          ),
        ],
      ),
    );
  }
}

class _EstimateControlIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _EstimateControlIconButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minSize: 0,
      onPressed: onTap,
      child: _EstimateControlIconCapsule(icon: icon),
    );
  }
}

class _EstimateControlIconCapsule extends StatelessWidget {
  final IconData icon;
  final bool active;

  const _EstimateControlIconCapsule({
    required this.icon,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _kEstInnerTop,
            _kEstInnerBot,
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: active
              ? const Color(0xFF4A5160)
              : Colors.white.withOpacity(0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Icon(
        icon,
        color: Colors.white,
        size: 18,
      ),
    );
  }
}

class _EstimateFilterIconPopup extends StatelessWidget {
  final String selectedStatus;
  final ValueChanged<String> onSelected;

  const _EstimateFilterIconPopup({
    required this.selectedStatus,
    required this.onSelected,
  });

  static const List<String> _statuses = [
    'all',
    'draft',
    'sent',
    'approved',
    'rejected',
    'archived',
  ];

  String _label(String status) {
    switch (status) {
      case 'all':
        return 'All';
      case 'draft':
        return 'Draft';
      case 'sent':
        return 'Sent';
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      case 'archived':
        return 'Archived';
      default:
        return 'All';
    }
  }

  IconData _icon(String status) {
    switch (status) {
      case 'all':
        return CupertinoIcons.square_grid_2x2;
      case 'draft':
        return CupertinoIcons.doc_text;
      case 'sent':
        return CupertinoIcons.paperplane;
      case 'approved':
        return CupertinoIcons.checkmark_seal;
      case 'rejected':
        return CupertinoIcons.xmark_circle;
      case 'archived':
        return CupertinoIcons.archivebox;
      default:
        return CupertinoIcons.square_grid_2x2;
    }
  }

  Color _color(String status) {
    switch (status) {
      case 'all':
        return _kEstAccent;
      case 'draft':
        return const Color(0xFFBFC6D4);
      case 'sent':
        return const Color(0xFF38BDF8);
      case 'approved':
        return const Color(0xFF22C55E);
      case 'rejected':
        return const Color(0xFFE85D3D);
      case 'archived':
        return const Color(0xFF8E93A6);
      default:
        return _kEstAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = selectedStatus != 'all';

    return PopupMenuButton<String>(
      constraints: const BoxConstraints(
        minWidth: 230,
        maxWidth: 230,
      ),
      padding: EdgeInsets.zero,
      tooltip: '',
      offset: const Offset(0, 8),
      position: PopupMenuPosition.under,
      color: const Color(0xFF1B1F28),
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(
          color: Color(0xFF343A49),
          width: 1,
        ),
      ),
      onSelected: onSelected,
      itemBuilder: (context) {
        return _statuses.map((status) {
          final selected = status == selectedStatus;
          final color = _color(status);

          return PopupMenuItem<String>(
            value: status,
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: Container(
              width: 210,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                gradient: selected
                    ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF303643),
                    Color(0xFF242A32),
                  ],
                )
                    : null,
                color: selected ? null : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? const Color(0xFF4A5160)
                      : Colors.transparent,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _icon(status),
                    color: color,
                    size: 17,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      _label(status),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFF1F4F8),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (selected)
                    const Icon(
                      CupertinoIcons.checkmark_circle_fill,
                      color: Color(0xFFE6EAF2),
                      size: 17,
                    ),
                ],
              ),
            ),
          );
        }).toList();
      },
      child: _EstimateControlIconCapsule(
        icon: _icon(selectedStatus),
        active: active,
      ),
    );
  }
}

class _EstimatesSummaryPanel extends StatelessWidget {
  final int totalCount;
  final int draftCount;
  final int sentCount;
  final int approvedCount;

  const _EstimatesSummaryPanel({
    required this.totalCount,
    required this.draftCount,
    required this.sentCount,
    required this.approvedCount,
  });

  Widget _compactStat({
    required String title,
    required String value,
    required Color accent,
    required IconData icon,
  }) {
    return Expanded(
      child: Container(
        height: 96,
        padding: const EdgeInsets.fromLTRB(7, 9, 7, 9),
        decoration: BoxDecoration(
          color: const Color(0xFF242730),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: const Color(0xFF343846),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.22),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: accent),
            const SizedBox(height: 7),
            Text(
              title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF9EA7BA),
                fontSize: 9.2,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.15,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFF6F8FC),
                fontSize: 18.5,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.2,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _kEstCardTop,
            _kEstCardBot,
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withOpacity(0.07),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.30),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          _compactStat(
            title: 'Total',
            value: totalCount.toString(),
            accent: _kEstAccent,
            icon: Icons.request_quote_rounded,
          ),
          const SizedBox(width: 8),
          _compactStat(
            title: 'Draft',
            value: draftCount.toString(),
            accent: const Color(0xFFBFC6D4),
            icon: Icons.edit_note_rounded,
          ),
          const SizedBox(width: 8),
          _compactStat(
            title: 'Sent',
            value: sentCount.toString(),
            accent: const Color(0xFF38BDF8),
            icon: Icons.send_rounded,
          ),
          const SizedBox(width: 8),
          _compactStat(
            title: 'Approved',
            value: approvedCount.toString(),
            accent: const Color(0xFF22C55E),
            icon: Icons.verified_rounded,
          ),
        ],
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
        return const Color(0xFFB8C0CF);
      case 'sent':
        return const Color(0xFF38BDF8);
      case 'approved':
        return const Color(0xFF22C55E);
      case 'rejected':
        return const Color(0xFFE85D3D);
      case 'archived':
        return const Color(0xFF8E93A6);
      default:
        return const Color(0xFFB8C0CF);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'draft':
        return 'Draft';
      case 'sent':
        return 'Sent';
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      case 'archived':
        return 'Archived';
      default:
        return status;
    }
  }

  Widget _infoRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
  }) {
    final sub = (subtitle ?? '').trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.10),
            border: Border.all(color: iconColor.withOpacity(0.14)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor, size: 19),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.manrope(
                  color: const Color(0xFF1A1F2A),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.15,
                  height: 1.25,
                ),
              ),
              if (sub.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    color: const Color(0xFF6B7280),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _miniBlock({
    required String label,
    required String value,
    required IconData icon,
    required Color accent,
  }) {
    return Expanded(
      child: Container(
        height: 64,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.035),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.black.withOpacity(0.07),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: accent, size: 17),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.jetBrainsMono(
                      color: const Color(0xFF8A93A3),
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.9,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      color: const Color(0xFF1A1F2A),
                      fontSize: 13.2,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.15,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _smallAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF171A21),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withOpacity(0.08),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: const Color(0xFFD8DDE8), size: 16),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: GoogleFonts.manrope(
                    color: const Color(0xFFF3F6FC),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isArchived = estimate.status == 'archived';
    final statusColor = _statusColor(estimate.status);
    final statusLabel = _statusLabel(estimate.status);

    final title = EstimateFormatters.safeText(
      estimate.title,
      fallback: 'Untitled Estimate',
    );

    final mainIcon = WorkioIconMapper.resolveFromTitle(title);

    final estimateDate = estimate.createdAt ?? estimate.updatedAt ?? DateTime.now();
    final dateText = EstimateFormatters.formatDate(estimateDate);

    return Opacity(
      opacity: isArchived ? 0.62 : 1,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onOpen,
          onLongPress: onMore,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            margin: const EdgeInsets.fromLTRB(3, 4, 3, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.52),
                  blurRadius: 28,
                  spreadRadius: -5,
                  offset: const Offset(0, 16),
                ),
                BoxShadow(
                  color: _kEstAccent.withOpacity(0.10),
                  blurRadius: 24,
                  spreadRadius: -8,
                  offset: const Offset(0, 7),
                ),
                BoxShadow(
                  color: Colors.white.withOpacity(0.04),
                  blurRadius: 0,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF171A21),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Column(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color(0xFF1A1F2A),
                                  Color(0xFF14181F),
                                ],
                              ),
                            ),
                          ),
                        ),

                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                center: const Alignment(1, -1),
                                radius: 1.1,
                                colors: [
                                  _kEstAccent.withOpacity(0.08),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),

                        Padding(
                          padding: const EdgeInsets.fromLTRB(22, 22, 22, 30),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                mainIcon,
                                color: Colors.white,
                                size: 34,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.manrope(
                                        color: Colors.white,
                                        fontSize: 16.5,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.25,
                                        height: 1.17,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      estimate.estimateNumber,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.jetBrainsMono(
                                        color: const Color(0xFF8D95A6),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(22, 30, 22, 22),
                          color: const Color(0xFFF5F4EE),
                          child: Column(
                            children: [
                              _infoRow(
                                icon: Icons.person_rounded,
                                iconColor: const Color(0xFF7C5CFF),
                                title: clientName,
                                subtitle: companyName,
                              ),

                              Container(
                                height: 1,
                                margin: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.transparent,
                                      Colors.black.withOpacity(0.08),
                                      Colors.black.withOpacity(0.08),
                                      Colors.transparent,
                                    ],
                                    stops: const [0, 0.2, 0.8, 1.0],
                                  ),
                                ),
                              ),

                              _infoRow(
                                icon: Icons.location_on_rounded,
                                iconColor: const Color(0xFFEF4444),
                                title: address,
                              ),
                            ],
                          ),
                        ),

                        Positioned(
                          left: 20,
                          top: -12,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(7, 3, 8, 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF171A21),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: const Color(0xFF64748B).withOpacity(0.45),
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.20),
                                  blurRadius: 9,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Text(
                              dateText.toUpperCase(),
                              style: GoogleFonts.jetBrainsMono(
                                color: const Color(0xFFCBD5E1),
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.9,
                              ),
                            ),
                          ),
                        ),

                        Positioned(
                          right: 20,
                          top: -12,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(7, 3, 8, 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF171A21),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: statusColor.withOpacity(0.45),
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.25),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 4.5,
                                  height: 4.5,
                                  decoration: BoxDecoration(
                                    color: statusColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  statusLabel.toUpperCase(),
                                  style: GoogleFonts.jetBrainsMono(
                                    color: statusColor,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.05,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
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

class _EstimateYearGroup {
  final int year;
  final List<_EstimateMonthGroup> months;

  const _EstimateYearGroup({
    required this.year,
    required this.months,
  });
}

class _EstimateMonthGroup {
  final int year;
  final int month;
  final String title;
  final List<EstimateModel> estimates;

  const _EstimateMonthGroup({
    required this.year,
    required this.month,
    required this.title,
    required this.estimates,
  });
}

class _EstimateYearGroupPanel extends StatelessWidget {
  final _EstimateYearGroup group;
  final bool expanded;
  final VoidCallback onTap;
  final bool Function(_EstimateMonthGroup month) isMonthExpanded;
  final void Function(_EstimateMonthGroup month) onMonthTap;
  final Widget Function(EstimateModel estimate) buildEstimateCard;

  const _EstimateYearGroupPanel({
    required this.group,
    required this.expanded,
    required this.onTap,
    required this.isMonthExpanded,
    required this.onMonthTap,
    required this.buildEstimateCard,
  });

  int get _count {
    var total = 0;
    for (final month in group.months) {
      total += month.estimates.length;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF242A33),
              Color(0xFF1E242D),
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: const Color(0xFF3A4150),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.26),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
                  child: Row(
                    children: [
                      AnimatedRotation(
                        turns: expanded ? 0.0 : -0.25,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Color(0xFFB8C0CF),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 8),

                      Text(
                        '${group.year}',
                        style: const TextStyle(
                          color: _kEstTextMain,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.25,
                        ),
                      ),

                      const SizedBox(width: 10),

                      Text(
                        '$_count estimate${_count == 1 ? '' : 's'}',
                        style: const TextStyle(
                          color: _kEstTextMute,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),

                      const SizedBox(width: 12),

                      Expanded(
                        child: Container(
                          height: 1,
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            if (expanded) ...[
              for (int i = 0; i < group.months.length; i++) ...[
                _EstimateMonthGroupPanel(
                  month: group.months[i],
                  expanded: isMonthExpanded(group.months[i]),
                  onTap: () => onMonthTap(group.months[i]),
                  buildEstimateCard: buildEstimateCard,
                ),
                if (i != group.months.length - 1)
                  const SizedBox(height: 12),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _EstimateMonthGroupPanel extends StatelessWidget {
  final _EstimateMonthGroup month;
  final bool expanded;
  final VoidCallback onTap;
  final Widget Function(EstimateModel estimate) buildEstimateCard;

  const _EstimateMonthGroupPanel({
    required this.month,
    required this.expanded,
    required this.onTap,
    required this.buildEstimateCard,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(2, 4, 2, 10),
                child: Row(
                  children: [
                    AnimatedRotation(
                      turns: expanded ? 0.0 : -0.25,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Color(0xFFB8C0CF),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      month.title,
                      style: const TextStyle(
                        color: _kEstTextMain,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: Container(
                        height: 1,
                        color: Colors.white.withOpacity(0.08),
                      ),
                    ),

                    const SizedBox(width: 12),

                    Text(
                      '${month.estimates.length}',
                      style: const TextStyle(
                        color: _kEstTextMute,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (expanded) ...[
            const SizedBox(height: 8),
            for (int i = 0; i < month.estimates.length; i++) ...[
              buildEstimateCard(month.estimates[i]),
              if (i != month.estimates.length - 1)
                const SizedBox(height: 18),
            ],
          ],
        ],
      ),
    );
  }
}