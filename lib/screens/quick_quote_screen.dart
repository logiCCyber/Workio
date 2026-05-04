import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'dart:io';
import 'dart:convert';

import '../models/ai_estimate_result_model.dart';
import '../models/estimate_item_model.dart';
import '../services/company_settings_service.dart';
import '../services/smart_estimate_service.dart';
import '../utils/estimate_calculator.dart';
import '../utils/estimate_formatters.dart';

import '../models/client_model.dart';
import '../models/property_model.dart';
import '../models/estimate_model.dart';
import '../models/estimate_price_rule_model.dart';

import '../services/client_service.dart';
import '../services/property_service.dart';
import '../services/estimate_service.dart';
import '../services/parse_estimate_mini_service.dart';
import '../services/estimate_price_rules_service.dart';
import '../services/estimate_rule_resolution_service.dart';

import 'estimate_details_screen.dart';
import '../dialogs/add_client_dialog.dart';
import '../dialogs/add_property_dialog.dart';

class QuickQuoteScreen extends StatefulWidget {
  const QuickQuoteScreen({super.key});

  @override
  State<QuickQuoteScreen> createState() => _QuickQuoteScreenState();
}

class _QuickQuoteScreenState extends State<QuickQuoteScreen> {
  final TextEditingController _promptController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _speechReady = false;
  bool _isListening = false;
  bool _voiceAppendMode = false;

  bool _photoMode = false;
  final List<XFile> _selectedPhotos = [];
  static const int _maxPhotos = 5;

  bool _isLoading = true;
  bool _isGenerating = false;
  bool _isConverting = false;
  bool _isAnalyzingPhoto = false;
  String? _photoDetectedIssue;
  String? _photoWarning;
  String? _photoMatchedService;
  double? _photoConfidence;

  String? _forcedServiceType;
  String? _matchedServiceLabel;
  EstimatePriceRuleModel? _selectedPriceRule;

  List<ClientModel> _clients = [];
  List<PropertyModel> _properties = [];

  ClientModel? _selectedClient;
  PropertyModel? _selectedProperty;

  AiEstimateResultModel? _result;

  double _taxRate = 0.13;
  String _taxLabel = 'Tax';
  String _currencyCode = 'CAD';

  @override
  void initState() {
    super.initState();
    _loadDefaults();
    _initSpeech();
  }

