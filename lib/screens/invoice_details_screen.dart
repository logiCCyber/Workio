import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';

import '../models/client_model.dart';
import '../models/invoice_item_model.dart';
import '../models/invoice_model.dart';
import '../models/invoice_payment_model.dart';
import '../models/property_model.dart';
import '../models/company_settings_model.dart';
import '../models/invoice_document_model.dart';
import '../models/invoice_email_log_model.dart';

import '../services/client_service.dart';
import '../services/invoice_service.dart';
import '../services/property_service.dart';
import '../services/company_settings_service.dart';
import '../services/invoice_document_service.dart';
import '../services/invoice_pdf_service.dart';
import '../services/invoice_email_service.dart';

import '../utils/estimate_calculator.dart';
import '../utils/estimate_formatters.dart';
import '../utils/company_logo_helper.dart';
import '../utils/workio_icon_mapper.dart';

import '../dialogs/send_invoice_dialog.dart';

class InvoiceDetailsScreen extends StatefulWidget {
  final String invoiceId;

  const InvoiceDetailsScreen({
    super.key,
    required this.invoiceId,
  });

  @override
  State<InvoiceDetailsScreen> createState() => _InvoiceDetailsScreenState();
}

class _InvoiceDetailsScreenState extends State<InvoiceDetailsScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _termsController = TextEditingController();
  final TextEditingController _paymentInstructionsController =
  TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isAddingPayment = false;
  bool _isArchiving = false;
  bool _isDeleting = false;
  bool _isPreviewingPdf = false;
  bool _isSharingPdf = false;
  bool _isSavingPdf = false;
  bool _isDocumentsLoading = false;
  bool _isSendingEmail = false;
  bool _isEmailLogsLoading = false;

  List<InvoiceEmailLogModel> _emailLogs = [];

  CompanySettingsModel? _companySettings;
  List<InvoiceDocumentModel> _documents = [];

  InvoiceModel? _invoice;
  ClientModel? _client;
  PropertyModel? _property;

  List<InvoiceItemModel> _items = [];
  List<InvoicePaymentModel> _payments = [];

  DateTime? _issueDate;
  DateTime? _dueDate;
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
        InvoiceService.getInvoiceById(widget.invoiceId),
        InvoiceService.getInvoiceItems(widget.invoiceId),
        InvoiceService.getInvoicePayments(widget.invoiceId),
        ClientService.getClients(),
        PropertyService.getProperties(),
        CompanySettingsService.getSettings(),
      ]);

      final invoice = results[0] as InvoiceModel?;
      final items = results[1] as List<InvoiceItemModel>;
      final payments = results[2] as List<InvoicePaymentModel>;
      final clients = results[3] as List<ClientModel>;
      final properties = results[4] as List<PropertyModel>;
      final companySettings = results[5] as CompanySettingsModel?;

      if (invoice == null) {
        if (!mounted) return;
        _showSnack('Invoice not found');
        Navigator.pop(context);
        return;
      }

      ClientModel? selectedClient;
      for (final client in clients) {
        if (client.id == invoice.clientId) {
          selectedClient = client;
          break;
        }
      }

      PropertyModel? selectedProperty;
      for (final property in properties) {
        if (property.id == invoice.propertyId) {
          selectedProperty = property;
          break;
        }
      }

      if (!mounted) return;

      setState(() {
        _invoice = invoice;
        _client = selectedClient;
        _property = selectedProperty;
        _items = items;
        _payments = payments;
        _companySettings = companySettings;
        _issueDate = invoice.issueDate;
        _dueDate = invoice.dueDate;
        _status = invoice.status;
        _taxAmount = invoice.tax;
        _discountAmount = invoice.discount;

        _titleController.text = invoice.title;
        _notesController.text = invoice.notes ?? '';
        _termsController.text = invoice.terms ?? '';
        _paymentInstructionsController.text =
            invoice.paymentInstructions ?? '';

        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showSnack('Failed to load invoice');
    }
    await _loadDocuments();
    await _loadEmailLogs();
  }

  Future<void> _editPayment(InvoicePaymentModel existingPayment) async {
    final payment = await _showPaymentEditor(
      existingPayment: existingPayment,
    );

    if (payment == null) return;

    setState(() {
      _isAddingPayment = true;
    });

    try {
      await InvoiceService.updatePayment(payment);

      if (!mounted) return;

      await _loadInitialData();
      _showSnack('Payment updated');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to update payment');
    } finally {
      if (!mounted) return;

      setState(() {
        _isAddingPayment = false;
      });
    }
  }

  Future<void> _markAsPaidShortcut() async {
    final invoice = _invoice;

    if (invoice == null) {
      _showSnack('Invoice not found');
      return;
    }

    if (_balanceDue <= 0) {
      _showSnack('This invoice is already paid');
      return;
    }

    final confirmed = await _showWorkioConfirmDialog(
      icon: CupertinoIcons.checkmark_circle_fill,
      accent: const Color(0xFF33C27F),
      title: 'Confirm full payment?',
      message:
      'Are you sure you received the full balance amount of ${EstimateFormatters.formatCurrency(_balanceDue)}?',
      confirmText: 'Mark Paid',
    );

    if (!confirmed) return;

    if (confirmed != true) return;

    setState(() {
      _isAddingPayment = true;
    });

    try {
      final payment = InvoicePaymentModel(
        id: '',
        invoiceId: invoice.id,
        adminAuthId: '',
        amount: _balanceDue,
        paymentDate: DateTime.now(),
        paymentMethod: 'Manual',
        referenceNumber: null,
        notes: 'Marked as paid from shortcut',
        createdAt: null,
      );

      await InvoiceService.addPayment(payment);

      if (!mounted) return;

      await _loadInitialData();
      _showSnack('Invoice marked as paid');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to mark invoice as paid');
    } finally {
      if (!mounted) return;

      setState(() {
        _isAddingPayment = false;
      });
    }
  }

  static const List<String> _paymentMethodOptions = [
    'Cash',
    'E.transfer',
    'Card',
    'Bank',
    'Cheque',
    'Other',
  ];

  Future<InvoicePaymentModel?> _showPaymentEditor({
    InvoicePaymentModel? existingPayment,
  }) async {
    final invoice = _invoice;
    if (invoice == null) return null;

    final amountController = TextEditingController(
      text: existingPayment == null || existingPayment.amount == 0
          ? ''
          : existingPayment.amount.toStringAsFixed(2),
    );

    final referenceController = TextEditingController(
      text: existingPayment?.referenceNumber ?? '',
    );

    final notesController = TextEditingController(
      text: existingPayment?.notes ?? '',
    );

    DateTime paymentDate = existingPayment?.paymentDate ?? DateTime.now();
    String selectedMethod = (existingPayment?.paymentMethod ?? '').trim();

    if (selectedMethod.isEmpty) {
      selectedMethod = 'Cash';
    }

    final result = await showModalBottomSheet<InvoicePaymentModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1B1E27),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
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

                    _buildSheetHeader(
                      icon: existingPayment == null
                          ? CupertinoIcons.plus_circle
                          : CupertinoIcons.pencil_circle,
                      title: existingPayment == null
                          ? 'Add Payment'
                          : 'Edit Payment',
                      subtitle: existingPayment == null
                          ? 'Record a payment for this invoice'
                          : 'Update payment details',
                    ),

                    const SizedBox(height: 18),

                    _paymentSheetPanel(
                      children: [
                        _paymentSheetInputRow(
                          icon: CupertinoIcons.money_dollar_circle,
                          color: const Color(0xFFF3F6FC),
                          label: 'Amount',
                          controller: amountController,
                          hintText: '0.00',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                        _summaryDivider(),
                        _paymentSheetPickerRow(
                          icon: CupertinoIcons.calendar,
                          color: const Color(0xFFF3F6FC),
                          label: 'Payment Date',
                          value: EstimateFormatters.formatDate(paymentDate),
                          onTap: () async {
                            final picked = await _pickDateWithWorkioSheet(
                              initialDate: paymentDate,
                              title: 'Select payment date',
                            );

                            if (picked == null) return;

                            setModalState(() {
                              paymentDate = picked;
                            });
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    Align(
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: const [
                          Icon(
                            CupertinoIcons.creditcard,
                            color: const Color(0xFFF3F6FC),
                            size: 15,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Payment Method',
                            style: TextStyle(
                              color: const Color(0xFFBFC6D4),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    _paymentMethodSegment(
                      selectedMethod: selectedMethod,
                      onChanged: (method) {
                        setModalState(() {
                          selectedMethod = method;
                        });
                      },
                    ),

                    const SizedBox(height: 14),

                    _paymentSheetPanel(
                      children: [
                        _paymentSheetInputRow(
                          color: const Color(0xFFF3F6FC),
                          label: 'Reference Number',
                          controller: referenceController,
                          hintText: 'Optional reference',
                        ),
                        _summaryDivider(),
                        _paymentSheetInputRow(
                          color: const Color(0xFFF3F6FC),
                          label: 'Notes',
                          controller: notesController,
                          hintText: 'Optional notes',
                          maxLines: 3,
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    SizedBox(
                      width: double.infinity,
                      child: CupertinoButton(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        color: const Color(0xFF7C5CFF),
                        borderRadius: BorderRadius.circular(16),
                        onPressed: () async {
                          final amount = EstimateCalculator.parseNumber(
                            amountController.text,
                          );

                          if (amount <= 0) return;

                          final payment = InvoicePaymentModel(
                            id: existingPayment?.id ?? '',
                            invoiceId: invoice.id,
                            adminAuthId: existingPayment?.adminAuthId ?? '',
                            amount: amount,
                            paymentDate: paymentDate,
                            paymentMethod: selectedMethod.trim().isEmpty
                                ? null
                                : selectedMethod,
                            referenceNumber: referenceController.text.trim().isEmpty
                                ? null
                                : referenceController.text.trim(),
                            notes: notesController.text.trim().isEmpty
                                ? null
                                : notesController.text.trim(),
                            createdAt: existingPayment?.createdAt,
                          );

                          FocusManager.instance.primaryFocus?.unfocus();
                          await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
                          await Future.delayed(const Duration(milliseconds: 300));

                          if (context.mounted) {
                            Navigator.pop(context, payment);
                          }
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              existingPayment == null
                                  ? CupertinoIcons.plus_circle
                                  : CupertinoIcons.checkmark_circle,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              existingPayment == null
                                  ? 'Add Payment'
                                  : 'Save Changes',
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
            );
          },
        );
      },
    );

    await Future.delayed(const Duration(milliseconds: 500));

    amountController.dispose();
    referenceController.dispose();
    notesController.dispose();

    return result;
  }

  Widget _paymentSheetPanel({
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF242730),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFF343846),
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
      child: Column(
        children: children,
      ),
    );
  }

  Widget _paymentSheetInputRow({
    IconData? icon,
    Color color = const Color(0xFF8E93A6),
    required String label,
    required TextEditingController controller,
    required String hintText,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        crossAxisAlignment:
        maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Padding(
              padding: EdgeInsets.only(top: maxLines > 1 ? 4 : 0),
              child: Icon(
                icon,
                color: color,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
          ],
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
                const SizedBox(height: 5),
                TextField(
                  controller: controller,
                  keyboardType: keyboardType,
                  maxLines: maxLines,
                  minLines: maxLines > 1 ? 3 : 1,
                  cursorColor: const Color(0xFF7C5CFF),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentSheetPickerRow({
    IconData? icon,
    Color color = const Color(0xFF8E93A6),
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  color: color,
                  size: 18,
                ),
                const SizedBox(width: 12),
              ],
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
                    const SizedBox(height: 5),
                    Text(
                      value,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
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

  IconData _paymentMethodIcon(String method) {
    switch (method.trim().toLowerCase()) {
      case 'cash':
        return CupertinoIcons.money_dollar_circle;

      case 'e-transfer':
      case 'e.transfer':
        return CupertinoIcons.paperplane_fill;

      case 'card':
        return CupertinoIcons.creditcard_fill;

      case 'bank transfer':
      case 'bank':
        return CupertinoIcons.building_2_fill;

      case 'cheque':
        return CupertinoIcons.doc_text_fill;

      case 'other':
        return CupertinoIcons.ellipsis_circle_fill;

      default:
        return CupertinoIcons.ellipsis_circle;
    }
  }

  Widget _paymentMethodSegment({
    required String selectedMethod,
    required ValueChanged<String> onChanged,
  }) {
    final methods = _paymentMethodOptions;
    final activeIndex = methods.indexOf(selectedMethod) < 0
        ? -1
        : methods.indexOf(selectedMethod);

    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFF242730),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFF343846),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final itemWidth = constraints.maxWidth / methods.length;

            return Stack(
              children: [
                if (activeIndex >= 0)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    left: itemWidth * activeIndex,
                    top: 0,
                    bottom: 0,
                    width: itemWidth,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C5CFF).withValues(alpha: 0.32),
                      ),
                    ),
                  ),

                Row(
                  children: [
                    for (final method in methods)
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onChanged(method),
                          child: Center(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 170),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (child, animation) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: ScaleTransition(
                                    scale: Tween<double>(
                                      begin: 0.88,
                                      end: 1.0,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                );
                              },
                              child: selectedMethod == method
                                  ? Text(
                                method,
                                key: ValueKey('active_$method'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              )
                                  : Icon(
                                _paymentMethodIcon(method),
                                key: ValueKey('icon_$method'),
                                color: const Color(0xFF8E93A6),
                                size: 17,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSheetHeader({
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
              size: 22,
              color: const Color(0xFFB8C1D9),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.58),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMiniFieldLabel({
    required IconData icon,
    required String text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8),
      child: Row(
        children: [
          Icon(
            icon,
            size: 15,
            color: const Color(0xFF9AA4BF),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF9AA4BF),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _showWorkioConfirmDialog({
    required IconData icon,
    required Color accent,
    required String title,
    required String message,
    String cancelText = 'Cancel',
    String confirmText = 'Confirm',
    bool destructive = false,
  }) async {
    final result = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.68),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return const SizedBox.shrink();
      },
      transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: MediaQuery.of(dialogContext).size.width - 42,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF242730),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: const Color(0xFF343846),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 34,
                        offset: const Offset(0, 18),
                      ),
                      BoxShadow(
                        color: accent.withValues(alpha: 0.12),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.13),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: accent.withValues(alpha: 0.42),
                          ),
                        ),
                        child: Icon(
                          icon,
                          color: accent,
                          size: 27,
                        ),
                      ),

                      const SizedBox(height: 14),

                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFF3F6FC),
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFA1A7B8),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          height: 1.38,
                        ),
                      ),

                      const SizedBox(height: 18),

                      Row(
                        children: [
                          Expanded(
                            child: CupertinoButton(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              color: const Color(0xFF20232D),
                              borderRadius: BorderRadius.circular(16),
                              onPressed: () {
                                Navigator.pop(dialogContext, false);
                              },
                              child: Text(
                                cancelText,
                                style: const TextStyle(
                                  color: Color(0xFFF3F6FC),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: CupertinoButton(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              color: destructive
                                  ? const Color(0xFFFF5C5C)
                                  : accent,
                              borderRadius: BorderRadius.circular(16),
                              onPressed: () {
                                Navigator.pop(dialogContext, true);
                              },
                              child: Text(
                                confirmText,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
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
          ),
        );
      },
    );

    return result == true;
  }

  void _showSnack(String message) {
    if (!mounted) return;

    final clean = message.trim();
    if (clean.isEmpty) return;

    final lower = clean.toLowerCase();

    final isError =
        lower.contains('failed') ||
            lower.contains('error') ||
            lower.contains('not found') ||
            lower.contains('cannot');

    final isSuccess =
        lower.contains('saved') ||
            lower.contains('updated') ||
            lower.contains('added') ||
            lower.contains('deleted') ||
            lower.contains('sent') ||
            lower.contains('copied') ||
            lower.contains('archived') ||
            lower.contains('paid');

    final Color accent = isError
        ? const Color(0xFFFF5C5C)
        : isSuccess
        ? const Color(0xFF33C27F)
        : const Color(0xFF7C5CFF);

    final IconData icon = isError
        ? CupertinoIcons.xmark_circle_fill
        : isSuccess
        ? CupertinoIcons.checkmark_circle_fill
        : CupertinoIcons.info_circle_fill;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();

    messenger.showSnackBar(
      SnackBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        padding: EdgeInsets.zero,
        duration: const Duration(milliseconds: 2400),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: const Color(0xFF242730),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: accent.withValues(alpha: 0.45),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 22,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: accent.withValues(alpha: 0.12),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: accent,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  clean,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFF3F6FC),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: messenger.hideCurrentSnackBar,
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(
                    CupertinoIcons.xmark,
                    color: Color(0xFF9AA3B7),
                    size: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendInvoice() async {
    final invoice = _invoice;

    if (invoice == null) {
      _showSnack('Invoice not found');
      return;
    }

    final dialogResult = await showSendInvoiceDialog(
      context: context,
      invoice: invoice,
      client: _client,
      companySettings: _companySettings,
      latestDocument: _latestSavedDocument,
    );

    if (dialogResult == null) return;

    await _executeInvoiceSend(dialogResult);
  }

  Future<void> _resendLastInvoice() async {
    final latestLog = _latestEmailLog;

    if (latestLog == null) {
      _showSnack('No previous send yet');
      return;
    }

    final dialogResult = SendInvoiceDialogResult(
      recipientEmail: latestLog.recipientEmail,
      subject: latestLog.subject,
      templateType: latestLog.templateType ?? 'standard',
      messageBody: (latestLog.messageBody ?? '').trim().isNotEmpty
          ? latestLog.messageBody!.trim()
          : 'Please find attached your invoice.',
      useLatestSavedPdf: _latestSavedDocument != null,
      generateNewPdfIfMissing: true,
      selectedDocumentId: _latestSavedDocument?.id,
    );

    await _executeInvoiceSend(dialogResult);
  }

  InvoiceEmailLogModel? get _latestEmailLog {
    if (_emailLogs.isEmpty) return null;
    return _emailLogs.first;
  }

  Future<void> _executeInvoiceSend(
      SendInvoiceDialogResult dialogResult,
      ) async {
    final invoice = _invoice;

    if (invoice == null) {
      _showSnack('Invoice not found');
      return;
    }

    setState(() {
      _isSendingEmail = true;
    });

    try {
      final result = await InvoiceEmailService.sendInvoice(
        invoice: invoice,
        items: _items,
        dialogResult: dialogResult,
        client: _client,
        property: _property,
        companySettings: _companySettings,
      );

      if (!mounted) return;

      setState(() {
        _invoice = result.updatedInvoice;
        _status = result.updatedInvoice.status;
      });

      await _loadDocuments();
      await _loadEmailLogs();

      _showSnack('Invoice sent');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to send invoice');
    } finally {
      if (!mounted) return;

      setState(() {
        _isSendingEmail = false;
      });
    }
  }

  Future<void> _loadEmailLogs() async {
    final invoice = _invoice;

    if (invoice == null || invoice.id.trim().isEmpty) {
      setState(() {
        _emailLogs = [];
      });
      return;
    }

    setState(() {
      _isEmailLogsLoading = true;
    });

    try {
      final logs = await InvoiceEmailService.getEmailLogsByInvoice(invoice.id);

      if (!mounted) return;

      setState(() {
        _emailLogs = logs;
        _isEmailLogsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _emailLogs = [];
        _isEmailLogsLoading = false;
      });

      _showSnack('Failed to load email history');
    }
  }

  void _openEmailHistorySheet() {
    if (_emailLogs.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF20242D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) {
        return FractionallySizedBox(
          heightFactor: 0.75,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 18),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Icon(
                          CupertinoIcons.mail_solid,
                          color: Color(0xFFF3F6FC),
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Email History',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Track sent emails, reminders, and delivery activity',
                              style: TextStyle(
                                color: Color(0xFF9AA3B2),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                height: 1.3,
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
                      itemCount: _emailLogs.length,
                      itemBuilder: (context, index) {
                        return _EmailLogTile(log: _emailLogs[index]);
                      },
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
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

  InvoiceDocumentModel? get _latestSavedDocument {
    if (_documents.isEmpty) return null;
    return _documents.first;
  }

  Future<void> _loadDocuments() async {
    final invoice = _invoice;

    if (invoice == null || invoice.id.trim().isEmpty) {
      setState(() {
        _documents = [];
      });
      return;
    }

    setState(() {
      _isDocumentsLoading = true;
    });

    try {
      final docs =
      await InvoiceDocumentService.getDocumentsByInvoice(invoice.id);

      if (!mounted) return;

      setState(() {
        _documents = docs;
        _isDocumentsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _documents = [];
        _isDocumentsLoading = false;
      });

      _showSnack('Failed to load email history');
    }
  }

  void _openSavedDocumentsSheet() {
    if (_documents.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1B1E27),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) {
        return FractionallySizedBox(
          heightFactor: 0.75,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Saved Documents',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _documents.length,
                      itemBuilder: (context, index) {
                        final document = _documents[index];
                        return _SavedDocumentTile(
                          document: document,
                          onOpen: () => _openSavedDocument(document),
                          onDelete: () => _deleteSavedDocument(document),
                        );
                      },
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
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

  Future<void> _previewPdf() async {
    final invoice = _invoice;

    if (invoice == null) {
      _showSnack('Invoice not found');
      return;
    }

    setState(() {
      _isPreviewingPdf = true;
    });

    try {
      await InvoicePdfService.previewInvoicePdf(
        invoice: invoice,
        items: _items,
        client: _client,
        property: _property,
        companyName: _companyNameForPdf,
        companyEmail: _companyEmailForPdf,
        companyPhone: _companyPhoneForPdf,
        companyAddress: _companyAddressForPdf,
        companyLogoUrl: _companyLogoUrlForPdf,
      );
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to open PDF');
    } finally {
      if (!mounted) return;

      setState(() {
        _isPreviewingPdf = false;
      });
    }
  }

  Future<void> _sharePdf() async {
    final invoice = _invoice;

    if (invoice == null) {
      _showSnack('Invoice not found');
      return;
    }

    setState(() {
      _isSharingPdf = true;
    });

    try {
      await InvoicePdfService.shareInvoicePdf(
        invoice: invoice,
        items: _items,
        client: _client,
        property: _property,
        companyName: _companyNameForPdf,
        companyEmail: _companyEmailForPdf,
        companyPhone: _companyPhoneForPdf,
        companyAddress: _companyAddressForPdf,
        companyLogoUrl: _companyLogoUrlForPdf,
      );
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to share PDF');
    } finally {
      if (!mounted) return;

      setState(() {
        _isSharingPdf = false;
      });
    }
  }

  Future<void> _savePdfToStorage() async {
    final invoice = _invoice;

    if (invoice == null) {
      _showSnack('Invoice not found');
      return;
    }

    if (invoice.id.trim().isEmpty) {
      _showSnack('Save the invoice first');
      return;
    }

    setState(() {
      _isSavingPdf = true;
    });

    try {
      await InvoiceDocumentService.saveInvoicePdf(
        invoice: invoice,
        items: _items,
        client: _client,
        property: _property,
        companyName: _companyNameForPdf,
        companyEmail: _companyEmailForPdf,
        companyPhone: _companyPhoneForPdf,
        companyAddress: _companyAddressForPdf,
        companyLogoUrl: _companyLogoUrlForPdf,
      );

      if (!mounted) return;

      _showSnack('PDF saved');
      await _loadDocuments();
    } catch (e) {
      if (!mounted) return;
      _showSnack('Error saving PDF');
    } finally {
      if (!mounted) return;

      setState(() {
        _isSavingPdf = false;
      });
    }
  }

  Future<void> _openSavedDocument(InvoiceDocumentModel document) async {
    try {
      final url = await InvoiceDocumentService.createSignedUrl(document);
      final uri = Uri.parse(url);

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        _showSnack('Could not open document');
      }
    } catch (e) {
      _showSnack('Error opening document');
    }
  }

  Future<void> _deleteSavedDocument(InvoiceDocumentModel document) async {
    try {
      await InvoiceDocumentService.deleteDocument(document);

      if (!mounted) return;

      _showSnack('Document deleted');
      await _loadDocuments();
    } catch (e) {
      if (!mounted) return;
      _showSnack('Error deleting document');
    }
  }

  String get _companyNameForPdf {
    final value = _companySettings?.companyName.trim() ?? '';
    return value.isEmpty ? 'Your Company Name' : value;
  }

  String? get _companyEmailForPdf {
    final value = _companySettings?.companyEmail?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  String? get _companyPhoneForPdf {
    final value = _companySettings?.companyPhone?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  String? get _companyAddressForPdf {
    final value = _companySettings?.companyAddress?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  String get _companyLogoUrlForPdf {
    return CompanyLogoHelper.resolvedLogoUrl(_companySettings);
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

  double get _paidAmount {
    final invoice = _invoice;
    if (invoice == null) return 0;
    return invoice.paidAmount;
  }

  double get _balanceDue {
    final result = _total - _paidAmount;
    return double.parse(math.max(result, 0).toStringAsFixed(2));
  }

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _workioMonthLabel(DateTime date) {
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

  String _workioShortDate(DateTime date) {
    const weekdays = [
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ];

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';
  }

  Future<DateTime?> _pickDateWithWorkioSheet({
    required DateTime initialDate,
    required String title,
  }) async {
    DateTime selectedDate = DateTime(
      initialDate.year,
      initialDate.month,
      initialDate.day,
    );

    DateTime visibleMonth = DateTime(
      selectedDate.year,
      selectedDate.month,
    );

    int monthDirection = 1;

    return showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1B1E27),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final firstDayOfMonth = DateTime(
              visibleMonth.year,
              visibleMonth.month,
              1,
            );

            final daysInMonth = DateTime(
              visibleMonth.year,
              visibleMonth.month + 1,
              0,
            ).day;

            final leadingEmptyDays = firstDayOfMonth.weekday % 7;

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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(
                              CupertinoIcons.calendar,
                              color: Color(0xFFF3F6FC),
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 180),
                                  child: Text(
                                    _workioShortDate(selectedDate),
                                    key: ValueKey(selectedDate.toIso8601String()),
                                    style: const TextStyle(
                                      color: Color(0xFFA1A7B8),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      Expanded(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: const Color(0xFF242730),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: const Color(0xFF343846)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.30),
                                blurRadius: 20,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  CupertinoButton(
                                    padding: EdgeInsets.zero,
                                    minSize: 42,
                                    onPressed: () {
                                      setModalState(() {
                                        monthDirection = -1;
                                        visibleMonth = DateTime(
                                          visibleMonth.year,
                                          visibleMonth.month - 1,
                                        );
                                      });
                                    },
                                    child: Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF20232D),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: const Color(0xFF343846),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.22),
                                            blurRadius: 10,
                                            offset: const Offset(0, 5),
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        CupertinoIcons.chevron_left,
                                        color: Color(0xFFB6BCD0),
                                        size: 18,
                                      ),
                                    ),
                                  ),

                                  Expanded(
                                    child: Center(
                                      child: Text(
                                        _workioMonthLabel(visibleMonth),
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
                                    minSize: 42,
                                    onPressed: () {
                                      setModalState(() {
                                        monthDirection = 1;
                                        visibleMonth = DateTime(
                                          visibleMonth.year,
                                          visibleMonth.month + 1,
                                        );
                                      });
                                    },
                                    child: Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF15161C),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: const Color(0xFF23252E),
                                        ),
                                      ),
                                      child: const Icon(
                                        CupertinoIcons.chevron_right,
                                        color: Color(0xFFB6BCD0),
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 16),

                              Expanded(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 240),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  transitionBuilder: (child, animation) {
                                    final slideAnimation = Tween<Offset>(
                                      begin: Offset(monthDirection > 0 ? 0.08 : -0.08, 0),
                                      end: Offset.zero,
                                    ).animate(
                                      CurvedAnimation(
                                        parent: animation,
                                        curve: Curves.easeOutCubic,
                                      ),
                                    );

                                    return FadeTransition(
                                      opacity: animation,
                                      child: SlideTransition(
                                        position: slideAnimation,
                                        child: child,
                                      ),
                                    );
                                  },
                                  child: Column(
                                    key: ValueKey('${visibleMonth.year}-${visibleMonth.month}'),
                                    children: [
                                      const Row(
                                        children: [
                                          _CalendarWeekDay('S'),
                                          _CalendarWeekDay('M'),
                                          _CalendarWeekDay('T'),
                                          _CalendarWeekDay('W'),
                                          _CalendarWeekDay('T'),
                                          _CalendarWeekDay('F'),
                                          _CalendarWeekDay('S'),
                                        ],
                                      ),

                                      const SizedBox(height: 10),
                                      const Divider(color: Color(0xFF343846), height: 1),
                                      const SizedBox(height: 10),

                                      Expanded(
                                        child: GridView.builder(
                                          padding: EdgeInsets.zero,
                                          physics: const NeverScrollableScrollPhysics(),
                                          itemCount: 42,
                                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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

                                            final isSelected = _isSameDate(date, selectedDate);

                                            return GestureDetector(
                                              onTap: () {
                                                setModalState(() {
                                                  selectedDate = DateTime(
                                                    date.year,
                                                    date.month,
                                                    date.day,
                                                  );

                                                  visibleMonth = DateTime(
                                                    date.year,
                                                    date.month,
                                                  );
                                                });
                                              },
                                              child: AnimatedScale(
                                                duration: const Duration(milliseconds: 140),
                                                scale: isSelected ? 1.06 : 1.0,
                                                curve: Curves.easeOutCubic,
                                                child: AnimatedContainer(
                                                  duration: const Duration(milliseconds: 160),
                                                  curve: Curves.easeOutCubic,
                                                  decoration: BoxDecoration(
                                                    color: isSelected
                                                        ? const Color(0xFF7C5CFF)
                                                        : isCurrentMonth
                                                        ? const Color(0xFF20232D)
                                                        : Colors.transparent,
                                                    borderRadius: BorderRadius.circular(14),
                                                    border: Border.all(
                                                      color: isSelected
                                                          ? const Color(0xFF9D7CFF)
                                                          : isCurrentMonth
                                                          ? const Color(0xFF303442)
                                                          : Colors.transparent,
                                                    ),
                                                    boxShadow: isSelected
                                                        ? [
                                                      BoxShadow(
                                                        color: const Color(0xFF7C5CFF).withValues(alpha: 0.22),
                                                        blurRadius: 12,
                                                        offset: const Offset(0, 6),
                                                      ),
                                                    ]
                                                        : null,
                                                  ),
                                                  alignment: Alignment.center,
                                                  child: Text(
                                                    '${date.day}',
                                                    style: TextStyle(
                                                      color: isSelected
                                                          ? Colors.white
                                                          : isCurrentMonth
                                                          ? const Color(0xFFF3F6FC)
                                                          : const Color(0xFF687086),
                                                      fontSize: 16,
                                                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
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
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      Row(
                        children: [
                          Expanded(
                            child: CupertinoButton(
                              padding:
                              const EdgeInsets.symmetric(vertical: 15),
                              color: const Color(0xFF20232D),
                              borderRadius: BorderRadius.circular(16),
                              onPressed: () {
                                Navigator.pop(sheetContext);
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
                              padding:
                              const EdgeInsets.symmetric(vertical: 15),
                              color: const Color(0xFF7C5CFF),
                              borderRadius: BorderRadius.circular(16),
                              onPressed: () {
                                Navigator.pop(sheetContext, selectedDate);
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
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _pickIssueDate() async {
    final picked = await _pickDateWithWorkioSheet(
      initialDate: _issueDate ?? DateTime.now(),
      title: 'Select issue date',
    );

    if (picked == null) return;

    setState(() {
      _issueDate = picked;
    });
  }

  Future<void> _pickDueDate() async {
    final picked = await _pickDateWithWorkioSheet(
      initialDate: _dueDate ?? DateTime.now().add(const Duration(days: 14)),
      title: 'Select due date',
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
                          CupertinoIcons.tag_fill,
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
                              'Choose the current invoice status',
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
                        final statusColor = _invoiceStatusColor(status);

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
                                    ? statusColor.withValues(alpha: 0.16)
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
                                children: [
                                  Icon(
                                    _invoiceStatusIcon(status),
                                    color: selectedNow
                                        ? statusColor
                                        : const Color(0xFFF3F6FC),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 13),
                                  Expanded(
                                    child: Text(
                                      _statusLabel(status),
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
                                        ? statusColor
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
      case 'archived':
        return 'Archived';
      default:
        return 'Unknown';
    }
  }

  Future<void> _showTaxEditor() async {
    final valueController = TextEditingController(
      text: _taxAmount == 0 ? '' : _taxAmount.toStringAsFixed(2),
    );

    final value = await showModalBottomSheet<double>(
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
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            MediaQuery.of(context).viewInsets.bottom + 20,
          ),
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

              _buildSheetHeader(
                icon: CupertinoIcons.percent,
                title: 'Tax Amount',
                subtitle: 'Set the tax amount for this invoice',
              ),

              const SizedBox(height: 16),

              _PremiumTextField(
                controller: valueController,
                label: 'Tax',
                hintText: '0.00',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),

              const SizedBox(height: 18),

              SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  color: const Color(0xFF7C5CFF),
                  borderRadius: BorderRadius.circular(16),
                  onPressed: () {
                    final parsed =
                    EstimateCalculator.parseNumber(valueController.text);
                    Navigator.pop(context, parsed);
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
                        'Apply',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
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

    valueController.dispose();

    if (value == null) return;

    setState(() {
      _taxAmount = value;
    });
  }

  Future<void> _showDiscountEditor() async {
    final valueController = TextEditingController(
      text: _discountAmount == 0 ? '' : _discountAmount.toStringAsFixed(2),
    );

    final value = await showModalBottomSheet<double>(
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
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            MediaQuery.of(context).viewInsets.bottom + 20,
          ),
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

              _buildSheetHeader(
                icon: CupertinoIcons.tag,
                title: 'Discount Amount',
                subtitle: 'Set the discount amount',
              ),

              const SizedBox(height: 16),

              _PremiumTextField(
                controller: valueController,
                label: 'Discount',
                hintText: '0.00',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),

              const SizedBox(height: 18),

              SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  color: const Color(0xFF7C5CFF),
                  borderRadius: BorderRadius.circular(16),
                  onPressed: () {
                    final parsed =
                    EstimateCalculator.parseNumber(valueController.text);
                    Navigator.pop(context, parsed);
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
                        'Apply',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
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

    valueController.dispose();

    if (value == null) return;

    setState(() {
      _discountAmount = value;
    });
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
      isDismissible: true,
      enableDrag: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF1B1F28),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      clipBehavior: Clip.antiAlias,
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
                    Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFF3D4250),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),

                    const SizedBox(height: 18),

                    _buildSheetHeader(
                      icon: existingItem == null
                          ? CupertinoIcons.add_circled
                          : CupertinoIcons.pencil_circle,
                      title: existingItem == null ? 'Add Item' : 'Edit Item',
                      subtitle: existingItem == null
                          ? 'Create a new invoice line item'
                          : 'Update line item details',
                    ),
                    const SizedBox(height: 18),
                    _paymentSheetPanel(
                      children: [
                        _paymentSheetInputRow(
                          icon: CupertinoIcons.tag,
                          label: 'Title',
                          controller: titleController,
                          hintText: 'Item title',
                        ),
                        _summaryDivider(),
                        _paymentSheetInputRow(
                          icon: CupertinoIcons.text_alignleft,
                          label: 'Description',
                          controller: descriptionController,
                          hintText: 'Optional description',
                          maxLines: 3,
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    _paymentSheetPanel(
                      children: [
                        _paymentSheetPickerRow(
                          icon: CupertinoIcons.cube_box,
                          label: 'Unit',
                          value: EstimateFormatters.formatUnit(selectedUnit),
                          onTap: () async {
                            final unit = await showModalBottomSheet<String>(
                              context: context,
                              isScrollControlled: true,
                              isDismissible: true,
                              enableDrag: true,
                              useSafeArea: true,
                              backgroundColor: const Color(0xFF1B1F28),
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(30),
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
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
                        _summaryDivider(),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                          child: Row(
                            children: [
                              Expanded(
                                child: _CenteredMiniInput(
                                  icon: CupertinoIcons.number,
                                  label: 'Quantity',
                                  controller: quantityController,
                                  hintText: '1',
                                  keyboardType: const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _CenteredMiniInput(
                                  icon: CupertinoIcons.money_dollar_circle,
                                  label: 'Unit Price',
                                  controller: unitPriceController,
                                  hintText: '0.00',
                                  keyboardType: const TextInputType.numberWithOptions(
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
                        color: const Color(0xFF7C5CFF),
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
                            invoiceId: existingItem?.invoiceId ?? widget.invoiceId,
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
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              existingItem == null
                                  ? CupertinoIcons.plus_circle_fill
                                  : CupertinoIcons.checkmark_circle_fill,
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
            );
          },
        );
      },
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

  Future<void> _removeItem(int index) async {
    if (index < 0 || index >= _items.length) return;

    final item = _items[index];

    final confirmed = await _showWorkioConfirmDialog(
      icon: CupertinoIcons.trash_fill,
      accent: const Color(0xFFFF5C5C),
      title: 'Delete item?',
      message: '“${item.title}” will be removed from this invoice.',
      confirmText: 'Delete',
      destructive: true,
    );

    if (!confirmed) return;

    setState(() {
      _items.removeAt(index);
      _items = _items
          .asMap()
          .entries
          .map((entry) => entry.value.copyWith(sortOrder: entry.key))
          .toList();
    });

    _showSnack('Item deleted');
  }

  Future<void> _addPayment() async {
    final payment = await _showPaymentEditor();

    if (payment == null) return;

    setState(() {
      _isAddingPayment = true;
    });

    try {
      await InvoiceService.addPayment(payment);

      if (!mounted) return;

      await _loadInitialData();
      _showSnack('Payment added');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Error adding payment');
    } finally {
      if (!mounted) return;

      setState(() {
        _isAddingPayment = false;
      });
    }
  }

  Future<void> _deletePayment(InvoicePaymentModel payment) async {
    final confirmed = await _showWorkioConfirmDialog(
      icon: CupertinoIcons.trash_fill,
      accent: const Color(0xFFFF5C5C),
      title: 'Delete payment?',
      message:
      'The payment of ${EstimateFormatters.formatCurrency(payment.amount)} will be deleted.',
      confirmText: 'Delete',
      destructive: true,
    );

    if (!confirmed) return;

    if (confirmed != true) return;

    try {
      await InvoiceService.deletePayment(payment.id);

      if (!mounted) return;

      await _loadInitialData();
      _showSnack('Payment deleted');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to delete payment');
    }
  }

  void _openPaymentsSheet() {
    if (_payments.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF20242D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) {
        return FractionallySizedBox(
          heightFactor: 0.80,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: Icon(
                          CupertinoIcons.creditcard_fill,
                          color: Color(0xFFF3F6FC),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Payments',
                              style: TextStyle(
                                color: Color(0xFFF1F4F8),
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_payments.length} payment${_payments.length == 1 ? '' : 's'} recorded',
                              style: const TextStyle(
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
                  const SizedBox(height: 14),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _payments.length,
                      itemBuilder: (context, index) {
                        final payment = _payments[index];
                        return _PaymentTile(
                          payment: payment,
                          onEdit: () => _editPayment(payment),
                          onDelete: () => _deletePayment(payment),
                        );
                      },
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
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

  Future<void> _archiveInvoice() async {
    final invoice = _invoice;
    if (invoice == null) return;

    final confirmed = await _showWorkioConfirmDialog(
      icon: CupertinoIcons.archivebox_fill,
      accent: const Color(0xFF8B5CF6),
      title: 'Archive invoice?',
      message: 'Invoice “${invoice.title}” will be moved to archived.',
      confirmText: 'Archive',
    );

    if (!confirmed) return;

    if (confirmed != true) return;

    setState(() {
      _isArchiving = true;
    });

    try {
      await InvoiceService.archiveInvoice(invoice.id);

      if (!mounted) return;

      setState(() {
        _status = 'archived';
        _invoice = invoice.copyWith(status: 'archived');
      });

      _showSnack('Invoice archived');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to archive invoice');
    } finally {
      if (!mounted) return;
      setState(() {
        _isArchiving = false;
      });
    }
  }

  Future<void> _deleteInvoicePermanently() async {
    final invoice = _invoice;
    if (invoice == null) return;

    final confirmed = await _showWorkioConfirmDialog(
      icon: CupertinoIcons.exclamationmark_triangle_fill,
      accent: const Color(0xFFFF5C5C),
      title: 'Delete permanently?',
      message:
      'Only mistaken draft invoices should be deleted permanently. This action cannot be undone.',
      confirmText: 'Delete',
      destructive: true,
    );

    if (!confirmed) return;

    setState(() {
      _isDeleting = true;
    });

    try {
      await InvoiceService.deleteInvoice(invoice.id);

      if (!mounted) return;

      _showSnack('Invoice deleted');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      final text = e.toString();

      if (text.contains('payments') ||
          text.contains('Only draft invoices can be deleted')) {
        _showSnack(text.replaceFirst('Exception: ', ''));
      } else {
        _showSnack('Failed to delete invoice');
      }
    } finally {
      if (!mounted) return;
      setState(() {
        _isDeleting = false;
      });
    }
  }

  Future<void> _saveChanges() async {
    final invoice = _invoice;
    if (invoice == null) return;

    if (_titleController.text.trim().isEmpty) {
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
      final updatedInvoice = invoice.copyWith(
        title: _titleController.text.trim(),
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
        paidAmount: _paidAmount,
        balanceDue: _balanceDue,
      );

      final saved = await InvoiceService.updateInvoiceWithItems(
        invoice: updatedInvoice,
        items: _items,
      );

      if (!mounted) return;

      setState(() {
        _invoice = saved;
      });

      _showSnack('Invoice updated');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Error saving invoice');
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
    final editorFocusNode = FocusNode();

    bool isClosing = false;

    Future<void> closeSheet(
        BuildContext sheetContext, {
          String? value,
        }) async {
      if (isClosing) return;
      isClosing = true;

      editorFocusNode.unfocus();
      FocusManager.instance.primaryFocus?.unfocus();

      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await Future.delayed(const Duration(milliseconds: 220));

      if (!sheetContext.mounted) return;

      Navigator.of(sheetContext).pop(value);
    }

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
        return WillPopScope(
          onWillPop: () async {
            return true;
          },
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
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
                          Icon(
                            icon,
                            color: const Color(0xFFF3F6FC),
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
                              _TextEditorIconButton(
                                icon: Icons.select_all_rounded,
                                color: const Color(0xFFF3F6FC),
                                onTap: () {
                                  final text = tempController.text;
                                  if (text.isEmpty) return;

                                  editorFocusNode.requestFocus();
                                  tempController.selection = TextSelection(
                                    baseOffset: 0,
                                    extentOffset: text.length,
                                  );
                                },
                              ),
                              const SizedBox(width: 6),
                              _TextEditorIconButton(
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
                              _TextEditorIconButton(
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
                            color: const Color(0xFF181B23),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: const Color(0xFF343846)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.26),
                                blurRadius: 18,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: TextField(
                            controller: tempController,
                            focusNode: editorFocusNode,
                            expands: true,
                            maxLines: null,
                            minLines: null,
                            keyboardType: TextInputType.multiline,
                            textAlignVertical: TextAlignVertical.top,
                            cursorColor: const Color(0xFF7C5CFF),
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
                                await closeSheet(sheetContext);
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
                              color: const Color(0xFF7C5CFF),
                              borderRadius: BorderRadius.circular(16),
                              onPressed: () async {
                                await closeSheet(
                                  sheetContext,
                                  value: tempController.text.trim(),
                                );
                              },
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    CupertinoIcons.checkmark_circle_fill,
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
          ),
        );
      },
    );

    final cleanResult = result?.trim();

    await Future.delayed(const Duration(milliseconds: 500));

    tempController.dispose();
    editorFocusNode.dispose();

    if (!mounted) return;
    if (cleanResult == null) return;

    setState(() {
      controller.text = cleanResult;
    });
  }

  Widget _buildCompanyLogoPreview() {
    return Container(
      width: 100,
      height: 75,
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF23252E)),
      ),
      alignment: Alignment.center,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          CompanyLogoHelper.resolvedLogoUrl(_companySettings),
          width: 100,
          height: 75,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Center(
            child: Icon(
              Icons.broken_image_outlined,
              color: Colors.white54,
              size: 26,
            ),
          ),
        ),
      ),
    );
  }

  IconData _invoiceStatusIcon(String status) {
    switch (status.trim().toLowerCase()) {
      case 'draft':
        return CupertinoIcons.doc_fill;
      case 'sent':
        return CupertinoIcons.paperplane_fill;
      case 'partial':
        return CupertinoIcons.clock_fill;
      case 'paid':
        return CupertinoIcons.checkmark_seal_fill;
      case 'overdue':
        return CupertinoIcons.exclamationmark_triangle_fill;
      case 'void':
        return CupertinoIcons.xmark_circle_fill;
      case 'archived':
        return CupertinoIcons.archivebox_fill;
      default:
        return CupertinoIcons.tag;
    }
  }

  Color _invoiceStatusColor(String status) {
    switch (status.trim().toLowerCase()) {
      case 'draft':
        return const Color(0xFFF3F6FC); // white
      case 'sent':
        return const Color(0xFF0EA5E9); // blue
      case 'partial':
        return const Color(0xFFFFB300); // yellow
      case 'paid':
        return const Color(0xFF16A34A); // green
      case 'overdue':
        return const Color(0xFFD94A4A); // soft red
      case 'void':
        return const Color(0xFF8E93A6); // gray
      case 'archived':
        return const Color(0xFF7C5CFF); // purple
      default:
        return const Color(0xFF8E93A6);
    }
  }

  Widget _summaryDivider() {
    return const Divider(
      color: Color(0xFF343846),
      height: 1,
      thickness: 1,
    );
  }

  Widget _historyGroup({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF181B23),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF303442)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: const Color(0xFF8E93A6),
                size: 19,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Text(
              subtitle,
              style: const TextStyle(
                color: Color(0xFF8E93A6),
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _actionGroup({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF181B23),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF303442)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _summaryGlowIcon(
      IconData icon,
      Color color, {
        double size = 18,
      }) {
    return Icon(
      icon,
      color: color.withValues(alpha: 0.92),
      size: size,
    );
  }

  Widget _editableSummarySurface({
    required Widget child,
  }) {
    return ColoredBox(
      color: const Color(0xFF181B23),
      child: child,
    );
  }

  Widget _summaryPanel({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF242730),
        borderRadius: BorderRadius.circular(20),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF343846),
          width: 1,
        ),
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _totalInfoRow({
    required IconData icon,
    Color iconColor = const Color(0xFF8E93A6),
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Icon(
            icon,
            color: iconColor,
            size: 18,
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFFD0D5E2),
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryInfoRow({
    required IconData icon,
    required String label,
    required String value,
    int maxLines = 2,
    Color iconColor = const Color(0xFFF3F6FC),
  }) {
    final isPlaceholder =
        value.trim().isEmpty || value.trim() == '—' || value.trim().toLowerCase() == 'not set';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _summaryGlowIcon(icon, iconColor),
          const SizedBox(width: 12),
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
                const SizedBox(height: 5),
                Text(
                  value,
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isPlaceholder
                        ? const Color(0xFF697086)
                        : const Color(0xFFD0D5E2),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryPickerRow({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
    int maxLines = 2,
    Color iconColor = const Color(0xFFF3F6FC),
  }) {
    final isPlaceholder = value.startsWith('Select') || value.trim() == '—';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _summaryGlowIcon(icon, iconColor),
              const SizedBox(width: 12),
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
                    const SizedBox(height: 5),
                    Text(
                      value,
                      maxLines: maxLines,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isPlaceholder ? const Color(0xFF697086) : Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
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

  Widget _summaryTitleRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 34),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _summaryGlowIcon(
                  CupertinoIcons.doc_text_fill,
                  const Color(0xFFF3F6FC),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Title',
                        style: TextStyle(
                          color: Color(0xFF8E93A6),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      TextField(
                        controller: _titleController,
                        maxLines: 2,
                        minLines: 1,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                        cursorColor: const Color(0xFF8B5CF6),
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: 'Invoice title',
                          hintStyle: TextStyle(
                            color: Color(0xFF697086),
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: Center(
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _titleController,
                builder: (context, value, _) {
                  if (value.text.trim().isEmpty) {
                    return const SizedBox.shrink();
                  }

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      _titleController.clear();
                      setState(() {});
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        CupertinoIcons.xmark_circle_fill,
                        color: Color(0xFF8E93A6),
                        size: 18,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCompactPicker({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
    Color iconColor = const Color(0xFFF3F6FC),
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _summaryGlowIcon(icon, iconColor, size: 16),
              const SizedBox(width: 8),
              Expanded(
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
                    const SizedBox(height: 5),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
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

  Widget _buildTextPreviewRow({
    required IconData icon,
    Color iconColor = const Color(0xFFF3F6FC),
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    final cleanValue = value.trim().isEmpty ? '—' : value.trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  icon,
                  size: 18,
                  color: iconColor,
                ),
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
                        const _SoftExpandHintIcon(),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      cleanValue,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.45,
                        letterSpacing: -0.1,
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

  Widget _buildSectionCard({
    required String title,
    String? subtitle,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF242730),
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
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFFF4F6FA),
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
                          color: Color(0xFFA1A7B8),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
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

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: background,
        body: Center(
          child: CupertinoActivityIndicator(radius: 16),
        ),
      );
    }

    final invoice = _invoice;

    if (invoice == null) {
      return const Scaffold(
        backgroundColor: background,
        body: Center(
          child: Text(
            'Invoice not found',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: background,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(92),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: Container(
              height: 66,
              padding: const EdgeInsets.symmetric(horizontal: 8),
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
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minSize: 46,
                    onPressed: () => Navigator.pop(context),
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2D36),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFF3A3E4B)),
                      ),
                      child: const Icon(
                        CupertinoIcons.chevron_left,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),

                  const SizedBox(width: 10),

                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Invoice Details',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Subtotal ${EstimateFormatters.formatCurrency(_subtotal)}',
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

                  IconButton(
                    onPressed: _isArchiving ? null : _archiveInvoice,
                    icon: _isArchiving
                        ? const CupertinoActivityIndicator(color: Colors.white)
                        : const Icon(
                      CupertinoIcons.archivebox_fill,
                      color: Color(0xFFB6BCD0),
                      size: 21,
                    ),
                    tooltip: 'Archive',
                  ),

                  if (_status == 'draft')
                    IconButton(
                      onPressed: _isDeleting ? null : _deleteInvoicePermanently,
                      icon: _isDeleting
                          ? const CupertinoActivityIndicator(color: Colors.white)
                          : const Icon(
                        CupertinoIcons.trash_fill,
                        color: Color(0xFFD94A4A),
                        size: 21,
                      ),
                      tooltip: 'Delete',
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
          children: [
            _buildSectionCard(
              title: 'Invoice Summary',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        CupertinoIcons.number,
                        color: Color(0xFF8E93A6),
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        invoice.invoiceNumber,
                        style: const TextStyle(
                          color: Color(0xFF8E93A6),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  _summaryPanel(
                    children: [
                      _summaryInfoRow(
                        icon: CupertinoIcons.person_fill,
                        iconColor: const Color(0xFF7C5CFF),
                        label: 'Client',
                        value: _client?.fullName ?? '—',
                      ),
                      _summaryDivider(),

                      _summaryInfoRow(
                        icon: CupertinoIcons.building_2_fill,
                        iconColor: const Color(0xFFFFC107),
                        label: 'Client Company',
                        value: (_client?.companyName ?? '').trim().isEmpty
                            ? '—'
                            : _client!.companyName!,
                      ),
                      _summaryDivider(),

                      _summaryInfoRow(
                        icon: CupertinoIcons.location_solid,
                        iconColor: const Color(0xFFD94A4A),
                        label: 'Property',
                        value: _property?.fullAddress ?? '—',
                      ),
                      _summaryDivider(),

                      _editableSummarySurface(
                        child: _summaryTitleRow(),
                      ),
                      _summaryDivider(),

                      _editableSummarySurface(
                        child: _summaryPickerRow(
                          icon: _invoiceStatusIcon(_status),
                          iconColor: _invoiceStatusColor(_status),
                          label: 'Status',
                          value: _statusLabel(_status),
                          onTap: _pickStatus,
                          maxLines: 1,
                        ),
                      ),
                      _summaryDivider(),

                      _editableSummarySurface(
                        child: SizedBox(
                          height: 76,
                          child: Row(
                            children: [
                              Expanded(
                                child: _summaryCompactPicker(
                                  icon: CupertinoIcons.calendar,
                                  iconColor: const Color(0xFF0EA5E9),
                                  label: 'Issue Date',
                                  value: EstimateFormatters.formatDate(_issueDate),
                                  onTap: _pickIssueDate,
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 64,
                                color: const Color(0xFF343846),
                              ),
                              Expanded(
                                child: _summaryCompactPicker(
                                  icon: CupertinoIcons.calendar_badge_plus,
                                  iconColor: const Color(0xFF0EA5E9),
                                  label: 'Due Date',
                                  value: EstimateFormatters.formatDate(_dueDate),
                                  onTap: _pickDueDate,
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
            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'Company Info',
              subtitle: 'These details are currently used in the PDF',
              child: _summaryPanel(
                children: [
                  _summaryInfoRow(
                    icon: CupertinoIcons.building_2_fill,
                    iconColor: const Color(0xFFFFC107),
                    label: 'Company',
                    value: (_companySettings?.companyName.trim().isNotEmpty ?? false)
                        ? _companySettings!.companyName
                        : 'Not set',
                    maxLines: 1,
                  ),
                  _summaryDivider(),
                  _summaryInfoRow(
                    icon: CupertinoIcons.mail_solid,
                    label: 'Email',
                    value: (_companySettings?.companyEmail?.trim().isNotEmpty ?? false)
                        ? _companySettings!.companyEmail!
                        : 'Not set',
                    maxLines: 2,
                  ),
                  _summaryDivider(),
                  _summaryInfoRow(
                    icon: CupertinoIcons.phone_fill,
                    iconColor: const Color(0xFF7C5CFF),
                    label: 'Phone',
                    value: (_companySettings?.companyPhone?.trim().isNotEmpty ?? false)
                        ? _companySettings!.companyPhone!
                        : 'Not set',
                    maxLines: 1,
                  ),
                  _summaryDivider(),
                  _summaryInfoRow(
                    icon: CupertinoIcons.location_solid,
                    iconColor: const Color(0xFFD94A4A),
                    label: 'Address',
                    value: (_companySettings?.companyAddress?.trim().isNotEmpty ?? false)
                        ? _companySettings!.companyAddress!
                        : 'Not set',
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'Items',
              subtitle: 'Invoice items',
              trailing: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => _addOrEditItem(),
                child: const Icon(
                  CupertinoIcons.add_circled_solid,
                  color: Color(0xFF7C5CFF),
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
              child: _summaryPanel(
                children: [
                  _editableSummarySurface(
                    child: _buildTextPreviewRow(
                      icon: CupertinoIcons.text_bubble_fill,
                      iconColor: const Color(0xFFF3F6FC),
                      label: 'Notes',
                      value: _notesController.text.trim(),
                      onTap: () => _openLargeTextEditor(
                        title: 'Edit Notes',
                        controller: _notesController,
                        icon: CupertinoIcons.text_alignleft,
                      ),
                    ),
                  ),
                  _summaryDivider(),

                  _editableSummarySurface(
                    child: _buildTextPreviewRow(
                      icon: CupertinoIcons.doc_text_fill,
                      iconColor: const Color(0xFFF3F6FC),
                      label: 'Terms',
                      value: _termsController.text.trim(),
                      onTap: () => _openLargeTextEditor(
                        title: 'Edit Terms',
                        controller: _termsController,
                        icon: CupertinoIcons.doc_text_fill,
                      ),
                    ),
                  ),
                  _summaryDivider(),

                  _editableSummarySurface(
                    child: _buildTextPreviewRow(
                      icon: CupertinoIcons.creditcard_fill,
                      iconColor: const Color(0xFF7C5CFF),
                      label: 'Payment Instructions',
                      value: _paymentInstructionsController.text.trim(),
                      onTap: () => _openLargeTextEditor(
                        title: 'Edit Payment Instructions',
                        controller: _paymentInstructionsController,
                        icon: CupertinoIcons.creditcard_fill,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'Totals',
              subtitle: 'Invoice totals and balance',
              child: Column(
                children: [
                  _summaryPanel(
                    children: [
                      _editableSummarySurface(
                        child: _TotalsActionRow(
                          icon: CupertinoIcons.money_dollar_circle,
                          iconColor: const Color(0xFFF3F6FC),
                          label: 'Tax Amount',
                          value: EstimateFormatters.formatCurrency(_taxAmount),
                          onTap: _showTaxEditor,
                          compact: true,
                        ),
                      ),
                      _summaryDivider(),

                      _editableSummarySurface(
                        child: _TotalsActionRow(
                          icon: CupertinoIcons.tag,
                          iconColor: const Color(0xFFF3F6FC),
                          label: 'Discount Amount',
                          value: EstimateFormatters.formatCurrency(_discountAmount),
                          onTap: _showDiscountEditor,
                          compact: true,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  _summaryPanel(
                    children: [
                      _totalInfoRow(
                        icon: CupertinoIcons.sum,
                        iconColor: const Color(0xFFFFB300),
                        label: 'Subtotal',
                        value: EstimateFormatters.formatCurrency(_subtotal),
                      ),
                      _summaryDivider(),
                      _totalInfoRow(
                        icon: CupertinoIcons.money_dollar_circle,
                        iconColor: const Color(0xFFF3F6FC),
                        label: 'Tax',
                        value: EstimateFormatters.formatCurrency(_taxAmount),
                      ),
                      _summaryDivider(),
                      _totalInfoRow(
                        icon: CupertinoIcons.tag,
                        iconColor: const Color(0xFFE85D3D),
                        label: 'Discount',
                        value: '- ${EstimateFormatters.formatCurrency(_discountAmount)}',
                      ),
                      _summaryDivider(),
                      _totalInfoRow(
                        icon: CupertinoIcons.checkmark_seal,
                        iconColor: const Color(0xFF84CC16),
                        label: 'Total',
                        value: EstimateFormatters.formatCurrency(_total),
                      ),
                      _summaryDivider(),
                      _totalInfoRow(
                        icon: CupertinoIcons.creditcard,
                        iconColor: const Color(0xFF7C5CFF),
                        label: 'Paid',
                        value: EstimateFormatters.formatCurrency(_paidAmount),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  _TotalGrandBar(
                    label: 'Balance Due',
                    value: EstimateFormatters.formatCurrency(_balanceDue),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'Actions',
              subtitle: 'Preview, send, save, or resend this invoice',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _actionGroup(
                    title: 'PDF',
                    subtitle: 'Preview, share, or save this invoice',
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _ActionButtonWide(
                                icon: CupertinoIcons.eye,
                                label: _isPreviewingPdf ? 'Opening...' : 'Preview PDF',
                                onTap: _isPreviewingPdf ? null : _previewPdf,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _ActionButtonWide(
                                icon: CupertinoIcons.share,
                                label: _isSharingPdf ? 'Sharing...' : 'Share PDF',
                                onTap: _isSharingPdf ? null : _sharePdf,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _ActionButtonWide(
                          icon: CupertinoIcons.arrow_down_doc,
                          label: _isSavingPdf ? 'Saving PDF...' : 'Save PDF',
                          onTap: _isSavingPdf ? null : _savePdfToStorage,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  _actionGroup(
                    title: 'Client',
                    subtitle: 'Send invoice by email',
                    child: Row(
                      children: [
                        Expanded(
                          child: _ActionButtonWide(
                            icon: CupertinoIcons.paperplane,
                            label: _isSendingEmail ? 'Sending...' : 'Send Invoice',
                            onTap: _isSendingEmail ? null : _sendInvoice,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _ActionButtonWide(
                            icon: CupertinoIcons.arrow_clockwise,
                            label: _isSendingEmail ? 'Please wait...' : 'Resend Last',
                            onTap: _isSendingEmail ? null : _resendLastInvoice,
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
              title: 'Documents & History',
              subtitle: 'Saved PDFs and email activity',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _historyGroup(
                    icon: CupertinoIcons.doc_text,
                    title: 'Saved Documents',
                    subtitle: _documents.isEmpty
                        ? 'No saved PDFs yet'
                        : '${_documents.length} saved PDF${_documents.length == 1 ? '' : 's'}',
                    child: _isDocumentsLoading
                        ? const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: CupertinoActivityIndicator(radius: 14),
                      ),
                    )
                        : _documents.isEmpty
                        ? const _EmptyDocumentsState()
                        : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ...List.generate(
                          _documents.length > 2 ? 2 : _documents.length,
                              (index) {
                            final document = _documents[index];
                            final visibleCount =
                            _documents.length > 2 ? 2 : _documents.length;

                            return Padding(
                              padding: EdgeInsets.only(
                                bottom: index == visibleCount - 1 ? 0 : 10,
                              ),
                              child: _SavedDocumentTile(
                                document: document,
                                onOpen: () => _openSavedDocument(document),
                                onDelete: () => _deleteSavedDocument(document),
                              ),
                            );
                          },
                        ),
                        if (_documents.length > 2) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: CupertinoButton(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              color: const Color(0xFF0D0E14),
                              borderRadius: BorderRadius.circular(16),
                              onPressed: _openSavedDocumentsSheet,
                              child: Text(
                                'View all documents (${_documents.length})',
                                style: const TextStyle(
                                  color: Color(0xFFB6BCD0),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  _historyGroup(
                    icon: CupertinoIcons.mail,
                    title: 'Email History',
                    subtitle: _emailLogs.isEmpty
                        ? 'No emails sent yet'
                        : '${_emailLogs.length} email${_emailLogs.length == 1 ? '' : 's'} sent',
                    child: _isEmailLogsLoading
                        ? const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: CupertinoActivityIndicator(radius: 14),
                      ),
                    )
                        : _emailLogs.isEmpty
                        ? const _EmptyEmailLogsState()
                        : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ...List.generate(
                          _emailLogs.length > 2 ? 2 : _emailLogs.length,
                              (index) {
                            final log = _emailLogs[index];
                            final visibleCount =
                            _emailLogs.length > 2 ? 2 : _emailLogs.length;

                            return Padding(
                              padding: EdgeInsets.only(
                                bottom: index == visibleCount - 1 ? 0 : 10,
                              ),
                              child: _EmailLogTile(log: log),
                            );
                          },
                        ),
                        if (_emailLogs.length > 2) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: CupertinoButton(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              color: const Color(0xFF7C5CFF).withValues(alpha: 0.28),
                              borderRadius: BorderRadius.circular(16),
                              onPressed: _openEmailHistorySheet,
                              child: Text(
                                'View all history (${_emailLogs.length})',
                                style: const TextStyle(
                                  color: Color(0xFFC4B5FD),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'Payments',
              subtitle: 'Track payments and remaining balance',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _summaryPanel(
                    children: [
                      _totalInfoRow(
                        icon: CupertinoIcons.money_dollar_circle,
                        iconColor: _total > 0
                            ? const Color(0xFFE85D3D)
                            : const Color(0xFFF3F6FC),
                        label: 'Invoice Total',
                        value: EstimateFormatters.formatCurrency(_total),
                      ),
                      _summaryDivider(),
                      _totalInfoRow(
                        icon: CupertinoIcons.checkmark_seal,
                        iconColor: _paidAmount > 0
                            ? const Color(0xFF22C55E)
                            : const Color(0xFFF3F6FC),
                        label: 'Paid',
                        value: EstimateFormatters.formatCurrency(_paidAmount),
                      ),
                      _summaryDivider(),
                      _totalInfoRow(
                        icon: CupertinoIcons.exclamationmark_circle,
                        iconColor: const Color(0xFFBFC6D4),
                        label: 'Balance Due',
                        value: EstimateFormatters.formatCurrency(_balanceDue),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: _ActionButtonWide(
                          icon: CupertinoIcons.add,
                          iconColor: const Color(0xFF8B5CF6),
                          glowColor: const Color(0xFF8B5CF6),
                          elevated: true,
                          label: _isAddingPayment ? 'Please wait...' : 'Add Payment',
                          onTap: _isAddingPayment ? null : _addPayment,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ActionButtonWide(
                          icon: CupertinoIcons.check_mark_circled,
                          iconColor: const Color(0xFF22C55E),
                          glowColor: const Color(0xFF22C55E),
                          elevated: true,
                          label: _balanceDue <= 0 ? 'Paid' : 'Mark as Paid',
                          onTap: _isAddingPayment || _balanceDue <= 0
                              ? null
                              : _markAsPaidShortcut,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  _payments.isEmpty
                      ? const _EmptyPaymentsState()
                      : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ...List.generate(
                        _payments.length > 3 ? 3 : _payments.length,
                            (index) {
                          final payment = _payments[index];
                          final visibleCount =
                          _payments.length > 3 ? 3 : _payments.length;

                          return Padding(
                            padding: EdgeInsets.only(
                              bottom: index == visibleCount - 1 ? 0 : 10,
                            ),
                            child: _PaymentTile(
                              payment: payment,
                              onEdit: () => _editPayment(payment),
                              onDelete: () => _deletePayment(payment),
                            ),
                          );
                        },
                      ),
                      if (_payments.length > 3) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: CupertinoButton(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            color: const Color(0xFF0D0E14),
                            borderRadius: BorderRadius.circular(16),
                            onPressed: _openPaymentsSheet,
                            child: Text(
                              'View all payments (${_payments.length})',
                              style: const TextStyle(
                                color: Color(0xFFB6BCD0),
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.26),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: CupertinoButton(
                color: const Color(0xFF8B5CF6),
                borderRadius: BorderRadius.circular(18),
                padding: const EdgeInsets.symmetric(vertical: 16),
                onPressed: _isSaving ? null : _saveChanges,
                child: _isSaving
                    ? const CupertinoActivityIndicator(color: Colors.white)
                    : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      CupertinoIcons.checkmark_circle_fill,
                      color: Colors.white,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Save Changes',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
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
        heightFactor: 0.82,
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
                children: [
                  Icon(
                    CupertinoIcons.cube_box,
                    color: Color(0xFFF3F6FC),
                    size: 23,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Choose Unit',
                      style: TextStyle(
                        color: Color(0xFFF1F4F8),
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
                  padding: EdgeInsets.zero,
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
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            color: selected
                                ? const Color(0xFF7C5CFF).withValues(alpha: 0.18)
                                : const Color(0xFF151922),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: selected
                                  ? const Color(0xFF8D74FF)
                                  : const Color(0xFF343A49),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: selected ? 0.22 : 0.14,
                                ),
                                blurRadius: selected ? 20 : 14,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _unitIcon(unit),
                                color: const Color(0xFFF3F6FC),
                                size: 19,
                              ),
                              const SizedBox(width: 12),

                              Expanded(
                                child: Text(
                                  EstimateFormatters.formatUnit(unit),
                                  style: const TextStyle(
                                    color: Color(0xFFF1F4F8),
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
                                    ? const Color(0xFFB9A8FF)
                                    : const Color(0xFF9AA3B7),
                                size: selected ? 21 : 16,
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

class _CenteredMiniInput extends StatelessWidget {
  final IconData icon;
  final String label;
  final TextEditingController controller;
  final String hintText;
  final TextInputType keyboardType;

  const _CenteredMiniInput({
    required this.icon,
    required this.label,
    required this.controller,
    required this.hintText,
    required this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        minHeight: 78,
      ),
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
            cursorColor: const Color(0xFF7C5CFF),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
            decoration: const InputDecoration(
              isDense: true,
              hintText: '',
              hintStyle: TextStyle(
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
}

class _TextEditorIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _TextEditorIconButton({
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

class _CalendarWeekDay extends StatelessWidget {
  final String label;

  const _CalendarWeekDay(this.label);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Container(
          height: 30,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF20232D),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF343846)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFFB8C1D9),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
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
              cursorColor: const Color(0xFF7C5CFF),
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

  const _PremiumPickerField({
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
    this.showClearButton = false,
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
              'No items yet. Add your first one.',
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
    final description = (item.description ?? '').trim();
    final itemIcon = WorkioIconMapper.resolveFromTitle(item.title);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF181B23),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF303442)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                itemIcon,
                color: const Color(0xFFF3F6FC),
                size: 19,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
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
                color: const Color(0xFFFF6B6B),
              ),
            ],
          ),

          const SizedBox(height: 10),
          const Divider(
            color: Color(0xFF23252E),
            height: 1,
          ),

          if (description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    CupertinoIcons.exclamationmark_circle,
                    color: Color(0xFF8E93A6),
                    size: 17,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    description,
                    style: const TextStyle(
                      color: Color(0xFF8E93A6),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 10),

          _ItemMetricsBar(
            quantity: EstimateFormatters.formatQuantity(item.quantity),
            unit: EstimateFormatters.formatUnit(item.unit),
            unitPrice: EstimateFormatters.formatCurrency(item.unitPrice),
          ),

          const SizedBox(height: 10),

          _LineTotalBar(
            value: EstimateFormatters.formatCurrency(item.lineTotal),
          ),
        ],
      ),
    );
  }
}

class _EmptyPaymentsState extends StatelessWidget {
  const _EmptyPaymentsState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.money_dollar_circle,
            color: Color(0xFFF3F6FC),
            size: 19,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'No payments have been recorded for this invoice yet.',
              style: TextStyle(
                color: Color(0xFFA1A7B8),
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  final InvoicePaymentModel payment;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _PaymentTile({
    required this.payment,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final method = (payment.paymentMethod ?? '').trim();
    final reference = (payment.referenceNumber ?? '').trim();
    final notes = (payment.notes ?? '').trim();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF171B24),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFF343A49),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
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
            children: [
              const Icon(
                CupertinoIcons.money_dollar_circle,
                color: Color(0xFF22C55E),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  EstimateFormatters.formatCurrency(payment.amount),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              _SmallIconButton(
                icon: CupertinoIcons.pencil,
                onTap: onEdit,
              ),
              const SizedBox(width: 8),
              _SmallIconButton(
                icon: CupertinoIcons.trash,
                onTap: onDelete,
                color: const Color(0xFFFF6B6B),
              ),
            ],
          ),

          const SizedBox(height: 10),
          const Divider(color: Color(0xFF23252E), height: 1),
          const SizedBox(height: 10),

          _PaymentInfoRow(
            icon: CupertinoIcons.calendar,
            label: 'Date',
            value: EstimateFormatters.formatDate(payment.paymentDate),
          ),

          if (method.isNotEmpty) ...[
            const SizedBox(height: 8),
            _PaymentInfoRow(
              icon: CupertinoIcons.creditcard,
              label: 'Method',
              value: method,
            ),
          ],

          if (reference.isNotEmpty) ...[
            const SizedBox(height: 8),
            _PaymentInfoRow(
              icon: CupertinoIcons.number,
              label: 'Reference',
              value: reference,
            ),
          ],

          if (notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            _PaymentInfoRow(
              icon: CupertinoIcons.text_alignleft,
              label: 'Notes',
              value: notes,
            ),
          ],
        ],
      ),
    );
  }
}

class _PaymentInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _PaymentInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          color: const Color(0xFF8E93A6),
          size: 16,
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 76,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ),
      ],
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
        color: const Color(0xFF20232D),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF303442)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            textAlign: TextAlign.center,
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

class _ItemMetricsBar extends StatelessWidget {
  final String quantity;
  final String unit;
  final String unitPrice;

  const _ItemMetricsBar({
    required this.quantity,
    required this.unit,
    required this.unitPrice,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF20232D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF303442)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ItemMetricCell(
              label: 'Qty',
              value: quantity,
            ),
          ),
          _metricDivider(),
          Expanded(
            child: _ItemMetricCell(
              label: 'Unit',
              value: unit,
            ),
          ),
          _metricDivider(),
          Expanded(
            child: _ItemMetricCell(
              label: 'Unit Price',
              value: unitPrice,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricDivider() {
    return Container(
      width: 1,
      height: 54,
      color: const Color(0xFF303442),
    );
  }
}

class _ItemMetricCell extends StatelessWidget {
  final String label;
  final String value;

  const _ItemMetricCell({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 13,
      ),
      child: Column(
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFA1A7B8),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _LineTotalBar extends StatelessWidget {
  final String value;

  const _LineTotalBar({
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFF20232D),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF303442)),
      ),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.money_dollar_circle,
            color: Color(0xFF22C55E),
            size: 18,
          ),
          const SizedBox(width: 9),
          const Text(
            'Line Total',
            style: TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalsActionRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final VoidCallback onTap;
  final bool compact;

  const _TotalsActionRow({
    required this.icon,
    this.iconColor = const Color(0xFF8E93A6),
    required this.label,
    required this.value,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: compact ? Colors.transparent : const Color(0xFF101117),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: compact ? 13 : 14,
          ),
          decoration: compact
              ? null
              : BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF23252E)),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: iconColor,
                size: 18,
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
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

class _TotalGrandBar extends StatelessWidget {
  final String label;
  final String value;

  const _TotalGrandBar({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF181B23),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF343846)),
      ),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.money_dollar_circle_fill,
            color: Color(0xFF22C55E),
            size: 22,
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFB6BCD0),
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFFE1E5EF),
              fontSize: 21,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
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

class _ActionButtonWide extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Color? glowColor;
  final bool elevated;

  const _ActionButtonWide({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.glowColor,
    this.elevated = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = onTap == null;

    final effectiveIconColor = isDisabled
        ? const Color(0xFF5E6475)
        : iconColor ?? const Color(0xFFB6BCD0);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: elevated && !isDisabled
            ? [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.36),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.045),
            blurRadius: 8,
            spreadRadius: -5,
            offset: const Offset(0, -2),
          ),
        ]
            : [],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 54,
            decoration: BoxDecoration(
              color: isDisabled
                  ? const Color(0xFF1A1D25)
                  : const Color(0xFF20232D),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDisabled
                    ? const Color(0xFF2A2D38)
                    : const Color(0xFF3A3E4B),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: effectiveIconColor,
                  size: 19,
                ),
                const SizedBox(width: 9),
                Text(
                  label,
                  style: TextStyle(
                    color: isDisabled
                        ? const Color(0xFF5E6475)
                        : Colors.white,
                    fontSize: 14,
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
}

class _EmptyDocumentsState extends StatelessWidget {
  const _EmptyDocumentsState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF20232D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF303442)),
      ),
      child: const Row(
        children: [
          Icon(
            CupertinoIcons.doc,
            color: Color(0xFF8E93A6),
            size: 20,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'No saved PDF documents yet.',
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

class _SavedDocumentTile extends StatelessWidget {
  final InvoiceDocumentModel document;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  const _SavedDocumentTile({
    required this.document,
    required this.onOpen,
    required this.onDelete,
  });

  Widget _buildTopGradientDivider() {
    return Container(
      height: 1,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.transparent,
            Color(0xFF555B6B),
            Color(0xFF707789),
            Color(0xFF555B6B),
            Colors.transparent,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            icon,
            color: const Color(0xFF8E93A6),
            size: 15,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFFB6BCD0),
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFullDivider() {
    return Container(
      height: 1,
      width: double.infinity,
      color: const Color(0xFF303442),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2F3B),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFF3A4150),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              document.fileName,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ),

          const SizedBox(height: 12),
          _buildTopGradientDivider(),
          const SizedBox(height: 12),

          _buildInfoRow(
            CupertinoIcons.calendar,
            EstimateFormatters.formatDateTime(document.createdAt),
          ),

          const SizedBox(height: 14),
          _buildFullDivider(),
          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: _DocumentActionButton(
                  icon: CupertinoIcons.eye,
                  label: 'Open',
                  onTap: onOpen,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DocumentActionButton(
                  icon: CupertinoIcons.trash,
                  label: 'Delete',
                  onTap: onDelete,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DocumentActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _DocumentActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF20232D),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF303442)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: const Color(0xFFB6BCD0),
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
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyEmailLogsState extends StatelessWidget {
  const _EmptyEmailLogsState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2F3B),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFF3A4150),
          width: 1,
        ),
      ),
      child: const Row(
        children: [
          Icon(
            CupertinoIcons.mail,
            color: Color(0xFFB6BCD0),
            size: 18,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'No email history yet. Sent emails and reminders will appear here.',
              style: TextStyle(
                color: Color(0xFFB6BCD0),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmailLogTile extends StatelessWidget {
  final InvoiceEmailLogModel log;

  const _EmailLogTile({
    required this.log,
  });

  Color _statusColor(String status) {
    switch (status) {
      case 'sent':
        return const Color(0xFF33C27F);
      case 'failed':
        return const Color(0xFFE05A5A);
      case 'pending':
        return const Color(0xFF4A90E2);
      default:
        return const Color(0xFF8F96AB);
    }
  }

  String? _templateLabel(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case 'standard':
        return 'STANDARD';
      case 'updated':
        return 'UPDATED';
      case 'reminder':
        return 'REMINDER';
      case 'overdue':
        return 'OVERDUE';
      default:
        return null;
    }
  }

  Color _templateColor(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case 'standard':
        return const Color(0xFF5B8CFF);
      case 'updated':
        return const Color(0xFFFFB84D);
      case 'reminder':
        return const Color(0xFFB07CFF);
      case 'overdue':
        return const Color(0xFFE05A5A);
      default:
        return const Color(0xFF8F96AB);
    }
  }

  String _extractInvoiceNumber(String subject) {
    final match = RegExp(
      r'INV-\d+(?:-\d+)?',
      caseSensitive: false,
    ).firstMatch(subject);

    if (match != null) {
      return match.group(0)!.trim();
    }

    return subject.trim();
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            icon,
            color: const Color(0xFF8E93A6),
            size: 15,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFFB6BCD0),
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopGradientDivider() {
    return Container(
      height: 1,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.transparent,
            Color(0xFF555B6B),
            Color(0xFF707789),
            Color(0xFF555B6B),
            Colors.transparent,
          ],
        ),
      ),
    );
  }

  Widget _buildFullDivider() {
    return Container(
      height: 1,
      width: double.infinity,
      color: const Color(0xFF303442),
    );
  }

  Widget _buildPlainTag(String label, Color color) {
    return Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.4,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(log.status);
    final templateLabel = _templateLabel(log.templateType);
    final templateColor = _templateColor(log.templateType);
    final invoiceNumber = _extractInvoiceNumber(log.subject);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF242730),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFF343846),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              invoiceNumber,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ),

          const SizedBox(height: 12),
          _buildTopGradientDivider(),
          const SizedBox(height: 12),

          _buildInfoRow(
            CupertinoIcons.mail,
            log.recipientEmail,
          ),
          const SizedBox(height: 8),

          _buildInfoRow(
            CupertinoIcons.calendar,
            EstimateFormatters.formatDateTime(log.sentAt ?? log.createdAt),
          ),

          if ((log.providerName ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildInfoRow(
              CupertinoIcons.paperplane,
              'Provider: ${log.providerName}',
            ),
          ],

          const SizedBox(height: 12),
          _buildFullDivider(),
          const SizedBox(height: 10),

          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 14,
              runSpacing: 6,
              children: [
                _buildPlainTag(
                  log.status.toUpperCase(),
                  statusColor,
                ),
                if (templateLabel != null)
                  _buildPlainTag(
                    templateLabel,
                    templateColor,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentSummaryCard extends StatelessWidget {
  final double total;
  final double paid;
  final double balance;

  const _PaymentSummaryCard({
    required this.total,
    required this.paid,
    required this.balance,
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
      child: Row(
        children: [
          Expanded(
            child: _MiniInfo(
              label: 'Total',
              value: EstimateFormatters.formatCurrency(total),
              emphasized: true,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _MiniInfo(
              label: 'Paid',
              value: EstimateFormatters.formatCurrency(paid),
              emphasized: true,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _MiniInfo(
              label: 'Due',
              value: EstimateFormatters.formatCurrency(balance),
              emphasized: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentMethodChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback? onTap;

  const _PaymentMethodChip({
    required this.label,
    required this.isSelected,
    this.onTap,
  });

  IconData get _icon {
    switch (label.trim().toLowerCase()) {
      case 'cash':
        return CupertinoIcons.money_dollar_circle;
      case 'e-transfer':
        return CupertinoIcons.paperplane;
      case 'card':
        return CupertinoIcons.creditcard;
      case 'bank transfer':
        return CupertinoIcons.building_2_fill;
      case 'cheque':
        return CupertinoIcons.doc_text;
      default:
        return CupertinoIcons.ellipsis_circle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = isSelected
        ? const Color(0xFF182A55)
        : const Color(0xFF101117);

    final border = isSelected
        ? const Color(0xFF5B8CFF)
        : const Color(0xFF23252E);

    final textColor = isSelected
        ? const Color(0xFF8FB0FF)
        : const Color(0xFFB6BCD0);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _icon,
              color: textColor,
              size: 15,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SoftExpandHintIcon extends StatefulWidget {
  const _SoftExpandHintIcon();

  @override
  State<_SoftExpandHintIcon> createState() => _SoftExpandHintIconState();
}

class _SoftExpandHintIconState extends State<_SoftExpandHintIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutSine,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        final move = 1.0 + (_animation.value * 1.8);

        return SizedBox(
          width: 18,
          height: 18,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.translate(
                offset: Offset(-move, -move),
                child: Icon(
                  Icons.north_west_rounded,
                  color: const Color(0xFF8E93A6).withValues(alpha: 0.78),
                  size: 13,
                ),
              ),
              Transform.translate(
                offset: Offset(move, move),
                child: Icon(
                  Icons.south_east_rounded,
                  color: const Color(0xFF8E93A6).withValues(alpha: 0.78),
                  size: 13,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}