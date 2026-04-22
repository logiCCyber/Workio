import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/client_model.dart';
import '../models/company_settings_model.dart';
import '../models/estimate_document_model.dart';
import '../models/estimate_model.dart';

class SendEstimateDialogResult {
  final String recipientEmail;
  final String subject;
  final String messageBody;
  final bool useLatestSavedPdf;
  final bool generateNewPdfIfMissing;
  final String? selectedDocumentId;
  final String templateType;

  const SendEstimateDialogResult({
    required this.recipientEmail,
    required this.subject,
    required this.messageBody,
    required this.useLatestSavedPdf,
    required this.generateNewPdfIfMissing,
    this.selectedDocumentId,
    required this.templateType,
  });
}

enum EstimateEmailTemplate {
  standard,
  updated,
  followUp,
}

Future<SendEstimateDialogResult?> showSendEstimateDialog({
  required BuildContext context,
  required EstimateModel estimate,
  ClientModel? client,
  CompanySettingsModel? companySettings,
  EstimateDocumentModel? latestDocument,
}) {
  return showModalBottomSheet<SendEstimateDialogResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF15161C),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _SendEstimateDialogContent(
      estimate: estimate,
      client: client,
      companySettings: companySettings,
      latestDocument: latestDocument,
    ),
  );
}

class _SendEstimateDialogContent extends StatefulWidget {
  final EstimateModel estimate;
  final ClientModel? client;
  final CompanySettingsModel? companySettings;
  final EstimateDocumentModel? latestDocument;

  const _SendEstimateDialogContent({
    required this.estimate,
    this.client,
    this.companySettings,
    this.latestDocument,
  });

  @override
  State<_SendEstimateDialogContent> createState() =>
      _SendEstimateDialogContentState();
}