  @override
  void dispose() {
    _speech.stop();
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _loadDefaults() async {
    try {
      final settings = await CompanySettingsService.getSettings();
      final clients = await ClientService.getClients();

      if (!mounted) return;

      final taxLabel = settings?.taxLabel.trim() ?? '';
      final currencyCode = settings?.currencyCode.trim() ?? '';

      setState(() {
        _taxRate = settings?.defaultTaxRate ?? 0.13;
        _taxLabel = taxLabel.isEmpty ? 'Tax' : taxLabel;
        _currencyCode = currencyCode.isEmpty ? 'CAD' : currencyCode.toUpperCase();
        _clients = clients;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showSnack('Failed to load quick quote data');
    }
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
      onError: (_) {
        if (!mounted) return;

        setState(() {
          _isListening = false;
        });

        _showSnack('Voice input failed');
      },
    );

    if (!mounted) return;

    setState(() {
      _speechReady = ready;
    });
  }

  void _insertVoiceText(
      String spokenText, {
        required bool append,
      }) {
    final clean = spokenText.trim();
    if (clean.isEmpty) return;

    final current = _promptController.text.trim();

    final next = append
        ? (current.isEmpty ? clean : '$current $clean').trim()
        : clean;

    _promptController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  Future<void> _startVoiceInput({
    required bool append,
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

        if (result.finalResult) {
          _insertVoiceText(
            result.recognizedWords,
            append: _voiceAppendMode,
          );

          setState(() {
            _isListening = false;
          });
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

  Future<void> _openVoicePromptSheet() async {
    if (_isListening) {
      await _stopVoiceInput();
      return;
    }

    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) {
        return CupertinoActionSheet(
          title: const Text('Voice Prompt'),
          message: const Text('Choose how Workio should insert your voice text'),
          actions: [
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, 'replace'),
              child: const Text('Replace prompt'),
            ),
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, 'append'),
              child: const Text('Append to prompt'),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        );
      },
    );

    if (action == 'replace') {
      await _startVoiceInput(append: false);
    } else if (action == 'append') {
      await _startVoiceInput(append: true);
    }
  }

  EstimateTotals get _totals {
    return EstimateCalculator.calculateTotals(
      items: _result?.items ?? const <EstimateItemModel>[],
      taxRate: _taxRate,
      discountValue: 0,
      discountIsPercentage: false,
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _cleanEstimateText(String value) {
    var text = value.trim();

    if (text.isEmpty) return '';

    text = text
    // empty brackets
        .replaceAll(RegExp(r'\(\s*\)'), '')
        .replaceAll(RegExp(r'\[\s*\]'), '')
        .replaceAll(RegExp(r'\{\s*\}'), '')

    // empty placeholders / ugly punctuation
        .replaceAll(RegExp(r'\s+,\s*'), ', ')
        .replaceAll(RegExp(r'\s+;\s*'), '; ')
        .replaceAll(RegExp(r'\s+:\s*'), ': ')
        .replaceAll(RegExp(r'\.{2,}'), '.')
        .replaceAll(RegExp(r'\s+\.'), '.')
        .replaceAll(RegExp(r'\s+,'), ',')

    // remove repeated generic AI opening
        .replaceAll(
      RegExp(
        r'^Complete the requested work for\s+[^:]+:\s*',
        caseSensitive: false,
      ),
      '',
    )
        .replaceAll(
      RegExp(
        r'^Complete the requested\s+',
        caseSensitive: false,
      ),
      '',
    )
        .replaceAll(
      RegExp(r'\bMaterials not included\.\s*Not\.', caseSensitive: false),
      'Materials not included.',
    )
        .replaceAll(
      RegExp(r'\bNot\.\s*On-site labor', caseSensitive: false),
      'On-site labor',
    )
        .replaceAll(
      RegExp(r'\bNot\.\s*Labor', caseSensitive: false),
      'Labor',
    )
        .replaceAll(
      RegExp(r'\bNot\.\s*Verify', caseSensitive: false),
      'Verify',
    )

    // cleanup wording
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();

    text = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n');

    return text;
  }

  String _resultServiceTitle(AiEstimateResultModel result, int index) {
    String cleanTitle(String value) {
      var text = value.trim();

      text = text
          .replaceAll(
        RegExp(r'\s+estimate$', caseSensitive: false),
        '',
      )
          .replaceAll(
        RegExp(r'\s+quick quote$', caseSensitive: false),
        '',
      )
          .replaceAll(RegExp(r'\s{2,}'), ' ')
          .trim();

      return text;
    }

    final title = cleanTitle(result.title ?? '');

    if (title.isNotEmpty &&
        title.toLowerCase() != 'quick quote' &&
        title.toLowerCase() != 'ai estimate') {
      return title;
    }

    final firstItemTitle = result.items.isNotEmpty
        ? cleanTitle(result.items.first.title)
        : '';

    if (firstItemTitle.isNotEmpty) {
      return firstItemTitle;
    }

    return 'Service ${index + 1}';
  }

  String _buildRichMultiScope(List<AiEstimateResultModel> results) {
    final sections = <String>[];

    for (var i = 0; i < results.length; i++) {
      final result = results[i];

      final title = _cleanEstimateText(_resultServiceTitle(result, i));
      final scope = _cleanEstimateText(result.scope ?? '');

      if (scope.isEmpty) continue;

      sections.add('$title\n$scope');
    }

    return sections.join('\n\n');
  }

  String _buildRichMultiNotes(List<AiEstimateResultModel> results) {
    final sections = <String>[];

    for (var i = 0; i < results.length; i++) {
      final result = results[i];

      final title = _cleanEstimateText(_resultServiceTitle(result, i));
      final notes = _cleanEstimateText(result.notes ?? '');

      if (notes.isEmpty) continue;

      sections.add('$title\n$notes');
    }

    return sections.join('\n\n');
  }

  Future<String?> _normalizeQuickQuotePrompt(String rawPrompt) async {
    final original = rawPrompt.trim();
    if (original.isEmpty) return null;

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'normalize-quick-quote-prompt',
        body: {
          'prompt': original,
        },
      );

      final data = Map<String, dynamic>.from(response.data as Map);

      final cleanPrompt = (data['cleanPrompt'] ?? original).toString().trim();

      // ВАЖНО:
      // Никаких popup. Admin не должен отвечать вручную.
      // Если AI сомневается по материалам — мы всё равно продолжаем.
      // Явные материалы потом отдельно парсит ParseEstimateMiniService.
      return cleanPrompt.isEmpty ? original : cleanPrompt;
    } catch (_) {
      return original;
    }
  }

  Map<String, dynamic> _ruleToCandidate(EstimatePriceRuleModel rule) {
    return {
      'ruleId': rule.id,
      'serviceType': rule.serviceType,
      'displayName': rule.displayName,
      'unit': rule.unit,
      'category': rule.category,
      'aliases': rule.aliases,
      'aiKeywords': rule.aiKeywords,
      'negativeKeywords': rule.negativeKeywords,
      'followupQuestions': rule.aiFollowupQuestions,
    };
  }

  String _intentClean(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _detectPromptIntent(String prompt) {
    final text = _intentClean(prompt);

    if (RegExp(r'\b(install|installation|mount|setup|put in|connect)\b').hasMatch(text)) {
      return 'installation';
    }

    if (RegExp(r'\b(replace|replacement|swap|change)\b').hasMatch(text)) {
      return 'replacement';
    }

    if (RegExp(r'\b(repair|fix|troubleshoot|service|leak|broken|not working)\b').hasMatch(text)) {
      return 'repair';
    }

    if (RegExp(r'\b(inspect|inspection|diagnose|check)\b').hasMatch(text)) {
      return 'inspection';
    }

    return 'broad';
  }

  String _detectRuleIntent(EstimatePriceRuleModel rule) {
    final text = _intentClean(
      '${rule.serviceType} ${rule.displayName ?? ''}',
    );

    if (RegExp(r'\b(install|installation|mount|setup)\b').hasMatch(text)) {
      return 'installation';
    }

    if (RegExp(r'\b(replace|replacement|swap)\b').hasMatch(text)) {
      return 'replacement';
    }

    if (RegExp(r'\b(repair|fix|troubleshoot|leak|broken)\b').hasMatch(text)) {
      return 'repair';
    }

    if (RegExp(r'\b(inspect|inspection|diagnose|diagnostic)\b').hasMatch(text)) {
      return 'inspection';
    }

    return 'broad';
  }

  bool _ruleIntentConflictsWithPrompt(
      String prompt,
      EstimatePriceRuleModel rule,
      ) {
    final promptIntent = _detectPromptIntent(prompt);
    final ruleIntent = _detectRuleIntent(rule);

    if (promptIntent == 'broad') return false;
    if (ruleIntent == 'broad') return false;

    return promptIntent != ruleIntent;
  }

  EstimatePriceRuleModel? _resolveRuleByLocalAliasFallback(
      String prompt,
      List<EstimatePriceRuleModel> rules,
      ) {
    String clean(String value) {
      return value
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9\s]+'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }

    String stem(String value) {
      var text = clean(value);

      if (text.endsWith('ies') && text.length > 4) {
        return '${text.substring(0, text.length - 3)}y';
      }

      if (text.endsWith('ches') && text.length > 5) {
        return text.substring(0, text.length - 2); // switches -> switch
      }

      if (text.endsWith('shes') && text.length > 5) {
        return text.substring(0, text.length - 2);
      }

      if (text.endsWith('es') && text.length > 4) {
        return text.substring(0, text.length - 2);
      }

      if (text.endsWith('s') && text.length > 3) {
        return text.substring(0, text.length - 1);
      }

      return text;
    }

    const genericWords = {
      'repair',
      'fix',
      'replace',
      'replacement',
      'install',
      'installation',
      'inspect',
      'inspection',
      'diagnose',
      'diagnostic',
      'service',
      'services',
      'work',
      'job',
      'labor',
      'labour',
      'urgent',
      'rush',
      'asap',
      'material',
      'materials',
      'included',
      'customer',
      'provided',
      'problem',
      'issue',
      'broken',
      'damaged',
      'burned',
      'check',
      'checking',
      'as',
      'needed',
    };

    List<String> tokens(String value) {
      return clean(value)
          .split(' ')
          .map((e) => stem(e))
          .where((e) => e.length >= 3)
          .where((e) => !genericWords.contains(e))
          .toList();
    }

    bool containsPhrase(String text, String phrase) {
      final cleanPhrase = clean(phrase);
      if (cleanPhrase.isEmpty) return false;

      return text.contains(RegExp(
        r'(^|\s)' + RegExp.escape(cleanPhrase) + r'(\s|$)',
      ));
    }

    final normalizedPrompt = clean(prompt);
    if (normalizedPrompt.isEmpty) return null;

    final promptTokens = tokens(normalizedPrompt).toSet();

    double bestScore = 0;
    EstimatePriceRuleModel? bestRule;

    for (final rule in rules) {
      double score = 0;

      final candidates = <({String text, double weight})>[
        (text: rule.serviceType, weight: 1.00),
        (text: rule.displayName ?? '', weight: 1.05),
        ...rule.aliases.map((e) => (text: e, weight: 1.35)),
        ...rule.aiKeywords.map((e) => (text: e, weight: 1.25)),
      ];

      int bestMatchedSpecificTokens = 0;

      for (final candidate in candidates) {
        final candidateText = clean(candidate.text);
        if (candidateText.isEmpty) continue;

        final candidateTokens = tokens(candidateText);
        if (candidateTokens.isEmpty) continue;

        int matchedTokens = 0;

        for (final token in candidateTokens) {
          if (promptTokens.contains(token)) {
            matchedTokens++;
          }
        }

        if (matchedTokens == 0) continue;

        bestMatchedSpecificTokens =
        matchedTokens > bestMatchedSpecificTokens
            ? matchedTokens
            : bestMatchedSpecificTokens;

        score += matchedTokens * 2.0 * candidate.weight;

        final allTokensMatched = candidateTokens.every(promptTokens.contains);
        if (allTokensMatched) {
          score += 3.0 * candidate.weight;
        }

        if (containsPhrase(normalizedPrompt, candidateText)) {
          score += 5.0 * candidate.weight;
        }

        // More specific object aliases should beat broad labor/category rules.
        if (candidateTokens.length <= 3 && allTokensMatched) {
          score += 2.0 * candidate.weight;
        }
      }

      for (final negative in rule.negativeKeywords) {
        final negativeText = clean(negative);
        if (negativeText.isEmpty) continue;

        final negativeTokens = tokens(negativeText);
        final negativeMatched =
            containsPhrase(normalizedPrompt, negativeText) ||
                negativeTokens.any(promptTokens.contains);

        if (negativeMatched) {
          score -= 8;
        }
      }

      if (bestMatchedSpecificTokens == 0) {
        score = 0;
      }

      if (_ruleIntentConflictsWithPrompt(prompt, rule)) {
        score -= 12;
      }

      if (score <= 0) {
        continue;
      }

      if (score > bestScore) {
        bestScore = score;
        bestRule = rule;
      }
    }

    return bestScore >= 2 ? bestRule : null;
  }

  Future<EstimatePriceRuleModel?> _resolveRuleForPrompt(String prompt) async {
    final rules = await EstimatePriceRulesService.getRules();
    final activeRules = rules.where((rule) => rule.isActive).toList();

    if (activeRules.isEmpty) return null;

    // Strong local fallback FIRST.
    // If prompt clearly contains a rule alias/keyword like "outlet",
    // do not let AI resolver reject inspection wording.
    final localFirst = _resolveRuleByLocalAliasFallback(prompt, activeRules);
    if (localFirst != null) {
      return localFirst;
    }

    final resolverResult = await EstimateRuleResolutionService.resolve(
      prompt: prompt,
      guidedAnswers: {
        'requested_work': prompt,
      },
      candidates: activeRules.map(_ruleToCandidate).toList(),
    );

    final selectedRuleId = resolverResult.selectedRuleId;

    if ((selectedRuleId ?? '').trim().isEmpty) {
      return _resolveRuleByLocalAliasFallback(prompt, activeRules);
    }

    final resolved = await EstimatePriceRulesService.getRuleById(
      selectedRuleId!.trim(),
    );

    if (resolved != null && _ruleIntentConflictsWithPrompt(prompt, resolved)) {
      return _resolveRuleByLocalAliasFallback(
        prompt,
        activeRules.where((rule) => rule.id != resolved.id).toList(),
      );
    }

    return resolved ?? _resolveRuleByLocalAliasFallback(prompt, activeRules);
  }

  Future<List<String>?> _splitQuickQuoteJobs(String prompt) async {
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'split-quick-quote-jobs',
        body: {
          'prompt': prompt,
        },
      );

      final data = Map<String, dynamic>.from(response.data as Map);

      final rawJobs = data['jobs'];
      if (rawJobs is! List) return [prompt];

      final jobs = rawJobs
          .whereType<Map>()
          .map((job) => (job['description'] ?? '').toString().trim())
          .where((text) => text.isNotEmpty)
          .toList();

      if (jobs.isEmpty) return [prompt];

      return jobs.length > 8 ? jobs.take(8).toList() : jobs;
    } catch (_) {
      return [prompt];
    }
  }

  Future<AiEstimateResultModel?> _generateSingleJobQuote(String jobPrompt) async {
    final selectedRule = await _resolveRuleForPrompt(jobPrompt);

    if (selectedRule == null) {
      return null;
    }

    final serviceLabel = selectedRule.displayName?.trim().isNotEmpty == true
        ? selectedRule.displayName!.trim()
        : selectedRule.serviceType.trim();

    final systemPrompt =
        'service_type: ${selectedRule.serviceType}. '
        'service_label: $serviceLabel. '
        'request: $jobPrompt';

    return SmartEstimateService.generate(
      prompt: systemPrompt,
      propertyCity: null,
      clientId: null,
      propertyId: null,
      ruleUnit: selectedRule.unit,
      selectedRule: selectedRule,
      allowDraftWithExplicitService: true,
    );
  }

  AiEstimateResultModel _mergeQuickQuoteResults({
    required String prompt,
    required List<AiEstimateResultModel> results,
  }) {
    final items = <EstimateItemModel>[];

    for (final result in results) {
      items.addAll(result.items);
    }

    final richScope = _buildRichMultiScope(results);
    final richNotes = _buildRichMultiNotes(results);

    final confidence = results.isEmpty
        ? 0.0
        : results
        .map((result) => result.confidence)
        .fold<double>(0, (sum, value) => sum + value) /
        results.length;

    return AiEstimateResultModel(
      title: results.length > 1 ? 'Multi-Service Quick Quote' : results.first.title,
      scope: richScope.trim().isEmpty ? null : richScope.trim(),
      notes: richNotes.trim().isEmpty ? null : richNotes.trim(),
      items: items,
      parsedRequest: results.first.parsedRequest,
      assumptions: results.expand((result) => result.assumptions).toList(),
      missingFields: results.expand((result) => result.missingFields).toList(),
      confidence: confidence,
    );
  }

  double? _promptNumber(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();

    final clean = value.toString().replaceAll(',', '.').trim();
    return double.tryParse(clean);
  }

  String _promptTitleCase(String value) {
    return value
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase())
        .join(' ');
  }

