import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/client_model.dart';
import '../models/invoice_model.dart';
import '../models/property_model.dart';

import '../services/client_service.dart';
import '../services/invoice_service.dart';
import '../services/property_service.dart';

import '../utils/estimate_formatters.dart';
import '../utils/workio_icon_mapper.dart';

import 'invoice_details_screen.dart';

import 'create_invoice_screen.dart';

const _kInvTintTop = Color(0xFF31343B);
const _kInvTintMid = Color(0xFF272A31);
const _kInvTintBot = Color(0xFF1D2027);

const _kInvCardTop = Color(0xFF262A31);
const _kInvCardBot = Color(0xFF1C2027);

const _kInvInnerTop = Color(0xFF242A32);
const _kInvInnerBot = Color(0xFF171C23);

const _kInvTextMain = Color(0xFFF3F6FC);
const _kInvTextSoft = Color(0xFFA0A7B8);
const _kInvTextMute = Color(0xFF8E93A6);

class InvoiceListScreen extends StatefulWidget {
  const InvoiceListScreen({super.key});

  @override
  State<InvoiceListScreen> createState() => _InvoiceListScreenState();
}

class _InvoiceListScreenState extends State<InvoiceListScreen> {
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String? _errorMessage;

  List<InvoiceModel> _allInvoices = [];
  List<InvoiceModel> _filteredInvoices = [];

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
        InvoiceService.getInvoices(),
        ClientService.getClients(),
        PropertyService.getProperties(),
      ]);

      final invoices = results[0] as List<InvoiceModel>;
      final clients = results[1] as List<ClientModel>;
      final properties = results[2] as List<PropertyModel>;

      _clientsById
        ..clear()
        ..addEntries(clients.map((e) => MapEntry(e.id, e)));

      _propertiesById
        ..clear()
        ..addEntries(properties.map((e) => MapEntry(e.id, e)));

      _allInvoices = invoices;
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
        _errorMessage = 'Failed to load invoices';
      });
    }
  }

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();

    final filtered = _allInvoices.where((invoice) {
      final client = _clientsById[invoice.clientId];
      final property = _propertiesById[invoice.propertyId];

      final clientName = (client?.fullName ?? '').toLowerCase();
      final companyName = (client?.companyName ?? '').toLowerCase();
      final invoiceNumber = invoice.invoiceNumber.toLowerCase();
      final title = invoice.title.toLowerCase();
      final address = (property?.fullAddress ?? '').toLowerCase();

      final matchesStatus = switch (_selectedStatus) {
        'all' => true,
        'unpaid' =>
        invoice.status == 'draft' ||
            invoice.status == 'sent' ||
            invoice.status == 'partial' ||
            invoice.status == 'overdue',
        _ => invoice.status == _selectedStatus,
      };

      final matchesQuery = query.isEmpty ||
          clientName.contains(query) ||
          companyName.contains(query) ||
          invoiceNumber.contains(query) ||
          title.contains(query) ||
          address.contains(query);

      return matchesStatus && matchesQuery;
    }).toList();

    if (!mounted) return;

    setState(() {
      _filteredInvoices = filtered;
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

  DateTime _invoiceDate(InvoiceModel invoice) {
    return invoice.issueDate ??
        invoice.createdAt ??
        invoice.dueDate ??
        DateTime(2000, 1, 1);
  }

  String get _groupModeLabel {
    switch (_groupMode) {
      case 'year_month':
        return 'Year / Month';
      default:
        return 'None';
    }
  }

  String _statusFilterLabel(String status) {
    switch (status) {
      case 'all':
        return 'All';
      case 'unpaid':
        return 'Unpaid';
      case 'draft':
        return 'Draft';
      case 'sent':
        return 'Sent';
      case 'partial':
        return 'Partial';
      case 'paid':
        return 'Paid';
      case 'overdue':
        return 'Overdue';
      case 'archived':
        return 'Archived';
      default:
        return 'All';
    }
  }

  IconData _statusFilterIcon(String status) {
    switch (status) {
      case 'all':
        return CupertinoIcons.square_grid_2x2;
      case 'unpaid':
        return CupertinoIcons.exclamationmark_circle;
      case 'draft':
        return CupertinoIcons.doc_text;
      case 'sent':
        return CupertinoIcons.paperplane;
      case 'partial':
        return CupertinoIcons.circle_lefthalf_fill;
      case 'paid':
        return CupertinoIcons.checkmark_seal;
      case 'overdue':
        return CupertinoIcons.exclamationmark_triangle;
      case 'archived':
        return CupertinoIcons.archivebox;
      default:
        return CupertinoIcons.square_grid_2x2;
    }
  }

  Color _statusFilterColor(String status) {
    switch (status) {
      case 'all':
        return const Color(0xFF8B5CF6);
      case 'unpaid':
        return const Color(0xFFE85D3D);
      case 'draft':
        return const Color(0xFFBFC6D4);
      case 'sent':
        return const Color(0xFF0EA5E9);
      case 'partial':
        return const Color(0xFFFFB300);
      case 'paid':
        return const Color(0xFF22C55E);
      case 'overdue':
        return const Color(0xFFE85D3D);
      case 'archived':
        return const Color(0xFF8E93A6);
      default:
        return const Color(0xFF8B5CF6);
    }
  }

  Future<void> _pickStatusFilter() async {
    const statuses = [
      'all',
      'unpaid',
      'draft',
      'sent',
      'partial',
      'paid',
      'overdue',
      'archived',
    ];

    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF1B1F28),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (_) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3D4250),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 18),

                const Row(
                  children: [
                    Icon(
                      CupertinoIcons.line_horizontal_3_decrease_circle,
                      color: Color(0xFFF3F6FC),
                      size: 24,
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Filter invoices',
                      style: TextStyle(
                        color: Color(0xFFF1F4F8),
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: statuses.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final status = statuses[index];
                    final selectedNow = status == _selectedStatus;
                    final color = _statusFilterColor(status);

                    return Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => Navigator.pop(context, status),
                        child: Container(
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            color: selectedNow
                                ? color.withValues(alpha: 0.16)
                                : const Color(0xFF151922),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: selectedNow
                                  ? color.withValues(alpha: 0.85)
                                  : const Color(0xFF343A49),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _statusFilterIcon(status),
                                color: color,
                                size: 20,
                              ),
                              const SizedBox(width: 13),
                              Expanded(
                                child: Text(
                                  _statusFilterLabel(status),
                                  style: const TextStyle(
                                    color: Color(0xFFF1F4F8),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              Icon(
                                selectedNow
                                    ? CupertinoIcons.checkmark_circle_fill
                                    : CupertinoIcons.chevron_right,
                                color: selectedNow
                                    ? color
                                    : const Color(0xFF9AA3B7),
                                size: selectedNow ? 21 : 16,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null) return;

    _setStatusFilter(selected);
  }

  String _monthLabel(int year, int month) {
    return DateFormat('MMMM').format(DateTime(year, month));
  }

  String _monthKey(int year, int month) => '$year-$month';

  List<_InvoiceYearGroup> _buildInvoiceYearGroups() {
    final sorted = [..._filteredInvoices]
      ..sort((a, b) => _invoiceDate(b).compareTo(_invoiceDate(a)));

    final grouped = <int, Map<int, List<InvoiceModel>>>{};

    for (final invoice in sorted) {
      final date = _invoiceDate(invoice);

      grouped.putIfAbsent(date.year, () => <int, List<InvoiceModel>>{});
      grouped[date.year]!.putIfAbsent(date.month, () => <InvoiceModel>[]);
      grouped[date.year]![date.month]!.add(invoice);
    }

    final years = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return years.map((year) {
      final monthMap = grouped[year]!;
      final monthKeys = monthMap.keys.toList()
        ..sort((a, b) => b.compareTo(a));

      final months = monthKeys.map((month) {
        return _InvoiceMonthGroup(
          year: year,
          month: month,
          title: _monthLabel(year, month),
          invoices: monthMap[month]!,
        );
      }).toList();

      return _InvoiceYearGroup(
        year: year,
        months: months,
      );
    }).toList();
  }

  int? get _latestVisibleYear {
    final groups = _buildInvoiceYearGroups();
    if (groups.isEmpty) return null;
    return groups.first.year;
  }

  String? get _latestVisibleMonthKey {
    final groups = _buildInvoiceYearGroups();
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

  Widget _buildInvoiceCard(InvoiceModel invoice) {
    final client = _clientsById[invoice.clientId];
    final property = _propertiesById[invoice.propertyId];

    return _InvoiceCard(
      invoice: invoice,
      clientName: client?.fullName ?? 'No client',
      companyName: client?.companyName,
      address: property?.fullAddress ?? 'No address',
      onOpen: () => _openInvoiceDetails(invoice.id),
      onMore: () => _showInvoiceActions(invoice),
    );
  }

  Widget _buildGroupedInvoiceContent(List<_InvoiceYearGroup> years) {
    return Column(
      children: [
        for (int y = 0; y < years.length; y++) ...[
          _YearGroupPanel(
            group: years[y],
            expanded: _isYearExpanded(years[y].year),
            onTap: () => _toggleYear(years[y].year),
            isMonthExpanded: (month) =>
                _isMonthExpanded(month.year, month.month),
            onMonthTap: (month) => _toggleMonth(month.year, month.month),
            buildInvoiceCard: _buildInvoiceCard,
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

  List<_InvoiceGroupedRow> _buildInvoiceGroupedRows() {
    final sorted = [..._filteredInvoices]
      ..sort((a, b) => _invoiceDate(b).compareTo(_invoiceDate(a)));

    final grouped = <int, Map<int, List<InvoiceModel>>>{};

    for (final invoice in sorted) {
      final date = _invoiceDate(invoice);

      grouped.putIfAbsent(date.year, () => <int, List<InvoiceModel>>{});
      grouped[date.year]!.putIfAbsent(date.month, () => <InvoiceModel>[]);
      grouped[date.year]![date.month]!.add(invoice);
    }

    final rows = <_InvoiceGroupedRow>[];

    final years = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    for (final year in years) {
      rows.add(_InvoiceGroupedRow.year(year));

      final months = grouped[year]!.keys.toList()
        ..sort((a, b) => b.compareTo(a));

      for (final month in months) {
        rows.add(_InvoiceGroupedRow.month(year, month));

        final items = grouped[year]![month]!;
        for (final invoice in items) {
          rows.add(_InvoiceGroupedRow.item(invoice));
        }
      }
    }

    return rows;
  }

  Future<void> _openCreateInvoice() async {
    final createdInvoiceId = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const CreateInvoiceScreen(),
      ),
    );

    if (createdInvoiceId == null || !mounted) {
      await _loadData();
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InvoiceDetailsScreen(invoiceId: createdInvoiceId),
      ),
    );

    await _loadData();
  }

  Future<void> _openInvoiceDetails(String invoiceId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InvoiceDetailsScreen(invoiceId: invoiceId),
      ),
    );

    await _loadData();
  }

  Future<void> _archiveInvoiceFromList(InvoiceModel invoice) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Archive invoice?'),
        content: Text(
          'Invoice "${invoice.title}" will be moved to archived.',
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
      await InvoiceService.archiveInvoice(invoice.id);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invoice archived')),
      );

      await _loadData();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to archive invoice')),
      );
    }
  }

  Future<void> _deleteInvoiceFromList(InvoiceModel invoice) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: Text('Delete permanently?'),
        content: Text(
          'Only mistaken draft invoices should be deleted permanently. This action cannot be undone.',
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
      await InvoiceService.deleteInvoice(invoice.id);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invoice deleted')),
      );

      await _loadData();
    } catch (e) {
      if (!mounted) return;

      final text = e.toString().replaceFirst('Exception: ', '');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            text.isEmpty ? 'Failed to delete invoice' : text,
          ),
        ),
      );
    }
  }

  Future<void> _showInvoiceActions(InvoiceModel invoice) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(
          invoice.title.trim().isEmpty ? 'Invoice' : invoice.title,
        ),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(context);
              await _archiveInvoiceFromList(invoice);
            },
            child: const Text('Archive'),
          ),
          if (invoice.status == 'draft')
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () async {
                Navigator.pop(context);
                await _deleteInvoiceFromList(invoice);
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

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF0B0B0F);
    final yearGroups = _groupMode == 'year_month'
        ? _buildInvoiceYearGroups()
        : <_InvoiceYearGroup>[];

    final paidCount = _filteredInvoices.where((e) => e.isPaid).length;
    final unpaidCount = _filteredInvoices
        .where((e) => e.isDraft || e.isSent || e.isPartial || e.isOverdue)
        .length;
    final overdueCount = _filteredInvoices.where((e) => e.isOverdue).length;

    double outstandingAmount = 0;
    double paidAmount = 0;

    for (final invoice in _filteredInvoices) {
      outstandingAmount += invoice.balanceDue;
      paidAmount += invoice.paidAmount;
    }

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        top: true,
        child: RefreshIndicator(
          onRefresh: _loadData,
          color: const Color(0xFF5B8CFF),
          backgroundColor: const Color(0xFF15161C),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                  child: _InvoicesTopPanel(
                    searchController: _searchController,
                    selectedStatus: _selectedStatus,
                    onStatusSelected: _setStatusFilter,
                    onCreate: _openCreateInvoice,
                    totalCount: _allInvoices.length,
                    unpaidCount: unpaidCount,
                    paidCount: paidCount,
                    overdueCount: overdueCount,
                    outstandingAmount: outstandingAmount,
                    paidAmount: paidAmount,
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
                    message: 'Failed to load invoices',
                  ),
                )
              else if (_filteredInvoices.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                    sliver: _groupMode == 'year_month'
                        ? SliverToBoxAdapter(
                      child: _buildGroupedInvoiceContent(yearGroups),
                    )
                        : SliverList.separated(
                      itemCount: _filteredInvoices.length,
                      itemBuilder: (context, index) {
                        final invoice = _filteredInvoices[index];
                        return _buildInvoiceCard(invoice);
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

class _InvoicesTopPanel extends StatelessWidget {
  final TextEditingController searchController;
  final String selectedStatus;
  final ValueChanged<String> onStatusSelected;
  final VoidCallback onCreate;

  final int totalCount;
  final int unpaidCount;
  final int paidCount;
  final int overdueCount;
  final double outstandingAmount;
  final double paidAmount;

  const _InvoicesTopPanel({
    required this.searchController,
    required this.selectedStatus,
    required this.onStatusSelected,
    required this.onCreate,
    required this.totalCount,
    required this.unpaidCount,
    required this.paidCount,
    required this.overdueCount,
    required this.outstandingAmount,
    required this.paidAmount,
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
            _kInvTintTop,
            _kInvTintMid,
            _kInvTintBot,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.07),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.26),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _TopPanelIconButton(
                icon: CupertinoIcons.chevron_left,
                onTap: () => Navigator.maybePop(context),
              ),
              const SizedBox(width: 12),

              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Invoices',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _kInvTextMain,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.1,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Search, filter, and track invoice totals',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _kInvTextSoft,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          _InvoiceQuickControls(
            searchController: searchController,
            selectedStatus: selectedStatus,
            onStatusSelected: onStatusSelected,
            onCreate: onCreate,
          ),

          const SizedBox(height: 12),

          _SummaryHeader(
            totalCount: totalCount,
            unpaidCount: unpaidCount,
            paidCount: paidCount,
            overdueCount: overdueCount,
            outstandingAmount: outstandingAmount,
            paidAmount: paidAmount,
          ),
        ],
      ),
    );
  }
}

