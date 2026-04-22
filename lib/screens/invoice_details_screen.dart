import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
        _showSnack('Invoice не найден');
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

      _showSnack('Не удалось загрузить invoice');
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
      _showSnack('Платёж обновлён');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Ошибка при обновлении платежа');
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
      _showSnack('Invoice не найден');
      return;
    }

    if (_balanceDue <= 0) {
      _showSnack('Этот invoice уже оплачен');
      return;
    }

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
      _showSnack('Invoice отмечен как paid');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Ошибка при mark as paid');
    } finally {
      if (!mounted) return;

      setState(() {
        _isAddingPayment = false;
      });
    }
  }

  static const List<String> _paymentMethodOptions = [
    'Cash',
    'E-transfer',
    'Card',
    'Bank Transfer',
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

    final result = await showModalBottomSheet<InvoicePaymentModel>(
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
                      existingPayment == null ? 'Add Payment' : 'Edit Payment',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _PremiumTextField(
                      controller: amountController,
                      label: 'Amount',
                      hintText: '0.00',
                      keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 12),
                    _PremiumPickerField(
                      label: 'Payment Date',
                      value: EstimateFormatters.formatDate(paymentDate),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: paymentDate,
                          firstDate:
                          DateTime.now().subtract(const Duration(days: 3650)),
                          lastDate:
                          DateTime.now().add(const Duration(days: 3650)),
                          builder: (context, child) {
                            return Theme(
                              data: ThemeData.dark().copyWith(
                                scaffoldBackgroundColor: const Color(0xFF0B0B0F),
                                colorScheme: const ColorScheme.dark(
                                  primary: Color(0xFF5B8CFF),
                                  surface: Color(0xFF15161C),
                                ),
                                dialogBackgroundColor:
                                const Color(0xFF15161C),
                              ),
                              child: child!,
                            );
                          },
                        );

                        if (picked == null) return;

                        setModalState(() {
                          paymentDate = picked;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _paymentMethodOptions.map((method) {
                          return _PaymentMethodChip(
                            label: method,
                            isSelected: selectedMethod == method,
                            onTap: () {
                              setModalState(() {
                                selectedMethod = method;
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _PremiumTextField(
                      controller: referenceController,
                      label: 'Reference Number',
                      hintText: 'Optional reference',
                    ),
                    const SizedBox(height: 12),
                    _PremiumTextField(
                      controller: notesController,
                      label: 'Notes',
                      hintText: 'Optional notes',
                      maxLines: 3,
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: CupertinoButton(
                        color: const Color(0xFF5B8CFF),
                        borderRadius: BorderRadius.circular(16),
                        onPressed: () {
                          final amount =
                          EstimateCalculator.parseNumber(amountController.text);

                          if (amount <= 0) return;

                          final payment = InvoicePaymentModel(
                            id: existingPayment?.id ?? '',
                            invoiceId: invoice.id,
                            adminAuthId: existingPayment?.adminAuthId ?? '',
                            amount: amount,
                            paymentDate: paymentDate,
                            paymentMethod:
                            selectedMethod.trim().isEmpty ? null : selectedMethod,
                            referenceNumber:
                            referenceController.text.trim().isEmpty
                                ? null
                                : referenceController.text.trim(),
                            notes: notesController.text.trim().isEmpty
                                ? null
                                : notesController.text.trim(),
                            createdAt: existingPayment?.createdAt,
                          );

                          Navigator.pop(context, payment);
                        },
                        child: Text(
                          existingPayment == null
                              ? 'Add Payment'
                              : 'Save Changes',
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

    return result;
  }

  void _showSnack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _sendInvoice() async {
    final invoice = _invoice;

    if (invoice == null) {
      _showSnack('Invoice не найден');
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
      _showSnack('Пока нет прошлой отправки');
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
      _showSnack('Invoice не найден');
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

      _showSnack('Invoice отправлен');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Ошибка при отправке invoice');
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

      _showSnack('Не удалось загрузить email history');
    }
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

      _showSnack('Не удалось загрузить документы');
    }
  }

  Future<void> _previewPdf() async {
    final invoice = _invoice;

    if (invoice == null) {
      _showSnack('Invoice не найден');
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
      _showSnack('Ошибка при открытии PDF');
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
      _showSnack('Invoice не найден');
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
      _showSnack('Ошибка при шаринге PDF');
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
      _showSnack('Invoice не найден');
      return;
    }

    if (invoice.id.trim().isEmpty) {
      _showSnack('Сначала сохрани invoice');
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

      _showSnack('PDF сохранён');
      await _loadDocuments();
    } catch (e) {
      if (!mounted) return;
      _showSnack('Ошибка при сохранении PDF');
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
        _showSnack('Не удалось открыть документ');
      }
    } catch (e) {
      _showSnack('Ошибка при открытии документа');
    }
  }

  Future<void> _deleteSavedDocument(InvoiceDocumentModel document) async {
    try {
      await InvoiceDocumentService.deleteDocument(document);

      if (!mounted) return;

      _showSnack('Документ удалён');
      await _loadDocuments();
    } catch (e) {
      if (!mounted) return;
      _showSnack('Ошибка при удалении документа');
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

  Future<void> _pickIssueDate() async {
    final initialDate = _issueDate ?? DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
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
    });
  }

  Future<void> _pickDueDate() async {
    final initialDate = _dueDate ?? DateTime.now().add(const Duration(days: 14));

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
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
      'archived',
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
          itemLabel: (status) => _statusLabel(status),
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
                  'Tax Amount',
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
                label: 'Tax',
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
                    EstimateCalculator.parseNumber(valueController.text);
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
                  'Discount Amount',
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
                label: 'Discount',
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
                    EstimateCalculator.parseNumber(valueController.text);
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
      _showSnack('Платёж добавлен');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Ошибка при добавлении платежа');
    } finally {
      if (!mounted) return;

      setState(() {
        _isAddingPayment = false;
      });
    }
  }

  Future<void> _deletePayment(InvoicePaymentModel payment) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Удалить платёж?'),
        content: Text(
          'Платёж на ${EstimateFormatters.formatCurrency(payment.amount)} будет удалён.',
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
      await InvoiceService.deletePayment(payment.id);

      if (!mounted) return;

      await _loadInitialData();
      _showSnack('Платёж удалён');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Ошибка при удалении платежа');
    }
  }

  Future<void> _archiveInvoice() async {
    final invoice = _invoice;
    if (invoice == null) return;

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

    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Delete permanently?'),
        content: const Text(
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
      _showSnack('Введите title invoice');
      return;
    }

    if (_items.isEmpty) {
      _showSnack('Добавь хотя бы один item');
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

      _showSnack('Invoice обновлён');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Ошибка при сохранении invoice');
    } finally {
      if (!mounted) return;

      setState(() {
        _isSaving = false;
      });
    }
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
      appBar: AppBar(
        backgroundColor: background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 20,
        title: const Text(
          'Invoice Details',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: IconButton(
              onPressed: _isArchiving ? null : _archiveInvoice,
              icon: _isArchiving
                  ? const CupertinoActivityIndicator(color: Colors.white)
                  : const Icon(CupertinoIcons.archivebox, color: Colors.white),
              tooltip: 'Archive',
            ),
          ),
          if (_status == 'draft')
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: IconButton(
                onPressed: _isDeleting ? null : _deleteInvoicePermanently,
                icon: _isDeleting
                    ? const CupertinoActivityIndicator(color: Colors.white)
                    : const Icon(CupertinoIcons.trash, color: Color(0xFFFF7B7B)),
                tooltip: 'Delete',
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: const Color(0xFF5B8CFF),
              borderRadius: BorderRadius.circular(14),
              onPressed: _isSaving ? null : _saveChanges,
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
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
          children: [
            _buildSectionCard(
              title: 'Invoice Header',
              subtitle: invoice.invoiceNumber,
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
                              if (_dueDate != null && _dueDate!.isBefore(_issueDate!)) {
                                _dueDate = _issueDate!.add(const Duration(days: 14));
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
                              final base = _issueDate ?? DateTime.now();
                              _dueDate = base.add(const Duration(days: 14));
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
              title: 'Company Info',
              subtitle: 'These details are currently used in the PDF',
              child: Column(
                children: [
                  Center(
                    child: _buildCompanyLogoPreview(),
                  ),
                  const SizedBox(height: 14),
                  _PreviewInfoRow(
                    label: 'Company',
                    value: (_companySettings?.companyName.trim().isNotEmpty ?? false)
                        ? _companySettings!.companyName
                        : 'Not set',
                  ),
                  const SizedBox(height: 10),
                  _PreviewInfoRow(
                    label: 'Email',
                    value: (_companySettings?.companyEmail?.trim().isNotEmpty ?? false)
                        ? _companySettings!.companyEmail!
                        : 'Not set',
                  ),
                  const SizedBox(height: 10),
                  _PreviewInfoRow(
                    label: 'Phone',
                    value: (_companySettings?.companyPhone?.trim().isNotEmpty ?? false)
                        ? _companySettings!.companyPhone!
                        : 'Not set',
                  ),
                  const SizedBox(height: 10),
                  _PreviewInfoRow(
                    label: 'Address',
                    value: (_companySettings?.companyAddress?.trim().isNotEmpty ?? false)
                        ? _companySettings!.companyAddress!
                        : 'Not set',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'Client & Property',
              subtitle: 'Привязка invoice',
              child: Column(
                children: [
                  _PreviewInfoRow(
                    label: 'Client',
                    value: _client?.fullName ?? '—',
                  ),
                  const SizedBox(height: 10),
                  _PreviewInfoRow(
                    label: 'Company',
                    value: (_client?.companyName ?? '').trim().isEmpty
                        ? '—'
                        : _client!.companyName!,
                  ),
                  const SizedBox(height: 10),
                  _PreviewInfoRow(
                    label: 'Property',
                    value: _property?.fullAddress ?? '—',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'Invoice Info',
              subtitle: 'Основная информация',
              child: _PremiumTextField(
                controller: _titleController,
                label: 'Title',
                hintText: 'Invoice title',
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'Items',
              subtitle: 'Позиции invoice',
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
              subtitle: 'Дополнительная информация',
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
              subtitle: 'Суммы по invoice',
              child: Column(
                children: [
                  _TotalsActionRow(
                    label: 'Tax Amount',
                    value: EstimateFormatters.formatCurrency(_taxAmount),
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
                  const SizedBox(height: 10),
                  _SummaryLine(
                    label: 'Paid',
                    value: EstimateFormatters.formatCurrency(_paidAmount),
                  ),
                  const SizedBox(height: 10),
                  _SummaryLine(
                    label: 'Balance Due',
                    value: EstimateFormatters.formatCurrency(_balanceDue),
                    isEmphasized: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'PDF Actions',
              subtitle: 'Открыть, поделиться или сохранить invoice',
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
            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'Saved Documents',
              subtitle: 'Сохранённые PDF файлы по этому invoice',
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
                children: List.generate(_documents.length, (index) {
                  final document = _documents[index];

                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: index == _documents.length - 1 ? 0 : 10,
                    ),
                    child: _SavedDocumentTile(
                      document: document,
                      onOpen: () => _openSavedDocument(document),
                      onDelete: () => _deleteSavedDocument(document),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'Send Invoice',
              subtitle: 'Отправка и повторная отправка invoice',
              child: Column(
                children: [
                  Row(
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
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'Email History',
              subtitle: 'История отправки этого invoice',
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
                children: List.generate(_emailLogs.length, (index) {
                  final log = _emailLogs[index];

                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: index == _emailLogs.length - 1 ? 0 : 10,
                    ),
                    child: _EmailLogTile(log: log),
                  );
                }),
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'Payments',
              subtitle: 'История оплат по invoice',
              child: Column(
                children: [
                  _PaymentSummaryCard(
                    total: _total,
                    paid: _paidAmount,
                    balance: _balanceDue,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _ActionButtonWide(
                          icon: CupertinoIcons.add,
                          label: _isAddingPayment ? 'Please wait...' : 'Add Payment',
                          onTap: _isAddingPayment ? null : _addPayment,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ActionButtonWide(
                          icon: CupertinoIcons.check_mark_circled,
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
                    children: List.generate(_payments.length, (index) {
                      final payment = _payments[index];

                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: index == _payments.length - 1 ? 0 : 10,
                        ),
                        child: _PaymentTile(
                          payment: payment,
                          onEdit: () => _editPayment(payment),
                          onDelete: () => _deletePayment(payment),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            CupertinoButton(
              color: const Color(0xFF5B8CFF),
              borderRadius: BorderRadius.circular(18),
              padding: const EdgeInsets.symmetric(vertical: 16),
              onPressed: _isSaving ? null : _saveChanges,
              child: _isSaving
                  ? const CupertinoActivityIndicator(color: Colors.white)
                  : const Text(
                'Save Invoice Changes',
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
              'Пока нет items. Добавь первую позицию.',
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

class _EmptyPaymentsState extends StatelessWidget {
  const _EmptyPaymentsState();

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
            CupertinoIcons.money_dollar_circle,
            color: Color(0xFF8E93A6),
            size: 20,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Пока нет платежей по этому invoice.',
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
                  EstimateFormatters.formatCurrency(payment.amount),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
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
                color: const Color(0xFFE05A5A),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            EstimateFormatters.formatDate(payment.paymentDate),
            style: const TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (method.isNotEmpty) ...[
            const SizedBox(height: 10),
            _PaymentMethodChip(
              label: method,
              isSelected: true,
            ),
          ],
          if (reference.isNotEmpty) ...[
            const SizedBox(height: 8),
            _PaymentInfoRow(
              label: 'Reference',
              value: reference,
            ),
          ],
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            _PaymentInfoRow(
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
  final String label;
  final String value;

  const _PaymentInfoRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '$label: ',
          style: const TextStyle(
            color: Color(0xFF8E93A6),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
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

class _ActionButtonWide extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ActionButtonWide({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = onTap == null;

    return Material(
      color: const Color(0xFF101117),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 50,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDisabled
                  ? const Color(0xFF1A1C24)
                  : const Color(0xFF23252E),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isDisabled
                    ? const Color(0xFF5E6475)
                    : const Color(0xFFB6BCD0),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isDisabled
                      ? const Color(0xFF5E6475)
                      : Colors.white,
                  fontSize: 14,
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

class _EmptyDocumentsState extends StatelessWidget {
  const _EmptyDocumentsState();

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
            CupertinoIcons.doc,
            color: Color(0xFF8E93A6),
            size: 20,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Пока нет сохранённых PDF документов.',
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
          Text(
            document.fileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            EstimateFormatters.formatDateTime(document.createdAt),
            style: const TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
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
      color: const Color(0xFF0D0E14),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1F212A)),
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF23252E)),
      ),
      child: const Row(
        children: [
          Icon(
            CupertinoIcons.mail,
            color: Color(0xFF8E93A6),
            size: 20,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Пока нет истории отправок.',
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

  Widget _buildTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withOpacity(0.35),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(log.status);
    final templateLabel = _templateLabel(log.templateType);
    final templateColor = _templateColor(log.templateType);

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
          Text(
            log.recipientEmail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            log.subject,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFB6BCD0),
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildTag(log.status.toUpperCase(), statusColor),
              if (templateLabel != null)
                _buildTag(templateLabel, templateColor),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            EstimateFormatters.formatDateTime(log.sentAt ?? log.createdAt),
            style: const TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          if ((log.providerName ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Provider: ${log.providerName}',
              style: const TextStyle(
                color: Color(0xFF8E93A6),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
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

  @override
  Widget build(BuildContext context) {
    final bg = isSelected
        ? const Color(0xFF5B8CFF)
        : const Color(0xFF101117);

    final border = isSelected
        ? const Color(0xFF5B8CFF)
        : const Color(0xFF23252E);

    final textColor = isSelected ? Colors.white : const Color(0xFFB6BCD0);

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
        child: Text(
          label,
          style: TextStyle(
            color: textColor,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}