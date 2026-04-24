import 'package:supabase_flutter/supabase_flutter.dart';

class RuleAiMetadataResult {
  final List<String> aliases;
  final List<String> aiKeywords;
  final String aiScopeTemplate;
  final String aiNotesTemplate;
  final String aiLaborTitle;
  final String aiLaborDescription;
  final String aiMaterialsTitle;
  final String aiMaterialsDescription;
  final String aiPrepTitle;
  final String aiPrepDescription;
  final String aiRushTitle;
  final String aiRushDescription;
  final String normalizedServiceType;
  final String suggestedDisplayName;
  final List<Map<String, dynamic>> aiFollowupQuestions;

  const RuleAiMetadataResult({
    required this.aliases,
    required this.aiKeywords,
    required this.aiScopeTemplate,
    required this.aiNotesTemplate,
    required this.aiLaborTitle,
    required this.aiLaborDescription,
    required this.aiMaterialsTitle,
    required this.aiMaterialsDescription,
    required this.aiPrepTitle,
    required this.aiPrepDescription,
    required this.aiRushTitle,
    required this.aiRushDescription,
    required this.aiFollowupQuestions,
    required this.normalizedServiceType,
    required this.suggestedDisplayName,
  });

  factory RuleAiMetadataResult.fromMap(Map<String, dynamic> map) {
    List<String> toList(dynamic value) {
      if (value is! List) return [];
      return value
          .map((e) => e.toString().trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    List<Map<String, dynamic>> toMapList(dynamic value) {
      if (value is! List) return const [];
      return value
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    String toText(dynamic value) => value?.toString().trim() ?? '';

    return RuleAiMetadataResult(
      aliases: toList(map['aliases']),
      aiKeywords: toList(map['aiKeywords']),
      aiScopeTemplate: toText(map['aiScopeTemplate']),
      aiNotesTemplate: toText(map['aiNotesTemplate']),
      aiLaborTitle: toText(map['aiLaborTitle']),
      aiLaborDescription: toText(map['aiLaborDescription']),
      aiMaterialsTitle: toText(map['aiMaterialsTitle']),
      aiMaterialsDescription: toText(map['aiMaterialsDescription']),
      aiPrepTitle: toText(map['aiPrepTitle']),
      aiPrepDescription: toText(map['aiPrepDescription']),
      aiRushTitle: toText(map['aiRushTitle']),
      aiRushDescription: toText(map['aiRushDescription']),
      aiFollowupQuestions: toMapList(map['aiFollowupQuestions']),
      normalizedServiceType: toText(map['normalizedServiceType']),
      suggestedDisplayName: toText(map['suggestedDisplayName']),
    );
  }
}

class RuleAiMetadataService {
  RuleAiMetadataService._();

  static final SupabaseClient _supabase = Supabase.instance.client;
  static const String _functionName = 'generate-rule-ai-metadata';

  static Future<RuleAiMetadataResult> generate({
    required String serviceType,
    String? displayName,
    String? category,
    String? unit,
    List<String>? aliases,
  }) async {
    final response = await _supabase.functions.invoke(
      _functionName,
      body: {
        'serviceType': serviceType,
        'displayName': displayName,
        'category': category,
        'unit': unit,
        'aliases': aliases ?? const [],
      },
    );

    final data = response.data;

    if (data is! Map) {
      throw Exception('Invalid AI metadata response');
    }

    final map = Map<String, dynamic>.from(data as Map);

    if ((map['error'] ?? '').toString().trim().isNotEmpty) {
      throw Exception(map['error'].toString());
    }

    return RuleAiMetadataResult.fromMap(map);
  }
}