  Future<List<EstimateItemModel>> _buildPromptMaterialItems(
      String prompt, {
        required int startSortOrder,
      }) async {
    try {
      final parsed = await ParseEstimateMiniService.parse(
        prompt: prompt,
        localParsed: const <String, dynamic>{},
      );

      final items = <EstimateItemModel>[];

      for (final material in parsed.parsedMaterials) {
        final rawName = (material['name'] ?? '').toString().trim();
        final rawText = (material['raw_text'] ?? '').toString().trim();

        final quantity = _promptNumber(material['quantity']) ?? 1;
        final unitPrice = _promptNumber(material['unit_price']);
        final lineTotal = _promptNumber(material['line_total']);

        double resolvedUnitPrice = unitPrice ?? 0;

        if (resolvedUnitPrice <= 0 && lineTotal != null && lineTotal > 0) {
          resolvedUnitPrice = quantity > 0 ? lineTotal / quantity : lineTotal;
        }

        if (resolvedUnitPrice <= 0) continue;

        final safeQty = quantity <= 0 ? 1.0 : quantity;
        final titleName = rawName.isEmpty ? 'Materials' : _promptTitleCase(rawName);
        final total = EstimateCalculator.calculateLineTotal(
          quantity: safeQty,
          unitPrice: resolvedUnitPrice,
        );

        items.add(
          EstimateItemModel(
            id: '',
            estimateId: '',
            title: '$titleName Materials',
            description: rawText.isEmpty
                ? 'Parsed from prompt material details.'
                : 'Parsed from prompt: $rawText',
            unit: 'item',
            quantity: safeQty,
            unitPrice: double.parse(resolvedUnitPrice.toStringAsFixed(2)),
            lineTotal: total,
            sortOrder: startSortOrder + items.length,
            createdAt: null,
          ),
        );
      }

      return items;
    } catch (_) {
      return const <EstimateItemModel>[];
    }
  }