class _TopPanelIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool isGradient;

  const _TopPanelIconButton({
    required this.icon,
    required this.onTap,
    this.color = const Color(0xFFF3F6FC),
    this.isGradient = false,
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
            gradient: isGradient
                ? const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF8B5CF6),
                Color(0xFF262B32),
              ],
            )
                : const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF2F3440),
                Color(0xFF252A34),
              ],
            ),
            borderRadius: borderRadius,
            border: Border.all(
              color: isGradient
                  ? const Color(0xFFA78BFA).withValues(alpha: 0.55)
                  : const Color(0xFF3A4150),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isGradient
                    ? const Color(0xFF8B5CF6).withValues(alpha: 0.22)
                    : Colors.black.withValues(alpha: 0.20),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Icon(
            icon,
            color: isGradient ? Colors.white : color,
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _InvoiceQuickControls extends StatefulWidget {
  final TextEditingController searchController;
  final String selectedStatus;
  final ValueChanged<String> onStatusSelected;
  final VoidCallback onCreate;

  const _InvoiceQuickControls({
    required this.searchController,
    required this.selectedStatus,
    required this.onStatusSelected,
    required this.onCreate,
  });

  @override
  State<_InvoiceQuickControls> createState() => _InvoiceQuickControlsState();
}

class _InvoiceQuickControlsState extends State<_InvoiceQuickControls> {
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.searchController.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant _InvoiceQuickControls oldWidget) {
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
          color: Colors.white.withValues(alpha: 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
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
                    Color(0xFF242A32),
                    Color(0xFF171C23),
                  ],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: _searchFocusNode.hasFocus
                      ? const Color(0xFF5B6374)
                      : Colors.white.withValues(alpha: 0.08),
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
                        color: _kInvTextMain,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      cursorColor: Color(0xFF8B5CF6),
                      decoration: const InputDecoration(
                        hintText: 'Search invoice...',
                        hintStyle: TextStyle(
                          color: _kInvTextMute,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
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

          _FilterIconPopup(
            selectedStatus: widget.selectedStatus,
            onSelected: widget.onStatusSelected,
          ),

          const SizedBox(width: 8),

          _ControlIconButton(
            icon: CupertinoIcons.plus,
            iconColor: Colors.white,
            onTap: widget.onCreate,
          ),
        ],
      ),
    );
  }
}

