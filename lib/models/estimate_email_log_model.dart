class EstimateEmailLogModel {
  final String id;
  final String estimateId;
  final String adminAuthId;
  final String recipientEmail;
  final String subject;
  final String? messageBody;
  final String? pdfDocumentId;
  final String status;
  final String? providerName;
  final String? providerMessageId;
  final DateTime? sentAt;
  final DateTime? createdAt;
  final String? templateType;

  const EstimateEmailLogModel({
    required this.id,
    required this.estimateId,
    required this.adminAuthId,
    required this.recipientEmail,
    required this.subject,
    this.messageBody,
    this.pdfDocumentId,
    required this.status,
    this.providerName,
    this.providerMessageId,
    this.sentAt,
    this.createdAt,
    this.templateType,
  });

  factory EstimateEmailLogModel.fromMap(Map<String, dynamic> map) {
    return EstimateEmailLogModel(
      id: map['id']?.toString() ?? '',
      estimateId: map['estimate_id']?.toString() ?? '',
      adminAuthId: map['admin_auth_id']?.toString() ?? '',
      recipientEmail: map['recipient_email']?.toString() ?? '',
      subject: map['subject']?.toString() ?? '',
      messageBody: map['message_body']?.toString(),
      pdfDocumentId: map['pdf_document_id']?.toString(),
      status: map['status']?.toString() ?? 'sent',
      providerName: map['provider_name']?.toString(),
      providerMessageId: map['provider_message_id']?.toString(),
      templateType: map['template_type']?.toString(),
      sentAt: map['sent_at'] != null
          ? DateTime.tryParse(map['sent_at'].toString())
          : null,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'estimate_id': estimateId,
      'admin_auth_id': adminAuthId,
      'recipient_email': recipientEmail,
      'subject': subject,
      'message_body': messageBody,
      'pdf_document_id': pdfDocumentId,
      'status': status,
      'provider_name': providerName,
      'provider_message_id': providerMessageId,
      'sent_at': sentAt?.toIso8601String(),
      'created_at': createdAt?.toIso8601String(),
      'template_type': templateType,
    };
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'estimate_id': estimateId,
      'admin_auth_id': adminAuthId,
      'recipient_email': recipientEmail,
      'subject': subject,
      'message_body': messageBody,
      'pdf_document_id': pdfDocumentId,
      'status': status,
      'provider_name': providerName,
      'provider_message_id': providerMessageId,
      'sent_at': sentAt?.toIso8601String(),
      'template_type': templateType,
    };
  }

  EstimateEmailLogModel copyWith({
    String? id,
    String? estimateId,
    String? adminAuthId,
    String? recipientEmail,
    String? subject,
    String? messageBody,
    String? pdfDocumentId,
    String? status,
    String? providerName,
    String? providerMessageId,
    DateTime? sentAt,
    DateTime? createdAt,
    String? templateType,
  }) {
    return EstimateEmailLogModel(
      id: id ?? this.id,
      estimateId: estimateId ?? this.estimateId,
      adminAuthId: adminAuthId ?? this.adminAuthId,
      recipientEmail: recipientEmail ?? this.recipientEmail,
      subject: subject ?? this.subject,
      messageBody: messageBody ?? this.messageBody,
      pdfDocumentId: pdfDocumentId ?? this.pdfDocumentId,
      status: status ?? this.status,
      providerName: providerName ?? this.providerName,
      providerMessageId: providerMessageId ?? this.providerMessageId,
      sentAt: sentAt ?? this.sentAt,
      createdAt: createdAt ?? this.createdAt,
      templateType: templateType ?? this.templateType,
    );
  }

  bool get isPending => status == 'pending';
  bool get isSent => status == 'sent';
  bool get isFailed => status == 'failed';
}