  AiEstimateResultModel _appendPromptMaterialItems(
      AiEstimateResultModel result,
      List<EstimateItemModel> materialItems,
      ) {
    if (materialItems.isEmpty) return result;

    String clean(String value) {
      return value
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9\s]+'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }

    String stem(String value) {
      var text = clean(value);

      if (text.endsWith('ies') && text.length > 4) {
        return '${text.substring(0, text.length - 3)}y';
      }

      if (text.endsWith('ches') && text.length > 5) {
        return text.substring(0, text.length - 2);
      }

      if (text.endsWith('shes') && text.length > 5) {
        return text.substring(0, text.length - 2);
      }

      if (text.endsWith('es') && text.length > 4) {
        return text.substring(0, text.length - 2);
      }

      if (text.endsWith('s') && text.length > 3) {
        return text.substring(0, text.length - 1);
      }

      return text;
    }

    Set<String> objectTokens(String value) {
      const ignored = {
        'material',
        'materials',
        'item',
        'items',
        'part',
        'parts',
        'supply',
        'supplies',
        'each',
        'per',
        'total',
        'cost',
        'price',
        'parsed',
        'from',
        'prompt',
        'detail',
        'details',
        'included',
        'include',
        'with',
        'for',
        'and',
        'the',
      };

      return clean(value)
          .split(' ')
          .map(stem)
          .where((e) => e.length >= 3)
          .where((e) => !ignored.contains(e))
          .toSet();
    }

    bool closeMoney(double a, double b) {
      return (a - b).abs() < 0.01;
    }

    bool isDuplicatePromptMaterial(
        EstimateItemModel existing,
        EstimateItemModel material,
        ) {
      final sameQty = closeMoney(existing.quantity, material.quantity);
      final sameUnitPrice = closeMoney(existing.unitPrice, material.unitPrice);
      final sameLineTotal = closeMoney(existing.lineTotal, material.lineTotal);

      if (!sameQty || !sameUnitPrice || !sameLineTotal) {
        return false;
      }

      final existingTokens = objectTokens(
        '${existing.title} ${existing.description}',
      );

      final materialTokens = objectTokens(
        '${material.title} ${material.description}',
      );

      if (existingTokens.isEmpty || materialTokens.isEmpty) return false;

      final hasSameObject =
          existingTokens.intersection(materialTokens).isNotEmpty;

      if (!hasSameObject) return false;

      final existingTitle = clean(existing.title);

      final looksLikeRealWork = RegExp(
        r'\b(installation|install|repair|replace|replacement|service|removal|remove|inspection|inspect|diagnose|troubleshoot|mount|assembly|assemble)\b',
      ).hasMatch(existingTitle);

      // Example:
      // Keep: "Outlet Service" / "Dishwasher Installation"
      // Remove: "Outlets" when exact same qty + price + total exists as material.
      return !looksLikeRealWork;
    }

    final filteredExistingItems = result.items.where((existing) {
      for (final material in materialItems) {
        if (isDuplicatePromptMaterial(existing, material)) {
          return false;
        }
      }

      return true;
    }).toList();

    final normalizedMaterials = materialItems.asMap().entries.map((entry) {
      final index = filteredExistingItems.length + entry.key;
      final item = entry.value;

      return item.copyWith(
        sortOrder: index,
        lineTotal: EstimateCalculator.calculateLineTotal(
          quantity: item.quantity,
          unitPrice: item.unitPrice,
        ),
      );
    }).toList();

    return result.copyWith(
      items: [
        ...filteredExistingItems,
        ...normalizedMaterials,
      ],
      notes: (result.notes ?? '').trim(),
    );
  }

  bool _isMaterialOnlyJobPrompt(String value) {
    final text = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s\$\.,]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (text.isEmpty) return false;

    final hasMoney = RegExp(
      r'(\$ ?\d+|\d+ ?\$|\b\d+(\.\d+)?\s*(each|per|total)\b)',
    ).hasMatch(text);

    final hasMaterialSignal = RegExp(
      r'\b(material|materials|part|parts|supply|supplies|included|cost|price|each|per|total)\b',
    ).hasMatch(text);

    final hasWorkAction = RegExp(
      r'\b(replace|repair|fix|install|mount|remove|clean|paint|inspect|diagnose|check|service|troubleshoot|change|swap|assemble|connect|disconnect|move|build|cut|seal|patch|caulk)\b',
    ).hasMatch(text);

