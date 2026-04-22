import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/client_model.dart';
import '../models/estimate_model.dart';
import '../models/invoice_model.dart';
import '../models/property_model.dart';
import '../services/client_service.dart';
import '../services/estimate_service.dart';
import '../services/invoice_service.dart';
import '../services/property_service.dart';
import '../utils/estimate_formatters.dart';
import 'client_details_screen.dart';
import 'estimate_details_screen.dart';
import 'invoice_details_screen.dart';
import 'property_details_screen.dart';

class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String? _errorMessage;

  List<ClientModel> _clients = [];
  List<PropertyModel> _properties = [];
  List<EstimateModel> _estimates = [];
  List<InvoiceModel> _invoices = [];

  final Map<String, ClientModel> _clientsById = {};
  final Map<String, PropertyModel> _propertiesById = {};

  List<ClientModel> _filteredClients = [];
  List<PropertyModel> _filteredProperties = [];
  List<EstimateModel> _filteredEstimates = [];
  List<InvoiceModel> _filteredInvoices = [];

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchController.removeListener(_applyFilter);
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
        ClientService.getClients(),
        PropertyService.getProperties(),
        EstimateService.getEstimates(),
        InvoiceService.getInvoices(),
      ]);

      final clients = results[0] as List<ClientModel>;
      final properties = results[1] as List<PropertyModel>;
      final estimates = results[2] as List<EstimateModel>;
      final invoices = results[3] as List<InvoiceModel>;

      _clientsById
        ..clear()
        ..addEntries(clients.map((e) => MapEntry(e.id, e)));

      _propertiesById
        ..clear()
        ..addEntries(properties.map((e) => MapEntry(e.id, e)));

      if (!mounted) return;

      setState(() {
        _clients = clients;
        _properties = properties;
        _estimates = estimates;
        _invoices = invoices;
        _isLoading = false;
      });

      _applyFilter();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = 'Не удалось загрузить данные для поиска';
      });
    }
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();

    bool containsAny(List<String> values) {
      if (query.isEmpty) return true;
      for (final value in values) {
        if (value.toLowerCase().contains(query)) return true;
      }
      return false;
    }

    final filteredClients = _clients.where((client) {
      return containsAny([
        client.fullName,
        client.companyName ?? '',
        client.email ?? '',
        client.phone ?? '',
        client.notes ?? '',
      ]);
    }).toList();

    final filteredProperties = _properties.where((property) {
      final client = _clientsById[property.clientId];
      return containsAny([
        property.addressLine1,
        property.addressLine2 ?? '',
        property.city ?? '',
        property.province ?? '',
        property.postalCode ?? '',
        property.propertyType ?? '',
        property.notes ?? '',
        property.fullAddress,
        client?.fullName ?? '',
        client?.companyName ?? '',
      ]);
    }).toList();

    final filteredEstimates = _estimates.where((estimate) {
      final client = _clientsById[estimate.clientId];
      final property = _propertiesById[estimate.propertyId];

      return containsAny([
        estimate.title,
        estimate.estimateNumber,
        estimate.status,
        estimate.notes ?? '',
        estimate.scopeText ?? '',
        client?.fullName ?? '',
        client?.companyName ?? '',
        property?.fullAddress ?? '',
      ]);
    }).toList();

    final filteredInvoices = _invoices.where((invoice) {
      final client = _clientsById[invoice.clientId];
      final property = _propertiesById[invoice.propertyId];

      return containsAny([
        invoice.title,
        invoice.invoiceNumber,
        invoice.status,
        invoice.notes ?? '',
        invoice.terms ?? '',
        client?.fullName ?? '',
        client?.companyName ?? '',
        property?.fullAddress ?? '',
      ]);
    }).toList();

    if (!mounted) return;

    setState(() {
      _filteredClients = filteredClients;
      _filteredProperties = filteredProperties;
      _filteredEstimates = filteredEstimates;
      _filteredInvoices = filteredInvoices;
    });
  }

  Future<void> _openClient(ClientModel client) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClientDetailsScreen(client: client),
      ),
    );
    await _loadData();
  }

  Future<void> _openProperty(PropertyModel property) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PropertyDetailsScreen(property: property),
      ),
    );
    await _loadData();
  }

  Future<void> _openEstimate(String estimateId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EstimateDetailsScreen(estimateId: estimateId),
      ),
    );
    await _loadData();
  }

  Future<void> _openInvoice(String invoiceId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InvoiceDetailsScreen(invoiceId: invoiceId),
      ),
    );
    await _loadData();
  }

  int get _totalResults =>
      _filteredClients.length +
          _filteredProperties.length +
          _filteredEstimates.length +
          _filteredInvoices.length;

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF0B0B0F);

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 20,
        title: const Text(
          'Global Search',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _loadData,
          color: const Color(0xFF5B8CFF),
          backgroundColor: const Color(0xFF15161C),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Column(
                    children: [
                      _SearchField(
                        controller: _searchController,
                        hintText:
                        'Ищи по имени, адресу, номеру estimate/invoice...',
                      ),
                      const SizedBox(height: 14),
                      _TopSummaryCard(
                        totalResults: _totalResults,
                        clientsCount: _filteredClients.length,
                        propertiesCount: _filteredProperties.length,
                        estimatesCount: _filteredEstimates.length,
                        invoicesCount: _filteredInvoices.length,
                      ),
                      const SizedBox(height: 18),
                    ],
                  ),
                ),
              ),
              if (_isLoading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: CupertinoActivityIndicator(radius: 16),
                  ),
                )
              else if (_errorMessage != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _InlineMessageState(
                    icon: CupertinoIcons.exclamationmark_triangle,
                    text: _errorMessage!,
                  ),
                )
              else if (_totalResults == 0)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _InlineMessageState(
                      icon: CupertinoIcons.search,
                      text: 'Ничего не найдено.',
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 30),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        if (_filteredClients.isNotEmpty) ...[
                          _SectionHeader(
                            title: 'Clients',
                            count: _filteredClients.length,
                          ),
                          const SizedBox(height: 10),
                          ...List.generate(_filteredClients.length, (index) {
                            final client = _filteredClients[index];

                            return Padding(
                              padding: EdgeInsets.only(
                                bottom:
                                index == _filteredClients.length - 1 ? 0 : 10,
                              ),
                              child: _SearchResultTile(
                                icon: CupertinoIcons.person_2,
                                title: client.fullName,
                                subtitle: [
                                  if ((client.companyName ?? '').trim().isNotEmpty)
                                    client.companyName!,
                                  if ((client.email ?? '').trim().isNotEmpty)
                                    client.email!,
                                  if ((client.phone ?? '').trim().isNotEmpty)
                                    client.phone!,
                                ].join(' • '),
                                onTap: () => _openClient(client),
                              ),
                            );
                          }),
                          const SizedBox(height: 18),
                        ],
                        if (_filteredProperties.isNotEmpty) ...[
                          _SectionHeader(
                            title: 'Properties',
                            count: _filteredProperties.length,
                          ),
                          const SizedBox(height: 10),
                          ...List.generate(_filteredProperties.length, (index) {
                            final property = _filteredProperties[index];
                            final client = _clientsById[property.clientId];

                            return Padding(
                              padding: EdgeInsets.only(
                                bottom: index == _filteredProperties.length - 1
                                    ? 0
                                    : 10,
                              ),
                              child: _SearchResultTile(
                                icon: CupertinoIcons.location_solid,
                                title: property.fullAddress,
                                subtitle: [
                                  if ((client?.fullName ?? '').trim().isNotEmpty)
                                    client!.fullName,
                                  if ((property.propertyType ?? '')
                                      .trim()
                                      .isNotEmpty)
                                    property.propertyType!,
                                ].join(' • '),
                                onTap: () => _openProperty(property),
                              ),
                            );
                          }),
                          const SizedBox(height: 18),
                        ],
                        if (_filteredEstimates.isNotEmpty) ...[
                          _SectionHeader(
                            title: 'Estimates',
                            count: _filteredEstimates.length,
                          ),
                          const SizedBox(height: 10),
                          ...List.generate(_filteredEstimates.length, (index) {
                            final estimate = _filteredEstimates[index];
                            final client = _clientsById[estimate.clientId];
                            final property = _propertiesById[estimate.propertyId];

                            return Padding(
                              padding: EdgeInsets.only(
                                bottom: index == _filteredEstimates.length - 1
                                    ? 0
                                    : 10,
                              ),
                              child: _SearchResultTile(
                                icon: CupertinoIcons.doc_text,
                                title: estimate.title.trim().isEmpty
                                    ? 'Untitled Estimate'
                                    : estimate.title,
                                subtitle: [
                                  estimate.estimateNumber,
                                  EstimateFormatters.formatStatus(estimate.status),
                                  client?.fullName ?? '',
                                  property?.fullAddress ?? '',
                                ].where((e) => e.trim().isNotEmpty).join(' • '),
                                trailingText: EstimateFormatters.formatCurrency(
                                  estimate.total,
                                ),
                                onTap: () => _openEstimate(estimate.id),
                              ),
                            );
                          }),
                          const SizedBox(height: 18),
                        ],
                        if (_filteredInvoices.isNotEmpty) ...[
                          _SectionHeader(
                            title: 'Invoices',
                            count: _filteredInvoices.length,
                          ),
                          const SizedBox(height: 10),
                          ...List.generate(_filteredInvoices.length, (index) {
                            final invoice = _filteredInvoices[index];
                            final client = _clientsById[invoice.clientId];
                            final property = _propertiesById[invoice.propertyId];

                            return Padding(
                              padding: EdgeInsets.only(
                                bottom: index == _filteredInvoices.length - 1
                                    ? 0
                                    : 10,
                              ),
                              child: _SearchResultTile(
                                icon: CupertinoIcons.doc_plaintext,
                                title: invoice.title.trim().isEmpty
                                    ? 'Untitled Invoice'
                                    : invoice.title,
                                subtitle: [
                                  invoice.invoiceNumber,
                                  _invoiceStatusLabel(invoice.status),
                                  client?.fullName ?? '',
                                  property?.fullAddress ?? '',
                                ].where((e) => e.trim().isNotEmpty).join(' • '),
                                trailingText: EstimateFormatters.formatCurrency(
                                  invoice.balanceDue,
                                ),
                                onTap: () => _openInvoice(invoice.id),
                              ),
                            );
                          }),
                        ],
                      ]),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  String _invoiceStatusLabel(String status) {
    switch (status) {
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
      case 'void':
        return 'Void';
      default:
        return 'Unknown';
    }
  }
}