class _ControlIconButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;
  final bool active;
  final bool isAdd;

  const _ControlIconButton({
    required this.icon,
    required this.onTap,
    this.iconColor = Colors.white,
    this.active = false,
    this.isAdd = false,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minSize: 0,
      onPressed: onTap,
      child: _ControlIconCapsule(
        icon: icon,
        iconColor: iconColor,
        active: active,
        isAdd: isAdd,
      ),
    );
  }
}

class _ControlIconCapsule extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final bool active;
  final bool isAdd;

  const _ControlIconCapsule({
    required this.icon,
    required this.iconColor,
    this.active = false,
    this.isAdd = false,
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
            Color(0xFF242A32),
            Color(0xFF171C23),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: active
              ? const Color(0xFF4A5160)
              : Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
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

class _FilterIconPopup extends StatelessWidget {
  final String selectedStatus;
  final ValueChanged<String> onSelected;

  const _FilterIconPopup({
    required this.selectedStatus,
    required this.onSelected,
  });

  static const List<String> _statuses = [
    'all',
    'unpaid',
    'draft',
    'sent',
    'partial',
    'paid',
    'overdue',
    'archived',
  ];

  String _label(String status) {
    switch (status) {
      case 'all':
        return 'All';
      case 'unpaid':
        return 'Unpaid';
      case 'draft':
        return 'Draft';
      case 'sent':
        return 'Sent';
      case 'partial':
        return 'Partial';
      case 'paid':
        return 'Paid';
      case 'overdue':
        return 'Overdue';
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
      case 'unpaid':
        return CupertinoIcons.exclamationmark_circle;
      case 'draft':
        return CupertinoIcons.doc_text;
      case 'sent':
        return CupertinoIcons.paperplane;
      case 'partial':
        return CupertinoIcons.circle_lefthalf_fill;
      case 'paid':
        return CupertinoIcons.checkmark_seal;
      case 'overdue':
        return CupertinoIcons.exclamationmark_triangle;
      case 'archived':
        return CupertinoIcons.archivebox;
      default:
        return CupertinoIcons.square_grid_2x2;
    }
  }

  Color _color(String status) {
    switch (status) {
      case 'all':
        return const Color(0xFF8B5CF6);
      case 'unpaid':
        return const Color(0xFFE85D3D);
      case 'draft':
        return const Color(0xFFBFC6D4);
      case 'sent':
        return const Color(0xFF0EA5E9);
      case 'partial':
        return const Color(0xFFFFB300);
      case 'paid':
        return const Color(0xFF22C55E);
      case 'overdue':
        return const Color(0xFFE85D3D);
      case 'archived':
        return const Color(0xFF8E93A6);
      default:
        return const Color(0xFF8B5CF6);
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
      child: _ControlIconCapsule(
        icon: _icon(selectedStatus),
        iconColor: Colors.white,
        active: active,
      ),
    );
  }
}

class _TopPanelAddButton extends StatelessWidget {
  final VoidCallback onTap;

  const _TopPanelAddButton({
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF8B5CF6),
                Color(0xFF6D4CFF),
              ],
            ),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: Color(0xFF9F86FF),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0xFF8B5CF6).withValues(alpha: 0.28),
                blurRadius: 16,
                offset: Offset(0, 7),
              ),
            ],
          ),
          child: const Icon(
            CupertinoIcons.plus,
            color: Colors.white,
            size: 19,
          ),
        ),
      ),
    );
  }
}