class _SendEstimateDialogContentState
    extends State<_SendEstimateDialogContent> {
  late final TextEditingController _toController;
  late final TextEditingController _subjectController;
  late final TextEditingController _messageController;

  late bool _useLatestSavedPdf;
  bool _generateNewPdfIfMissing = true;

  late EstimateEmailTemplate _selectedTemplate;

  @override
  void initState() {
    super.initState();

    _toController = TextEditingController(
      text: widget.client?.email?.trim() ?? '',
    );
    _subjectController = TextEditingController();
    _messageController = TextEditingController();

    _selectedTemplate = _resolveDefaultTemplate();
    _applyTemplate(_selectedTemplate);

    _useLatestSavedPdf = widget.latestDocument != null;
  }

  @override
  void dispose() {
    _toController.dispose();
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  EstimateEmailTemplate _resolveDefaultTemplate() {
    final status = widget.estimate.status.trim().toLowerCase();

    if (status == 'sent') {
      return EstimateEmailTemplate.followUp;
    }

    return EstimateEmailTemplate.standard;
  }

  String get _templateKey {
    switch (_selectedTemplate) {
      case EstimateEmailTemplate.standard:
        return 'standard';
      case EstimateEmailTemplate.updated:
        return 'updated';
      case EstimateEmailTemplate.followUp:
        return 'follow_up';
    }
  }

  String get _clientName {
    final value = widget.client?.fullName.trim() ?? '';
    return value.isEmpty ? 'Client' : value;
  }

  String get _companyName {
    final value = widget.companySettings?.companyName.trim() ?? '';
    return value.isEmpty ? 'Your Company' : value;
  }

  String get _estimateNumber {
    final value = widget.estimate.estimateNumber.trim();
    return value.isEmpty ? 'ESTIMATE' : value;
  }

  String get _templateTitle {
    switch (_selectedTemplate) {
      case EstimateEmailTemplate.standard:
        return 'Standard';
      case EstimateEmailTemplate.updated:
        return 'Updated Estimate';
      case EstimateEmailTemplate.followUp:
        return 'Follow-up Reminder';
    }
  }

  String get _templateSubtitle {
    switch (_selectedTemplate) {
      case EstimateEmailTemplate.standard:
        return 'Default estimate email';
      case EstimateEmailTemplate.updated:
        return 'Use when estimate was revised';
      case EstimateEmailTemplate.followUp:
        return 'Use when checking back with client';
    }
  }

  void _applyTemplate(EstimateEmailTemplate template) {
    _selectedTemplate = template;
    _subjectController.text = _buildSubject(template);
    _messageController.text = _buildMessage(template);
  }

  String _buildSubject(EstimateEmailTemplate template) {
    switch (template) {
      case EstimateEmailTemplate.standard:
        return 'Estimate $_estimateNumber';
      case EstimateEmailTemplate.updated:
        return 'Updated Estimate $_estimateNumber';
      case EstimateEmailTemplate.followUp:
        return 'Follow-up on Estimate $_estimateNumber';
    }
  }

  String _buildMessage(EstimateEmailTemplate template) {
    switch (template) {
      case EstimateEmailTemplate.standard:
        return '''
Hello $_clientName,

Please find attached your estimate $_estimateNumber.

If you have any questions, feel free to reply to this email.

Best regards,
$_companyName
''';

      case EstimateEmailTemplate.updated:
        return '''
Hello $_clientName,

Please find attached the updated estimate $_estimateNumber.

This version includes the latest changes discussed with you.

Best regards,
$_companyName
''';

      case EstimateEmailTemplate.followUp:
        return '''
Hello $_clientName,

I’m following up regarding estimate $_estimateNumber.

Please let us know if you would like to proceed or if you have any questions.

Best regards,
$_companyName
''';
    }
  }

  Future<void> _pickTemplate() async {
    final selected = await showModalBottomSheet<EstimateEmailTemplate>(
      context: context,
      backgroundColor: const Color(0xFF15161C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Choose Email Template',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                _TemplatePickerTile(
                  title: 'Standard',
                  subtitle: 'Default estimate email',
                  selected:
                  _selectedTemplate == EstimateEmailTemplate.standard,
                  onTap: () => Navigator.pop(
                    context,
                    EstimateEmailTemplate.standard,
                  ),
                ),
                const SizedBox(height: 10),
                _TemplatePickerTile(
                  title: 'Updated Estimate',
                  subtitle: 'Use when estimate was revised',
                  selected:
                  _selectedTemplate == EstimateEmailTemplate.updated,
                  onTap: () => Navigator.pop(
                    context,
                    EstimateEmailTemplate.updated,
                  ),
                ),
                const SizedBox(height: 10),
                _TemplatePickerTile(
                  title: 'Follow-up Reminder',
                  subtitle: 'Use when checking back with client',
                  selected:
                  _selectedTemplate == EstimateEmailTemplate.followUp,
                  onTap: () => Navigator.pop(
                    context,
                    EstimateEmailTemplate.followUp,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null) return;

    setState(() {
      _applyTemplate(selected);
    });
  }

  void _submit() {
    final recipient = _toController.text.trim();
    final subject = _subjectController.text.trim();
    final message = _messageController.text.trim();

    if (recipient.isEmpty) return;
    if (subject.isEmpty) return;
    if (message.isEmpty) return;

    Navigator.pop(
      context,
      SendEstimateDialogResult(
        recipientEmail: recipient,
        templateType: _templateKey,
        subject: subject,
        messageBody: message,
        useLatestSavedPdf: _useLatestSavedPdf,
        generateNewPdfIfMissing: _generateNewPdfIfMissing,
        selectedDocumentId:
        _useLatestSavedPdf ? widget.latestDocument?.id : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final latestDocument = widget.latestDocument;

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
            const Text(
              'Send Estimate',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            _PremiumTextField(
              controller: _toController,
              label: 'To',
              hintText: 'client@email.com',
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            _SelectionCard(
              label: 'Email Template',
              title: _templateTitle,
              subtitle: _templateSubtitle,
              onTap: _pickTemplate,
            ),
            const SizedBox(height: 12),
            _PremiumTextField(
              controller: _subjectController,
              label: 'Subject',
              hintText: 'Estimate EST-...',
            ),
            const SizedBox(height: 12),
            _PremiumTextField(
              controller: _messageController,
              label: 'Message',
              hintText: 'Write your message...',
              maxLines: 8,
            ),
            const SizedBox(height: 14),
            _ChoiceCard(
              title: 'Attachment Source',
              subtitle: latestDocument != null
                  ? 'Latest PDF: ${latestDocument.fileName}'
                  : 'No saved PDF found yet',
              child: Column(
                children: [
                  _SwitchRow(
                    label: 'Use latest saved PDF',
                    value: _useLatestSavedPdf,
                    onChanged: latestDocument == null
                        ? null
                        : (value) {
                      setState(() {
                        _useLatestSavedPdf = value;
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  _SwitchRow(
                    label: 'Generate new PDF if needed',
                    value: _generateNewPdfIfMissing,
                    onChanged: (value) {
                      setState(() {
                        _generateNewPdfIfMissing = value;
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: CupertinoButton(
                color: const Color(0xFF5B8CFF),
                borderRadius: BorderRadius.circular(16),
                onPressed: _submit,
                child: const Text(
                  'Continue',
                  style: TextStyle(fontWeight: FontWeight.w700),
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

class _ChoiceCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _ChoiceCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
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
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _SelectionCard extends StatelessWidget {
  final String label;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SelectionCard({
    required this.label,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF101117),
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
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF8E93A6),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Icon(
              CupertinoIcons.chevron_right,
              color: Color(0xFF8E93A6),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplatePickerTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _TemplatePickerTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF16233F) : const Color(0xFF101117),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? const Color(0xFF5B8CFF)
                : const Color(0xFF23252E),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
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
            Icon(
              selected
                  ? CupertinoIcons.check_mark_circled_solid
                  : CupertinoIcons.circle,
              color: selected
                  ? const Color(0xFF5B8CFF)
                  : const Color(0xFF5E6475),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onChanged == null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0E14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1F212A)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: disabled ? const Color(0xFF5E6475) : Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          CupertinoSwitch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF5B8CFF),
          ),
        ],
      ),
    );
  }
}