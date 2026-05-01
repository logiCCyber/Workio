import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/ai_estimate_result_model.dart';
import '../models/estimate_item_model.dart';
import '../services/company_settings_service.dart';
import '../services/smart_estimate_service.dart';
import '../utils/estimate_calculator.dart';
import '../utils/estimate_formatters.dart';

import '../models/client_model.dart';
import '../models/property_model.dart';
import '../models/estimate_model.dart';

import '../services/client_service.dart';
import '../services/property_service.dart';
import '../services/estimate_service.dart';

import 'estimate_details_screen.dart';

class QuickQuoteScreen extends StatefulWidget {
  const QuickQuoteScreen({super.key});

  @override
  State<QuickQuoteScreen> createState() => _QuickQuoteScreenState();
}

class _QuickQuoteScreenState extends State<QuickQuoteScreen> {
  final TextEditingController _promptController = TextEditingController();

  bool _isLoading = true;
  bool _isGenerating = false;
  bool _isConverting = false;

  List<ClientModel> _clients = [];
  List<PropertyModel> _properties = [];

  ClientModel? _selectedClient;
  PropertyModel? _selectedProperty;

  AiEstimateResultModel? _result;

  double _taxRate = 0.13;
  String _taxLabel = 'Tax';
  String _currencyCode = 'CAD';

