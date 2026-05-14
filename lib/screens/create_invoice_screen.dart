import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

    final selected = await _openWorkioPickerSheet<ClientModel>(
      title: 'Choose Client',
      subtitle: 'Select the customer for this invoice',
      icon: CupertinoIcons.person_2_fill,
      items: _clients,
      itemIconBuilder: (_) => CupertinoIcons.person_crop_circle,
      titleBuilder: (client) => client.fullName,
      subtitleBuilder: (client) {
        final company = (client.companyName ?? '').trim();
        return company.isEmpty ? 'No company' : company;
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

    final selected = await _openWorkioPickerSheet<PropertyModel>(
      title: 'Choose Property',
      subtitle: 'Select the invoice property',
      icon: CupertinoIcons.location_solid,
      items: _properties,
      itemIconBuilder: (_) => CupertinoIcons.house_fill,
      titleBuilder: (property) => property.fullAddress,
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
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF15161C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) {
        return _SimpleDateSheet(
          title: 'Select issue date',
          initialDate: _issueDate,
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
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF15161C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) {
        return _SimpleDateSheet(
          title: 'Select due date',
          initialDate: _dueDate,
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

    final selected = await _openWorkioPickerSheet<String>(
      title: 'Change Status',
      subtitle: 'Select invoice payment status',
      icon: CupertinoIcons.checkmark_seal,
      items: statuses,
      itemIconBuilder: (status) {
        switch (status) {
          case 'draft':
            return CupertinoIcons.doc_text;
          case 'sent':
            return CupertinoIcons.paperplane;
          case 'partial':
            return CupertinoIcons.circle_lefthalf_fill;
          case 'paid':
            return CupertinoIcons.checkmark_circle_fill;
          case 'overdue':
            return CupertinoIcons.exclamationmark_triangle_fill;
          case 'void':
            return CupertinoIcons.xmark_circle_fill;
          default:
            return CupertinoIcons.circle;
        }
      },
      titleBuilder: _statusLabel,
      subtitleBuilder: (status) {
        switch (status) {
          case 'draft':
            return 'Invoice is still being prepared';
          case 'sent':
            return 'Invoice was sent to the client';
          case 'partial':
            return 'Client paid part of the invoice';
          case 'paid':
            return 'Invoice is fully paid';
          case 'overdue':
            return 'Payment is past due';
          case 'void':
            return 'Invoice is cancelled or invalid';
          default:
            return '';
        }
      },
    );

    if (selected == null) return;

    setState(() {
      _status = selected;
    });
  }

  String _shortDateLabel(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];

    return '${months[date.month - 1]} ${date.day}, ${date.year}';
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

    controller.dispose();

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

    controller.dispose();

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
    final isTax = title.toLowerCase().contains('tax');

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
            14,
            20,
            MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFF3A3D49),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),

              const SizedBox(height: 18),

              _sheetHeader(
                icon: isTax ? CupertinoIcons.percent : CupertinoIcons.tag,
                title: title,
                subtitle: isTax
                    ? 'Set the invoice tax amount'
                    : 'Set the invoice discount amount',
              ),

              const SizedBox(height: 18),

              _sheetInputPanel(
                icon: isTax
                    ? CupertinoIcons.money_dollar_circle
                    : CupertinoIcons.tag_circle,
                label: label,
                controller: controller,
                hintText: '0.00',
              ),

              const SizedBox(height: 18),

              SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  color: const Color(0xFF5B8CFF),
                  borderRadius: BorderRadius.circular(16),
                  onPressed: () async {
                    final parsed = EstimateCalculator.parseNumber(
                      controller.text,
                    );

                    FocusManager.instance.primaryFocus?.unfocus();
                    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
                    await Future.delayed(const Duration(milliseconds: 250));

                    if (!context.mounted) return;
                    Navigator.pop(context, parsed);
                  },
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        CupertinoIcons.checkmark_circle,
                        color: Colors.white,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Apply',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
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
    final titleController = TextEditingController(
      text: existingItem?.title ?? '',
    );

    final descriptionController = TextEditingController(
      text: existingItem?.description ?? '',
    );

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

    bool itemSheetClosing = false;

    Future<void> closeItemSheet(
        BuildContext sheetContext, [
          InvoiceItemModel? item,
        ]) async {
      if (itemSheetClosing) return;
      itemSheetClosing = true;

      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await Future.delayed(const Duration(milliseconds: 300));

      if (!sheetContext.mounted) return;
      Navigator.pop(sheetContext, item);
    }

    final result = await showModalBottomSheet<InvoiceItemModel>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: const Color(0xFF15161C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Widget panel({required List<Widget> children}) {
              return Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF101117),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF23252E)),
                ),
                child: Column(children: children),
              );
            }

            Widget inputRow({
              required IconData icon,
              required String label,
              required TextEditingController controller,
              required String hintText,
              TextInputType keyboardType = TextInputType.text,
              int maxLines = 1,
            }) {
              final hasText = controller.text.trim().isNotEmpty;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                child: Row(
                  crossAxisAlignment:
                  maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding: EdgeInsets.only(top: maxLines > 1 ? 2 : 0),
                                child: Icon(
                                  icon,
                                  color: const Color(0xFF8E93A6),
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                label,
                                style: const TextStyle(
                                  color: Color(0xFF8E93A6),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          Padding(
                            padding: const EdgeInsets.only(left: 24),
                            child: TextField(
                              controller: controller,
                              keyboardType: keyboardType,
                              maxLines: maxLines,
                              minLines: maxLines > 1 ? 3 : 1,
                              cursorColor: const Color(0xFF5B8CFF),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                height: 1.35,
                              ),
                              onChanged: (_) {
                                setModalState(() {});
                              },
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: hintText,
                                hintStyle: const TextStyle(
                                  color: Color(0xFF697086),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (hasText) ...[
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () {
                          controller.clear();
                          setModalState(() {});
                        },
                        child: const Icon(
                          CupertinoIcons.xmark_circle_fill,
                          color: Color(0xFF8E93A6),
                          size: 18,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }

            Widget pickerRow({
              required IconData icon,
              required String label,
              required String value,
              required VoidCallback onTap,
            }) {
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 13,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    icon,
                                    color: const Color(0xFF8E93A6),
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    label,
                                    style: const TextStyle(
                                      color: Color(0xFF8E93A6),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 7),
                              Padding(
                                padding: const EdgeInsets.only(left: 24),
                                child: Text(
                                  value,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Icon(
                          CupertinoIcons.chevron_down,
                          color: Color(0xFF8E93A6),
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            Widget centeredInput({
              required IconData icon,
              required String label,
              required TextEditingController controller,
              required String hintText,
              required TextInputType keyboardType,
            }) {
              return Container(
                constraints: const BoxConstraints(minHeight: 78),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D0E14),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF23252E)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      color: const Color(0xFF8E93A6),
                      size: 16,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF8E93A6),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    TextField(
                      controller: controller,
                      keyboardType: keyboardType,
                      textAlign: TextAlign.center,
                      cursorColor: const Color(0xFF5B8CFF),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: hintText,
                        hintStyle: const TextStyle(
                          color: Color(0xFF697086),
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              );
            }

            return PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, result) async {
                if (didPop) return;
                await closeItemSheet(sheetContext);
              },
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  14,
                  20,
                  MediaQuery.of(context).viewInsets.bottom + 24,
                ),
                child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFF3A3D49),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 18),

                    Row(
                      children: [
                        Icon(
                          existingItem == null
                              ? CupertinoIcons.add_circled
                              : CupertinoIcons.pencil_circle,
                          color: const Color(0xFFB8C1D9),
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            existingItem == null ? 'Add Item' : 'Edit Item',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    panel(
                      children: [
                        inputRow(
                          icon: CupertinoIcons.tag,
                          label: 'Title',
                          controller: titleController,
                          hintText: 'Labor / Materials',
                        ),
                        const Divider(color: Color(0xFF23252E), height: 1),
                        inputRow(
                          icon: CupertinoIcons.text_alignleft,
                          label: 'Description',
                          controller: descriptionController,
                          hintText: 'Optional description',
                          maxLines: 3,
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    panel(
                      children: [
                        pickerRow(
                          icon: CupertinoIcons.cube_box,
                          label: 'Unit',
                          value: EstimateFormatters.formatUnit(selectedUnit),
                          onTap: () async {
                            FocusManager.instance.primaryFocus?.unfocus();
                            await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
                            await Future.delayed(const Duration(milliseconds: 250));

                            if (!sheetContext.mounted) return;

                            const units = [
                              'fixed',
                              'sqft',
                              'room',
                              'wall',
                              'hour',
                              'item',
                              'day',
                            ];

                            final unit = await showModalBottomSheet<String>(
                              context: context,
                              backgroundColor: const Color(0xFF15161C),
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(28),
                                ),
                              ),
                              builder: (_) {
                                return _UnitSelectionSheet(
                                  units: units,
                                  selectedUnit: selectedUnit,
                                );
                              },
                            );

                            if (unit == null) return;

                            setModalState(() {
                              selectedUnit = unit;
                            });
                          },
                        ),
                        const Divider(color: Color(0xFF23252E), height: 1),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 13,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: centeredInput(
                                  icon: CupertinoIcons.number,
                                  label: 'Quantity',
                                  controller: quantityController,
                                  hintText: '1',
                                  keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: centeredInput(
                                  icon: CupertinoIcons.money_dollar_circle,
                                  label: 'Unit Price',
                                  controller: unitPriceController,
                                  hintText: '0.00',
                                  keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    SizedBox(
                      width: double.infinity,
                      child: CupertinoButton(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        color: const Color(0xFF5B8CFF),
                        borderRadius: BorderRadius.circular(16),
                        onPressed: () async {
                          final title = titleController.text.trim();
                          if (title.isEmpty) return;

                          final quantity = EstimateCalculator.parseNumber(
                            quantityController.text,
                          ).toDouble();

                          final unitPrice = EstimateCalculator.parseNumber(
                            unitPriceController.text,
                          ).toDouble();

                          final safeQuantity = quantity <= 0 ? 1.0 : quantity;

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

                          await closeItemSheet(sheetContext, item);
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              existingItem == null
                                  ? CupertinoIcons.plus_circle
                                  : CupertinoIcons.checkmark_circle,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              existingItem == null ? 'Add Item' : 'Save Changes',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            );
          },
        );
      },
    );

    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await Future.delayed(const Duration(milliseconds: 500));

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

  Future<void> _openLargeTextEditor({
    required String title,
    required TextEditingController controller,
    required IconData icon,
  }) async {
    final tempController = TextEditingController(text: controller.text.trim());
    final focusNode = FocusNode();

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF15161C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.88,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                child: Column(
                  children: [
                    Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFF3A3D49),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Icon(
                          icon,
                          color: const Color(0xFF8FB0FF),
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () async {
                            FocusManager.instance.primaryFocus?.unfocus();
                            await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
                            await Future.delayed(const Duration(milliseconds: 250));

                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext);
                            }
                          },
                          child: const Icon(
                            CupertinoIcons.xmark_circle_fill,
                            color: Color(0xFF8E93A6),
                            size: 28,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Review and edit this text before saving.',
                        style: TextStyle(
                          color: Color(0xFF8E93A6),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    Expanded(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF101117),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: const Color(0xFF23252E)),
                        ),
                        child: TextField(
                          controller: tempController,
                          focusNode: focusNode,
                          expands: true,
                          maxLines: null,
                          minLines: null,
                          keyboardType: TextInputType.multiline,
                          textAlignVertical: TextAlignVertical.top,
                          cursorColor: const Color(0xFF5B8CFF),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            height: 1.45,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Enter text...',
                            hintStyle: TextStyle(
                              color: Color(0xFF697086),
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    Row(
                      children: [
                        Expanded(
                          child: CupertinoButton(
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            color: const Color(0xFF20232D),
                            borderRadius: BorderRadius.circular(16),
                            onPressed: () async {
                              FocusManager.instance.primaryFocus?.unfocus();
                              await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
                              await Future.delayed(const Duration(milliseconds: 250));

                              if (sheetContext.mounted) {
                                Navigator.pop(sheetContext);
                              }
                            },
                            child: const Text(
                              'Cancel',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: CupertinoButton(
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            color: const Color(0xFF5B8CFF),
                            borderRadius: BorderRadius.circular(16),
                            onPressed: () async {
                              final value = tempController.text.trim();

                              FocusManager.instance.primaryFocus?.unfocus();
                              await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
                              await Future.delayed(const Duration(milliseconds: 250));

                              if (sheetContext.mounted) {
                                Navigator.pop(sheetContext, value);
                              }
                            },
                            child: const Text(
                              'Save',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
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
        );
      },
    );

    await Future.delayed(const Duration(milliseconds: 500));

    tempController.dispose();
    focusNode.dispose();

    if (result == null) return;

    setState(() {
      controller.text = result.trim();
    });
  }

  Widget _sheetHeader({
    required IconData icon,
    required String title,
    String? subtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              color: const Color(0xFFB8C1D9),
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
        if ((subtitle ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 5),
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: Text(
              subtitle!,
              style: const TextStyle(
                color: Color(0xFF8E93A6),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _sheetInputPanel({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    required String hintText,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF23252E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: const Color(0xFF8E93A6),
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF8E93A6),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          const SizedBox(height: 7),

          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              cursorColor: const Color(0xFF5B8CFF),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: hintText,
                hintStyle: const TextStyle(
                  color: Color(0xFF697086),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _formPanel({
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF23252E)),
      ),
      child: Column(children: children),
    );
  }

  Widget _largeTextRow({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    final cleanValue = value.trim().isEmpty ? 'Tap to add text' : value.trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                color: const Color(0xFF8E93A6),
                size: 18,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            color: Color(0xFF8E93A6),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        const Icon(
                          CupertinoIcons.arrow_up_left_arrow_down_right,
                          color: Color(0xFF8E93A6),
                          size: 15,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      cleanValue,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: value.trim().isEmpty
                            ? const Color(0xFF697086)
                            : Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<T?> _openWorkioPickerSheet<T>({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<T> items,
    required String Function(T item) titleBuilder,
    String Function(T item)? subtitleBuilder,
    IconData Function(T item)? itemIconBuilder,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF15161C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: FractionallySizedBox(
            heightFactor: 0.70,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
              child: Column(
                children: [
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3A3D49),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 18),

                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            icon,
                            color: const Color(0xFFB8C1D9),
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Padding(
                        padding: const EdgeInsets.only(left: 30),
                        child: Text(
                          subtitle,
                          style: const TextStyle(
                            color: Color(0xFF8E93A6),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  Expanded(
                    child: ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final itemTitle = titleBuilder(item);
                        final itemSubtitle = subtitleBuilder?.call(item) ?? '';
                        final itemIcon =
                            itemIconBuilder?.call(item) ?? CupertinoIcons.circle;

                        return Material(
                          color: const Color(0xFF101117),
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => Navigator.pop(sheetContext, item),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: const Color(0xFF23252E),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    itemIcon,
                                    color: const Color(0xFF8E93A6),
                                    size: 19,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          itemTitle,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                            height: 1.25,
                                          ),
                                        ),
                                        if (itemSubtitle.trim().isNotEmpty) ...[
                                          const SizedBox(height: 5),
                                          Text(
                                            itemSubtitle,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Color(0xFF8E93A6),
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w500,
                                              height: 1.3,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const SizedBox(
                                    height: 48,
                                    child: Center(
                                      child: Icon(
                                        CupertinoIcons.chevron_right,
                                        color: Color(0xFF8E93A6),
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ],
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
          ),
        );
      },
    );
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
              child: _formPanel(
                children: [
                  _PremiumPickerField(
                    label: 'Client',
                    leadingIcon: CupertinoIcons.person_crop_circle,
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
                  const Divider(color: Color(0xFF23252E), height: 1),
                  _PremiumPickerField(
                    label: 'Property',
                    leadingIcon: CupertinoIcons.house_fill,
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
              child: _formPanel(
                children: [
                  _PremiumPickerField(
                    label: 'Status',
                    leadingIcon: CupertinoIcons.checkmark_seal,
                    value: _statusLabel(_status),
                    onTap: _pickStatus,
                    showClearButton: _status != 'draft',
                    onClear: () {
                      setState(() {
                        _status = 'draft';
                      });
                    },
                  ),
                  const Divider(color: Color(0xFF23252E), height: 1),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: _PremiumPickerField(
                            label: 'Issue Date',
                            leadingIcon: CupertinoIcons.calendar,
                            value: _shortDateLabel(_issueDate),
                            valueMaxLines: 1,
                            onTap: _pickIssueDate,
                            showClearButton: false,
                            showChevron: false,
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 58,
                          color: const Color(0xFF23252E),
                        ),
                        Expanded(
                          child: _PremiumPickerField(
                            label: 'Due Date',
                            leadingIcon: CupertinoIcons.clock,
                            value: _shortDateLabel(_dueDate),
                            valueMaxLines: 1,
                            onTap: _pickDueDate,
                            showClearButton: false,
                            showChevron: false,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'Invoice Info',
              subtitle: 'Main information',
              child: _formPanel(
                children: [
                  _PremiumTitleField(
                    controller: _titleController,
                    label: 'Title',
                    hintText: 'Invoice title',
                    icon: CupertinoIcons.doc_text,
                  ),
                ],
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
              child: _formPanel(
                children: [
                  _largeTextRow(
                    icon: CupertinoIcons.text_alignleft,
                    label: 'Notes',
                    value: _notesController.text,
                    onTap: () {
                      _openLargeTextEditor(
                        title: 'Edit Notes',
                        controller: _notesController,
                        icon: CupertinoIcons.text_alignleft,
                      );
                    },
                  ),
                  const Divider(color: Color(0xFF23252E), height: 1),
                  _largeTextRow(
                    icon: CupertinoIcons.doc_text,
                    label: 'Terms',
                    value: _termsController.text,
                    onTap: () {
                      _openLargeTextEditor(
                        title: 'Edit Terms',
                        controller: _termsController,
                        icon: CupertinoIcons.doc_text,
                      );
                    },
                  ),
                  const Divider(color: Color(0xFF23252E), height: 1),
                  _largeTextRow(
                    icon: CupertinoIcons.creditcard,
                    label: 'Payment Instructions',
                    value: _paymentInstructionsController.text,
                    onTap: () {
                      _openLargeTextEditor(
                        title: 'Edit Payment Instructions',
                        controller: _paymentInstructionsController,
                        icon: CupertinoIcons.creditcard,
                      );
                    },
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
                  _TotalsPanel(
                    children: [
                      _TotalsEditRow(
                        icon: CupertinoIcons.money_dollar_circle,
                        label: 'Tax Amount',
                        value: '${EstimateFormatters.formatCurrency(_taxAmount)} ($_currencyCode)',
                        onTap: _showTaxEditor,
                      ),
                      const Divider(color: Color(0xFF23252E), height: 1),
                      _TotalsEditRow(
                        icon: CupertinoIcons.tag,
                        label: 'Discount Amount',
                        value: EstimateFormatters.formatCurrency(_discountAmount),
                        onTap: _showDiscountEditor,
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  _TotalsPanel(
                    children: [
                      _TotalsValueRow(
                        icon: CupertinoIcons.sum,
                        label: 'Subtotal',
                        value: EstimateFormatters.formatCurrency(_subtotal),
                        muted: true,
                      ),
                      _TotalsValueRow(
                        icon: CupertinoIcons.percent,
                        label: 'Tax',
                        value: EstimateFormatters.formatCurrency(_taxAmount),
                        muted: true,
                      ),
                      _TotalsValueRow(
                        icon: CupertinoIcons.tag,
                        label: 'Discount',
                        value: '- ${EstimateFormatters.formatCurrency(_discountAmount)}',
                        muted: true,
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  _TotalsGrandRow(
                    value: EstimateFormatters.formatCurrency(_total),
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

class _PremiumTitleField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hintText;
  final IconData icon;

  const _PremiumTitleField({
    required this.controller,
    required this.label,
    required this.hintText,
    required this.icon,
  });

  @override
  State<_PremiumTitleField> createState() => _PremiumTitleFieldState();
}

class _PremiumTitleFieldState extends State<_PremiumTitleField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final showX = widget.controller.text.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      widget.icon,
                      color: const Color(0xFF8E93A6),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.label,
                      style: const TextStyle(
                        color: Color(0xFF8E93A6),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 24),
                  child: TextField(
                    controller: widget.controller,
                  cursorColor: const Color(0xFF5B8CFF),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: widget.hintText,
                    hintStyle: const TextStyle(
                      color: Color(0xFF697086),
                      fontSize: 15,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                 ),
                ),
              ],
            ),
          ),
          if (showX) ...[
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () {
                widget.controller.clear();
              },
              child: const Icon(
                CupertinoIcons.xmark_circle_fill,
                color: Color(0xFF8E93A6),
                size: 18,
              ),
            ),
          ],
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
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
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
  final IconData? leadingIcon;
  final bool showChevron;
  final int valueMaxLines;

  const _PremiumPickerField({
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
    this.showClearButton = false,
    this.emptyIcon,
    this.onEmptyIconTap,
    this.leadingIcon,
    this.showChevron = true,
    this.valueMaxLines = 2,
  });

  @override
  Widget build(BuildContext context) {
    final isPlaceholder =
        value.startsWith('Select') || value.trim().isEmpty || value == '—';

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (leadingIcon != null) ...[
                          Icon(
                            leadingIcon,
                            color: const Color(0xFF8E93A6),
                            size: 15,
                          ),
                          const SizedBox(width: 7),
                        ],
                        Text(
                          label,
                          style: const TextStyle(
                            color: Color(0xFF8E93A6),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: EdgeInsets.only(
                        left: leadingIcon != null ? 22 : 0,
                      ),
                      child: Text(
                        value,
                        maxLines: valueMaxLines,
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
              else if (showChevron)
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

class _SimpleDateSheet extends StatefulWidget {
  final String title;
  final DateTime initialDate;

  const _SimpleDateSheet({
    required this.title,
    required this.initialDate,
  });

  @override
  State<_SimpleDateSheet> createState() => _SimpleDateSheetState();
}

class _SimpleDateSheetState extends State<_SimpleDateSheet> {
  late DateTime selectedDate;
  late DateTime visibleMonth;

  @override
  void initState() {
    super.initState();
    selectedDate = DateTime(
      widget.initialDate.year,
      widget.initialDate.month,
      widget.initialDate.day,
    );
    visibleMonth = DateTime(selectedDate.year, selectedDate.month);
  }

  String _monthLabel(DateTime date) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];

    return '${months[date.month - 1]} ${date.year}';
  }

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(visibleMonth.year, visibleMonth.month, 1);
    final daysInMonth = DateTime(
      visibleMonth.year,
      visibleMonth.month + 1,
      0,
    ).day;

    final leadingEmptyDays = firstDay.weekday % 7;

    return SafeArea(
      top: false,
      child: FractionallySizedBox(
        heightFactor: 0.82,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFF3A3D49),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Icon(
                    CupertinoIcons.calendar,
                    color: Color(0xFFB8C1D9),
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    widget.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF101117),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF23252E)),
                ),
                child: Row(
                  children: [
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        setState(() {
                          visibleMonth = DateTime(
                            visibleMonth.year,
                            visibleMonth.month - 1,
                          );
                        });
                      },
                      child: const Icon(
                        CupertinoIcons.chevron_left,
                        color: Color(0xFFB6BCD0),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          _monthLabel(visibleMonth),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        setState(() {
                          visibleMonth = DateTime(
                            visibleMonth.year,
                            visibleMonth.month + 1,
                          );
                        });
                      },
                      child: const Icon(
                        CupertinoIcons.chevron_right,
                        color: Color(0xFFB6BCD0),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF101117),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF23252E)),
                  ),
                  child: GridView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: 42,
                    gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                    ),
                    itemBuilder: (context, index) {
                      final dayNumber = index - leadingEmptyDays + 1;
                      final isCurrentMonth =
                          dayNumber >= 1 && dayNumber <= daysInMonth;

                      final date = DateTime(
                        visibleMonth.year,
                        visibleMonth.month,
                        dayNumber,
                      );

                      final selected = _sameDay(date, selectedDate);

                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            selectedDate = date;
                          });
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: selected
                                ? const Color(0xFF5B8CFF)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${date.day}',
                            style: TextStyle(
                              color: selected
                                  ? Colors.white
                                  : isCurrentMonth
                                  ? Colors.white
                                  : const Color(0xFF4F5668),
                              fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  color: const Color(0xFF5B8CFF),
                  borderRadius: BorderRadius.circular(16),
                  onPressed: () {
                    Navigator.pop(context, selectedDate);
                  },
                  child: const Text(
                    'Apply Date',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnitSelectionSheet extends StatelessWidget {
  final List<String> units;
  final String selectedUnit;

  const _UnitSelectionSheet({
    required this.units,
    required this.selectedUnit,
  });

  IconData _unitIcon(String unit) {
    switch (unit.trim().toLowerCase()) {
      case 'fixed':
        return CupertinoIcons.checkmark_seal;
      case 'sqft':
        return CupertinoIcons.square_grid_2x2;
      case 'room':
        return CupertinoIcons.house;
      case 'wall':
        return CupertinoIcons.rectangle;
      case 'hour':
        return CupertinoIcons.clock;
      case 'item':
        return CupertinoIcons.cube_box;
      case 'day':
        return CupertinoIcons.calendar;
      default:
        return CupertinoIcons.circle_grid_hex;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: FractionallySizedBox(
        heightFactor: 0.78,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFF3A3D49),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 18),
              const Row(
                children: [
                  Icon(
                    CupertinoIcons.cube_box,
                    color: Color(0xFFB8C1D9),
                    size: 22,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Choose Unit',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  itemCount: units.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final unit = units[index];
                    final selected = unit == selectedUnit;

                    return Material(
                      color: selected
                          ? const Color(0xFF16233F)
                          : const Color(0xFF101117),
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => Navigator.pop(context, unit),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: selected
                                  ? const Color(0xFF5B8CFF)
                                  : const Color(0xFF23252E),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _unitIcon(unit),
                                color: selected
                                    ? const Color(0xFF8FB0FF)
                                    : const Color(0xFF8E93A6),
                                size: 19,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  EstimateFormatters.formatUnit(unit),
                                  style: TextStyle(
                                    color: selected
                                        ? Colors.white
                                        : const Color(0xFFE7EAF2),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              Icon(
                                selected
                                    ? CupertinoIcons.checkmark_circle_fill
                                    : CupertinoIcons.chevron_right,
                                color: selected
                                    ? const Color(0xFF5B8CFF)
                                    : const Color(0xFF8E93A6),
                                size: selected ? 20 : 16,
                              ),
                            ],
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
    final sheetHeight = math.min(
      MediaQuery.of(context).size.height * 0.70,
      520.0,
    );

    return SafeArea(
      top: false,
      child: SizedBox(
        height: sheetHeight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFF3A3D49),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 18),

              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              Expanded(
                child: ListView.separated(
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 15,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: const Color(0xFF23252E),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  itemLabel(item),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
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
                  },
                ),
              ),
            ],
          ),
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

class _TotalsPanel extends StatelessWidget {
  final List<Widget> children;

  const _TotalsPanel({
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF23252E)),
      ),
      child: Column(children: children),
    );
  }
}

class _TotalsEditRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _TotalsEditRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFF8E93A6), size: 18),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: Color(0xFFB8C1D9),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                CupertinoIcons.chevron_right,
                color: Color(0xFF8E93A6),
                size: 15,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TotalsValueRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool muted;

  const _TotalsValueRow({
    required this.icon,
    required this.label,
    required this.value,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF8E93A6), size: 18),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: muted ? const Color(0xFF8E93A6) : Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            value,
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

class _TotalsGrandRow extends StatelessWidget {
  final String value;

  const _TotalsGrandRow({
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF5B8CFF)),
      ),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              color: Color(0xFF8E93A6),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text(
                r'$',
                style: TextStyle(
                  color: Color(0xFF101117),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Total',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}