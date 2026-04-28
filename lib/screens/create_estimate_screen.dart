import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/client_model.dart';
import '../models/estimate_item_model.dart';
import '../models/estimate_model.dart';
import '../models/property_model.dart';
import '../models/estimate_template_model.dart';
import '../models/company_settings_model.dart';

import '../services/client_service.dart';
import '../services/estimate_service.dart';
import '../services/property_service.dart';
import '../services/company_settings_service.dart';
import '../services/estimate_template_service.dart';

import '../utils/estimate_calculator.dart';
import '../utils/estimate_formatters.dart';

import '../dialogs/add_client_dialog.dart';
import '../dialogs/add_property_dialog.dart';

class CreateEstimateScreen extends StatefulWidget {
  const CreateEstimateScreen({super.key});

  @override
  State<CreateEstimateScreen> createState() => _CreateEstimateScreenState();
}

class _CreateEstimateScreenState extends State<CreateEstimateScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _scopeController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;

  List<ClientModel> _clients = [];
  List<PropertyModel> _properties = [];
  List<EstimateItemModel> _items = [];
  List<EstimateTemplateModel> _templates = [];

  EstimateTemplateModel? _selectedTemplate;
  CompanySettingsModel? _companySettings;

  ClientModel? _selectedClient;
  PropertyModel? _selectedProperty;

  DateTime? _validUntil = DateTime.now().add(const Duration(days: 14));

  double _taxRate = 0.13;
  double _discountValue = 0;
  bool _discountIsPercentage = false;

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _scopeController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _addNewProperty() async {
    final client = _selectedClient;

    if (client == null) {
      _showSnack('Select a client first');
      return;
    }

    final created = await showAddPropertyDialog(
      context,
      clientId: client.id,
    );

    if (created == null) return;

    await _loadPropertiesForClient(client.id);

    if (!mounted) return;

    setState(() {
      _selectedProperty = created;
    });

    _maybeAutoFillTitle();
    _showSnack('Property created');
  }

  Future<void> _addNewClient() async {
    final created = await showAddClientDialog(context);

    if (created == null) return;

    await _loadClients();

    if (!mounted) return;

    setState(() {
      _selectedClient = created;
      _selectedProperty = null;
      _properties = [];
    });

    await _loadPropertiesForClient(created.id);

    _showSnack('Client created');
  }

  Future<void> _loadClients() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final results = await Future.wait([
        ClientService.getClients(),
        CompanySettingsService.getSettings(),
        EstimateTemplateService.getTemplates(),
      ]);

      final clients = results[0] as List<ClientModel>;
      final companySettings = results[1] as CompanySettingsModel?;
      final templates = results[2] as List<EstimateTemplateModel>;

      if (!mounted) return;

      setState(() {
        _clients = clients;
        _templates = templates;
        _companySettings = companySettings;
        _taxRate = companySettings?.defaultTaxRate ?? 0.13;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showSnack('Failed to load clients');
    }
  }

  Future<void> _loadPropertiesForClient(String clientId) async {
    setState(() {
      _isLoading = true;
      _properties = [];
      _selectedProperty = null;
    });

    try {
      final properties = await PropertyService.getPropertiesByClient(clientId);

      if (!mounted) return;

      setState(() {
        _properties = properties;
        _isLoading = false;
      });

      if (properties.isNotEmpty) {
        setState(() {
          _selectedProperty = properties.first;
        });
        _maybeAutoFillTitle();
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showSnack('Failed to load client properties');
    }
  }

  String get _taxLabel {
    final value = _companySettings?.taxLabel.trim() ?? '';
    return value.isEmpty ? 'Tax' : value;
  }

  String get _currencyCode {
    final value = _companySettings?.currencyCode.trim() ?? '';
    return value.isEmpty ? 'CAD' : value.toUpperCase();
  }

  void _maybeAutoFillTitle() {
    if (_titleController.text.trim().isNotEmpty) return;

    final property = _selectedProperty;
    if (property == null) return;

    _titleController.text = EstimateFormatters.buildEstimateTitle(
      serviceType: 'Estimate',
      city: property.city,
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  EstimateTotals get _totals {
    return EstimateCalculator.calculateTotals(
      items: _items,
      taxRate: _taxRate,
      discountValue: _discountValue,
      discountIsPercentage: _discountIsPercentage,
    );
  }

  Future<void> _pickValidUntil() async {
    final initialDate = _validUntil ?? DateTime.now().add(const Duration(days: 14));

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            scaffoldBackgroundColor: const Color(0xFF0B0B0F),
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF5B8CFF),
              surface: Color(0xFF15161C),
            ),
            dialogBackgroundColor: const Color(0xFF15161C),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) return;

    setState(() {
      _validUntil = picked;
    });
  }

  Future<void> _selectClient() async {
    if (_clients.isEmpty) {
      _showSnack('Add at least one client first');
      return;
    }

    final selected = await showModalBottomSheet<ClientModel>(
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

    if (selected == null) return;

    setState(() {
      _selectedClient = selected;
      _selectedProperty = null;
      _properties = [];
    });

    await _loadPropertiesForClient(selected.id);
  }

  Future<void> _selectProperty() async {
    if (_selectedClient == null) {
      _showSnack('Select a client first');
      return;
    }

    if (_properties.isEmpty) {
      _showSnack('This client has no properties yet');
      return;
    }

    final selected = await showModalBottomSheet<PropertyModel>(
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

    if (selected == null) return;

    setState(() {
      _selectedProperty = selected;
    });

    _maybeAutoFillTitle();
  }

  void _applyTemplate(EstimateTemplateModel template) {
    setState(() {
      _selectedTemplate = template;
      _titleController.text = template.name;
      _scopeController.text = template.defaultScopeText ?? '';
      _notesController.text = template.defaultNotes ?? '';
    });
  }

  Future<void> _selectTemplate() async {
    if (_templates.isEmpty) {
      _showSnack('No templates yet');
      return;
    }

    final selected = await showModalBottomSheet<EstimateTemplateModel>(
      context: context,
      backgroundColor: const Color(0xFF15161C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) {
        return _SelectionSheet<EstimateTemplateModel>(
          title: 'Choose Template',
          items: _templates,
          itemLabel: (template) => template.name,
        );
      },
    );

    if (selected == null) return;

    _applyTemplate(selected);
  }

  Future<void> _showDiscountEditor() async {
    final valueController = TextEditingController(
      text: _discountValue == 0 ? '' : _discountValue.toString(),
    );

    bool isPercent = _discountIsPercentage;

    final result = await showModalBottomSheet<_DiscountResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF15161C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Discount',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _PremiumTextField(
                    controller: valueController,
                    label: 'Discount value',
                    hintText: '0',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _ChoiceButton(
                          label: 'Fixed',
                          selected: !isPercent,
                          onTap: () => setModalState(() => isPercent = false),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ChoiceButton(
                          label: 'Percent',
                          selected: isPercent,
                          onTap: () => setModalState(() => isPercent = true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: CupertinoButton(
                      color: const Color(0xFF5B8CFF),
                      borderRadius: BorderRadius.circular(16),
                      onPressed: () {
                        final value = EstimateCalculator.parseNumber(valueController.text);
                        Navigator.pop(
                          context,
                          _DiscountResult(
                            value: value,
                            isPercentage: isPercent,
                          ),
                        );
                      },
                      child: const Text(
                        'Apply',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (result == null) return;

    setState(() {
      _discountValue = result.value;
      _discountIsPercentage = result.isPercentage;
    });
  }

  Future<void> _showTaxEditor() async {
    final valueController = TextEditingController(
      text: (_taxRate * 100).toStringAsFixed(2),
    );

    final value = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF15161C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Tax Rate %',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _PremiumTextField(
                controller: valueController,
                label: 'Tax percent',
                hintText: '13',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  color: const Color(0xFF5B8CFF),
                  borderRadius: BorderRadius.circular(16),
                  onPressed: () {
                    final percent = EstimateCalculator.parseNumber(valueController.text);
                    Navigator.pop(context, percent / 100);
                  },
                  child: const Text(
                    'Apply',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (value == null) return;

    setState(() {
      _taxRate = value;
    });
  }

  Future<void> _addOrEditItem({EstimateItemModel? existingItem, int? index}) async {
    final result = await Navigator.push<EstimateItemModel>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _AddEditItemPage(
          existingItem: existingItem,
          index: index,
          itemsLength: _items.length,
        ),
      ),
    );

    if (result == null) return;

    setState(() {
      if (index != null) {
        _items[index] = result;
      } else {
        _items.add(result);
      }
    });
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
      _items = _items
          .asMap()
          .entries
          .map(
            (entry) => entry.value.copyWith(sortOrder: entry.key),
      )
          .toList();
    });
  }

  Future<void> _saveEstimate() async {
    if (_selectedClient == null) {
      _showSnack('Select a client');
      return;
    }

    if (_selectedProperty == null) {
      _showSnack('Select a property');
      return;
    }

    if (_titleController.text.trim().isEmpty) {
      _showSnack('Enter an estimate title');
      return;
    }

    if (_items.isEmpty) {
      _showSnack('Add at least one item');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final estimate = EstimateModel(
        id: '',
        adminAuthId: '',
        clientId: _selectedClient!.id,
        propertyId: _selectedProperty!.id,
        estimateNumber: '',
        title: _titleController.text.trim(),
        status: 'draft',
        scopeText: _scopeController.text.trim().isEmpty
            ? null
            : _scopeController.text.trim(),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        subtotal: 0,
        tax: 0,
        discount: 0,
        total: 0,
        validUntil: _validUntil,
        createdAt: null,
        updatedAt: null,
      );

      final created = await EstimateService.createEstimateWithItems(
        estimate: estimate,
        items: _items,
        taxRate: _taxRate,
        discountValue: _discountValue,
        discountIsPercentage: _discountIsPercentage,
      );

      if (!mounted) return;

      _showSnack('Estimate ${created.estimateNumber} saved');

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to save estimate');
    } finally {
      if (!mounted) return;

      setState(() {
        _isSaving = false;
      });
    }
  }

  Widget _buildSectionCard({
    required String title,
    String? subtitle,
    required Widget child,
    Widget? trailing,
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
          Row(
            children: [
              Expanded(
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
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF0B0B0F);
    final totals = _totals;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 20,
        title: const Text(
          'New Estimate',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: const Color(0xFF5B8CFF),
              borderRadius: BorderRadius.circular(14),
              onPressed: _isSaving ? null : _saveEstimate,
              child: _isSaving
                  ? const CupertinoActivityIndicator(color: Colors.white)
                  : const Text(
                'Save',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
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
            _PremiumPickerField(
              label: 'Client',
              value: _selectedClient == null
                  ? 'Select client'
                  : _selectedClient!.fullName,
              onTap: _selectClient,
              showClearButton: _selectedClient != null,
              onClear: () {
                setState(() {
                  _selectedClient = null;
                  _selectedProperty = null;
                  _properties = [];
                });
              },
              emptyIcon: CupertinoIcons.add,
              onEmptyIconTap: _addNewClient,
            ),
            const SizedBox(height: 12),
            _PremiumPickerField(
              label: 'Property',
              value: _selectedProperty == null
                  ? 'Select property'
                  : _selectedProperty!.fullAddress,
              onTap: _selectProperty,
              showClearButton: _selectedProperty != null,
              onClear: () {
                setState(() {
                  _selectedProperty = null;
                });
              },
              emptyIcon: CupertinoIcons.add,
              onEmptyIconTap: _addNewProperty,
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'Estimate Info',
              subtitle: 'Main estimate information',
              child: Column(
                children: [
                  _PremiumPickerField(
                    label: 'Template',
                    value: _selectedTemplate == null
                        ? 'Select template'
                        : _selectedTemplate!.name,
                    onTap: _selectTemplate,
                    showClearButton: _selectedTemplate != null,
                    onClear: () {
                      setState(() {
                        _selectedTemplate = null;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  _PremiumTextField(
                    controller: _titleController,
                    label: 'Title',
                    hintText: 'Service Estimate • City',
                  ),
                  const SizedBox(height: 12),
                  _PremiumPickerField(
                    label: 'Valid Until',
                    value: EstimateFormatters.formatDate(_validUntil),
                    onTap: _pickValidUntil,
                    showClearButton: _validUntil != null,
                    onClear: () {
                      setState(() {
                        _validUntil = null;
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'Scope of Work',
              subtitle: 'Scope of work description',
              child: _PremiumTextField(
                controller: _scopeController,
                label: 'Scope',
                hintText: 'Describe the work scope, included tasks, exclusions, and cleanup...',
                maxLines: 6,
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'Items',
              subtitle: 'Estimate line items',
              trailing: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => _addOrEditItem(),
                child: const Icon(
                  CupertinoIcons.add_circled_solid,
                  color: Color(0xFF5B8CFF),
                  size: 24,
                ),
              ),
              child: _items.isEmpty
                  ? const _InlineEmptyItemsState()
                  : Column(
                children: List.generate(_items.length, (index) {
                  final item = _items[index];

                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: index == _items.length - 1 ? 0 : 10,
                    ),
                    child: _EstimateItemTile(
                      item: item,
                      onEdit: () => _addOrEditItem(
                        existingItem: item,
                        index: index,
                      ),
                      onDelete: () => _removeItem(index),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'Notes',
              subtitle: 'Additional notes for the client',
              child: _PremiumTextField(
                controller: _notesController,
                label: 'Notes',
                hintText:
                'Materials included. Final color selection by client. Additional repairs not included...',
                maxLines: 5,
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'Totals',
              subtitle: 'Tax, discount, and total amount',
              child: Column(
                children: [
                  _TotalsActionRow(
                    label: '$_taxLabel Rate',
                    value: '${(_taxRate * 100).toStringAsFixed(2)}% ($_currencyCode)',
                    onTap: _showTaxEditor,
                  ),
                  const SizedBox(height: 10),
                  _TotalsActionRow(
                    label: 'Discount',
                    value: _discountValue <= 0
                        ? 'None'
                        : _discountIsPercentage
                        ? '${_discountValue.toStringAsFixed(2)}%'
                        : EstimateFormatters.formatCurrency(_discountValue),
                    onTap: _showDiscountEditor,
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: Color(0xFF262832), height: 1),
                  const SizedBox(height: 16),
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
                    label: 'Total',
                    value: EstimateFormatters.formatCurrency(totals.total),
                    isEmphasized: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'Company Defaults',
              subtitle: 'Auto-filled from company settings',
              child: Column(
                children: [
                  _PreviewInfoRow(
                    label: 'Tax Label',
                    value: _taxLabel,
                  ),
                  const SizedBox(height: 10),
                  _PreviewInfoRow(
                    label: 'Default Rate',
                    value: '${(_taxRate * 100).toStringAsFixed(2)}%',
                  ),
                  const SizedBox(height: 10),
                  _PreviewInfoRow(
                    label: 'Currency',
                    value: _currencyCode,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            CupertinoButton(
              color: const Color(0xFF5B8CFF),
              borderRadius: BorderRadius.circular(18),
              padding: const EdgeInsets.symmetric(vertical: 16),
              onPressed: _isSaving ? null : _saveEstimate,
              child: _isSaving
                  ? const CupertinoActivityIndicator(color: Colors.white)
                  : const Text(
                'Save Draft Estimate',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hintText;
  final int maxLines;
  final TextInputType? keyboardType;

  const _PremiumTextField({
    required this.controller,
    required this.label,
    required this.hintText,
    this.maxLines = 1,
    this.keyboardType,
  });

  @override
  State<_PremiumTextField> createState() => _PremiumTextFieldState();
}

class _PremiumTextFieldState extends State<_PremiumTextField> {
  late final FocusNode _focusNode;

  bool get _showClearButton =>
      widget.maxLines == 1 &&
          _focusNode.hasFocus &&
          widget.controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_refresh);
    widget.controller.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant _PremiumTextField oldWidget) {
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
    final isSingleLine = widget.maxLines == 1;

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
              widget.label,
              style: const TextStyle(
                color: Color(0xFF8E93A6),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment:
              isSingleLine ? CrossAxisAlignment.center : CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focusNode,
                    keyboardType: widget.keyboardType,
                    maxLines: widget.maxLines,
                    minLines: isSingleLine ? 1 : widget.maxLines,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                    cursorColor: const Color(0xFF5B8CFF),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: widget.hintText,
                      hintStyle: const TextStyle(
                        color: Color(0xFF697086),
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                if (_showClearButton) ...[
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _clearText,
                    child: const Icon(
                      CupertinoIcons.xmark_circle_fill,
                      color: Color(0xFF8E93A6),
                      size: 18,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumInitialTextField extends StatelessWidget {
  final String initialValue;
  final String label;
  final String hintText;
  final int maxLines;
  final TextInputType? keyboardType;
  final ValueChanged<String> onChanged;

  const _PremiumInitialTextField({
    required this.initialValue,
    required this.label,
    required this.hintText,
    required this.onChanged,
    this.maxLines = 1,
    this.keyboardType,
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
            TextFormField(
              initialValue: initialValue,
              keyboardType: keyboardType,
              maxLines: maxLines,
              minLines: maxLines == 1 ? 1 : maxLines,
              onChanged: onChanged,
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

class _PremiumPickerField extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  final bool showClearButton;
  final IconData? emptyIcon;
  final VoidCallback? onEmptyIconTap;

  const _PremiumPickerField({
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
    this.showClearButton = false,
    this.emptyIcon,
    this.onEmptyIconTap,
  });

  @override
  Widget build(BuildContext context) {
    final isPlaceholder =
        value.startsWith('Select') || value.trim().isEmpty || value == '—';

    return Material(
      color: const Color(0xFF101117),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF23252E)),
          ),
          child: Row(
            children: [
              Expanded(
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
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isPlaceholder
                            ? const Color(0xFF697086)
                            : Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (showClearButton && onClear != null)
                GestureDetector(
                  onTap: onClear,
                  child: const Icon(
                    CupertinoIcons.xmark_circle_fill,
                    color: Color(0xFF8E93A6),
                    size: 18,
                  ),
                )
              else if (emptyIcon != null && onEmptyIconTap != null)
                GestureDetector(
                  onTap: onEmptyIconTap,
                  child: Icon(
                    emptyIcon,
                    color: const Color(0xFF8E93A6),
                    size: 18,
                  ),
                )
              else
                const Icon(
                  CupertinoIcons.chevron_down,
                  color: Color(0xFF8E93A6),
                  size: 18,
                ),
            ],
          ),
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
      child: SizedBox(
        height: 420,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFF3A3D49),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            const Divider(color: Color(0xFF262832), height: 1),
            Expanded(
              child: items.isEmpty
                  ? const Center(
                child: Text(
                  'Empty',
                  style: TextStyle(
                    color: Color(0xFF8E93A6),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              )
                  : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = items[index];

                  return Material(
                    color: const Color(0xFF101117),
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => Navigator.pop(context, item),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: const Color(0xFF23252E),
                          ),
                        ),
                        child: Text(
                          itemLabel(item),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
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

class _InlineEmptyItemsState extends StatelessWidget {
  const _InlineEmptyItemsState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF23252E)),
      ),
      child: const Row(
        children: [
          Icon(
            CupertinoIcons.square_list,
            color: Color(0xFF8E93A6),
            size: 20,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'No items yet. Add your first line item.',
              style: TextStyle(
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

class _EstimateItemTile extends StatelessWidget {
  final EstimateItemModel item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _EstimateItemTile({
    required this.item,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
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
                  item.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _SmallIconButton(
                icon: CupertinoIcons.pencil,
                onTap: onEdit,
              ),
              const SizedBox(width: 8),
              _SmallIconButton(
                icon: CupertinoIcons.trash,
                onTap: onDelete,
                color: const Color(0xFFE05A5A),
              ),
            ],
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
          const SizedBox(height: 10),
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
            value: EstimateFormatters.formatCurrency(item.lineTotal),
            emphasized: true,
          ),
        ],
      ),
    );
  }
}

class _SmallIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  const _SmallIconButton({
    required this.icon,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? const Color(0xFFB6BCD0);

    return Material(
      color: const Color(0xFF171922),
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
          child: Icon(
            icon,
            size: 16,
            color: effectiveColor,
          ),
        ),
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

class _TotalsActionRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _TotalsActionRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF101117),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF23252E)),
          ),
          child: Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                value,
                style: const TextStyle(
                  color: Color(0xFF8E93A6),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                CupertinoIcons.chevron_right,
                color: Color(0xFF8E93A6),
                size: 16,
              ),
            ],
          ),
        ),
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

class _ChoiceButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFF5B8CFF) : const Color(0xFF101117),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? const Color(0xFF5B8CFF)
                  : const Color(0xFF23252E),
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFFB6BCD0),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DiscountResult {
  final double value;
  final bool isPercentage;

  const _DiscountResult({
    required this.value,
    required this.isPercentage,
  });
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

class _UnitDropdownField extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String?> onChanged;

  const _UnitDropdownField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const units = [
      'fixed',
      'sqft',
      'room',
      'wall',
      'hour',
      'item',
      'day',
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(18),
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
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: const Color(0xFF15161C),
              icon: const Icon(
                CupertinoIcons.chevron_down,
                color: Color(0xFF8E93A6),
                size: 18,
              ),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              items: units.map((unit) {
                return DropdownMenuItem<String>(
                  value: unit,
                  child: Text(
                    EstimateFormatters.formatUnit(unit),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddEditItemPage extends StatefulWidget {
  final EstimateItemModel? existingItem;
  final int? index;
  final int itemsLength;

  const _AddEditItemPage({
    this.existingItem,
    this.index,
    required this.itemsLength,
  });

  @override
  State<_AddEditItemPage> createState() => _AddEditItemPageState();
}

class _AddEditItemPageState extends State<_AddEditItemPage> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _quantityController;
  late final TextEditingController _unitPriceController;

  late String _selectedUnit;
  bool _isClosing = false;
  bool _keyboardWasClosed = false;

  @override
  void initState() {
    super.initState();

    final existingItem = widget.existingItem;

    _titleController = TextEditingController(
      text: existingItem?.title ?? '',
    );

    _descriptionController = TextEditingController(
      text: existingItem?.description ?? '',
    );

    _quantityController = TextEditingController(
      text: existingItem != null && existingItem.quantity != 0
          ? EstimateFormatters.formatQuantity(existingItem.quantity)
          : '',
    );

    _unitPriceController = TextEditingController(
      text: existingItem != null && existingItem.unitPrice != 0
          ? EstimateFormatters.formatNumber(existingItem.unitPrice)
          : '',
    );

    _selectedUnit = existingItem?.unit ?? 'fixed';
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isClosing) return;

    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    final double quantity =
    EstimateCalculator.parseNumber(_quantityController.text).toDouble();

    final double unitPrice =
    EstimateCalculator.parseNumber(_unitPriceController.text).toDouble();

    final double normalizedQuantity = quantity <= 0 ? 1.0 : quantity;

    final item = EstimateItemModel(
      id: widget.existingItem?.id ?? '',
      estimateId: widget.existingItem?.estimateId ?? '',
      title: title,
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      unit: _selectedUnit,
      quantity: normalizedQuantity,
      unitPrice: unitPrice,
      lineTotal: EstimateCalculator.calculateLineTotal(
        quantity: normalizedQuantity,
        unitPrice: unitPrice,
      ),
      sortOrder: widget.index ?? widget.itemsLength,
      createdAt: widget.existingItem?.createdAt,
    );

    _isClosing = true;

    await Future.delayed(const Duration(milliseconds: 150));

    if (!mounted) return;

    Navigator.of(context).pop(item);
  }

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF0B0B0F);

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          widget.existingItem == null ? 'Add Item' : 'Edit Item',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: const Color(0xFF5B8CFF),
              borderRadius: BorderRadius.circular(14),
              onPressed: _submit,
              child: const Text(
                'Save',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF15161C),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFF262832)),
              ),
              child: Column(
                children: [
                  _PremiumTextField(
                    controller: _titleController,
                    label: 'Title',
                    hintText: 'Service item title',
                  ),
                  const SizedBox(height: 12),
                  _PremiumTextField(
                    controller: _descriptionController,
                    label: 'Description',
                    hintText: 'Optional description',
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  _UnitDropdownField(
                    label: 'Unit',
                    value: _selectedUnit,
                    onChanged: (unit) {
                      if (unit == null) return;
                      setState(() {
                        _selectedUnit = unit;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _PremiumTextField(
                          controller: _quantityController,
                          label: 'Quantity',
                          hintText: '1',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _PremiumTextField(
                          controller: _unitPriceController,
                          label: 'Unit Price',
                          hintText: '0.00',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: CupertinoButton(
                      color: const Color(0xFF5B8CFF),
                      borderRadius: BorderRadius.circular(16),
                      onPressed: _submit,
                      child: Text(
                        widget.existingItem == null ? 'Add Item' : 'Save Changes',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
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
}