  @override
  void initState() {
    super.initState();
    _loadDefaults();
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _loadDefaults() async {
    try {
      final settings = await CompanySettingsService.getSettings();
      final clients = await ClientService.getClients();

      if (!mounted) return;

      final taxLabel = settings?.taxLabel.trim() ?? '';
      final currencyCode = settings?.currencyCode.trim() ?? '';

      setState(() {
        _taxRate = settings?.defaultTaxRate ?? 0.13;
        _taxLabel = taxLabel.isEmpty ? 'Tax' : taxLabel;
        _currencyCode = currencyCode.isEmpty ? 'CAD' : currencyCode.toUpperCase();
        _clients = clients;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showSnack('Failed to load quick quote data');
    }
  }

  EstimateTotals get _totals {
    return EstimateCalculator.calculateTotals(
      items: _result?.items ?? const <EstimateItemModel>[],
      taxRate: _taxRate,
      discountValue: 0,
      discountIsPercentage: false,
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _generateQuote() async {
    final prompt = _promptController.text.trim();

    if (prompt.isEmpty) {
      _showSnack('Describe the work first');
      return;
    }

    setState(() {
      _isGenerating = true;
      _result = null;
    });

    try {
      final result = await SmartEstimateService.generate(
        prompt: prompt,
        propertyCity: null,
        clientId: null,
        propertyId: null,
      );

      if (!mounted) return;

      setState(() {
        _result = result;
      });

      if (result.items.isEmpty) {
        _showSnack('No matching Price Rule found. Add one in Price Rules first.');
      }
    } catch (_) {
      if (!mounted) return;
      _showSnack('Failed to generate quick quote');
    } finally {
      if (!mounted) return;

      setState(() {
        _isGenerating = false;
      });
    }
  }

  void _clearQuote() {
    setState(() {
      _promptController.clear();
      _result = null;
    });
  }

  Future<void> _loadPropertiesForClient(ClientModel client) async {
    try {
      final properties = await PropertyService.getPropertiesByClient(client.id);

      if (!mounted) return;

      setState(() {
        _properties = properties;
      });
    } catch (_) {
      if (!mounted) return;
      _showSnack('Failed to load client properties');
    }
  }

  Future<ClientModel?> _pickClient() async {
    if (_clients.isEmpty) {
      _showSnack('Add at least one client first');
      return null;
    }

    return showModalBottomSheet<ClientModel>(
      context: context,
      backgroundColor: const Color(0xFF15161C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) {
        return _SelectionSheet<ClientModel>(
          title: 'Choose Client',
          items: _clients,
          itemLabel: (client) {
            final company = (client.companyName ?? '').trim();
            if (company.isNotEmpty) {
              return '${client.fullName} • $company';
            }
            return client.fullName;
          },
        );
      },
    );
  }

  Future<PropertyModel?> _pickProperty(ClientModel client) async {
    await _loadPropertiesForClient(client);

    if (!mounted) return null;

    if (_properties.isEmpty) {
      _showSnack('This client has no properties yet');
      return null;
    }

    return showModalBottomSheet<PropertyModel>(
      context: context,
      backgroundColor: const Color(0xFF15161C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) {
        return _SelectionSheet<PropertyModel>(
          title: 'Choose Property',
          items: _properties,
          itemLabel: (property) => property.fullAddress,
        );
      },
    );
  }

  Future<void> _openEstimateDetails(String estimateId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EstimateDetailsScreen(estimateId: estimateId),
      ),
    );
  }

  Future<void> _convertToEstimate() async {
    final result = _result;

    if (result == null || result.items.isEmpty) {
      _showSnack('Generate a quick quote first');
      return;
    }

    final client = await _pickClient();
    if (client == null) return;

    final property = await _pickProperty(client);
    if (property == null) return;

    setState(() {
      _isConverting = true;
      _selectedClient = client;
      _selectedProperty = property;
    });

    try {
      final title = (result.title ?? '').trim().isEmpty
          ? 'Quick Quote Estimate'
          : result.title!.trim();

      final estimate = EstimateModel(
        id: '',
        adminAuthId: '',
        clientId: client.id,
        propertyId: property.id,
        estimateNumber: '',
        title: title,
        status: 'draft',
        scopeText: (result.scope ?? '').trim(),
        notes: (result.notes ?? '').trim(),
        subtotal: 0,
        tax: 0,
        discount: 0,
        total: 0,
        validUntil: DateTime.now().add(const Duration(days: 14)),
        createdAt: null,
        updatedAt: null,
      );

      final created = await EstimateService.createEstimateWithItems(
        estimate: estimate,
        items: result.items,
        taxRate: _taxRate,
        discountValue: 0,
        discountIsPercentage: false,
      );

      if (!mounted) return;

      _showSnack('Estimate ${created.estimateNumber} created');

      await _openEstimateDetails(created.id);
    } catch (_) {
      if (!mounted) return;
      _showSnack('Failed to convert quote to estimate');
    } finally {
      if (!mounted) return;

      setState(() {
        _isConverting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF0B0B0F);
    final result = _result;
    final totals = _totals;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 20,
        title: const Text(
          'Quick Quote',
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
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
          children: [
            _SectionCard(
              title: 'Text Quick Quote',
              subtitle: 'Fast rough pricing using Price Rules',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Workio says: describe the job, quantity, materials, and urgency.',
                    style: TextStyle(
                      color: Color(0xFF8E93A6),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _PremiumTextField(
                    controller: _promptController,
                    label: 'Prompt',
                    hintText: 'Repair roof shingles, 120 sqft, urgent, materials included',
                    maxLines: 6,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: CupertinoButton(
                          color: const Color(0xFF5B8CFF),
                          borderRadius: BorderRadius.circular(16),
                          onPressed: _isGenerating ? null : _generateQuote,
                          child: _isGenerating
                              ? const CupertinoActivityIndicator(
                            color: Colors.white,
                          )
                              : const Text(
                            'Generate Quote',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        color: const Color(0xFF101117),
                        borderRadius: BorderRadius.circular(16),
                        onPressed: _isGenerating ? null : _clearQuote,
                        child: const Icon(
                          CupertinoIcons.clear,
                          color: Color(0xFFB6BCD0),
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (result == null)
              const _EmptyQuoteState()
            else ...[
              _QuickQuoteHero(
                total: EstimateFormatters.formatCurrency(totals.total),
                subtotal: EstimateFormatters.formatCurrency(totals.subtotal),
                taxLabel: _taxLabel,
                tax: EstimateFormatters.formatCurrency(totals.tax),
                currencyCode: _currencyCode,
                confidence: '${(result.confidence * 100).round()}%',
              ),
              const SizedBox(height: 14),

              _SectionCard(
                title: 'Price Breakdown',
                subtitle: 'Calculated from Price Rules',
                child: result.items.isEmpty
                    ? const _InlineEmptyState(
                  text: 'No quote items generated.',
                )
                    : Column(
                  children: List.generate(result.items.length, (index) {
                    final item = result.items[index];

                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: index == result.items.length - 1 ? 0 : 10,
                      ),
                      child: _QuickQuoteItemTile(item: item),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 14),

              _SectionCard(
                title: 'Totals',
                subtitle: 'Quick quote summary',
                child: Column(
                  children: [
                    _SummaryLine(
                      label: 'Subtotal',
                      value: EstimateFormatters.formatCurrency(totals.subtotal),
                    ),
                    const SizedBox(height: 10),
                    _SummaryLine(
                      label: _taxLabel,
                      value: EstimateFormatters.formatCurrency(totals.tax),
                    ),
                    const SizedBox(height: 10),
                    _SummaryLine(
                      label: 'Discount',
                      value: '- ${EstimateFormatters.formatCurrency(totals.discount)}',
                    ),
                    const SizedBox(height: 12),
                    const Divider(color: Color(0xFF262832), height: 1),
                    const SizedBox(height: 12),
                    _SummaryLine(
                      label: 'Estimated Total',
                      value: EstimateFormatters.formatCurrency(totals.total),
                      isEmphasized: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              _SectionCard(
                title: 'Next Step',
                subtitle: 'Create a full estimate only if the client agrees',
                child: SizedBox(
                  width: double.infinity,
                  child: CupertinoButton(
                    color: const Color(0xFF5B8CFF),
                    borderRadius: BorderRadius.circular(16),
                    onPressed: result.items.isEmpty || _isConverting
                        ? null
                        : _convertToEstimate,
                    child: _isConverting
                        ? const CupertinoActivityIndicator(color: Colors.white)
                        : const Text(
                      'Convert to Estimate',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _SectionCard({
    required this.title,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
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

class _PremiumTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hintText;
  final int maxLines;

  const _PremiumTextField({
    required this.controller,
    required this.label,
    required this.hintText,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF23252E)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF8E93A6),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              maxLines: maxLines,
              minLines: maxLines == 1 ? 1 : maxLines,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
              cursorColor: const Color(0xFF5B8CFF),
              decoration: InputDecoration(
                isDense: true,
                hintText: hintText,
                hintStyle: const TextStyle(
                  color: Color(0xFF697086),
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BigTotalBlock extends StatelessWidget {
  final String total;
  final String currencyCode;

  const _BigTotalBlock({
    required this.total,
    required this.currencyCode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF23252E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Estimated Total',
            style: TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            total,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            currencyCode,
            style: const TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickQuoteHero extends StatelessWidget {
  final String total;
  final String subtotal;
  final String taxLabel;
  final String tax;
  final String currencyCode;
  final String confidence;

  const _QuickQuoteHero({
    required this.total,
    required this.subtotal,
    required this.taxLabel,
    required this.tax,
    required this.currencyCode,
    required this.confidence,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1E2A4A),
            Color(0xFF15161C),
            Color(0xFF101117),
          ],
        ),
        border: Border.all(color: Color(0xFF2E5BFF)),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF5B8CFF).withOpacity(0.18),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quick Quote Total',
            style: TextStyle(
              color: Color(0xFFB6BCD0),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            total,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 38,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$currencyCode • rough price including tax',
            style: const TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _HeroMiniStat(
                  label: 'Subtotal',
                  value: subtotal,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeroMiniStat(
                  label: taxLabel,
                  value: tax,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeroMiniStat(
                  label: 'Confidence',
                  value: confidence,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroMiniStat extends StatelessWidget {
  final String label;
  final String value;

  const _HeroMiniStat({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewInfoBlock extends StatelessWidget {
  final String label;
  final String value;
  final bool multiline;

  const _PreviewInfoBlock({
    required this.label,
    required this.value,
    this.multiline = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF23252E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: multiline ? null : 2,
            overflow: multiline ? TextOverflow.visible : TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickQuoteItemTile extends StatelessWidget {
  final EstimateItemModel item;

  const _QuickQuoteItemTile({
    required this.item,
  });

  bool get _isMaterial {
    final text = '${item.title} ${item.description ?? ''}'.toLowerCase();
    return text.contains('material') ||
        text.contains('outlet') ||
        text.contains('fixture') ||
        text.contains('bulb') ||
        text.contains('wire') ||
        text.contains('pipe') ||
        text.contains('part');
  }

  bool get _isRush {
    final text = item.title.toLowerCase();
    return text.contains('rush') ||
        text.contains('expedited') ||
        text.contains('priority');
  }

  IconData get _icon {
    if (_isRush) return CupertinoIcons.bolt_fill;
    if (_isMaterial) return CupertinoIcons.cube_box_fill;
    return CupertinoIcons.hammer_fill;
  }

  String get _tag {
    if (_isRush) return 'Rush';
    if (_isMaterial) return 'Materials';
    return 'Labor';
  }

  @override
  Widget build(BuildContext context) {
    final lineTotal = item.lineTotal > 0
        ? item.lineTotal
        : EstimateCalculator.calculateLineTotal(
      quantity: item.quantity,
      unitPrice: item.unitPrice,
    );

    final qty = EstimateFormatters.formatQuantity(item.quantity);
    final unit = EstimateFormatters.formatUnit(item.unit);
    final unitPrice = EstimateFormatters.formatCurrency(item.unitPrice);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF23252E)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF5B8CFF).withOpacity(0.14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFF5B8CFF).withOpacity(0.22),
              ),
            ),
            child: Icon(
              _icon,
              color: const Color(0xFF8FB0FF),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '$_tag • $qty $unit × $unitPrice',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF8E93A6),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            EstimateFormatters.formatCurrency(lineTotal),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _EstimateItemTile extends StatelessWidget {
  final EstimateItemModel item;

  const _EstimateItemTile({
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    final lineTotal = item.lineTotal > 0
        ? item.lineTotal
        : EstimateCalculator.calculateLineTotal(
      quantity: item.quantity,
      unitPrice: item.unitPrice,
    );

    return Container(
      width: double.infinity,
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
            item.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          if ((item.description ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              item.description!,
              style: const TextStyle(
                color: Color(0xFF8E93A6),
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MiniInfo(
                  label: 'Qty',
                  value: EstimateFormatters.formatQuantity(item.quantity),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniInfo(
                  label: 'Unit',
                  value: EstimateFormatters.formatUnit(item.unit),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniInfo(
                  label: 'Unit Price',
                  value: EstimateFormatters.formatCurrency(item.unitPrice),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _MiniInfo(
            label: 'Line Total',
            value: EstimateFormatters.formatCurrency(lineTotal),
            emphasized: true,
          ),
        ],
      ),
    );
  }
}

class _MiniInfo extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasized;

  const _MiniInfo({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0E14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1F212A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: emphasized ? 15 : 13,
              fontWeight: emphasized ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  final String label;
  final String value;
  final bool isEmphasized;

  const _SummaryLine({
    required this.label,
    required this.value,
    this.isEmphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            color: isEmphasized ? Colors.white : const Color(0xFF8E93A6),
            fontSize: isEmphasized ? 16 : 14,
            fontWeight: isEmphasized ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontSize: isEmphasized ? 18 : 15,
            fontWeight: isEmphasized ? FontWeight.w800 : FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }
}

class _InlineEmptyState extends StatelessWidget {
  final String text;

  const _InlineEmptyState({
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF23252E)),
      ),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.info,
            color: Color(0xFF8E93A6),
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
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyQuoteState extends StatelessWidget {
  const _EmptyQuoteState();

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Quote Preview',
      subtitle: 'The generated quick quote will appear here',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF101117),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF23252E)),
        ),
        child: const Row(
          children: [
            Icon(
              CupertinoIcons.bolt,
              color: Color(0xFF8E93A6),
              size: 20,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Describe the work and Workio will calculate a fast rough quote.',
                style: TextStyle(
                  color: Color(0xFF8E93A6),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionSheet<T> extends StatelessWidget {
  final String title;
  final List<T> items;
  final String Function(T item) itemLabel;

  const _SelectionSheet({
    required this.title,
    required this.items,
    required this.itemLabel,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFF3A3D49),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = items[index];

                  return GestureDetector(
                    onTap: () => Navigator.pop(context, item),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF101117),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF23252E)),
                      ),
                      child: Text(
                        itemLabel(item),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}