    return hasMaterialSignal && hasMoney && !hasWorkAction;
  }

  bool _hasRushSignalInPrompt(String value) {
    final text = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (RegExp(
      r'\b(no rush|not urgent|not rush|standard timing|normal schedule|not srochnaya|ne srochnaya|rabota ne srochnaya)\b',
    ).hasMatch(text)) {
      return false;
    }

    return RegExp(
      r'\b(urgent|rush|asap|same day|emergency|priority|expedited|srochno|srochnaya|rabota srochnaya|shoshilinch)\b',
    ).hasMatch(text);
  }

  Future<void> _generateQuote() async {
    final rawPrompt = _promptController.text.trim();

    if (rawPrompt.isEmpty) {
      _showSnack('Describe the work first');
      return;
    }

    setState(() {
      _isGenerating = true;
      _result = null;
      _selectedPriceRule = null;
      _forcedServiceType = null;
      _matchedServiceLabel = null;
    });

    try {
      final normalizedPrompt = await _normalizeQuickQuotePrompt(rawPrompt);
      if (normalizedPrompt == null || normalizedPrompt.trim().isEmpty) {
        return;
      }

      final jobs = await _splitQuickQuoteJobs(normalizedPrompt.trim());
      if (jobs == null || jobs.isEmpty) {
        return;
      }

      final results = <AiEstimateResultModel>[];
      final failedJobs = <String>[];

      for (final job in jobs) {
        if (_isMaterialOnlyJobPrompt(job)) {
          continue;
        }

        final cleanJob = await _normalizeQuickQuotePrompt(job);

        if (cleanJob == null || cleanJob.trim().isEmpty) {
          failedJobs.add(job);
          continue;
        }

        final cleanJobText = cleanJob.trim();

        if (_isMaterialOnlyJobPrompt(cleanJobText)) {
          continue;
        }

        final finalJobPrompt = _hasRushSignalInPrompt(normalizedPrompt.trim()) &&
            !_hasRushSignalInPrompt(cleanJobText)
            ? '$cleanJobText. Urgent.'
            : cleanJobText;

        final result = await _generateSingleJobQuote(finalJobPrompt);

        if (result == null || result.items.isEmpty) {
          failedJobs.add(cleanJobText);
          continue;
        }

        results.add(result);
      }

      if (!mounted) return;

      if (results.isEmpty) {
        _showSnack('No matching Price Rules found. Add them in Price Rules first.');
        return;
      }

      final merged = _mergeQuickQuoteResults(
        prompt: normalizedPrompt.trim(),
        results: results,
      );

      final promptMaterialItems = await _buildPromptMaterialItems(
        normalizedPrompt.trim(),
        startSortOrder: merged.items.length,
      );

      final finalResult = _appendPromptMaterialItems(
        merged,
        promptMaterialItems,
      );

      setState(() {
        _result = finalResult;
      });

      if (failedJobs.isNotEmpty) {
        _showSnack(
          'Some jobs were not priced: ${failedJobs.take(2).join(', ')}',
        );
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('Failed to generate multi quick quote: $e');
      _showSnack('Failed to generate quick quote');
    } finally {
      if (!mounted) return;

      setState(() {
        _isGenerating = false;
      });
    }
  }

  void _clearQuote() {
    setState(() {
      _promptController.clear();
      _result = null;
      _forcedServiceType = null;
      _matchedServiceLabel = null;
      _selectedPriceRule = null;
    });
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      if (_selectedPhotos.length >= _maxPhotos) {
        _showSnack('Maximum $_maxPhotos photos allowed');
        return;
      }

      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 82,
        maxWidth: 1600,
      );

      if (picked == null) return;

      setState(() {
        _selectedPhotos.add(picked);
        _result = null;
        _forcedServiceType = null;
        _matchedServiceLabel = null;
        _selectedPriceRule = null;
      });
    } catch (_) {
      _showSnack('Failed to pick photo');
    }
  }

  void _clearPhoto() {
    setState(() {
      _selectedPhotos.clear();
      _result = null;
      _forcedServiceType = null;
      _matchedServiceLabel = null;
      _selectedPriceRule = null;
    });
  }

  void _removePhotoAt(int index) {
    if (index < 0 || index >= _selectedPhotos.length) return;

    setState(() {
      _selectedPhotos.removeAt(index);
      _result = null;
      _forcedServiceType = null;
      _matchedServiceLabel = null;
      _selectedPriceRule = null;
    });
  }

  Future<void> _analyzePhotoQuote() async {
    if (_selectedPhotos.isEmpty) {
      _showSnack('Choose at least one photo first');
      return;
    }

    setState(() {
      _isAnalyzingPhoto = true;
      _photoDetectedIssue = null;
      _photoWarning = null;
      _photoMatchedService = null;
      _photoConfidence = null;
      _result = null;
    });

    try {
      final images = <Map<String, dynamic>>[];

      for (final photo in _selectedPhotos) {
        final bytes = await photo.readAsBytes();

        images.add({
          'imageBase64': base64Encode(bytes),
          'mimeType': photo.mimeType ?? 'image/jpeg',
        });
      }

      final rules = await EstimatePriceRulesService.getRules();

      final activeRules = rules
          .where((rule) => rule.isActive == true)
          .map((rule) {
        return {
          'rule_id': rule.id,
          'service_type': rule.serviceType,
          'display_name': rule.displayName,
          'category': rule.category,
          'unit': rule.unit,
          'aliases': rule.aliases,
          'ai_keywords': rule.aiKeywords,
          'negative_keywords': rule.negativeKeywords,
        };
      }).toList();

      final response = await Supabase.instance.client.functions.invoke(
        'analyze-quick-quote-photo',
        body: {
          'images': images,
          'priceRules': activeRules,
        },
      );

      final data = Map<String, dynamic>.from(response.data as Map);

      final matched = data['matched'] == true;
      final confidence = (data['confidence'] is num)
          ? (data['confidence'] as num).toDouble()
          : 0.0;

      if (!mounted) return;

      if (!matched) {
        setState(() {
          _photoConfidence = confidence;
          _photoDetectedIssue = (data['detected_issue'] ?? '').toString();
          _photoWarning =
              (data['warning'] ?? 'No matching Price Rule found.').toString();
        });

        _showSnack('No matching Price Rule found');
        return;
      }

      final suggestedPrompt = (data['suggested_prompt'] ?? '').toString().trim();
      final ruleId = (data['rule_id'] ?? '').toString().trim();
      final serviceType = (data['service_type'] ?? '').toString().trim();
      final serviceLabel = (data['service_label'] ?? '').toString().trim();

      EstimatePriceRuleModel? matchedRule;

      if (ruleId.isNotEmpty) {
        matchedRule = await EstimatePriceRulesService.getRuleById(ruleId);
      }

      matchedRule ??= rules.where((rule) {
        return rule.serviceType.trim().toLowerCase() ==
            serviceType.trim().toLowerCase();
      }).cast<EstimatePriceRuleModel?>().firstWhere(
            (rule) => rule != null,
        orElse: () => null,
      );

      if (matchedRule == null) {
        if (!mounted) return;

        setState(() {
          _photoConfidence = confidence;
          _photoDetectedIssue = (data['detected_issue'] ?? '').toString();
          _photoWarning = 'Matched service was not found in Price Rules.';
        });

        _showSnack('Matched Price Rule not found');
        return;
      }

      final resolvedRule = matchedRule;
      final resolvedServiceLabel = serviceLabel.isEmpty
          ? ((resolvedRule.displayName ?? '').trim().isNotEmpty
          ? resolvedRule.displayName!.trim()
          : resolvedRule.serviceType.trim())
          : serviceLabel;

      setState(() {
        _photoMode = false;

        // Admin sees clean text only.
        _promptController.text = suggestedPrompt;

        // System keeps matched Price Rule internally.
        _selectedPriceRule = resolvedRule;
        _forcedServiceType = resolvedRule.serviceType;
        _matchedServiceLabel = resolvedServiceLabel;

        _photoConfidence = confidence;
        _photoDetectedIssue = (data['detected_issue'] ?? '').toString();
        _photoMatchedService = resolvedServiceLabel;
        _photoWarning = (data['warning'] ?? '').toString();
      });

      _showSnack('Photos analyzed. Review the suggested prompt.');
    } catch (_) {
      if (!mounted) return;
      _showSnack('Failed to analyze photos');
    } finally {
      if (!mounted) return;

      setState(() {
        _isAnalyzingPhoto = false;
      });
    }
  }

  Future<void> _loadPropertiesForClient(ClientModel client) async {
    try {
      final properties = await PropertyService.getPropertiesByClient(client.id);

      if (!mounted) return;

      setState(() {
        _properties = properties;
      });
    } catch (_) {
      if (!mounted) return;
      _showSnack('Failed to load client properties');
    }
  }

  Future<ClientModel?> _createClientFromQuickQuote() async {
    final created = await showAddClientDialog(context);

    if (created == null) return null;

    final clients = await ClientService.getClients();

    if (!mounted) return created;

    setState(() {
      _clients = clients;
      _selectedClient = created;
      _selectedProperty = null;
      _properties = [];
    });

    _showSnack('Client created');

    return created;
  }

  Future<PropertyModel?> _createPropertyFromQuickQuote(ClientModel client) async {
    final created = await showAddPropertyDialog(
      context,
      clientId: client.id,
    );

    if (created == null) return null;

    await _loadPropertiesForClient(client);

    if (!mounted) return created;

    setState(() {
      _selectedClient = client;
      _selectedProperty = created;
    });

    _showSnack('Property created');

    return created;
  }

  Future<ClientModel?> _pickClient() async {
    final clients = _clients;

    final selected = await showModalBottomSheet<ClientModel>(
      context: context,
      backgroundColor: const Color(0xFF15161C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) {
        return _SelectionSheet<ClientModel>(
          title: 'Choose Client',
          items: clients,
          itemLabel: (client) {
            final company = (client.companyName ?? '').trim();
            if (company.isNotEmpty) {
              return '${client.fullName} • $company';
            }
            return client.fullName;
          },
          actionLabel: '+ Add New Client',
          onActionTap: () async {
            Navigator.pop(context);
            final created = await _createClientFromQuickQuote();
            if (!mounted || created == null) return;

            // reopen flow by returning selected client through state
            setState(() {
              _selectedClient = created;
            });
          },
        );
      },
    );

    if (selected != null) return selected;

    if (_selectedClient != null) {
      return _selectedClient;
    }

    return null;
  }

  Future<PropertyModel?> _pickProperty(ClientModel client) async {
    await _loadPropertiesForClient(client);

    if (!mounted) return null;

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
          emptyText: 'No properties yet. Add one to continue.',
          actionLabel: '+ Add New Property',
          onActionTap: () async {
            Navigator.pop(context);
            final created = await _createPropertyFromQuickQuote(client);
            if (!mounted || created == null) return;

            setState(() {
              _selectedProperty = created;
            });
          },
        );
      },
    );

    if (selected != null) return selected;

    if (_selectedProperty != null && _selectedProperty!.clientId == client.id) {
      return _selectedProperty;
    }

    return null;
  }

  Future<void> _openEstimateDetails(String estimateId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EstimateDetailsScreen(estimateId: estimateId),
      ),
    );
  }

  Future<void> _convertToEstimate() async {
    final result = _result;

    if (result == null || result.items.isEmpty) {
      _showSnack('Generate a quick quote first');
      return;
    }

    final client = await _pickClient();
    if (client == null) return;

    final property = await _pickProperty(client);
    if (property == null) return;

    setState(() {
      _isConverting = true;
      _selectedClient = client;
      _selectedProperty = property;
    });

    try {
      final title = (result.title ?? '').trim().isEmpty
          ? 'Quick Quote Estimate'
          : result.title!.trim();

      final estimate = EstimateModel(
        id: '',
        adminAuthId: '',
        clientId: client.id,
        propertyId: property.id,
        estimateNumber: '',
        title: title,
        status: 'draft',
        scopeText: (result.scope ?? '').trim(),
        notes: (result.notes ?? '').trim(),
        subtotal: 0,
        tax: 0,
        discount: 0,
        total: 0,
        validUntil: DateTime.now().add(const Duration(days: 14)),
        createdAt: null,
        updatedAt: null,
      );

      final created = await EstimateService.createEstimateWithItems(
        estimate: estimate,
        items: result.items,
        taxRate: _taxRate,
        discountValue: 0,
        discountIsPercentage: false,
      );

      if (!mounted) return;

      _showSnack('Estimate ${created.estimateNumber} created');

      await _openEstimateDetails(created.id);
    } catch (_) {
      if (!mounted) return;
      _showSnack('Failed to convert quote to estimate');
    } finally {
      if (!mounted) return;

      setState(() {
        _isConverting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF0B0B0F);
    final result = _result;
    final totals = _totals;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 20,
        title: const Text(
          'Quick Quote',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
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
        _SectionCard(
        title: _photoMode ? 'Photo Quick Quote' : 'Text Quick Quote',
          subtitle: _photoMode
              ? 'Upload a job photo and let Workio prepare a rough quote'
              : 'Fast rough pricing using Price Rules',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ModeSwitch(
                photoMode: _photoMode,
                onChanged: (value) {
                  setState(() {
                    _photoMode = value;
                    _result = null;
                  });
                },
              ),
              const SizedBox(height: 16),

              if (!_photoMode) ...[
                const Text(
                  'Workio says: describe the job, quantity, materials, and urgency.',
                  style: TextStyle(
                    color: Color(0xFF8E93A6),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                _PremiumTextField(
                  controller: _promptController,
                  label: 'Prompt',
                  hintText: 'Replace 2 outlets, materials included, urgent',
                  maxLines: 6,
                ),
                const SizedBox(height: 10),

                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _isListening
                            ? (_voiceAppendMode
                            ? 'Workio says: listening... I’ll append your words.'
                            : 'Workio says: listening... I’ll replace the prompt.')
                            : 'Workio says: tap the mic to dictate your prompt.',
                        style: const TextStyle(
                          color: Color(0xFF8E93A6),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      color: _isListening
                          ? const Color(0xFF7A1F1F)
                          : const Color(0xFF101117),
                      borderRadius: BorderRadius.circular(16),
                      onPressed: !_speechReady
                          ? null
                          : (_isListening ? _stopVoiceInput : _openVoicePromptSheet),
                      child: Icon(
                        _isListening
                            ? CupertinoIcons.stop_fill
                            : CupertinoIcons.mic_fill,
                        color: _isListening
                            ? Colors.white
                            : const Color(0xFFB6BCD0),
                        size: 20,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: CupertinoButton(
                        color: const Color(0xFF5B8CFF),
                        borderRadius: BorderRadius.circular(16),
                        onPressed: _isGenerating ? null : _generateQuote,
                        child: _isGenerating
                            ? const CupertinoActivityIndicator(color: Colors.white)
                            : const Text(
                          'Generate Quote',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      color: const Color(0xFF101117),
                      borderRadius: BorderRadius.circular(16),
                      onPressed: _isGenerating ? null : _clearQuote,
                      child: const Icon(
                        CupertinoIcons.clear,
                        color: Color(0xFFB6BCD0),
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const _PhotoAiWarningBlock(),
                const SizedBox(height: 12),

                _PhotoPickerBlock(
                  photos: _selectedPhotos,
                  maxPhotos: _maxPhotos,
                  onCamera: () => _pickPhoto(ImageSource.camera),
                  onGallery: () => _pickPhoto(ImageSource.gallery),
                  onClearAll: _clearPhoto,
                  onRemoveAt: _removePhotoAt,
                ),

                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: CupertinoButton(
                    color: const Color(0xFF5B8CFF),
                    borderRadius: BorderRadius.circular(16),
                    onPressed: _selectedPhotos.isEmpty || _isAnalyzingPhoto
                        ? null
                        : _analyzePhotoQuote,
                    child: _isAnalyzingPhoto
                        ? const CupertinoActivityIndicator(color: Colors.white)
                        : const Text(
                      'Analyze Photos',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
            const SizedBox(height: 14),
            if (result == null)
              const _EmptyQuoteState()
            else ...[
              _QuickQuoteHero(
                total: EstimateFormatters.formatCurrency(totals.total),
                subtotal: EstimateFormatters.formatCurrency(totals.subtotal),
                taxLabel: _taxLabel,
                tax: EstimateFormatters.formatCurrency(totals.tax),
                currencyCode: _currencyCode,
                confidence: '${(result.confidence * 100).round()}%',
              ),
              const SizedBox(height: 14),

              _SectionCard(
                title: 'Price Breakdown',
                subtitle: 'Calculated from Price Rules',
                child: result.items.isEmpty
                    ? const _InlineEmptyState(
                  text: 'No quote items generated.',
                )
                    : Column(
                  children: List.generate(result.items.length, (index) {
                    final item = result.items[index];

                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: index == result.items.length - 1 ? 0 : 10,
                      ),
                      child: _QuickQuoteItemTile(item: item),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 14),

              _SectionCard(
                title: 'Totals',
                subtitle: 'Quick quote summary',
                child: Column(
                  children: [
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
                      label: 'Estimated Total',
                      value: EstimateFormatters.formatCurrency(totals.total),
                      isEmphasized: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              _SectionCard(
                title: 'Next Step',
                subtitle: 'Create a full estimate only if the client agrees',
                child: SizedBox(
                  width: double.infinity,
                  child: CupertinoButton(
                    color: const Color(0xFF5B8CFF),
                    borderRadius: BorderRadius.circular(16),
                    onPressed: result.items.isEmpty || _isConverting
                        ? null
                        : _convertToEstimate,
                    child: _isConverting
                        ? const CupertinoActivityIndicator(color: Colors.white)
                        : const Text(
                      'Convert to Estimate',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _SectionCard({
    required this.title,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
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
          const SizedBox(height: 16),
          child,
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

  const _PremiumTextField({
    required this.controller,
    required this.label,
    required this.hintText,
    this.maxLines = 1,
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

class _BigTotalBlock extends StatelessWidget {
  final String total;
  final String currencyCode;

  const _BigTotalBlock({
    required this.total,
    required this.currencyCode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF23252E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Estimated Total',
            style: TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            total,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            currencyCode,
            style: const TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickQuoteHero extends StatelessWidget {
  final String total;
  final String subtotal;
  final String taxLabel;
  final String tax;
  final String currencyCode;
  final String confidence;

  const _QuickQuoteHero({
    required this.total,
    required this.subtotal,
    required this.taxLabel,
    required this.tax,
    required this.currencyCode,
    required this.confidence,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1E2A4A),
            Color(0xFF15161C),
            Color(0xFF101117),
          ],
        ),
        border: Border.all(color: Color(0xFF2E5BFF)),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF5B8CFF).withOpacity(0.18),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quick Quote Total',
            style: TextStyle(
              color: Color(0xFFB6BCD0),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            total,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 38,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$currencyCode • rough price including tax',
            style: const TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _HeroMiniStat(
                  label: 'Subtotal',
                  value: subtotal,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeroMiniStat(
                  label: taxLabel,
                  value: tax,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeroMiniStat(
                  label: 'Confidence',
                  value: confidence,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroMiniStat extends StatelessWidget {
  final String label;
  final String value;

  const _HeroMiniStat({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewInfoBlock extends StatelessWidget {
  final String label;
  final String value;
  final bool multiline;

  const _PreviewInfoBlock({
    required this.label,
    required this.value,
    this.multiline = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(16),
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
          Text(
            value,
            maxLines: multiline ? null : 2,
            overflow: multiline ? TextOverflow.visible : TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickQuoteItemTile extends StatelessWidget {
  final EstimateItemModel item;

  const _QuickQuoteItemTile({
    required this.item,
  });

  bool get _isMaterial {
    final title = item.title.toLowerCase();
    final description = (item.description ?? '').toLowerCase();

    if (title.contains('labor') || title.contains('diagnostic')) {
      return false;
    }

    return title.contains('material') ||
        title.contains('parts') ||
        title.contains('consumables') ||
        description.contains('parsed from prompt');
  }

  bool get _isRush {
    final text = item.title.toLowerCase();
    return text.contains('rush') ||
        text.contains('expedited') ||
        text.contains('priority');
  }

  IconData get _icon {
    if (_isRush) return CupertinoIcons.bolt_fill;
    if (_isMaterial) return CupertinoIcons.cube_box_fill;
    return CupertinoIcons.hammer_fill;
  }

  String get _tag {
    if (_isRush) return 'Rush';
    if (_isMaterial) return 'Materials';
    return 'Labor';
  }

  @override
  Widget build(BuildContext context) {
    final lineTotal = item.lineTotal > 0
        ? item.lineTotal
        : EstimateCalculator.calculateLineTotal(
      quantity: item.quantity,
      unitPrice: item.unitPrice,
    );

    final qty = EstimateFormatters.formatQuantity(item.quantity);
    final unit = EstimateFormatters.formatUnit(item.unit);
    final unitPrice = EstimateFormatters.formatCurrency(item.unitPrice);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF23252E)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF5B8CFF).withOpacity(0.14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFF5B8CFF).withOpacity(0.22),
              ),
            ),
            child: Icon(
              _icon,
              color: const Color(0xFF8FB0FF),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '$_tag • $qty $unit × $unitPrice',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF8E93A6),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            EstimateFormatters.formatCurrency(lineTotal),
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

class _EstimateItemTile extends StatelessWidget {
  final EstimateItemModel item;

  const _EstimateItemTile({
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    final lineTotal = item.lineTotal > 0
        ? item.lineTotal
        : EstimateCalculator.calculateLineTotal(
      quantity: item.quantity,
      unitPrice: item.unitPrice,
    );

    return Container(
      width: double.infinity,
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
            item.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
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
          const SizedBox(height: 12),
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
            value: EstimateFormatters.formatCurrency(lineTotal),
            emphasized: true,
          ),
        ],
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

class _InlineEmptyState extends StatelessWidget {
  final String text;

  const _InlineEmptyState({
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF23252E)),
      ),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.info,
            color: Color(0xFF8E93A6),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF8E93A6),
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyQuoteState extends StatelessWidget {
  const _EmptyQuoteState();

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Quote Preview',
      subtitle: 'The generated quick quote will appear here',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF101117),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF23252E)),
        ),
        child: const Row(
          children: [
            Icon(
              CupertinoIcons.bolt,
              color: Color(0xFF8E93A6),
              size: 20,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Describe the work and Workio will calculate a fast rough quote.',
                style: TextStyle(
                  color: Color(0xFF8E93A6),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionSheet<T> extends StatelessWidget {
  final String title;
  final List<T> items;
  final String Function(T item) itemLabel;
  final String? emptyText;
  final String? actionLabel;
  final VoidCallback? onActionTap;

  const _SelectionSheet({
    required this.title,
    required this.items,
    required this.itemLabel,
    this.emptyText,
    this.actionLabel,
    this.onActionTap,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            const SizedBox(height: 14),

            if (actionLabel != null && onActionTap != null) ...[
              SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  color: const Color(0xFF5B8CFF),
                  borderRadius: BorderRadius.circular(16),
                  onPressed: onActionTap,
                  child: Text(
                    actionLabel!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            if (items.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF101117),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF23252E)),
                ),
                child: Text(
                  emptyText ?? 'No items found',
                  style: const TextStyle(
                    color: Color(0xFF8E93A6),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = items[index];

                    return GestureDetector(
                      onTap: () => Navigator.pop(context, item),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF101117),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFF23252E)),
                        ),
                        child: Text(
                          itemLabel(item),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
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

class _ModeSwitch extends StatelessWidget {
  final bool photoMode;
  final ValueChanged<bool> onChanged;

  const _ModeSwitch({
    required this.photoMode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF23252E)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeSwitchButton(
              label: 'Text',
              icon: CupertinoIcons.text_alignleft,
              active: !photoMode,
              onTap: () => onChanged(false),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _ModeSwitchButton(
              label: 'Photo',
              icon: CupertinoIcons.camera_fill,
              active: photoMode,
              onTap: () => onChanged(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeSwitchButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _ModeSwitchButton({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(14),
      color: active ? const Color(0xFF5B8CFF) : Colors.transparent,
      onPressed: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 17,
            color: active ? Colors.white : const Color(0xFFB6BCD0),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : const Color(0xFFB6BCD0),
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoPickerBlock extends StatelessWidget {
  final List<XFile> photos;
  final int maxPhotos;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onClearAll;
  final void Function(int index) onRemoveAt;

  const _PhotoPickerBlock({
    required this.photos,
    required this.maxPhotos,
    required this.onCamera,
    required this.onGallery,
    required this.onClearAll,
    required this.onRemoveAt,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhotos = photos.isNotEmpty;
    final canAddMore = photos.length < maxPhotos;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF23252E)),
      ),
      child: Column(
        children: [
          if (!hasPhotos) ...[
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: const Color(0xFF5B8CFF).withOpacity(0.14),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: const Color(0xFF5B8CFF).withOpacity(0.22),
                ),
              ),
              child: const Icon(
                CupertinoIcons.camera_fill,
                color: Color(0xFF8FB0FF),
                size: 26,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Add job photos',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Add 1–$maxPhotos clear photos showing the problem, damaged area, or items to be serviced.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF8E93A6),
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${photos.length}/$maxPhotos photos ready',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  color: const Color(0xFF1C1D24),
                  borderRadius: BorderRadius.circular(12),
                  onPressed: onClearAll,
                  child: const Icon(
                    CupertinoIcons.trash,
                    color: Color(0xFFFF6B6B),
                    size: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (photos.length == 1)
              SizedBox(
                width: double.infinity,
                height: 260,
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(
                        File(photos.first.path),
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      right: 8,
                      top: 8,
                      child: CupertinoButton(
                        padding: EdgeInsets.zero,
                        minSize: 34,
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(999),
                        onPressed: () => onRemoveAt(0),
                        child: const Icon(
                          CupertinoIcons.xmark,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: photos.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.2,
                ),
                itemBuilder: (context, index) {
                  final photo = photos[index];

                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.file(
                          File(photo.path),
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        right: 6,
                        top: 6,
                        child: CupertinoButton(
                          padding: EdgeInsets.zero,
                          minSize: 30,
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(999),
                          onPressed: () => onRemoveAt(index),
                          child: const Icon(
                            CupertinoIcons.xmark,
                            color: Colors.white,
                            size: 15,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
          ],

          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: CupertinoButton(
                  color: const Color(0xFF1C1D24),
                  borderRadius: BorderRadius.circular(16),
                  onPressed: canAddMore ? onCamera : null,
                  child: const Text(
                    'Camera',
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
                  color: const Color(0xFF1C1D24),
                  borderRadius: BorderRadius.circular(16),
                  onPressed: canAddMore ? onGallery : null,
                  child: const Text(
                    'Gallery',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PhotoAiWarningBlock extends StatelessWidget {
  const _PhotoAiWarningBlock();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFFFC857).withOpacity(0.24),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFFFC857).withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              CupertinoIcons.exclamationmark_triangle_fill,
              color: Color(0xFFFFC857),
              size: 18,
            ),
          ),
          const SizedBox(width: 11),
          const Expanded(
            child: Text(
              'Photo AI works best for visible problems like damage, leaks, broken items, junk, stains, or burned parts. For new installation, upgrades, moving items, or hidden issues, add a short instruction. Always review the suggested prompt before generating a quote.',
              style: TextStyle(
                color: Color(0xFFB6BCD0),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.38,
              ),
            ),
          ),
        ],
      ),
    );
  }
}