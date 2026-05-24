import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter/foundation.dart';

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
import '../utils/workio_icon_mapper.dart';

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
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _speechReady = false;
  bool _isListening = false;
  bool _voiceAppendMode = true;

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
    _initSpeech();
  }

  @override
  void dispose() {
    _speech.stop();
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

    final lower = message.toLowerCase();

    final isSuccess = lower.contains('created') ||
        lower.contains('saved') ||
        lower.contains('updated') ||
        lower.contains('uploaded') ||
        lower.contains('removed');

    final isError = lower.contains('failed') ||
        lower.contains('error') ||
        lower.contains('select') ||
        lower.contains('enter') ||
        lower.contains('add at least');

    final icon = isSuccess
        ? CupertinoIcons.checkmark_circle_fill
        : isError
        ? CupertinoIcons.xmark_circle_fill
        : CupertinoIcons.info_circle_fill;

    final color = isSuccess
        ? const Color(0xFF22C55E)
        : isError
        ? const Color(0xFFFF6B6B)
        : const Color(0xFFF59E0B);

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        duration: const Duration(seconds: 3),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF22252D),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: color.withValues(alpha: 0.35),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: color,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _initSpeech() async {
    final ready = await _speech.initialize(
      onStatus: (status) {
        if (!mounted) return;

        if (status == 'done' || status == 'notListening') {
          setState(() {
            _isListening = false;
          });
        }
      },
      onError: (error) {
        if (!mounted) return;

        setState(() {
          _isListening = false;
        });

        _showSnack('Voice input failed: ${error.errorMsg}');
      },
    );

    if (!mounted) return;

    setState(() {
      _speechReady = ready;
    });
  }

  void _insertVoiceTextToController(
      TextEditingController controller,
      String spokenText, {
        required bool append,
      }) {
    final clean = spokenText.trim();
    if (clean.isEmpty) return;

    final current = controller.text.trim();

    final next = append
        ? (current.isEmpty ? clean : '$current $clean').trim()
        : clean;

    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  Future<void> _startVoiceInput({
    required TextEditingController controller,
    required bool append,
    ValueChanged<String>? onLiveText,
    VoidCallback? onDone,
  }) async {
    if (!_speechReady) {
      _showSnack('Voice input is not available on this device');
      return;
    }

    if (_isListening) return;

    setState(() {
      _voiceAppendMode = append;
      _isListening = true;
    });

    await _speech.listen(
      onResult: (result) {
        if (!mounted) return;

        final spoken = result.recognizedWords.trim();

        if (spoken.isNotEmpty) {
          if (onLiveText != null) {
            onLiveText(spoken);
          } else if (result.finalResult) {
            _insertVoiceTextToController(
              controller,
              spoken,
              append: _voiceAppendMode,
            );
          }
        }

        if (result.finalResult) {
          setState(() {
            _isListening = false;
          });

          onDone?.call();
        }
      },
      listenMode: stt.ListenMode.dictation,
      partialResults: true,
      cancelOnError: true,
      listenFor: const Duration(seconds: 45),
      pauseFor: const Duration(seconds: 5),
    );
  }

  Future<void> _stopVoiceInput() async {
    await _speech.stop();

    if (!mounted) return;

    setState(() {
      _isListening = false;
    });
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
      backgroundColor: const Color(0xFF242730),
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
      backgroundColor: const Color(0xFF242730),
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

    String subtitleFor(String status) {
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
    }

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
          child: FractionallySizedBox(
            heightFactor: 0.72,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
              child: Column(
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: Icon(
                          CupertinoIcons.checkmark_seal_fill,
                          color: Color(0xFFF3F6FC),
                          size: 23,
                        ),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Change Status',
                              style: TextStyle(
                                color: Color(0xFFF1F4F8),
                                fontSize: 23,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Select invoice payment status',
                              style: TextStyle(
                                color: Color(0xFFA0A7B8),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  Expanded(
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: statuses.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final status = statuses[index];
                        final selectedNow = status == _status;
                        final statusColor = _statusColor(status);

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
                                    ? statusColor.withValues(alpha: 0.14)
                                    : const Color(0xFF151922),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: selectedNow
                                      ? statusColor.withValues(alpha: 0.85)
                                      : const Color(0xFF343A49),
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.18),
                                    blurRadius: 18,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Icon(
                                      _statusIcon(status),
                                      color: statusColor,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 13),

                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _statusLabel(status),
                                          style: const TextStyle(
                                            color: Color(0xFFF1F4F8),
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          subtitleFor(status),
                                          style: const TextStyle(
                                            color: Color(0xFFA0A7B8),
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w500,
                                            height: 1.25,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(width: 8),

                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Icon(
                                      selectedNow
                                          ? CupertinoIcons.checkmark_circle_fill
                                          : CupertinoIcons.chevron_right,
                                      color: selectedNow
                                          ? statusColor
                                          : const Color(0xFF9AA3B7),
                                      size: selectedNow ? 21 : 16,
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

  Color _statusColor(String status) {
    switch (status.trim().toLowerCase()) {
      case 'draft':
        return const Color(0xFFF3F6FC);
      case 'sent':
        return const Color(0xFF0EA5E9);
      case 'partial':
        return const Color(0xFFFFB300);
      case 'paid':
        return const Color(0xFF22C55E);
      case 'overdue':
        return const Color(0xFFE85D3D);
      case 'void':
        return const Color(0xFFBFC6D4);
      default:
        return const Color(0xFFBFC6D4);
    }
  }

  IconData _statusIcon(String status) {
    switch (status.trim().toLowerCase()) {
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
      case 'void':
        return CupertinoIcons.xmark_circle_fill;
      default:
        return CupertinoIcons.circle_fill;
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

  Future<void> _showTaxEditor() async {
    final controller = TextEditingController(
      text: _taxAmount == 0 ? '' : _taxAmount.toStringAsFixed(2),
    );

    final value = await _showAmountEditor(
      title: 'Tax Amount',
      label: 'Tax',
      controller: controller,
    );

    await Future.delayed(const Duration(milliseconds: 450));
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

    await Future.delayed(const Duration(milliseconds: 450));
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
      backgroundColor: const Color(0xFF242730),
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
                  color: const Color(0xFF8B5CF6),
                  borderRadius: BorderRadius.circular(18),
                  onPressed: () {
                    final parsed = EstimateCalculator.parseNumber(
                      controller.text,
                    );

                    FocusManager.instance.primaryFocus?.unfocus();
                    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');

                    Navigator.of(context).pop(parsed);
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
      backgroundColor: const Color(0xFF242730),
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
                  color: const Color(0xFF181B23),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF303442)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.26),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.025),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
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
                                child: _PremiumPickerLeadingIcon(
                                  icon: icon,
                                  tone: _PickerIconTone.softWhite,
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
                                  _PremiumPickerLeadingIcon(
                                    icon: icon,
                                    tone: _PickerIconTone.softWhite,
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
                constraints: const BoxConstraints(minHeight: 84),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                decoration: BoxDecoration(
                  color: const Color(0xFF181B23),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF303442)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.02),
                      blurRadius: 6,
                      offset: const Offset(0, -1),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _PremiumPickerLeadingIcon(
                      icon: icon,
                      tone: _PickerIconTone.softWhite,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFA1A7B8),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    TextField(
                      controller: controller,
                      keyboardType: keyboardType,
                      textAlign: TextAlign.center,
                      cursorColor: const Color(0xFF8B5CF6),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: hintText,
                        hintStyle: const TextStyle(
                          color: Color(0xFF8E93A6),
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
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
                            color: const Color(0xFFF3F6FC),
                            size: 30,
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
                          const Divider(color: Color(0xFF303442), height: 1),
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
                                backgroundColor: const Color(0xFF242730),
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
                          const Divider(color: Color(0xFF303442), height: 1),
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
                          color: const Color(0xFF8B5CF6),
                          borderRadius: BorderRadius.circular(18),
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
                                  fontSize: 16,
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
    final listeningNotifier = ValueNotifier<bool>(false);
    final speechPreviewNotifier = ValueNotifier<String>('');
    String liveVoiceBaseText = '';

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: const Color(0xFF1B1F28),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.84,
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
                        _PremiumPickerLeadingIcon(
                          icon: icon,
                          tone: _PickerIconTone.softWhite,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: Color(0xFFF1F4F8),
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
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

                    const SizedBox(height: 12),

                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF151922),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: const Color(0xFF343A49),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ValueListenableBuilder<bool>(
                              valueListenable: listeningNotifier,
                              builder: (context, isRecording, _) {
                                return _LargeEditorActionButton(
                                  icon: isRecording
                                      ? CupertinoIcons.stop_fill
                                      : CupertinoIcons.mic_fill,
                                  color: isRecording
                                      ? const Color(0xFFFF6B6B)
                                      : const Color(0xFF8B5CF6),
                                  onTap: () async {
                                    if (isRecording) {
                                      await _stopVoiceInput();
                                      listeningNotifier.value = false;
                                      speechPreviewNotifier.value = '';
                                    } else {
                                      listeningNotifier.value = true;
                                      speechPreviewNotifier.value = '';
                                      liveVoiceBaseText = tempController.text.trim();

                                      await _startVoiceInput(
                                        controller: tempController,
                                        append: true,
                                        onLiveText: (spokenText) {
                                          final clean = spokenText.trim();
                                          if (clean.isEmpty) return;

                                          speechPreviewNotifier.value = clean;

                                          final next = liveVoiceBaseText.isEmpty
                                              ? clean
                                              : '$liveVoiceBaseText $clean';

                                          tempController.value = TextEditingValue(
                                            text: next,
                                            selection: TextSelection.collapsed(
                                              offset: next.length,
                                            ),
                                          );
                                        },
                                        onDone: () {
                                          listeningNotifier.value = false;
                                          speechPreviewNotifier.value = '';
                                        },
                                      );
                                    }
                                  },
                                );
                              },
                            ),
                            const SizedBox(width: 6),
                            _LargeEditorActionButton(
                              icon: Icons.select_all_rounded,
                              color: const Color(0xFFF3F6FC),
                              onTap: () {
                                final text = tempController.text;
                                if (text.isEmpty) return;

                                focusNode.requestFocus();
                                tempController.selection = TextSelection(
                                  baseOffset: 0,
                                  extentOffset: text.length,
                                );
                              },
                            ),
                            const SizedBox(width: 6),
                            _LargeEditorActionButton(
                              icon: CupertinoIcons.doc_on_doc,
                              color: const Color(0xFFF3F6FC),
                              onTap: () async {
                                final text = tempController.text.trim();
                                if (text.isEmpty) return;

                                await Clipboard.setData(ClipboardData(text: text));
                                _showSnack('Copied');
                              },
                            ),
                            const SizedBox(width: 6),
                            _LargeEditorActionButton(
                              icon: CupertinoIcons.xmark,
                              color: const Color(0xFFFF6B6B),
                              onTap: () {
                                tempController.clear();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    Expanded(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF151922),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: const Color(0xFF343A49),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.26),
                              blurRadius: 18,
                              offset: const Offset(0, 10),
                            ),
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.025),
                              blurRadius: 8,
                              offset: const Offset(0, -2),
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: tempController,
                          focusNode: focusNode,
                          expands: true,
                          maxLines: null,
                          minLines: null,
                          keyboardType: TextInputType.multiline,
                          textAlignVertical: TextAlignVertical.top,
                          cursorColor: const Color(0xFF8B5CF6),
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

                    ValueListenableBuilder<bool>(
                      valueListenable: listeningNotifier,
                      builder: (context, isRecording, _) {
                        if (!isRecording) return const SizedBox.shrink();

                        return GestureDetector(
                          onTap: () async {
                            await _stopVoiceInput();
                            listeningNotifier.value = false;
                            speechPreviewNotifier.value = '';
                          },
                          child: Container(
                            margin: const EdgeInsets.only(top: 12),
                            padding: const EdgeInsets.fromLTRB(14, 11, 14, 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF181B23),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFF8B5CF6).withValues(alpha: 0.75),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.24),
                                  blurRadius: 14,
                                  offset: const Offset(0, 7),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      CupertinoIcons.waveform,
                                      color: Color(0xFF8B5CF6),
                                      size: 17,
                                    ),
                                    const SizedBox(width: 10),
                                    const Expanded(
                                      child: Text(
                                        'Listening... speak now',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.1,
                                        ),
                                      ),
                                    ),
                                    const _RecordingPulseDot(),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                const _RecordingActiveBar(),
                                const SizedBox(height: 8),
                                _LiveSpeechTypingPreview(
                                  textListenable: speechPreviewNotifier,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 14),

                    Row(
                      children: [
                        Expanded(
                          child: CupertinoButton(
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            color: const Color(0xFF2A2D36),
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
                                color: Color(0xFFF3F6FC),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: CupertinoButton(
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            color: const Color(0xFF8B5CF6),
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
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  CupertinoIcons.check_mark_circled_solid,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Save',
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
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    await Future.delayed(const Duration(milliseconds: 500));

    listeningNotifier.dispose();
    speechPreviewNotifier.dispose();
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
            _PremiumPickerLeadingIcon(
              icon: icon,
              tone: _PickerIconTone.softWhite,
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
                color: Color(0xFFA1A7B8),
                fontSize: 13,
                fontWeight: FontWeight.w600,
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
        color: const Color(0xFF181B23),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF303442)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.26),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.025),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PremiumPickerLeadingIcon(
                icon: icon,
                tone: _PickerIconTone.softWhite,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFFA1A7B8),
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
              cursorColor: const Color(0xFF8B5CF6),
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

  Widget _clientPropertyFormPanel({
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF181B23),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF303442),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.26),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.025),
            blurRadius: 8,
            spreadRadius: -4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildClientPropertySectionCard({
    required String title,
    String? subtitle,
    required Widget child,
    Widget? trailing,
  }) {
    return _buildSectionCard(
      title: title,
      subtitle: subtitle,
      child: child,
      trailing: trailing,
    );
  }

  Widget _formPanel({
    required List<Widget> children,
  }) {
    return _clientPropertyFormPanel(children: children);
  }

  Widget _largeTextRow({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
    _PickerIconTone iconTone = _PickerIconTone.neutral,
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
              _PremiumPickerLeadingIcon(
                icon: icon,
                tone: iconTone,
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

  Widget _sheetGlowingIcon({
    required IconData icon,
    required _PickerIconTone tone,
    double size = 20,
  }) {
    Color iconColor;

    switch (tone) {
      case _PickerIconTone.clientBlue:
        iconColor = const Color(0xFF38BDF8);
        break;

      case _PickerIconTone.softWhite:
        iconColor = const Color(0xFFF3F6FC);
        break;

      default:
        iconColor = const Color(0xFFB8C1D9);
        break;
    }

    return SizedBox(
      width: size + 4,
      height: size + 4,
      child: Center(
        child: Icon(
          icon,
          color: iconColor.withValues(alpha: 0.88),
          size: size,
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
    final sheetHeight = items.length <= 1
        ? 0.42
        : items.length <= 3
        ? 0.56
        : 0.72;

    return showModalBottomSheet<T>(
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
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: FractionallySizedBox(
            heightFactor: sheetHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
              child: Column(
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

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Icon(
                          icon,
                          color: const Color(0xFFF3F6FC),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: Color(0xFFF1F4F8),
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              style: const TextStyle(
                                color: Color(0xFFA0A7B8),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  Expanded(
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final itemTitle = titleBuilder(item).trim();
                        final itemSubtitle =
                        (subtitleBuilder?.call(item) ?? '').trim();
                        final itemIcon =
                            itemIconBuilder?.call(item) ?? CupertinoIcons.circle;

                        return Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => Navigator.pop(sheetContext, item),
                            child: Container(
                              padding: const EdgeInsets.all(15),
                              decoration: BoxDecoration(
                                color: const Color(0xFF151922),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0xFF343A49),
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.20),
                                    blurRadius: 18,
                                    offset: const Offset(0, 8),
                                  ),
                                  BoxShadow(
                                    color: Colors.white.withValues(alpha: 0.018),
                                    blurRadius: 8,
                                    spreadRadius: -4,
                                    offset: const Offset(0, -2),
                                  ),
                                ],
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Icon(
                                      itemIcon,
                                      color: const Color(0xFFF3F6FC),
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 13),

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
                                            color: Color(0xFFF1F4F8),
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                            height: 1.25,
                                          ),
                                        ),
                                        if (itemSubtitle.isNotEmpty) ...[
                                          const SizedBox(height: 5),
                                          Text(
                                            itemSubtitle,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Color(0xFFA0A7B8),
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

                                  const Padding(
                                    padding: EdgeInsets.only(top: 3),
                                    child: Icon(
                                      CupertinoIcons.chevron_right,
                                      color: Color(0xFFBFC6D4),
                                      size: 16,
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
        color: const Color(0xFF252934),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF343846),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.38),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.035),
            blurRadius: 12,
            spreadRadius: -6,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFFF4F6FA),
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.25,
                      ),
                    ),
                    if ((subtitle ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          color: Color(0xFFA0A7B8),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                trailing,
              ],
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
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(96),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF242730),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: const Color(0xFF343846),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.38),
                        blurRadius: 28,
                        offset: const Offset(0, 16),
                      ),
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.035),
                        blurRadius: 12,
                        spreadRadius: -6,
                        offset: const Offset(0, -3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Back button
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A2D36),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFF3A3E4B),
                                width: 1,
                              ),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.arrow_back_ios_new_rounded,
                                color: Colors.white.withOpacity(0.82),
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Title + icon
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Create Invoice',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Color(0xFFF4F6FA),
                                fontWeight: FontWeight.w800,
                                fontSize: 20,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Subtotal ${EstimateFormatters.formatCurrency(_subtotal)} • Total ${EstimateFormatters.formatCurrency(_total)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFA0A7B8),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.receipt_long_rounded,
                          // receipt_long_rounded
                        color: Color(0xFF9B7FE8),
                        size: 24,
                      ),
                      const SizedBox(width: 6),
                    ],
                  ),
                ),
              ),
            ),
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
            _buildClientPropertySectionCard(
              title: 'Client & Property',
              subtitle: 'Client and invoice property',
              child: _clientPropertyFormPanel(
                children: [
                  _PremiumPickerField(
                    label: 'Client',
                    leadingIcon: CupertinoIcons.person_fill,
                    iconTone: _PickerIconTone.clientBlue,
                    value: _selectedClient == null
                        ? ''
                        : _selectedClient!.fullName,
                    onTap: _selectClient,
                    showClearButton: _selectedClient != null,
                    showChevron: false,
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
                  const Divider(color: Color(0xFF303442), height: 1),
                  _PremiumPickerField(
                    label: 'Property',
                    leadingIcon: CupertinoIcons.house_fill,
                    iconTone: _PickerIconTone.propertyOrange,
                    value: _selectedProperty == null
                        ? ''
                        : _selectedProperty!.fullAddress,
                    onTap: _selectProperty,
                    showClearButton: _selectedProperty != null,
                    showChevron: false,
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
            _buildClientPropertySectionCard(
              title: 'Invoice Header',
              subtitle: 'Status and dates',
              child: _clientPropertyFormPanel(
                children: [
                  _PremiumPickerField(
                    label: 'Status',
                    leadingIcon: _statusIcon(_status),
                    iconTone: _PickerIconTone.statusGreen,
                    iconColor: _statusColor(_status),
                    value: _statusLabel(_status),
                    onTap: _pickStatus,
                    showClearButton: false,
                  ),
                  const Divider(color: Color(0xFF303442), height: 1),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: _PremiumPickerField(
                            label: 'Issue Date',
                            leadingIcon: CupertinoIcons.calendar,
                            iconTone: _PickerIconTone.itemBlue,
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
                          color: const Color(0xFF303442),
                        ),
                        Expanded(
                          child: _PremiumPickerField(
                            label: 'Due Date',
                            leadingIcon: CupertinoIcons.calendar_badge_plus,
                            iconTone: _PickerIconTone.itemBlue,
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
            _buildClientPropertySectionCard(
              title: 'Invoice Info',
              subtitle: 'Main information',
              child: _clientPropertyFormPanel(
                children: [
                  _PremiumTitleField(
                    controller: _titleController,
                    label: 'Title',
                    hintText: 'Invoice title',
                    icon: CupertinoIcons.doc_fill,
                    iconTone: _PickerIconTone.softWhite,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildClientPropertySectionCard(
              title: 'Items',
              subtitle: 'Invoice line items',
              trailing: GestureDetector(
                onTap: () => _addOrEditItem(),
                child: const SizedBox(
                  width: 28,
                  height: 28,
                  child: Center(
                    child: Icon(
                      CupertinoIcons.add_circled_solid,
                      color: Color(0xFF8B5CF6),
                      size: 26,
                    ),
                  ),
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
            _buildClientPropertySectionCard(
              title: 'Notes & Terms',
              subtitle: 'Additional information',
              child: _clientPropertyFormPanel(
                children: [
                  _largeTextRow(
                    icon: CupertinoIcons.text_bubble_fill,
                    iconTone: _PickerIconTone.softWhite,
                    label: 'Notes',
                    value: _notesController.text,
                    onTap: () {
                      _openLargeTextEditor(
                        title: 'Edit Notes',
                        controller: _notesController,
                        icon: CupertinoIcons.text_bubble_fill,
                      );
                    },
                  ),
                  const Divider(color: Color(0xFF303442), height: 1),
                  _largeTextRow(
                    icon: CupertinoIcons.doc_text_fill,
                    iconTone: _PickerIconTone.softWhite,
                    label: 'Terms',
                    value: _termsController.text,
                    onTap: () {
                      _openLargeTextEditor(
                        title: 'Edit Terms',
                        controller: _termsController,
                        icon: CupertinoIcons.doc_text_fill,
                      );
                    },
                  ),
                  const Divider(color: Color(0xFF303442), height: 1),
                  _largeTextRow(
                    icon: CupertinoIcons.creditcard_fill,
                    iconTone: _PickerIconTone.emptyPurple,
                    label: 'Payment Instructions',
                    value: _paymentInstructionsController.text,
                    onTap: () {
                      _openLargeTextEditor(
                        title: 'Edit Payment Instructions',
                        controller: _paymentInstructionsController,
                        icon: CupertinoIcons.creditcard_fill,
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildClientPropertySectionCard(
              title: 'Totals',
              subtitle: 'Invoice totals',
              child: Column(
                children: [
                  _TotalsPanel(
                    children: [
                      _TotalsEditRow(
                        icon: CupertinoIcons.money_dollar_circle,
                        iconTone: _PickerIconTone.softWhite,
                        label: 'Tax Amount',
                        value: '${EstimateFormatters.formatCurrency(_taxAmount)} ($_currencyCode)',
                        onTap: _showTaxEditor,
                      ),
                      const Divider(color: Color(0xFF303442), height: 1),
                      _TotalsEditRow(
                        icon: CupertinoIcons.tag,
                        iconTone: _PickerIconTone.softWhite,
                        label: 'Discount Amount',
                        value: EstimateFormatters.formatCurrency(_discountAmount),
                        onTap: _showDiscountEditor,
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  _TotalsPanel(
                    readOnly: true,
                    children: [
                      _TotalsValueRow(
                        icon: CupertinoIcons.sum,
                        iconTone: _PickerIconTone.propertyOrange,
                        label: 'Subtotal',
                        value: EstimateFormatters.formatCurrency(_subtotal),
                        muted: true,
                      ),
                      const Divider(color: Color(0xFF303442), height: 1),

                      _TotalsValueRow(
                        icon: CupertinoIcons.percent,
                        iconTone: _PickerIconTone.softWhite,
                        label: 'Tax',
                        value: EstimateFormatters.formatCurrency(_taxAmount),
                        muted: true,
                      ),
                      const Divider(color: Color(0xFF303442), height: 1),

                      _TotalsValueRow(
                        icon: CupertinoIcons.tag,
                        iconTone: _PickerIconTone.paymentRed,
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
              color: const Color(0xFF8B5CF6),
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

class _PremiumPickerField extends StatelessWidget {
  final String label;
  final IconData leadingIcon;
  final _PickerIconTone iconTone;
  final String value;
  final VoidCallback onTap;
  final bool showClearButton;
  final VoidCallback? onClear;
  final IconData? emptyIcon;
  final VoidCallback? onEmptyIconTap;
  final int valueMaxLines;
  final bool showChevron;
  final Color? iconColor;

  const _PremiumPickerField({
    required this.label,
    required this.leadingIcon,
    required this.value,
    required this.onTap,
    this.iconTone = _PickerIconTone.neutral,
    this.showClearButton = false,
    this.onClear,
    this.emptyIcon,
    this.onEmptyIconTap,
    this.valueMaxLines = 2,
    this.showChevron = true,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = value.trim().isNotEmpty;
    final isPlaceholder = value.trim().toLowerCase().startsWith('select');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            14,
            hasValue ? 12 : 0,
            14,
            hasValue ? 12 : 0,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: hasValue ? 58 : 68,
            ),
            child: Row(
              children: [
                Expanded(
                  child: hasValue
                      ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _PremiumPickerLeadingIcon(
                            icon: leadingIcon,
                            tone: iconTone,
                            colorOverride: iconColor,
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
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.only(left: 24),
                        child: Text(
                          value,
                          maxLines: valueMaxLines,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isPlaceholder
                                ? const Color(0xFF697086)
                                : Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  )
                      : Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Transform.scale(
                        scale: 1.22,
                        child: _PremiumPickerLeadingIcon(
                          icon: leadingIcon,
                          tone: iconTone,
                          colorOverride: iconColor,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        label,
                        style: const TextStyle(
                          color: Color(0xFFA1A7B8),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
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
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: const Color(0xFF20232D),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: const Color(0xFF343846),
                          width: 1,
                        ),
                      ),
                      child: const Icon(
                        CupertinoIcons.add,
                        color: Color(0xFF8B5CF6),
                        size: 20,
                      ),
                    ),
                  )
                else if (showChevron)
                    const Icon(
                      CupertinoIcons.chevron_right,
                      color: Color(0xFF8E93A6),
                      size: 18,
                    ),
              ],
            ),
          ),
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
  final _PickerIconTone iconTone;

  const _PremiumTitleField({
    required this.controller,
    required this.label,
    required this.hintText,
    required this.icon,
    this.iconTone = _PickerIconTone.neutral,
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
                    _PremiumPickerLeadingIcon(
                      icon: widget.icon,
                      tone: widget.iconTone,
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

enum _PickerIconTone {
  neutral,
  clientBlue,
  propertyOrange,
  statusGreen,
  softWhite,
  invoiceYellow,
  itemBlue,
  emptyPurple,
  notesYellow,
  termsTurquoise,
  paymentRed,
}

class _PremiumPickerLeadingIcon extends StatelessWidget {
  final IconData icon;
  final _PickerIconTone tone;
  final Color? colorOverride;

  const _PremiumPickerLeadingIcon({
    required this.icon,
    required this.tone,
    this.colorOverride,
  });

  @override
  Widget build(BuildContext context) {
    Color iconColor;

    switch (tone) {
      case _PickerIconTone.clientBlue:
        iconColor = const Color(0xFF7C5CFF);
        break;

      case _PickerIconTone.propertyOrange:
        iconColor = const Color(0xFFFFA726);
        break;

      case _PickerIconTone.statusGreen:
        iconColor = const Color(0xFF22C55E);
        break;

      case _PickerIconTone.softWhite:
        iconColor = const Color(0xFFF3F6FC);
        break;

      case _PickerIconTone.invoiceYellow:
        iconColor = const Color(0xFFFFB300);
        break;

      case _PickerIconTone.itemBlue:
        iconColor = const Color(0xFF3B82F6);
        break;

      case _PickerIconTone.emptyPurple:
        iconColor = const Color(0xFFA855F7);
        break;

      case _PickerIconTone.notesYellow:
        iconColor = const Color(0xFFFFB300);
        break;

      case _PickerIconTone.termsTurquoise:
        iconColor = const Color(0xFF22D3EE);
        break;

      case _PickerIconTone.paymentRed:
        iconColor = const Color(0xFFFF6B6B);
        break;

      case _PickerIconTone.neutral:
        iconColor = const Color(0xFF8E93A6);
        break;
    }

    return SizedBox(
      width: 19,
      height: 19,
      child: Center(
        child: Icon(
          icon,
          color: (colorOverride ?? iconColor).withValues(alpha: 0.88),
          size: 15.5,
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
  int _monthDirection = 1;

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
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return '${months[date.month - 1]} ${date.year}';
  }

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  void _changeMonth(int delta) {
    setState(() {
      _monthDirection = delta >= 0 ? 1 : -1;
      visibleMonth = DateTime(
        visibleMonth.year,
        visibleMonth.month + delta,
      );
    });
  }

  BoxDecoration _sheetPanelDecoration() {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF252830),
          Color(0xFF1D2028),
          Color(0xFF181B23),
        ],
      ),
      border: Border.all(color: const Color(0xFF343846)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.30),
          blurRadius: 22,
          offset: const Offset(0, 12),
        ),
        BoxShadow(
          color: Colors.white.withValues(alpha: 0.025),
          blurRadius: 8,
          offset: const Offset(0, -2),
        ),
      ],
    );
  }

  Widget _navButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF20232D),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF303442)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Icon(
            icon,
            color: const Color(0xFFE3E7F2),
            size: 18,
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedMonthTitle() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      transitionBuilder: (child, animation) {
        final offsetTween = Tween<Offset>(
          begin: Offset(_monthDirection > 0 ? 0.18 : -0.18, 0),
          end: Offset.zero,
        );

        return ClipRect(
          child: FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: offsetTween.animate(
                CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                ),
              ),
              child: child,
            ),
          ),
        );
      },
      child: Text(
        _monthLabel(visibleMonth),
        key: ValueKey('month-${visibleMonth.year}-${visibleMonth.month}'),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.2,
        ),
      ),
    );
  }

  Widget _weekdayCell(String text) {
    return Container(
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF20232D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF343846)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFFB8C1D9),
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.25,
        ),
      ),
    );
  }

  Widget _buildWeekdaysRow() {
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: List.generate(days.length, (index) {
          return Expanded(
            child: _weekdayCell(days[index]),
          );
        }),
      ),
    );
  }

  Widget _buildCalendarGrid({
    required int leadingEmptyDays,
    required int daysInMonth,
  }) {
    return GridView.builder(
      key: ValueKey('grid-${visibleMonth.year}-${visibleMonth.month}'),
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: 42,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemBuilder: (context, index) {
        final dayNumber = index - leadingEmptyDays + 1;
        final isCurrentMonth = dayNumber >= 1 && dayNumber <= daysInMonth;

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
              visibleMonth = DateTime(date.year, date.month);
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: selected
                  ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF9B6BFF),
                  Color(0xFF7C4DFF),
                ],
              )
                  : isCurrentMonth
                  ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF20232D).withValues(alpha: 0.78),
                  const Color(0xFF181B23).withValues(alpha: 0.62),
                ],
              )
                  : null,
              color: (!selected && !isCurrentMonth)
                  ? Colors.transparent
                  : null,
              border: Border.all(
                color: selected
                    ? const Color(0xFFB99CFF).withValues(alpha: 0.95)
                    : isCurrentMonth
                    ? const Color(0xFF343846).withValues(alpha: 0.65)
                    : Colors.transparent,
                width: 1,
              ),
              boxShadow: selected
                  ? [
                BoxShadow(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.34),
                  blurRadius: 16,
                  offset: const Offset(0, 5),
                ),
              ]
                  : isCurrentMonth
                  ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ]
                  : null,
            ),
            alignment: Alignment.center,
            child: Text(
              '${date.day}',
              style: TextStyle(
                color: selected
                    ? Colors.white
                    : isCurrentMonth
                    ? const Color(0xFFF2F5FB)
                    : const Color(0xFF667089),
                fontSize: 16,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
        );
      },
    );
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
        heightFactor: 0.84,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFF4B4F5F),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 18),

              Row(
                children: [
                  const _PremiumPickerLeadingIcon(
                    icon: CupertinoIcons.calendar,
                    tone: _PickerIconTone.softWhite,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    widget.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: _sheetPanelDecoration(),
                child: Row(
                  children: [
                    _navButton(
                      icon: CupertinoIcons.chevron_left,
                      onTap: () => _changeMonth(-1),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Center(
                        child: _buildAnimatedMonthTitle(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _navButton(
                      icon: CupertinoIcons.chevron_right,
                      onTap: () => _changeMonth(1),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                  decoration: _sheetPanelDecoration(),
                  child: Column(
                    children: [
                      _buildWeekdaysRow(),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          transitionBuilder: (child, animation) {
                            final offsetTween = Tween<Offset>(
                              begin: Offset(_monthDirection > 0 ? 0.12 : -0.12, 0),
                              end: Offset.zero,
                            );

                            return ClipRect(
                              child: FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: offsetTween.animate(
                                    CurvedAnimation(
                                      parent: animation,
                                      curve: Curves.easeOutCubic,
                                    ),
                                  ),
                                  child: child,
                                ),
                              ),
                            );
                          },
                          child: _buildCalendarGrid(
                            leadingEmptyDays: leadingEmptyDays,
                            daysInMonth: daysInMonth,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Color(0xFF8B5CF6),
                      Color(0xFF7C4DFF),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.30),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  borderRadius: BorderRadius.circular(18),
                  color: Colors.transparent,
                  onPressed: () {
                    Navigator.pop(context, selectedDate);
                  },
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        CupertinoIcons.check_mark_circled_solid,
                        color: Colors.white,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Apply Date',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
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
                  _PremiumPickerLeadingIcon(
                    icon: CupertinoIcons.cube_box,
                    tone: _PickerIconTone.softWhite,
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
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => Navigator.pop(context, unit),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: selected
                                ? const Color(0xFF2D313C)
                                : const Color(0xFF181B23),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFF303442),
                            ),
                            boxShadow: null,
                          ),
                          child: Row(
                            children: [
                              _PremiumPickerLeadingIcon(
                                icon: _unitIcon(unit),
                                tone: _PickerIconTone.softWhite,
                              ),
                              const SizedBox(width: 12),

                              Expanded(
                                child: Text(
                                  EstimateFormatters.formatUnit(unit),
                                  style: const TextStyle(
                                    color: Colors.white,
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
                                    ? const Color(0xFFE5E7EB)
                                    : const Color(0xFF9AA3B7),
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
                              color: const Color(0xFF303442),
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
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF181B23),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF303442)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.025),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: const Row(
        children: [
          _PremiumPickerLeadingIcon(
            icon: CupertinoIcons.square_list,
            tone: _PickerIconTone.softWhite,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'No items yet. Add your first line item.',
              style: TextStyle(
                color: Color(0xFFB8BECC),
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.3,
                shadows: [
                  Shadow(
                    color: Color(0x66000000),
                    blurRadius: 7,
                    offset: Offset(0, 2),
                  ),
                ],
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

  Widget _metricCell({
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        child: Column(
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFA0A7B8),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFF1F4F8),
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricDivider() {
    return Container(
      width: 1,
      height: 52,
      color: const Color(0xFF303645),
    );
  }

  @override
  Widget build(BuildContext context) {
    final description = (item.description ?? '').trim();
    final itemIcon = WorkioIconMapper.resolveFromTitle(item.title);

    final lineTotal = item.lineTotal > 0
        ? item.lineTotal
        : EstimateCalculator.calculateLineTotal(
      quantity: item.quantity,
      unitPrice: item.unitPrice,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF151922),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFF343A49),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.018),
            blurRadius: 8,
            spreadRadius: -4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  itemIcon,
                  color: const Color(0xFFF3F6FC),
                  size: 19,
                ),
              ),
              const SizedBox(width: 12),

              Expanded(
                child: Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFF1F4F8),
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
              ),

              const SizedBox(width: 10),

              _SmallIconButton(
                icon: CupertinoIcons.pencil,
                onTap: onEdit,
              ),
              const SizedBox(width: 8),
              _SmallIconButton(
                icon: CupertinoIcons.trash,
                onTap: onDelete,
                color: const Color(0xFFE85D3D),
              ),
            ],
          ),

          if (description.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              height: 1,
              width: double.infinity,
              color: const Color(0xFF2F3543),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    CupertinoIcons.info_circle,
                    color: Color(0xFFA0A7B8),
                    size: 17,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFA0A7B8),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 14),

          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF1C2029),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF343A49),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                _metricCell(
                  label: 'Qty',
                  value: EstimateFormatters.formatQuantity(item.quantity),
                ),
                _metricDivider(),
                _metricCell(
                  label: 'Unit',
                  value: EstimateFormatters.formatUnit(item.unit),
                ),
                _metricDivider(),
                _metricCell(
                  label: 'Unit Price',
                  value: EstimateFormatters.formatCurrency(item.unitPrice),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: const Color(0xFF1C2029),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: const Color(0xFF343A49),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  CupertinoIcons.money_dollar_circle,
                  color: Color(0xFF22C55E),
                  size: 18,
                ),
                const SizedBox(width: 10),
                const Text(
                  'Line Total',
                  style: TextStyle(
                    color: Color(0xFFA0A7B8),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  EstimateFormatters.formatCurrency(lineTotal),
                  style: const TextStyle(
                    color: Color(0xFFF1F4F8),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
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
      color: const Color(0xFF20242D),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF343A49)),
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

class _TotalsPanel extends StatelessWidget {
  final List<Widget> children;
  final bool readOnly;

  const _TotalsPanel({
    required this.children,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: readOnly
            ? const Color(0xFF242730)
            : const Color(0xFF181B23),
        borderRadius: BorderRadius.circular(20),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: readOnly
              ? const Color(0xFF343846)
              : const Color(0xFF303442),
          width: 1,
        ),
      ),
      child: Column(children: children),
    );
  }
}

class _TotalsEditRow extends StatelessWidget {
  final IconData icon;
  final _PickerIconTone iconTone;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _TotalsEditRow({
    required this.icon,
    required this.iconTone,
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
              _PremiumPickerLeadingIcon(
                icon: icon,
                tone: iconTone,
              ),
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
  final _PickerIconTone iconTone;
  final String label;
  final String value;
  final bool muted;

  const _TotalsValueRow({
    required this.icon,
    required this.iconTone,
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
          _PremiumPickerLeadingIcon(
            icon: icon,
            tone: iconTone,
          ),
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
              color: Color(0xFFD0D5E2),
              fontSize: 15,
              fontWeight: FontWeight.w800,
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
        color: const Color(0xFF181B23),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF303442)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.26),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.025),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          const _PremiumPickerLeadingIcon(
            icon: CupertinoIcons.money_dollar_circle_fill,
            tone: _PickerIconTone.statusGreen,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Total',
              style: TextStyle(
                color: Color(0xFFE1E5EF),
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFFE1E5EF),
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

class _VoiceWaveBar extends StatefulWidget {
  const _VoiceWaveBar();

  @override
  State<_VoiceWaveBar> createState() => _VoiceWaveBarState();
}

class _VoiceWaveBarState extends State<_VoiceWaveBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  final List<double> _bars = const [
    0.25, 0.45, 0.30, 0.65, 0.40, 0.80, 0.35, 0.55,
    0.28, 0.70, 0.42, 0.95, 0.38, 0.60, 0.32, 0.75,
    0.44, 0.58, 0.36, 0.82, 0.30, 0.50, 0.26, 0.68,
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_bars.length, (index) {
              final wave = math.sin(
                (_controller.value * math.pi * 2) + index * 0.45,
              );

              final height = 8 + (_bars[index] * 22 * (0.55 + wave.abs()));

              return Container(
                width: 3,
                height: height,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF8E93A6),
                  borderRadius: BorderRadius.circular(99),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

class _RecordingActiveBar extends StatefulWidget {
  const _RecordingActiveBar();

  @override
  State<_RecordingActiveBar> createState() => _RecordingActiveBarState();
}

class _RecordingActiveBarState extends State<_RecordingActiveBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: 4,
        width: double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final trackWidth = constraints.maxWidth;
            final segmentWidth = trackWidth * 0.38;

            return AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final left = (trackWidth + segmentWidth) * _controller.value -
                    segmentWidth;

                return Stack(
                  children: [
                    Container(
                      height: 4,
                      width: double.infinity,
                      color: const Color(0xFF2A2D38),
                    ),
                    Positioned(
                      left: left,
                      top: 0,
                      bottom: 0,
                      width: segmentWidth,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Color(0xFF8B5CF6),
                              Color(0xFFA855F7),
                              Color(0xFF8B5CF6),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _RecordingPulseDot extends StatefulWidget {
  const _RecordingPulseDot();

  @override
  State<_RecordingPulseDot> createState() => _RecordingPulseDotState();
}

class _RecordingPulseDotState extends State<_RecordingPulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1.0).animate(_controller),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: const Color(0xFFFF4D5E),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF4D5E).withValues(alpha: 0.45),
              blurRadius: 8,
              offset: const Offset(0, 0),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveSpeechTypingPreview extends StatelessWidget {
  final ValueListenable<String> textListenable;

  const _LiveSpeechTypingPreview({
    required this.textListenable,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: textListenable,
      builder: (context, text, _) {
        final clean = text.trim();

        if (clean.isEmpty) {
          return const SizedBox.shrink();
        }

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.25),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
                child: child,
              ),
            );
          },
          child: Row(
            key: ValueKey(clean),
            children: [
              const Text(
                'Typing:',
                style: TextStyle(
                  color: Color(0xFFA1A7B8),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  clean,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const _BlinkingTypingCaret(),
            ],
          ),
        );
      },
    );
  }
}

class _BlinkingTypingCaret extends StatefulWidget {
  const _BlinkingTypingCaret();

  @override
  State<_BlinkingTypingCaret> createState() => _BlinkingTypingCaretState();
}

class _BlinkingTypingCaretState extends State<_BlinkingTypingCaret>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.25, end: 1).animate(_controller),
      child: Container(
        width: 2,
        height: 14,
        decoration: BoxDecoration(
          color: const Color(0xFF8B5CF6),
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }
}

class _LargeEditorActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _LargeEditorActionButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF242730),
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          width: 38,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: const Color(0xFF3A4150),
              width: 1,
            ),
          ),
          child: Icon(
            icon,
            color: color,
            size: 18,
          ),
        ),
      ),
    );
  }
}