class _StatusFilterDropdown extends StatelessWidget {
  final String selectedStatus;
  final ValueChanged<String> onSelected;

  const _StatusFilterDropdown({
    required this.selectedStatus,
    required this.onSelected,
  });

  static const List<String> _statuses = [
    'all',
    'unpaid',
    'draft',
    'sent',
    'partial',
    'paid',
    'overdue',
    'archived',
  ];

  String _label(String status) {
    switch (status) {
      case 'all':
        return 'All';
      case 'unpaid':
        return 'Unpaid';
      case 'draft':
        return 'Draft';
      case 'sent':
        return 'Sent';
      case 'partial':
        return 'Partial';
      case 'paid':
        return 'Paid';
      case 'overdue':
        return 'Overdue';
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
      case 'unpaid':
        return CupertinoIcons.exclamationmark_circle;
      case 'draft':
        return CupertinoIcons.doc_text;
      case 'sent':
        return CupertinoIcons.paperplane;
      case 'partial':
        return CupertinoIcons.circle_lefthalf_fill;
      case 'paid':
        return CupertinoIcons.checkmark_seal;
      case 'overdue':
        return CupertinoIcons.exclamationmark_triangle;
      case 'archived':
        return CupertinoIcons.archivebox;
      default:
        return CupertinoIcons.square_grid_2x2;
    }
  }

