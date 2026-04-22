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
      appBar: AppBar(
        backgroundColor: background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 20,
        title: const Text(
          'Property Details',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
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
                child: Column(
                  children: [
                    _PreviewInfoRow(
                      label: 'Address',
                      value: property.addressLine1,
                    ),
                    if (address2.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _PreviewInfoRow(
                        label: 'Address 2',
                        value: address2,
                      ),
                    ],
                    const SizedBox(height: 10),
                    _PreviewInfoRow(
                      label: 'City',
                      value: city.isEmpty ? '—' : city,
                    ),
                    const SizedBox(height: 10),
                    _PreviewInfoRow(
                      label: 'Province',
                      value: province.isEmpty ? '—' : province,
                    ),
                    const SizedBox(height: 10),
                    _PreviewInfoRow(
                      label: 'Postal Code',
                      value: postalCode.isEmpty ? '—' : postalCode,
                    ),
                    const SizedBox(height: 10),
                    _PreviewInfoRow(
                      label: 'Type',
                      value: propertyType.isEmpty ? '—' : propertyType,
                    ),
                    const SizedBox(height: 10),
                    _PreviewInfoRow(
                      label: 'Square Footage',
                      value: property.squareFootage > 0
                          ? property.squareFootage.toStringAsFixed(0)
                          : '—',
                    ),
                    if (notes.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _PreviewInfoRow(
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
                child: Column(
                  children: [
                    _PreviewInfoRow(
                      label: 'Name',
                      value: _client?.fullName ?? '—',
                    ),
                    const SizedBox(height: 10),
                    _PreviewInfoRow(
                      label: 'Company',
                      value: ((_client?.companyName ?? '').trim().isEmpty)
                          ? '—'
                          : _client!.companyName!,
                    ),
                    const SizedBox(height: 10),
                    _PreviewInfoRow(
                      label: 'Email',
                      value: ((_client?.email ?? '').trim().isEmpty)
                          ? '—'
                          : _client!.email!,
                    ),
                    const SizedBox(height: 10),
                    _PreviewInfoRow(
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
                            title: 'Estimates',
                            value: _estimates.length.toString(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _MiniStatCard(
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
                            title: 'Unpaid',
                            value: _unpaidInvoicesCount.toString(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _MiniMoneyCard(
                            title: 'Outstanding',
                            value: EstimateFormatters.formatCurrency(
                              _outstandingAmount,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _MiniMoneyWideCard(
                      title: 'Collected',
                      value: EstimateFormatters.formatCurrency(
                        _collectedAmount,
                      ),
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

  Widget _buildSectionCard({
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF15161C),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF262832)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          if ((subtitle ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: const TextStyle(
                color: Color(0xFF8E93A6),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _PreviewInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _PreviewInfoRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF23252E)),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
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
              fontSize: 24,
              fontWeight: FontWeight.w800,
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniMoneyWideCard extends StatelessWidget {
  final String title;
  final String value;

  const _MiniMoneyWideCard({
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 84,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF23252E)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Color(0xFF8E93A6),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
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
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF23252E)),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF23252E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  estimate.title.trim().isEmpty
                      ? 'Untitled Estimate'
                      : estimate.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _StatusBadge(
                label: EstimateFormatters.formatStatus(estimate.status),
                color: color,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${estimate.estimateNumber} • ${EstimateFormatters.formatShortDate(estimate.createdAt)}',
            style: const TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                EstimateFormatters.formatCurrency(estimate.total),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              _OpenButton(onTap: onOpen),
            ],
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF23252E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  invoice.title.trim().isEmpty
                      ? 'Untitled Invoice'
                      : invoice.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _StatusBadge(
                label: _statusLabel(invoice.status),
                color: color,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${invoice.invoiceNumber} • ${EstimateFormatters.formatShortDate(invoice.createdAt)}',
            style: const TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Due: ${EstimateFormatters.formatCurrency(invoice.balanceDue)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _OpenButton(onTap: onOpen),
            ],
          ),
        ],
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

class _OpenButton extends StatelessWidget {
  final VoidCallback onTap;

  const _OpenButton({
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0D0E14),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1F212A)),
          ),
          child: const Row(
            children: [
              Icon(
                CupertinoIcons.chevron_right,
                color: Color(0xFFB6BCD0),
                size: 16,
              ),
              SizedBox(width: 6),
              Text(
                'Open',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
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