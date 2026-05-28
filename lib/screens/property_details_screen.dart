import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/client_model.dart';
import '../models/estimate_model.dart';
import '../models/invoice_model.dart';
import '../models/property_model.dart';
import '../services/client_service.dart';
import '../services/estimate_service.dart';
import '../services/invoice_service.dart';
import '../utils/estimate_formatters.dart';
import 'estimate_details_screen.dart';
import 'invoice_details_screen.dart';

const _kPropertyAccent = Color(0xFF38BDF8);
const _kPropertyCard = Color(0xFF1F232C);
const _kPropertyPanel = Color(0xFF202530);
const _kPropertyPanelSoft = Color(0xFF1B2028);
const _kPropertyBorder = Color(0xFF3A4050);
const _kPropertyTextSoft = Color(0xFFA0A7B8);

class PropertyDetailsScreen extends StatefulWidget {
  final PropertyModel property;

  const PropertyDetailsScreen({
    super.key,
    required this.property,
  });

  @override
  State<PropertyDetailsScreen> createState() => _PropertyDetailsScreenState();
}

class _PropertyDetailsScreenState extends State<PropertyDetailsScreen> {
  bool _isLoading = true;

  ClientModel? _client;
  List<EstimateModel> _estimates = [];
  List<InvoiceModel> _invoices = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final results = await Future.wait([
        ClientService.getClients(),
        EstimateService.getEstimates(),
        InvoiceService.getInvoices(),
      ]);

      final clients = results[0] as List<ClientModel>;
      final allEstimates = results[1] as List<EstimateModel>;
      final allInvoices = results[2] as List<InvoiceModel>;

      ClientModel? client;
      for (final item in clients) {
        if (item.id == widget.property.clientId) {
          client = item;
          break;
        }
      }

      final estimates = allEstimates
          .where((e) => e.propertyId == widget.property.id)
          .toList()
        ..sort((a, b) {
          final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bDate.compareTo(aDate);
        });

      final invoices = allInvoices
          .where((e) => e.propertyId == widget.property.id)
          .toList()
        ..sort((a, b) {
          final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bDate.compareTo(aDate);
        });

      if (!mounted) return;

      setState(() {
        _client = client;
        _estimates = estimates;
        _invoices = invoices;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось загрузить данные объекта')),
      );
    }
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

  int get _unpaidInvoicesCount {
    return _invoices
        .where((e) => e.isDraft || e.isSent || e.isPartial || e.isOverdue)
        .length;
  }

  double get _outstandingAmount {
    double total = 0;

    for (final invoice in _invoices) {
      total += invoice.balanceDue;
    }

    return double.parse(total.toStringAsFixed(2));
  }