class _SearchField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;

  const _SearchField({
    required this.controller,
    required this.hintText,
  });

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
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
  void didUpdateWidget(covariant _SearchField oldWidget) {
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
        autofocus: true,
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

class _TopSummaryCard extends StatelessWidget {
  final int totalResults;
  final int clientsCount;
  final int propertiesCount;
  final int estimatesCount;
  final int invoicesCount;

  const _TopSummaryCard({
    required this.totalResults,
    required this.clientsCount,
    required this.propertiesCount,
    required this.estimatesCount,
    required this.invoicesCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF15161C),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF262832)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  title: 'Results',
                  value: totalResults.toString(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStat(
                  title: 'Clients',
                  value: clientsCount.toString(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStat(
                  title: 'Properties',
                  value: propertiesCount.toString(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  title: 'Estimates',
                  value: estimatesCount.toString(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStat(
                  title: 'Invoices',
                  value: invoicesCount.toString(),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(child: SizedBox()),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String title;
  final String value;

  const _MiniStat({
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF23252E)),
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
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;

  const _SectionHeader({
    required this.title,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF101117),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFF23252E)),
          ),
          child: Text(
            count.toString(),
            style: const TextStyle(
              color: Color(0xFFB6BCD0),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? trailingText;
  final VoidCallback onTap;

  const _SearchResultTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailingText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final trailing = (trailingText ?? '').trim();

    return Material(
      color: const Color(0xFF15161C),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFF262832)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF101117),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: const Color(0xFFB6BCD0),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF8E93A6),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (trailing.isNotEmpty)
                    Text(
                      trailing,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  const SizedBox(height: 6),
                  const Icon(
                    CupertinoIcons.chevron_right,
                    color: Color(0xFF8E93A6),
                    size: 16,
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

class _InlineMessageState extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InlineMessageState({
    required this.icon,
    required this.text,
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
              Icon(icon, color: Colors.white, size: 30),
              const SizedBox(height: 18),
              Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}