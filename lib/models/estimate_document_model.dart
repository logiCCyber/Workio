class EstimateDocumentModel {
  final String id;
  final String estimateId;
  final String fileName;
  final String filePath;
  final String? fileUrl;
  final DateTime? createdAt;

  const EstimateDocumentModel({
    required this.id,
    required this.estimateId,
    required this.fileName,
    required this.filePath,
    this.fileUrl,
    this.createdAt,
  });

  factory EstimateDocumentModel.fromMap(Map<String, dynamic> map) {
    return EstimateDocumentModel(
      id: map['id']?.toString() ?? '',
      estimateId: map['estimate_id']?.toString() ?? '',
      fileName: map['file_name']?.toString() ?? '',
      filePath: map['file_path']?.toString() ?? '',
      fileUrl: map['file_url']?.toString(),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'estimate_id': estimateId,
      'file_name': fileName,
      'file_path': filePath,
      'file_url': fileUrl,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'estimate_id': estimateId,
      'file_name': fileName,
      'file_path': filePath,
      'file_url': fileUrl,
    };
  }

  EstimateDocumentModel copyWith({
    String? id,
    String? estimateId,
    String? fileName,
    String? filePath,
    String? fileUrl,
    DateTime? createdAt,
  }) {
    return EstimateDocumentModel(
      id: id ?? this.id,
      estimateId: estimateId ?? this.estimateId,
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      fileUrl: fileUrl ?? this.fileUrl,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}