  double get _collectedAmount {
    double total = 0;

    for (final invoice in _invoices) {
      total += invoice.paidAmount;
    }

    return double.parse(total.toStringAsFixed(2));
  }

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF0B0B0F);
    final property = widget.property;

    final address2 = (property.addressLine2 ?? '').trim();
    final city = (property.city ?? '').trim();
    final province = (property.province ?? '').trim();
    final postalCode = (property.postalCode ?? '').trim();
    final propertyType = (property.propertyType ?? '').trim();
    final notes = (property.notes ?? '').trim();

    return Scaffold(
      backgroundColor: background,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(104),
        child: _PropertyDetailsTopBar(
          title: property.addressLine1,
          subtitle: [
            if (city.isNotEmpty) city,
            if (province.isNotEmpty) province,
          ].join(' • ').trim().isEmpty
              ? 'Property details'
              : [
            if (city.isNotEmpty) city,
            if (province.isNotEmpty) province,
          ].join(' • '),
          onBack: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: _isLoading
          ? const Center(
        child: CupertinoActivityIndicator(radius: 16),
      )
          : SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _loadData,
          color: const Color(0xFF5B8CFF),
          backgroundColor: const Color(0xFF15161C),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
            children: [
              _buildSectionCard(
                title: 'Property Info',
                subtitle: 'Основная информация об объекте',
                child: _formPanel(
                  children: [
                    _PreviewInfoRow(
                      icon: CupertinoIcons.location_solid,
                      label: 'Address',
                      value: property.addressLine1,
                    ),
                    if (address2.isNotEmpty) ...[
                      const Divider(color: Color(0xFF23252E), height: 1),
                      _PreviewInfoRow(
                        icon: CupertinoIcons.location,
                        label: 'Address 2',
                        value: address2,
                      ),
                    ],
                    const Divider(color: Color(0xFF23252E), height: 1),
                    _PreviewInfoRow(
                      icon: CupertinoIcons.building_2_fill,
                      label: 'City',
                      value: city.isEmpty ? '—' : city,
                    ),
                    const Divider(color: Color(0xFF23252E), height: 1),
                    _PreviewInfoRow(
                      icon: CupertinoIcons.map,
                      label: 'Province',
                      value: province.isEmpty ? '—' : province,
                    ),
                    const Divider(color: Color(0xFF23252E), height: 1),
                    _PreviewInfoRow(
                      icon: CupertinoIcons.number,
                      label: 'Postal Code',
                      value: postalCode.isEmpty ? '—' : postalCode,
                    ),
                    const Divider(color: Color(0xFF23252E), height: 1),
                    _PreviewInfoRow(
                      icon: CupertinoIcons.house_fill,
                      label: 'Type',
                      value: propertyType.isEmpty ? '—' : propertyType,
                    ),
                    const Divider(color: Color(0xFF23252E), height: 1),
                    _PreviewInfoRow(
                      icon: CupertinoIcons.square_grid_2x2,
                      label: 'Square Footage',
                      value: property.squareFootage > 0
                          ? property.squareFootage.toStringAsFixed(0)
                          : '—',
                    ),
                    if (notes.isNotEmpty) ...[
                      const Divider(color: Color(0xFF23252E), height: 1),
                      _PreviewInfoRow(
                        icon: CupertinoIcons.text_alignleft,
                        label: 'Notes',
                        value: notes,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _buildSectionCard(
                title: 'Client',
                subtitle: 'Кому принадлежит объект',
                child: _formPanel(
                  children: [
                    _PreviewInfoRow(
                      icon: CupertinoIcons.person_crop_circle,
                      label: 'Name',
                      value: _client?.fullName ?? '—',
                    ),
                    const Divider(color: Color(0xFF23252E), height: 1),
                    _PreviewInfoRow(
                      icon: CupertinoIcons.building_2_fill,
                      label: 'Company',
                      value: ((_client?.companyName ?? '').trim().isEmpty)
                          ? '—'
                          : _client!.companyName!,
                    ),
                    const Divider(color: Color(0xFF23252E), height: 1),
                    _PreviewInfoRow(
                      icon: CupertinoIcons.mail,
                      label: 'Email',
                      value: ((_client?.email ?? '').trim().isEmpty)
                          ? '—'
                          : _client!.email!,
                    ),
                    const Divider(color: Color(0xFF23252E), height: 1),
                    _PreviewInfoRow(
                      icon: CupertinoIcons.phone,
                      label: 'Phone',
                      value: ((_client?.phone ?? '').trim().isEmpty)
                          ? '—'
                          : _client!.phone!,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _buildSectionCard(
                title: 'Summary',
                subtitle: 'Быстрый обзор по объекту',
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _MiniStatCard(
                            icon: CupertinoIcons.doc_text_fill,
                            title: 'Estimates',
                            value: _estimates.length.toString(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _MiniStatCard(
                            icon: CupertinoIcons.doc_plaintext,
                            title: 'Invoices',
                            value: _invoices.length.toString(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _MiniStatCard(
                            icon: CupertinoIcons.clock_fill,
                            title: 'Unpaid',
                            value: _unpaidInvoicesCount.toString(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _MiniMoneyCard(
                            icon: CupertinoIcons.money_dollar_circle_fill,
                            title: 'Outstanding',
                            value: EstimateFormatters.formatCurrency(_outstandingAmount),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _MiniMoneyWideCard(
                      icon: CupertinoIcons.chart_bar_fill,
                      title: 'Collected',
                      value: EstimateFormatters.formatCurrency(_collectedAmount),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _buildSectionCard(
                title: 'Estimates',
                subtitle: 'Все estimates по этому объекту',
                child: _estimates.isEmpty
                    ? const _EmptyInlineState(
                  icon: CupertinoIcons.doc_text,
                  text: 'По этому объекту пока нет estimates.',
                )
                    : Column(
                  children: List.generate(_estimates.length, (index) {
                    final estimate = _estimates[index];

                    return Padding(
                      padding: EdgeInsets.only(
                        bottom:
                        index == _estimates.length - 1 ? 0 : 10,
                      ),
                      child: _EstimateTile(
                        estimate: estimate,
                        onOpen: () => _openEstimate(estimate.id),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 14),
              _buildSectionCard(
                title: 'Invoices',
                subtitle: 'Все invoices по этому объекту',
                child: _invoices.isEmpty
                    ? const _EmptyInlineState(
                  icon: CupertinoIcons.doc_plaintext,
                  text: 'По этому объекту пока нет invoices.',
                )
                    : Column(
                  children: List.generate(_invoices.length, (index) {
                    final invoice = _invoices[index];

                    return Padding(
                      padding: EdgeInsets.only(
                        bottom:
                        index == _invoices.length - 1 ? 0 : 10,
                      ),
                      child: _InvoiceTile(
                        invoice: invoice,
                        onOpen: () => _openInvoice(invoice.id),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _formPanel({
    required List<Widget> children,
  }) {
    return Column(
      children: children,
    );
  }

  Widget _buildSectionCard({
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    final cleanSubtitle = (subtitle ?? '').trim();

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        color: _kPropertyCard,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: _kPropertyBorder,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.34),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.025),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFF4F6FA),
              fontSize: 21,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.25,
              height: 1.0,
            ),
          ),
          if (cleanSubtitle.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              cleanSubtitle,
              style: const TextStyle(
                color: _kPropertyTextSoft,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
            ),
          ],
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _PropertyDetailsTopBar extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onBack;

  const _PropertyDetailsTopBar({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Container(
          height: 82,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: _kPropertyCard,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: _kPropertyBorder,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.42),
                blurRadius: 30,
                offset: const Offset(0, 16),
              ),
              BoxShadow(
                color: Colors.white.withOpacity(0.035),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              CupertinoButton(
                padding: EdgeInsets.zero,
                minSize: 0,
                onPressed: onBack,
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: _kPropertyPanel,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _kPropertyBorder),
                  ),
                  child: const Icon(
                    CupertinoIcons.chevron_left,
                    color: Color(0xFFF3F6FC),
                    size: 25,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFF4F6FA),
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.25,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _kPropertyTextSoft,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(
                CupertinoIcons.house_fill,
                color: _kPropertyAccent,
                size: 23,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _PreviewInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final isEmpty = value.trim() == '—';

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(
        minHeight: label == 'Notes' ? 88 : 66,
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: _kPropertyPanelSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _kPropertyBorder,
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 26,
            child: Icon(
              icon,
              color: const Color(0xFF9AA3B7),
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _kPropertyTextSoft,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  maxLines: label == 'Notes' ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isEmpty
                        ? const Color(0xFF697086)
                        : const Color(0xFFF3F6FC),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                    letterSpacing: -0.05,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _MiniStatCard({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 88,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kPropertyPanelSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kPropertyBorder),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: Icon(
              icon,
              color: const Color(0xFF8E93A6),
              size: 17,
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _kPropertyTextSoft,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  value,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFF3F6FC),
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniMoneyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _MiniMoneyCard({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 88,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kPropertyPanelSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kPropertyBorder),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: Icon(
              icon,
              color: const Color(0xFF8E93A6),
              size: 17,
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _kPropertyTextSoft,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  value,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFF3F6FC),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniMoneyWideCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _MiniMoneyWideCard({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: _kPropertyPanelSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kPropertyBorder),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: const Color(0xFF8E93A6),
            size: 17,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: _kPropertyTextSoft,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFFF3F6FC),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyInlineState extends StatelessWidget {
  final IconData icon;
  final String text;

  const _EmptyInlineState({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _kPropertyPanelSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kPropertyBorder),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: const Color(0xFF8E93A6),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF8E93A6),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EstimateTile extends StatelessWidget {
  final EstimateModel estimate;
  final VoidCallback onOpen;

  const _EstimateTile({
    required this.estimate,
    required this.onOpen,
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
    final color = _statusColor(estimate.status);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kPropertyPanelSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _kPropertyBorder,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.025),
            blurRadius: 6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: Icon(
              CupertinoIcons.doc_text,
              color: Color(0xFF9AA3B7),
              size: 18,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _DocInfoBlock(
                        label: 'Title',
                        value: estimate.title.trim().isEmpty
                            ? 'Untitled Estimate'
                            : estimate.title.trim(),
                        valueMaxLines: 2,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _StatusBadge(
                      label: EstimateFormatters.formatStatus(estimate.status),
                      color: color,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _DocInfoBlock(
                        label: 'Estimate ID',
                        value: estimate.estimateNumber,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _DocInfoBlock(
                        label: 'Date',
                        value: EstimateFormatters.formatShortDate(
                          estimate.createdAt,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(
                  color: Color(0xFF343A49),
                  height: 1,
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: _DocInfoBlock(
                        label: 'Total',
                        value: EstimateFormatters.formatCurrency(
                          estimate.total,
                        ),
                      ),
                    ),
                    _OpenButton(onTap: onOpen),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceTile extends StatelessWidget {
  final InvoiceModel invoice;
  final VoidCallback onOpen;

  const _InvoiceTile({
    required this.invoice,
    required this.onOpen,
  });

  Color _statusColor(String status) {
    switch (status) {
      case 'draft':
        return const Color(0xFF8F96AB);
      case 'sent':
        return const Color(0xFF4A90E2);
      case 'partial':
        return const Color(0xFFE6A23C);
      case 'paid':
        return const Color(0xFF33C27F);
      case 'overdue':
        return const Color(0xFFE05A5A);
      case 'void':
        return const Color(0xFF6C7283);
      default:
        return const Color(0xFF8F96AB);
    }
  }

  String _statusLabel(String status) {
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

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(invoice.status);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kPropertyPanelSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _kPropertyBorder,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.025),
            blurRadius: 6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: Icon(
              CupertinoIcons.doc_plaintext,
              color: Color(0xFF9AA3B7),
              size: 18,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _DocInfoBlock(
                        label: 'Title',
                        value: invoice.title.trim().isEmpty
                            ? 'Untitled Invoice'
                            : invoice.title.trim(),
                        valueMaxLines: 2,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _StatusBadge(
                      label: _statusLabel(invoice.status),
                      color: color,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _DocInfoBlock(
                        label: 'Invoice ID',
                        value: invoice.invoiceNumber,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _DocInfoBlock(
                        label: 'Date',
                        value: EstimateFormatters.formatShortDate(
                          invoice.createdAt,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(
                  color: Color(0xFF343A49),
                  height: 1,
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: _DocInfoBlock(
                        label: 'Due',
                        value: EstimateFormatters.formatCurrency(
                          invoice.balanceDue,
                        ),
                      ),
                    ),
                    _OpenButton(onTap: onOpen),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DocInfoBlock extends StatelessWidget {
  final String label;
  final String value;
  final int valueMaxLines;

  const _DocInfoBlock({
    required this.label,
    required this.value,
    this.valueMaxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _kPropertyTextSoft,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          maxLines: valueMaxLines,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFFF3F6FC),
            fontSize: 13.4,
            fontWeight: FontWeight.w700,
            height: 1.22,
            letterSpacing: -0.05,
          ),
        ),
      ],
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
      height: 26,
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
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _OpenButton extends StatelessWidget {
  final VoidCallback onTap;

  const _OpenButton({
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minSize: 0,
      onPressed: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: _kPropertyPanel,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: _kPropertyBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.28),
              blurRadius: 12,
              offset: const Offset(0, 7),
            ),
            BoxShadow(
              color: Colors.white.withOpacity(0.035),
              blurRadius: 6,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.chevron_right,
              color: Color(0xFFD6DCE8),
              size: 16,
            ),
            SizedBox(width: 7),
            Text(
              'Open',
              style: TextStyle(
                color: Color(0xFFF3F6FC),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}