  Color _color(String status) {
    switch (status) {
      case 'all':
        return const Color(0xFF8B5CF6);
      case 'unpaid':
        return const Color(0xFFE85D3D);
      case 'draft':
        return const Color(0xFFBFC6D4);
      case 'sent':
        return const Color(0xFF0EA5E9);
      case 'partial':
        return const Color(0xFFFFB300);
      case 'paid':
        return const Color(0xFF22C55E);
      case 'overdue':
        return const Color(0xFFE85D3D);
      case 'archived':
        return const Color(0xFF8E93A6);
      default:
        return const Color(0xFF8B5CF6);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedColor = _color(selectedStatus);

    return PopupMenuButton<String>(
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
              width: 170,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: selected
                    ? color.withValues(alpha: 0.16)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? color.withValues(alpha: 0.70)
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
                    Icon(
                      CupertinoIcons.checkmark_circle_fill,
                      color: color,
                      size: 17,
                    ),
                ],
              ),
            ),
          );
        }).toList();
      },
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2F3B),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFF3A4150),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              _icon(selectedStatus),
              color: selectedColor,
              size: 18,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                _label(selectedStatus),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFF1F4F8),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              CupertinoIcons.chevron_down,
              color: Color(0xFFBFC6D4),
              size: 13,
            ),
          ],
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
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _kInvInnerTop,
            _kInvInnerBot,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        cursorColor: const Color(0xFF8B5CF6),
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
      {'value': 'unpaid', 'label': 'Unpaid'},
      {'value': 'draft', 'label': 'Draft'},
      {'value': 'sent', 'label': 'Sent'},
      {'value': 'partial', 'label': 'Partial'},
      {'value': 'paid', 'label': 'Paid'},
      {'value': 'overdue', 'label': 'Overdue'},
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

