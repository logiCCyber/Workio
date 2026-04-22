import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../dialogs/add_client_dialog.dart';
import '../dialogs/add_property_dialog.dart';
import '../models/client_model.dart';
import '../models/company_settings_model.dart';
import '../models/invoice_item_model.dart';
import '../models/invoice_model.dart';
import '../models/property_model.dart';
import '../services/client_service.dart';
import '../services/company_settings_service.dart';
import '../services/invoice_service.dart';
import '../services/property_service.dart';
import '../utils/estimate_calculator.dart';
import '../utils/estimate_formatters.dart';

class CreateInvoiceScreen extends StatefulWidget {
  const CreateInvoiceScreen({super.key});

  @override
  State<CreateInvoiceScreen> createState() => _CreateInvoiceScreenState();
}

class _CreateInvoiceScreenState extends State<CreateInvoiceScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _termsController = TextEditingController();
  final TextEditingController _paymentInstructionsController =
  TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;

  List<ClientModel> _clients = [];
  List<PropertyModel> _properties = [];

  ClientModel? _selectedClient;
  PropertyModel? _selectedProperty;
  CompanySettingsModel? _companySettings;

  List<InvoiceItemModel> _items = [];

  DateTime _issueDate = DateTime.now();
  DateTime _dueDate = DateTime.now().add(const Duration(days: 14));
  String _status = 'draft';

  double _taxAmount = 0;
  double _discountAmount = 0;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _termsController.dispose();
    _paymentInstructionsController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final results = await Future.wait([
        ClientService.getClients(),
        CompanySettingsService.getSettings(),
      ]);

      final clients = results[0] as List<ClientModel>;
      final companySettings = results[1] as CompanySettingsModel?;

      if (!mounted) return;

      setState(() {
        _clients = clients;
        _companySettings = companySettings;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showSnack('Failed to load data');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String get _currencyCode {
    final value = _companySettings?.currencyCode.trim() ?? '';
    return value.isEmpty ? 'CAD' : value.toUpperCase();
  }

  double get _subtotal {
    double sum = 0;

    for (final item in _items) {
      final lineTotal = item.lineTotal > 0
          ? item.lineTotal
          : EstimateCalculator.calculateLineTotal(
        quantity: item.quantity,
        unitPrice: item.unitPrice,
      );

      sum += lineTotal;
    }

    return double.parse(sum.toStringAsFixed(2));
  }

  double get _total {
    final result = _subtotal + _taxAmount - _discountAmount;
    return double.parse(math.max(result, 0).toStringAsFixed(2));
  }

  Future<void> _loadPropertiesForClient(String clientId) async {
    try {
      final properties = await PropertyService.getPropertiesByClient(clientId);

      if (!mounted) return;

      setState(() {
        _properties = properties;
      });
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to load client properties');
    }
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
            return company.isEmpty
                ? client.fullName
                : '${client.fullName} • $company';
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
  }

  Future<void> _addNewClient() async {
    final created = await showAddClientDialog(context);

    if (created == null) return;

    await _loadInitialData();

    if (!mounted) return;

    setState(() {
      _selectedClient = created;
      _selectedProperty = null;
      _properties = [];
    });

    await _loadPropertiesForClient(created.id);

    _showSnack('Client created');
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

    _showSnack('Property created');
  }

  Future<void> _pickIssueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _issueDate,
      firstDate: DateTime.now().subtract(const Duration(days: 3650)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
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
      _issueDate = picked;
      if (_dueDate.isBefore(_issueDate)) {
        _dueDate = _issueDate.add(const Duration(days: 14));
      }
    });
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime.now().subtract(const Duration(days: 3650)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
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
      _dueDate = picked;
    });
  }

  Future<void> _pickStatus() async {
    const statuses = [
      'draft',
      'sent',
      'partial',
      'paid',
      'overdue',
      'void',
    ];

    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF15161C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) {
        return _SelectionSheet<String>(
          title: 'Change Status',
          items: statuses,
          itemLabel: _statusLabel,
        );
      },
    );

    if (selected == null) return;

    setState(() {
      _status = selected;
    });
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

  Future<void> _showTaxEditor() async {
    final controller = TextEditingController(
      text: _taxAmount == 0 ? '' : _taxAmount.toStringAsFixed(2),
    );

    final value = await _showAmountEditor(
      title: 'Tax Amount',
      label: 'Tax',
      controller: controller,
    );

    if (value == null) return;

    setState(() {
      _taxAmount = value;
    });
  }

  Future<void> _showDiscountEditor() async {
    final controller = TextEditingController(
      text: _discountAmount == 0 ? '' : _discountAmount.toStringAsFixed(2),
    );

    final value = await _showAmountEditor(
      title: 'Discount Amount',
      label: 'Discount',
      controller: controller,
    );

    if (value == null) return;

    setState(() {
      _discountAmount = value;
    });
  }

  Future<double?> _showAmountEditor({
    required String title,
    required String label,
    required TextEditingController controller,
  }) {
    return showModalBottomSheet<double>(
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
              const SizedBox(height: 16),
              _PremiumTextField(
                controller: controller,
                label: label,
                hintText: '0.00',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  color: const Color(0xFF5B8CFF),
                  borderRadius: BorderRadius.circular(16),
                  onPressed: () {
                    final parsed =
                    EstimateCalculator.parseNumber(controller.text);
                    Navigator.pop(context, parsed);
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
  }

  Future<void> _addOrEditItem({
    InvoiceItemModel? existingItem,
    int? index,
  }) async {
    final titleController = TextEditingController(text: existingItem?.title ?? '');
    final descriptionController =
    TextEditingController(text: existingItem?.description ?? '');
    final quantityController = TextEditingController(
      text: existingItem != null && existingItem.quantity != 0
          ? EstimateFormatters.formatQuantity(existingItem.quantity)
          : '',
    );
    final unitPriceController = TextEditingController(
      text: existingItem != null && existingItem.unitPrice != 0
          ? EstimateFormatters.formatNumber(existingItem.unitPrice)
          : '',
    );

    String selectedUnit = existingItem?.unit ?? 'fixed';

    final result = await showModalBottomSheet<InvoiceItemModel>(
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
                MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      existingItem == null ? 'Add Item' : 'Edit Item',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _PremiumTextField(
                      controller: titleController,
                      label: 'Title',
                      hintText: 'Labor / Materials',
                    ),
                    const SizedBox(height: 12),
                    _PremiumTextField(
                      controller: descriptionController,
                      label: 'Description',
                      hintText: 'Optional description',
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    _PremiumPickerField(
                      label: 'Unit',
                      value: EstimateFormatters.formatUnit(selectedUnit),
                      onTap: () async {
                        final unit = await showModalBottomSheet<String>(
                          context: context,
                          backgroundColor: const Color(0xFF15161C),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(28),
                            ),
                          ),
                          builder: (_) {
                            const units = [
                              'fixed',
                              'sqft',
                              'room',
                              'wall',
                              'hour',
                              'item',
                              'day',
                            ];

                            return _SelectionSheet<String>(
                              title: 'Choose Unit',
                              items: units,
                              itemLabel: (unit) =>
                                  EstimateFormatters.formatUnit(unit),
                            );
                          },
                        );

                        if (unit == null) return;

                        setModalState(() {
                          selectedUnit = unit;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _PremiumTextField(
                            controller: quantityController,
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
                            controller: unitPriceController,
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
                        onPressed: () {
                          final title = titleController.text.trim();
                          if (title.isEmpty) return;

                          final double quantity =
                          EstimateCalculator.parseNumber(quantityController.text).toDouble();

                          final double unitPrice =
                          EstimateCalculator.parseNumber(unitPriceController.text).toDouble();

                          final double safeQuantity = quantity <= 0 ? 1.0 : quantity;

                          final item = InvoiceItemModel(
                            id: existingItem?.id ?? '',
                            invoiceId: existingItem?.invoiceId ?? '',
                            title: title,
                            description: descriptionController.text.trim().isEmpty
                                ? null
                                : descriptionController.text.trim(),
                            unit: selectedUnit,
                            quantity: safeQuantity,
                            unitPrice: unitPrice,
                            lineTotal: EstimateCalculator.calculateLineTotal(
                              quantity: safeQuantity,
                              unitPrice: unitPrice,
                            ),
                            sortOrder: index ?? _items.length,
                            createdAt: existingItem?.createdAt,
                          );

                          Navigator.pop(context, item);
                        },
                        child: Text(
                          existingItem == null ? 'Add Item' : 'Save Changes',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    titleController.dispose();
    descriptionController.dispose();
    quantityController.dispose();
    unitPriceController.dispose();

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
          .map((entry) => entry.value.copyWith(sortOrder: entry.key))
          .toList();
    });
  }

  Future<void> _saveInvoice() async {
    if (_selectedClient == null) {
      _showSnack('Сначала выбери клиента');
      return;
    }

    if (_selectedProperty == null) {
      _showSnack('Select a property first');
      return;
    }

    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _showSnack('Enter invoice title');
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
      final invoice = InvoiceModel(
        id: '',
        adminAuthId: '',
        estimateId: null,
        clientId: _selectedClient!.id,
        propertyId: _selectedProperty!.id,
        invoiceNumber: '',
        title: title,
        status: _status,
        issueDate: _issueDate,
        dueDate: _dueDate,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        terms: _termsController.text.trim().isEmpty
            ? null
            : _termsController.text.trim(),
        paymentInstructions:
        _paymentInstructionsController.text.trim().isEmpty
            ? null
            : _paymentInstructionsController.text.trim(),
        subtotal: _subtotal,
        tax: _taxAmount,
        discount: _discountAmount,
        total: _total,
        paidAmount: 0,
        balanceDue: _total,
        createdAt: null,
        updatedAt: null,
      );

      final created = await InvoiceService.createInvoiceWithItems(
        invoice: invoice,
        items: _items,
      );

      if (!mounted) return;

      Navigator.pop(context, created.id);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to create invoice');
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

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 20,
        title: const Text(
          'Create Invoice',
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
              onPressed: _isSaving ? null : _saveInvoice,
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
            _buildSectionCard(
              title: 'Client & Property',
              subtitle: 'Client and invoice property',
              child: Column(
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
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'Invoice Header',
              subtitle: 'Status and dates',
              child: Column(
                children: [
                  _PremiumPickerField(
                    label: 'Status',
                    value: _statusLabel(_status),
                    onTap: _pickStatus,
                    showClearButton: _status != 'draft',
                    onClear: () {
                      setState(() {
                        _status = 'draft';
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _PremiumPickerField(
                          label: 'Issue Date',
                          value: EstimateFormatters.formatDate(_issueDate),
                          onTap: _pickIssueDate,
                          showClearButton: true,
                          onClear: () {
                            setState(() {
                              _issueDate = DateTime.now();
                              if (_dueDate.isBefore(_issueDate)) {
                                _dueDate = _issueDate.add(const Duration(days: 14));
                              }
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _PremiumPickerField(
                          label: 'Due Date',
                          value: EstimateFormatters.formatDate(_dueDate),
                          onTap: _pickDueDate,
                          showClearButton: true,
                          onClear: () {
                            setState(() {
                              _dueDate = _issueDate.add(const Duration(days: 14));
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'Invoice Info',
              subtitle: 'Main information',
              child: _PremiumTextField(
                controller: _titleController,
                label: 'Title',
                hintText: 'Invoice title',
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'Items',
              subtitle: 'Invoice line items',
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
                    child: _InvoiceItemTile(
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
              title: 'Notes & Terms',
              subtitle: 'Additional information',
              child: Column(
                children: [
                  _PremiumTextField(
                    controller: _notesController,
                    label: 'Notes',
                    hintText: 'Invoice notes',
                    maxLines: 4,
                  ),
                  const SizedBox(height: 12),
                  _PremiumTextField(
                    controller: _termsController,
                    label: 'Terms',
                    hintText: 'Payment terms',
                    maxLines: 4,
                  ),
                  const SizedBox(height: 12),
                  _PremiumTextField(
                    controller: _paymentInstructionsController,
                    label: 'Payment Instructions',
                    hintText: 'E-transfer / bank details / other instructions',
                    maxLines: 4,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'Totals',
              subtitle: 'Invoice totals',
              child: Column(
                children: [
                  _TotalsActionRow(
                    label: 'Tax Amount',
                    value:
                    '${EstimateFormatters.formatCurrency(_taxAmount)} ($_currencyCode)',
                    onTap: _showTaxEditor,
                  ),
                  const SizedBox(height: 10),
                  _TotalsActionRow(
                    label: 'Discount Amount',
                    value: EstimateFormatters.formatCurrency(_discountAmount),
                    onTap: _showDiscountEditor,
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: Color(0xFF262832), height: 1),
                  const SizedBox(height: 16),
                  _SummaryLine(
                    label: 'Subtotal',
                    value: EstimateFormatters.formatCurrency(_subtotal),
                  ),
                  const SizedBox(height: 10),
                  _SummaryLine(
                    label: 'Tax',
                    value: EstimateFormatters.formatCurrency(_taxAmount),
                  ),
                  const SizedBox(height: 10),
                  _SummaryLine(
                    label: 'Discount',
                    value:
                    '- ${EstimateFormatters.formatCurrency(_discountAmount)}',
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: Color(0xFF262832), height: 1),
                  const SizedBox(height: 12),
                  _SummaryLine(
                    label: 'Total',
                    value: EstimateFormatters.formatCurrency(_total),
                    isEmphasized: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            CupertinoButton(
              color: const Color(0xFF5B8CFF),
              borderRadius: BorderRadius.circular(18),
              padding: const EdgeInsets.symmetric(vertical: 16),
              onPressed: _isSaving ? null : _saveInvoice,
              child: _isSaving
                  ? const CupertinoActivityIndicator(color: Colors.white)
                  : const Text(
                'Create Invoice',
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

class _PremiumTextField extends StatelessWidget {
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
              keyboardType: keyboardType,
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
              child: ListView.separated(
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

class _InvoiceItemTile extends StatelessWidget {
  final InvoiceItemModel item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _InvoiceItemTile({
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