class _SummaryHeader extends StatefulWidget {
  final int totalCount;
  final int unpaidCount;
  final int paidCount;
  final int overdueCount;
  final double outstandingAmount;
  final double paidAmount;

  const _SummaryHeader({
    required this.totalCount,
    required this.unpaidCount,
    required this.paidCount,
    required this.overdueCount,
    required this.outstandingAmount,
    required this.paidAmount,
  });

  @override
  State<_SummaryHeader> createState() => _SummaryHeaderState();
}

class _SummaryHeaderState extends State<_SummaryHeader> {
  bool _balanceOpen = false;

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
              color: Colors.black.withValues(alpha: 0.22),
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
                color: _kInvTextMute,
                fontSize: 8.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.7,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _kInvTextMain,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _moneyRow({
    required String title,
    required String value,
    required IconData icon,
    required Color accent,
  }) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF242730),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF343846),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: accent, size: 17),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _kInvTextSoft,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: _kInvTextMain,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _balanceFooter() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _balanceOpen = !_balanceOpen;
          });
        },
        child: SizedBox(
          width: double.infinity,
          height: 46,
          child: Row(
            children: [
              const SizedBox(width: 4),

              const Icon(
                CupertinoIcons.chart_bar_alt_fill,
                color: Color(0xFFB8C0CF),
                size: 16,
              ),

              const SizedBox(width: 10),

              const Expanded(
                child: Text(
                  'Balance summary',
                  style: TextStyle(
                    color: _kInvTextSoft,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),

              AnimatedRotation(
                turns: _balanceOpen ? 0.5 : 0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: const Icon(
                  CupertinoIcons.chevron_down,
                  color: Color(0xFFB8C0CF),
                  size: 15,
                ),
              ),

              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _kInvCardTop,
              _kInvCardBot,
            ],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.07),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.30),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                _compactStat(
                  title: 'Total',
                  value: widget.totalCount.toString(),
                  accent: const Color(0xFF8B5CF6),
                  icon: Icons.receipt_long_rounded,
                ),
                const SizedBox(width: 8),
                _compactStat(
                  title: 'Unpaid',
                  value: widget.unpaidCount.toString(),
                  accent: const Color(0xFF38BDF8),
                  icon: Icons.error_rounded,
                ),
                const SizedBox(width: 8),
                _compactStat(
                  title: 'Paid',
                  value: widget.paidCount.toString(),
                  accent: const Color(0xFF59F0A7),
                  icon: Icons.verified_rounded,
                ),
                const SizedBox(width: 8),
                _compactStat(
                  title: 'Overdue',
                  value: widget.overdueCount.toString(),
                  accent: const Color(0xFFFF8A7A),
                  icon: Icons.warning_amber_rounded,
                ),
              ],
            ),

            const SizedBox(height: 10),

            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: !_balanceOpen
                  ? const SizedBox.shrink()
                  : Column(
                key: const ValueKey('balance-open'),
                children: [
                  _moneyRow(
                    title: 'Outstanding',
                    value: EstimateFormatters.formatCurrency(
                      widget.outstandingAmount,
                    ),
                    icon: Icons.attach_money_rounded,
                    accent: const Color(0xFFE85D3D),
                  ),
                  const SizedBox(height: 8),
                  _moneyRow(
                    title: 'Collected',
                    value: EstimateFormatters.formatCurrency(
                      widget.paidAmount,
                    ),
                    icon: Icons.account_balance_wallet_rounded,
                    accent: const Color(0xFFFFB300),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),

            Container(
              height: 1,
              width: double.infinity,
              color: Colors.white.withValues(alpha: 0.07),
            ),

            _balanceFooter(),
          ],
        ),
      ),
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

class _MiniMoneyCard extends StatelessWidget {
  final String title;
  final String value;

  const _MiniMoneyCard({
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
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceCard extends StatefulWidget {
  final InvoiceModel invoice;
  final String clientName;
  final String? companyName;
  final String address;
  final VoidCallback onOpen;
  final VoidCallback onMore;

  const _InvoiceCard({
    required this.invoice,
    required this.clientName,
    required this.companyName,
    required this.address,
    required this.onOpen,
    required this.onMore,
  });

  @override
  State<_InvoiceCard> createState() => _InvoiceCardState();
}

class _InvoiceCardState extends State<_InvoiceCard> {
  Color _statusColor(String status) {
    switch (status) {
      case 'draft':
        return const Color(0xFFB8C0CF);
      case 'sent':
        return const Color(0xFF38BDF8);
      case 'partial':
        return const Color(0xFFFFB300);
      case 'paid':
        return const Color(0xFF22C55E);
      case 'overdue':
        return const Color(0xFFE85D3D);
      case 'archived':
        return const Color(0xFF8E93A6);
      default:
        return const Color(0xFFB8C0CF);
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'draft':
        return CupertinoIcons.doc_text_fill;
      case 'sent':
        return CupertinoIcons.paperplane_fill;
      case 'partial':
        return CupertinoIcons.circle_lefthalf_fill;
      case 'paid':
        return CupertinoIcons.checkmark_seal_fill;
      case 'overdue':
        return CupertinoIcons.exclamationmark_triangle_fill;
      case 'archived':
        return CupertinoIcons.archivebox_fill;
      default:
        return CupertinoIcons.info_circle_fill;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'draft': return 'Draft';
      case 'sent': return 'Sent';
      case 'partial': return 'Partial';
      case 'paid': return 'Paid';
      case 'overdue': return 'Overdue';
      case 'archived': return 'Archived';
      default: return status;
    }
  }

  Widget _infoRow({
    required IconData icon,
    required Color iconColor,
    required String label,
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

  @override
  Widget build(BuildContext context) {
    final isArchived = widget.invoice.status == 'archived';
    final statusColor = _statusColor(widget.invoice.status);
    final statusLabel = _statusLabel(widget.invoice.status);

    final title = widget.invoice.title.trim().isEmpty
        ? 'Untitled Invoice'
        : widget.invoice.title.trim();

    final mainIcon = WorkioIconMapper.resolveFromTitle(title);

    final invoiceDate = widget.invoice.issueDate ??
        widget.invoice.createdAt ??
        widget.invoice.dueDate;

    final dateText = invoiceDate == null
        ? 'No date'
        : EstimateFormatters.formatDate(invoiceDate);

    return Opacity(
      opacity: isArchived ? 0.62 : 1,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: widget.onOpen,
          onLongPress: widget.onMore,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            margin: const EdgeInsets.fromLTRB(3, 4, 3, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.52),
                  blurRadius: 28,
                  spreadRadius: -5,
                  offset: const Offset(0, 16),
                ),
                BoxShadow(
                  color: const Color(0xFF8B5CF6).withOpacity(0.10),
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
                                const Color(0xFF5B49D6).withOpacity(0.08),
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
                                    widget.invoice.invoiceNumber,
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
                        padding: const EdgeInsets.fromLTRB(22, 30, 22, 20),
                        color: const Color(0xFFF5F4EE),
                        child: Column(
                          children: [
                            _infoRow(
                              icon: Icons.person_rounded,
                              iconColor: const Color(0xFF7C5CFF),
                              label: '',
                              title: widget.clientName,
                              subtitle: widget.companyName,
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
                              label: '',
                              title: widget.address,
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
  final IconData icon;

  const _StatusBadge({
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withValues(alpha: 0.38),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
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
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minSize: 0,
      onPressed: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: const Color(0xFF151922),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFF343846),
          ),
        ),
        child: const Icon(
          CupertinoIcons.ellipsis,
          color: Color(0xFFB8C0CF),
          size: 18,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String text;
  final String? secondary;

  const _InfoRow({
    required this.icon,
    required this.iconColor,
    required this.text,
    this.secondary,
  });

  @override
  Widget build(BuildContext context) {
    final secondaryText = (secondary ?? '').trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          color: iconColor,
          size: 19,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _kInvTextMain,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
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
                    color: _kInvTextMute,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
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
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  const _AmountBlock({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFF151922),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF343846),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 15),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _kInvTextMute,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _kInvTextMain,
              fontSize: 15,
              fontWeight: FontWeight.w900,
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
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minSize: 0,
      onPressed: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF242A32),
              Color(0xFF171C23),
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFF343846),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: const Color(0xFF8B5CF6),
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: _kInvTextMain,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
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

  const _ErrorState({
    required this.message,
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
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

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
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.doc_plaintext,
                color: Colors.white,
                size: 30,
              ),
              SizedBox(height: 18),
              Text(
                'No invoices yet',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Create your first invoice to start tracking billing and payments.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF8E93A6),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
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

class _YearGroupPanel extends StatelessWidget {
  final _InvoiceYearGroup group;
  final bool expanded;
  final VoidCallback onTap;
  final bool Function(_InvoiceMonthGroup month) isMonthExpanded;
  final void Function(_InvoiceMonthGroup month) onMonthTap;
  final Widget Function(InvoiceModel invoice) buildInvoiceCard;

  const _YearGroupPanel({
    required this.group,
    required this.expanded,
    required this.onTap,
    required this.isMonthExpanded,
    required this.onMonthTap,
    required this.buildInvoiceCard,
  });

  int get invoiceCount {
    int count = 0;
    for (final month in group.months) {
      count += month.invoices.length;
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _kInvTintTop,
              _kInvTintMid,
              _kInvTintBot,
            ],
          ),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 22,
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
                child: SizedBox(
                  height: 42,
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
                          color: _kInvTextMain,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '$invoiceCount invoice${invoiceCount == 1 ? '' : 's'}',
                        style: const TextStyle(
                          color: _kInvTextMute,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          height: 1,
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            if (expanded) ...[
              const SizedBox(height: 12),
              for (int i = 0; i < group.months.length; i++) ...[
                _MonthGroupPanel(
                  month: group.months[i],
                  expanded: isMonthExpanded(group.months[i]),
                  onTap: () => onMonthTap(group.months[i]),
                  buildInvoiceCard: buildInvoiceCard,
                ),
                if (i != group.months.length - 1) const SizedBox(height: 12),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _MonthGroupPanel extends StatelessWidget {
  final _InvoiceMonthGroup month;
  final bool expanded;
  final VoidCallback onTap;
  final Widget Function(InvoiceModel invoice) buildInvoiceCard;

  const _MonthGroupPanel({
    required this.month,
    required this.expanded,
    required this.onTap,
    required this.buildInvoiceCard,
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
                        color: _kInvTextMain,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: Container(
                        height: 1,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),

                    const SizedBox(width: 12),

                    Text(
                      '${month.invoices.length}',
                      style: const TextStyle(
                        color: _kInvTextMute,
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
            for (int i = 0; i < month.invoices.length; i++) ...[
              buildInvoiceCard(month.invoices[i]),
              if (i != month.invoices.length - 1)
                const SizedBox(height: 18),
            ],
          ],
        ],
      ),
    );
  }
}

class _InvoiceYearGroup {
  final int year;
  final List<_InvoiceMonthGroup> months;

  const _InvoiceYearGroup({
    required this.year,
    required this.months,
  });
}

class _InvoiceMonthGroup {
  final int year;
  final int month;
  final String title;
  final List<InvoiceModel> invoices;

  const _InvoiceMonthGroup({
    required this.year,
    required this.month,
    required this.title,
    required this.invoices,
  });
}

class _MonthSectionHeader extends StatelessWidget {
  final String title;

  const _MonthSectionHeader({
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 0, left: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF171B24),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF343846),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.calendar_month_rounded,
            color: Color(0xFFB8C0CF),
            size: 16,
          ),
          const SizedBox(width: 9),
          Text(
            title,
            style: const TextStyle(
              color: _kInvTextSoft,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceGroupedRow {
  final int? year;
  final int? month;
  final InvoiceModel? invoice;
  final _InvoiceGroupedRowType type;

  const _InvoiceGroupedRow._({
    required this.type,
    this.year,
    this.month,
    this.invoice,
  });

  const _InvoiceGroupedRow.year(int year)
      : this._(type: _InvoiceGroupedRowType.year, year: year);

  const _InvoiceGroupedRow.month(int year, int month)
      : this._(
    type: _InvoiceGroupedRowType.month,
    year: year,
    month: month,
  );

  const _InvoiceGroupedRow.item(InvoiceModel invoice)
      : this._(
    type: _InvoiceGroupedRowType.item,
    invoice: invoice,
  );

  bool get isYearHeader => type == _InvoiceGroupedRowType.year;
  bool get isMonthHeader => type == _InvoiceGroupedRowType.month;
  bool get isItem => type == _InvoiceGroupedRowType.item;
}

enum _InvoiceGroupedRowType {
  year,
  month,
  item,
}