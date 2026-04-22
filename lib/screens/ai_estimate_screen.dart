import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/client_model.dart';
import '../models/estimate_model.dart';
import '../models/property_model.dart';
import '../models/estimate_item_model.dart';
import '../models/estimate_template_model.dart';
import '../models/company_settings_model.dart';
import '../models/ai_estimate_result_model.dart';
import '../models/ai_missing_field_model.dart';
import '../models/ai_history_suggestion_model.dart';
import '../models/estimate_price_rule_model.dart';

import '../services/client_service.dart';
import '../services/estimate_ai_service.dart';
import '../services/estimate_service.dart';
import '../services/property_service.dart';
import '../services/estimate_template_service.dart';
import '../services/company_settings_service.dart';
import '../services/smart_estimate_service.dart';

import '../utils/estimate_calculator.dart';
import '../utils/estimate_formatters.dart';
import '../services/estimate_price_rules_service.dart';

import 'estimate_details_screen.dart';

import '../dialogs/add_client_dialog.dart';
import '../dialogs/add_property_dialog.dart';

class AiEstimateScreen extends StatefulWidget {
  const AiEstimateScreen({super.key});

  @override
  State<AiEstimateScreen> createState() => _AiEstimateScreenState();
}

class _AiEstimateScreenState extends State<AiEstimateScreen> {
  final TextEditingController _promptController = TextEditingController();

  bool _isLoading = true;
  bool _isGenerating = false;
  bool _isSaving = false;
  bool _isHistoryLoading = false;
  bool _isTemplatesLoading = false;

  List<EstimateModel> _clientHistory = [];
  List<EstimateModel> _propertyHistory = [];

  List<ClientModel> _clients = [];
  List<PropertyModel> _properties = [];
  List<EstimateTemplateModel> _templates = [];

  ClientModel? _selectedClient;
  PropertyModel? _selectedProperty;
  CompanySettingsModel? _companySettings;

  AiEstimateDraft? _draft;
  AiEstimateResultModel? _smartResult;

  double _taxRate = 0.13;
  double _discountValue = 0;
  bool _discountIsPercentage = false;

  final FocusNode _promptFocusNode = FocusNode();

  List<EstimatePriceRuleModel> _rules = [];
  List<_PromptSuggestion> _promptSuggestions = [];
  EstimatePriceRuleModel? _activePromptRule;

  @override
  void initState() {
    super.initState();
    _promptController.addListener(_onPromptChanged);
    _loadClients();
  }

  @override
  void dispose() {
    _promptController.removeListener(_onPromptChanged);
    _promptController.dispose();
    _promptFocusNode.dispose();
    super.dispose();
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

    await _loadHistory();
    _showSnack('Property created');
  }

  String _normalizePromptSearch(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  int _levenshtein(String a, String b) {
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final matrix = List.generate(
      a.length + 1,
          (_) => List<int>.filled(b.length + 1, 0),
    );

    for (int i = 0; i <= a.length; i++) {
      matrix[i][0] = i;
    }

    for (int j = 0; j <= b.length; j++) {
      matrix[0][j] = j;
    }

    for (int i = 1; i <= a.length; i++) {
      for (int j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        matrix[i][j] = [
          matrix[i - 1][j] + 1,
          matrix[i][j - 1] + 1,
          matrix[i - 1][j - 1] + cost,
        ].reduce((a, b) => a < b ? a : b);
      }
    }

    return matrix[a.length][b.length];
  }

  double _scorePromptCandidate(String query, String candidate) {
    final q = _normalizePromptSearch(query);
    final c = _normalizePromptSearch(candidate);

    if (q.isEmpty || c.isEmpty) return 0;

    if (c == q) return 1.0;
    if (c.startsWith(q)) return 0.95;
    if (c.contains(q)) return 0.85;

    final qWords = q.split(' ').where((e) => e.isNotEmpty).toList();
    final cWords = c.split(' ').where((e) => e.isNotEmpty).toList();

    for (final word in cWords) {
      final distance = _levenshtein(q, word);
      if (distance <= 2 && q.length >= 4) {
        return 0.72;
      }
    }

    for (final word in qWords) {
      if (c.contains(word) && word.length >= 4) {
        return 0.68;
      }
    }

    return 0;
  }

  List<_PromptSuggestion> _buildPromptSuggestions(String query) {
    final normalizedQuery = _normalizePromptSearch(query);
    if (normalizedQuery.isEmpty) return const [];

    final suggestions = <_PromptSuggestion>[];

    for (final rule in _rules) {
      final candidates = <String>{
        rule.serviceType.trim(),
        (rule.displayName ?? '').trim(),
        ...rule.aliases.map((e) => e.trim()),
        ...rule.aiKeywords.map((e) => e.trim()),
      }.where((e) => e.isNotEmpty).toList();

      double bestScore = 0;
      String bestMatch = '';

      for (final candidate in candidates) {
        final score = _scorePromptCandidate(normalizedQuery, candidate);
        if (score > bestScore) {
          bestScore = score;
          bestMatch = candidate;
        }
      }

      if (bestScore <= 0) continue;

      final label = (rule.displayName ?? '').trim().isNotEmpty
          ? rule.displayName!.trim()
          : rule.serviceType.trim();

      suggestions.add(
        _PromptSuggestion(
          rule: rule,
          label: label,
          matchText: bestMatch,
          score: bestScore,
        ),
      );
    }

    suggestions.sort((a, b) => b.score.compareTo(a.score));

    final unique = <String, _PromptSuggestion>{};
    for (final item in suggestions) {
      final key = '${item.rule.serviceType}_${item.rule.category}'.toLowerCase();
      unique[key] = item;
    }

    return unique.values.take(6).toList();
  }

  void _onPromptChanged() {
    final text = _promptController.text.trim();

    if (text.isEmpty) {
      if (!mounted) return;
      setState(() {
        _promptSuggestions = [];
        _activePromptRule = null;
      });
      return;
    }

    final suggestions = _buildPromptSuggestions(text);

    if (!mounted) return;
    setState(() {
      _promptSuggestions = suggestions;
      _activePromptRule = suggestions.isNotEmpty ? suggestions.first.rule : null;
    });
  }

  void _applyPromptSuggestion(_PromptSuggestion suggestion) {
    final label = (suggestion.rule.displayName ?? '').trim().isNotEmpty
        ? suggestion.rule.displayName!.trim()
        : suggestion.rule.serviceType.trim();

    _promptController.text = label;
    _promptController.selection = TextSelection.fromPosition(
      TextPosition(offset: _promptController.text.length),
    );

    setState(() {
      _activePromptRule = suggestion.rule;
      _promptSuggestions = [];
    });
  }

  List<String> _buildPromptChips(EstimatePriceRuleModel? rule) {
    if (rule == null) return const [];

    final chips = <String>[];

    final serviceType = rule.serviceType.trim().toLowerCase();
    final unit = rule.unit.trim().toLowerCase();

    if (!serviceType.contains('repair')) {
      chips.add('repair');
    }

    if (!serviceType.contains('installation') && !serviceType.contains('install')) {
      chips.add('installation');
    }

    if (!serviceType.contains('replacement') && !serviceType.contains('replace')) {
      chips.add('replacement');
    }

    chips.add('materials included');
    chips.add('labor only');
    chips.add('rush');
    chips.add('prep');

    if (unit == 'item' || unit == 'fixed') {
      chips.add('1 item');
      chips.add('2 items');
    }

    if (unit == 'room') {
      chips.add('1 room');
      chips.add('2 rooms');
    }

    if (unit == 'sqft') {
      chips.add('200 sqft');
      chips.add('500 sqft');
    }

    return chips.take(8).toList();
  }

  void _appendPromptToken(String token) {
    final current = _promptController.text.trim();
    final next = current.isEmpty ? token : '$current, $token';

    _promptController.text = next;
    _promptController.selection = TextSelection.fromPosition(
      TextPosition(offset: _promptController.text.length),
    );
  }

  Future<void> _addNewClient() async {
    final created = await showAddClientDialog(context);

    if (created == null) return;

    await _loadClients();

    if (!mounted) return;

    setState(() {
      _selectedClient = created;
      _selectedProperty = null;
      _properties = [];
    });

    await _loadPropertiesForClient(created.id);
    await _loadHistory();

    _showSnack('Client created');
  }

  Future<void> _loadClients() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final results = await Future.wait([
        ClientService.getClients(),
        EstimateTemplateService.getTemplates(),
        CompanySettingsService.getSettings(),
        EstimatePriceRulesService.getRules(),
      ]);

      final clients = results[0] as List<ClientModel>;
      final templates = results[1] as List<EstimateTemplateModel>;
      final companySettings = results[2] as CompanySettingsModel?;
      final rules = results[3] as List<EstimatePriceRuleModel>;

      if (!mounted) return;

      setState(() {
        _clients = clients;
        _templates = templates;
        _companySettings = companySettings;
        _taxRate = companySettings?.defaultTaxRate ?? 0.13;
        _isLoading = false;
        _rules = rules;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showSnack('Failed to load data');
    }
  }

  String get _taxLabel {
    final value = _companySettings?.taxLabel.trim() ?? '';
    return value.isEmpty ? 'Tax' : value;
  }

  String get _currencyCode {
    final value = _companySettings?.currencyCode.trim() ?? '';
    return value.isEmpty ? 'CAD' : value.toUpperCase();
  }

  Future<void> _loadPropertiesForClient(String clientId) async {
    setState(() {
      _isLoading = true;
      _properties = [];
      _selectedProperty = null;
    });

    try {
      final properties = await PropertyService.getPropertiesByClient(clientId);

      if (!mounted) return;

      setState(() {
        _properties = properties;
        _isLoading = false;
      });

      if (properties.isNotEmpty) {
        setState(() {
          _selectedProperty = properties.first;
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showSnack('Failed to load client properties');
    }
  }

  Future<void> _loadHistory() async {
    final client = _selectedClient;
    final property = _selectedProperty;

    if (client == null) {
      setState(() {
        _clientHistory = [];
        _propertyHistory = [];
      });
      return;
    }

    setState(() {
      _isHistoryLoading = true;
    });

    try {
      final clientHistory =
      await EstimateService.getPreviousEstimatesByClient(client.id);

      List<EstimateModel> propertyHistory = [];
      if (property != null) {
        propertyHistory =
        await EstimateService.getPreviousEstimatesByProperty(property.id);
      }

      if (!mounted) return;

      setState(() {
        _clientHistory = clientHistory.take(5).toList();
        _propertyHistory = propertyHistory.take(5).toList();
        _isHistoryLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isHistoryLoading = false;
        _clientHistory = [];
        _propertyHistory = [];
      });
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  AiEstimateDraft _mapSmartResultToDraft(AiEstimateResultModel result) {
    return AiEstimateDraft(
      title: (result.title ?? '').trim().isNotEmpty
          ? result.title!.trim()
          : 'General Estimate',
      scope: (result.scope ?? '').trim(),
      notes: (result.notes ?? '').trim(),
      items: result.items,
    );
  }


  void _applySmartResult(AiEstimateResultModel result) {
    setState(() {
      _smartResult = result;
      _draft = result.hasDraftContent ? _mapSmartResultToDraft(result) : null;
    });
  }

  void _showSmartResultMessage(AiEstimateResultModel result) {
    if (!mounted) return;

    if (!result.canAutoGenerate && result.missingFields.isNotEmpty) {
      _showSnack(result.missingFields.first.question);
      return;
    }

    if (result.usedFallback) {
      _showSnack('Smart AI used a fallback draft');
    }
  }

  Future<void> _answerMissingQuestions() async {
    final result = _smartResult;

    if (result == null || result.missingFields.isEmpty) {
      _showSnack('No questions to answer');
      return;
    }

    final answers = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF15161C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _SmartQuestionsSheet(fields: result.missingFields),
    );

    if (answers == null || answers.isEmpty) return;

    setState(() {
      _isGenerating = true;
    });

    try {
      final updated = await SmartEstimateService.regenerateWithAnswers(
        prompt: _promptController.text.trim(),
        answers: answers,
        propertyCity: _selectedProperty?.city,
        clientId: _selectedClient?.id,
        propertyId: _selectedProperty?.id,
      );

      if (!mounted) return;

      _applySmartResult(updated);
      _showSmartResultMessage(updated);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to update the draft');
    } finally {
      if (!mounted) return;

      setState(() {
        _isGenerating = false;
      });
    }
  }

  EstimateTotals get _totals {
    return EstimateCalculator.calculateTotals(
      items: _draft?.items ?? const [],
      taxRate: _taxRate,
      discountValue: _discountValue,
      discountIsPercentage: _discountIsPercentage,
    );
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
            if (company.isNotEmpty) {
              return '${client.fullName} • $company';
            }
            return client.fullName;
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
    await _loadHistory();
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

    await _loadHistory();
  }

  Future<void> _generateDraft() async {
    if (_selectedClient == null) {
      _showSnack('Select a client first');
      return;
    }

    if (_selectedProperty == null) {
      _showSnack('Select a property first');
      return;
    }

    final prompt = _promptController.text.trim();

    if (prompt.isEmpty) {
      _showSnack('Describe the work in plain language');
      return;
    }

    setState(() {
      _isGenerating = true;
    });

    try {
      final result = await SmartEstimateService.generate(
        prompt: prompt,
        propertyCity: _selectedProperty?.city,
        clientId: _selectedClient?.id,
        propertyId: _selectedProperty?.id,
      );

      if (!mounted) return;

      _applySmartResult(result);
      _showSmartResultMessage(result);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to generate draft');
    } finally {
      if (!mounted) return;

      setState(() {
        _isGenerating = false;
      });
    }
  }

  Future<void> _applyQuickPrompt(String text) async {
    _promptController.text = text;
    await _generateDraft();
  }

  Future<void> _openEstimateDetails(String estimateId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EstimateDetailsScreen(estimateId: estimateId),
      ),
    );

    await _loadHistory();
  }

  Future<void> _usePreviousEstimate(EstimateModel estimate) async {
    try {
      final items = await EstimateService.getEstimateItems(estimate.id);

      if (!mounted) return;

      final normalizedItems = items
          .asMap()
          .entries
          .map(
            (entry) => entry.value.copyWith(
          id: '',
          estimateId: '',
          sortOrder: entry.key,
          createdAt: null,
        ),
      )
          .toList();

      setState(() {
        _smartResult = null;
        _draft = AiEstimateDraft(
          title: estimate.title,
          scope: estimate.scopeText ?? '',
          notes: estimate.notes ?? '',
          items: normalizedItems,
        );
      });

      _showSnack('Previous estimate applied to the draft');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to load the previous estimate');
    }
  }

  Future<void> _applyHistorySuggestion(
      AiHistorySuggestionModel suggestion,
      ) async {
    final allEstimates = <EstimateModel>[
      ..._clientHistory,
      ..._propertyHistory,
    ];

    EstimateModel? matchedEstimate;

    for (final estimate in allEstimates) {
      if (estimate.id == suggestion.estimateId) {
        matchedEstimate = estimate;
        break;
      }
    }

    if (matchedEstimate == null) {
      _showSnack('Could not find the suggested estimate in recent history');
      return;
    }

    await _usePreviousEstimate(matchedEstimate);
  }

  Future<void> _reloadTemplates() async {
    setState(() {
      _isTemplatesLoading = true;
    });

    try {
      final templates = await EstimateTemplateService.getTemplates();

      if (!mounted) return;

      setState(() {
        _templates = templates;
        _isTemplatesLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isTemplatesLoading = false;
      });
    }
  }

  Future<void> _useTemplate(EstimateTemplateModel template) async {
    try {
      final result = await SmartEstimateService.generate(
        prompt: '${template.serviceType ?? template.name} job',
        propertyCity: _selectedProperty?.city,
        clientId: _selectedClient?.id,
        propertyId: _selectedProperty?.id,
      );

      final city = (_selectedProperty?.city ?? '').trim();

      final title = city.isEmpty
          ? template.name
          : '${template.name} • $city';

      final effectiveResult = result.copyWith(
        title: title,
        scope: (template.defaultScopeText ?? '').trim().isNotEmpty
            ? template.defaultScopeText!.trim()
            : result.scope,
        notes: (template.defaultNotes ?? '').trim().isNotEmpty
            ? template.defaultNotes!.trim()
            : result.notes,
      );

      if (!mounted) return;

      _applySmartResult(effectiveResult);
      _showSmartResultMessage(effectiveResult);

      _showSnack('Template applied to the draft');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to apply template');
    }
  }

  Future<void> _selectTemplate() async {
    if (_templates.isEmpty) {
      _showSnack('No templates yet');
      return;
    }

    final selected = await showModalBottomSheet<EstimateTemplateModel>(
      context: context,
      backgroundColor: const Color(0xFF15161C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) {
        return _SelectionSheet<EstimateTemplateModel>(
          title: 'Choose Template',
          items: _templates,
          itemLabel: (template) {
            final serviceType = (template.serviceType ?? '').trim();
            if (serviceType.isNotEmpty) {
              return '${template.name} • $serviceType';
            }
            return template.name;
          },
        );
      },
    );

    if (selected == null) return;

    await _useTemplate(selected);
  }

  void _clearDraft() {
    setState(() {
      _smartResult = null;
      _draft = null;
    });

    _showSnack('Draft cleared');
  }

  Future<void> _saveDraftEstimate() async {
    final draft = _draft;

    if (_selectedClient == null || _selectedProperty == null || draft == null) {
      _showSnack('Generate a draft first');
      return;
    }

    if (draft.items.isEmpty) {
      _showSnack('No items to save');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final estimate = EstimateModel(
        id: '',
        adminAuthId: '',
        clientId: _selectedClient!.id,
        propertyId: _selectedProperty!.id,
        estimateNumber: '',
        title: draft.title,
        status: 'draft',
        scopeText: draft.scope,
        notes: draft.notes,
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
        items: draft.items,
        taxRate: _taxRate,
        discountValue: _discountValue,
        discountIsPercentage: _discountIsPercentage,
      );

      if (!mounted) return;

      _showSnack('Estimate ${created.estimateNumber} saved');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to save estimate');
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

  Widget _buildSmartInsightsCard() {
    final result = _smartResult;

    if (result == null) {
      return const SizedBox.shrink();
    }

    final confidencePercent = (result.confidence * 100).round();
    final bestSuggestion = result.historyContext?.bestSuggestion;

    String confidenceLabel;
    if (result.confidence >= 0.80) {
      confidenceLabel = 'High';
    } else if (result.confidence >= 0.55) {
      confidenceLabel = 'Medium';
    } else {
      confidenceLabel = 'Low';
    }

    return _buildSectionCard(
      title: 'Smart AI Insights',
      subtitle: 'What AI understood and what it still needs',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _PreviewInfoBlock(
                  label: 'Confidence',
                  value: '$confidencePercent% • $confidenceLabel',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PreviewInfoBlock(
                  label: 'Mode',
                  value: result.usedFallback
                      ? 'Legacy fallback used'
                      : 'Smart engine',
                ),
              ),
            ],
          ),
          if (bestSuggestion != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _PreviewInfoBlock(
                    label: 'Best Match',
                    value: '${(bestSuggestion.score * 100).round()}% • ${bestSuggestion.title}',
                    multiline: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PreviewInfoBlock(
                    label: 'Last Similar Price',
                    value: EstimateFormatters.formatCurrency(
                      bestSuggestion.total,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (result.assumptions.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Assumptions',
                style: TextStyle(
                  color: Color(0xFFB6BCD0),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Column(
              children: List.generate(result.assumptions.length, (index) {
                final assumption = result.assumptions[index];

                final reason = (assumption.reason ?? '').trim();
                final value = reason.isEmpty
                    ? assumption.value
                    : '${assumption.value}\n$reason';

                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index == result.assumptions.length - 1 ? 0 : 10,
                  ),
                  child: _PreviewInfoBlock(
                    label: assumption.label,
                    value: value,
                    multiline: true,
                  ),
                );
              }),
            ),
          ],
          if (result.missingFields.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Missing Questions',
                style: TextStyle(
                  color: Color(0xFFB6BCD0),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Column(
              children: List.generate(result.missingFields.length, (index) {
                final field = result.missingFields[index];

                final hint = (field.hint ?? '').trim();
                final value = hint.isEmpty
                    ? field.question
                    : '${field.question}\n$hint';

                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index == result.missingFields.length - 1 ? 0 : 10,
                  ),
                  child: _PreviewInfoBlock(
                    label: field.key,
                    value: value,
                    multiline: true,
                  ),
                );
              }),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: CupertinoButton(
                color: const Color(0xFF5B8CFF),
                borderRadius: BorderRadius.circular(16),
                onPressed: _isGenerating ? null : _answerMissingQuestions,
                child: _isGenerating
                    ? const CupertinoActivityIndicator(color: Colors.white)
                    : const Text(
                  'Answer Questions',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHistorySuggestionsCard() {
    final historyContext = _smartResult?.historyContext;

    if (historyContext == null || !historyContext.hasSuggestions) {
      return const SizedBox.shrink();
    }

    return _buildSectionCard(
      title: 'Similar Estimates',
      subtitle: 'Suggestions based on previous estimates',
      child: Column(
        children: List.generate(historyContext.suggestions.length, (index) {
          final suggestion = historyContext.suggestions[index];

          final createdAt = suggestion.createdAt;
          final dateText = createdAt == null
              ? 'Unknown date'
              : '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')}';

          final scorePercent = (suggestion.score * 100).round();

          return Padding(
            padding: EdgeInsets.only(
              bottom: index == historyContext.suggestions.length - 1 ? 0 : 10,
            ),
            child: Container(
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
                    suggestion.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${suggestion.reason} • $dateText',
                    style: const TextStyle(
                      color: Color(0xFF8E93A6),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _MiniInfo(
                          label: 'Match',
                          value: '$scorePercent%',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _MiniInfo(
                          label: 'Total',
                          value: EstimateFormatters.formatCurrency(
                            suggestion.total,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _HistoryActionButton(
                          icon: CupertinoIcons.arrow_turn_down_right,
                          label: 'Use as Baseline',
                          onTap: () => _applyHistorySuggestion(suggestion),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF0B0B0F);
    final totals = _totals;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 20,
        title: const Text(
          'AI Estimate',
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
              onPressed: _isSaving ? null : _saveDraftEstimate,
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
                  _clientHistory = [];
                  _propertyHistory = [];
                  _smartResult = null;
                  _draft = null;
                  _promptController.clear();
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
                  _propertyHistory = [];
                  _smartResult = null;
                  _draft = null;
                  _promptController.clear();
                });
              },
              emptyIcon: CupertinoIcons.add,
              onEmptyIconTap: _addNewProperty,
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'Recent History',
              subtitle: 'Previous estimates for the client and property',
              child: _isHistoryLoading
                  ? const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: CupertinoActivityIndicator(radius: 14),
                ),
              )
                  : Column(
                children: [
                  _HistorySection(
                    title: 'Same Client',
                    estimates: _clientHistory,
                    onOpen: _openEstimateDetails,
                    onUse: _usePreviousEstimate,
                  ),
                  const SizedBox(height: 14),
                  _HistorySection(
                    title: 'Same Property',
                    estimates: _propertyHistory,
                    onOpen: _openEstimateDetails,
                    onUse: _usePreviousEstimate,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'Quick Start',
              subtitle: 'Start with a ready-made template',
              trailing: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _isTemplatesLoading ? null : _reloadTemplates,
                child: _isTemplatesLoading
                    ? const CupertinoActivityIndicator(
                  color: Color(0xFF5B8CFF),
                )
                    : const Icon(
                  CupertinoIcons.refresh,
                  color: Color(0xFF5B8CFF),
                  size: 22,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _ActionButtonWide(
                          icon: CupertinoIcons.square_stack_3d_up,
                          label: 'Use Template',
                          onTap: _selectTemplate,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ActionButtonWide(
                          icon: CupertinoIcons.clear_circled,
                          label: 'Clear Draft',
                          onTap: _draft == null ? null : _clearDraft,
                        ),
                      ),
                    ],
                  ),
                  if (_templates.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _templates.take(4).map((template) {
                          return _QuickPromptChip(
                            label: template.name,
                            onTap: () => _useTemplate(template),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'Company Defaults',
              subtitle: 'Default tax and currency from company settings',
              child: Column(
                children: [
                  _PreviewInfoBlock(
                    label: 'Defaults',
                    value: '$_taxLabel • ${(_taxRate * 100).toStringAsFixed(2)}% • $_currencyCode',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'Describe the Work',
              subtitle: 'Describe in plain language what needs to be done',
              trailing: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _isGenerating ? null : _generateDraft,
                child: _isGenerating
                    ? const CupertinoActivityIndicator(
                  color: Color(0xFF5B8CFF),
                )
                    : const Icon(
                  CupertinoIcons.sparkles,
                  color: Color(0xFF5B8CFF),
                  size: 24,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Workio says: describe the work, quantity, and materials.',
                      style: TextStyle(
                        color: Color(0xFF8E93A6),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _PremiumTextField(
                    controller: _promptController,
                    focusNode: _promptFocusNode,
                    label: 'Prompt',
                    hintText: 'Electrical repair, 2 outlets, labor only',
                    maxLines: 6,
                  ),
                  if (_promptSuggestions.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Suggestions',
                        style: TextStyle(
                          color: Color(0xFFB6BCD0),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Column(
                      children: _promptSuggestions.map((suggestion) {
                        final subtitle = suggestion.matchText.trim().isEmpty
                            ? suggestion.rule.serviceType
                            : '${suggestion.rule.category} • ${suggestion.matchText}';

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: GestureDetector(
                            onTap: () => _applyPromptSuggestion(suggestion),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF101117),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFF23252E)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    suggestion.label,
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
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  if (_activePromptRule != null) ...[
                    const SizedBox(height: 12),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Quick Add',
                        style: TextStyle(
                          color: Color(0xFFB6BCD0),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _buildPromptChips(_activePromptRule).map((chip) {
                        return _QuickPromptChip(
                          label: chip,
                          onTap: () => _appendPromptToken(chip),
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _QuickPromptChip(
                        label: 'Painting 1200 sqft',
                        onTap: () => _applyQuickPrompt(
                          'Painting basement 1200 sqft, walls and ceiling, 2 coats, materials included',
                        ),
                      ),
                      _QuickPromptChip(
                        label: 'Drywall repair',
                        onTap: () => _applyQuickPrompt(
                          'Drywall repair 600 sqft with prep and materials included',
                        ),
                      ),
                      _QuickPromptChip(
                        label: 'Cleaning job',
                        onTap: () => _applyQuickPrompt(
                          'Cleaning 3 bedroom condo 1100 sqft, materials included',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: CupertinoButton(
                      color: const Color(0xFF5B8CFF),
                      borderRadius: BorderRadius.circular(16),
                      onPressed: _isGenerating ? null : _generateDraft,
                      child: _isGenerating
                          ? const CupertinoActivityIndicator(color: Colors.white)
                          : const Text(
                        'Generate Draft',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (_draft == null) ...[
              if (_smartResult != null) ...[
                _buildSmartInsightsCard(),
                const SizedBox(height: 14),
                _buildHistorySuggestionsCard(),
                const SizedBox(height: 14),
              ],
              _buildSectionCard(
                title: 'AI Draft',
                subtitle: 'The generated result will appear here',
                child: const _AiEmptyState(),
              ),
            ] else ...[
              if (_smartResult != null) ...[
                _buildSmartInsightsCard(),
                const SizedBox(height: 14),
                _buildHistorySuggestionsCard(),
                const SizedBox(height: 14),
              ],
              _buildSectionCard(
                title: 'Generated Header',
                subtitle: 'AI prepared the main part of the estimate',
                child: Column(
                  children: [
                    _PreviewInfoBlock(
                      label: 'Title',
                      value: _draft!.title,
                    ),
                    const SizedBox(height: 12),
                    _PreviewInfoBlock(
                      label: 'Scope',
                      value: _draft!.scope,
                      multiline: true,
                    ),
                    const SizedBox(height: 12),
                    _PreviewInfoBlock(
                      label: 'Notes',
                      value: _draft!.notes,
                      multiline: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _buildSectionCard(
                title: 'Generated Items',
                subtitle: 'AI suggested estimate line items',
                child: Column(
                  children: List.generate(_draft!.items.length, (index) {
                    final item = _draft!.items[index];

                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: index == _draft!.items.length - 1 ? 0 : 10,
                      ),
                      child: _EstimateItemTile(item: item),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 14),
              _buildSectionCard(
                title: 'Totals',
                subtitle: 'Totals for the draft estimate',
                child: Column(
                  children: [
                    _PreviewInfoBlock(
                      label: 'Company Defaults',
                      value: '$_taxLabel • ${(_taxRate * 100).toStringAsFixed(2)}% • $_currencyCode',
                    ),
                    const SizedBox(height: 12),
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
                      label: 'Total',
                      value: EstimateFormatters.formatCurrency(totals.total),
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
                onPressed: _isSaving ? null : _saveDraftEstimate,
                child: _isSaving
                    ? const CupertinoActivityIndicator(color: Colors.white)
                    : const Text(
                  'Save Draft Estimate',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
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

class _SmartQuestionsSheet extends StatefulWidget {
  final List<AiMissingFieldModel> fields;

  const _SmartQuestionsSheet({
    required this.fields,
  });

  @override
  State<_SmartQuestionsSheet> createState() => _SmartQuestionsSheetState();
}

class _SmartQuestionsSheetState extends State<_SmartQuestionsSheet> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String> _selectedValues = {};

  @override
  void initState() {
    super.initState();

    for (final field in widget.fields) {
      if (field.answerType != 'single_select') {
        _controllers[field.key] = TextEditingController();
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickOption(AiMissingFieldModel field) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF15161C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) {
        return _SelectionSheet<String>(
          title: field.question,
          items: field.options,
          itemLabel: (option) => option,
        );
      },
    );

    if (selected == null) return;

    setState(() {
      _selectedValues[field.key] = selected;
    });
  }

  void _submit() {
    final answers = <String, dynamic>{};

    for (final field in widget.fields) {
      if (field.answerType == 'single_select' && field.options.isNotEmpty) {
        final value = (_selectedValues[field.key] ?? '').trim();
        if (value.isNotEmpty) {
          answers[field.key] = value;
        }
      } else {
        final value = (_controllers[field.key]?.text ?? '').trim();
        if (value.isNotEmpty) {
          answers[field.key] = value;
        }
      }
    }

    Navigator.pop(context, answers);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFF3A3D49),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Answer Missing Questions',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Add the missing details for a more accurate draft',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF8E93A6),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 18),
              Column(
                children: List.generate(widget.fields.length, (index) {
                  final field = widget.fields[index];
                  final hasOptions =
                      field.answerType == 'single_select' &&
                          field.options.isNotEmpty;

                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: index == widget.fields.length - 1 ? 0 : 14,
                    ),
                    child: Container(
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
                            field.question,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                            ),
                          ),
                          if ((field.hint ?? '').trim().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              field.hint!,
                              style: const TextStyle(
                                color: Color(0xFF8E93A6),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                height: 1.35,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          if (hasOptions)
                            _PremiumPickerField(
                              label: field.key,
                              value: (_selectedValues[field.key] ?? '').trim().isNotEmpty
                                  ? _selectedValues[field.key]!
                                  : 'Select answer',
                              onTap: () => _pickOption(field),
                            )
                          else
                            _PremiumTextField(
                              controller: _controllers[field.key]!,
                              label: field.key,
                              hintText: field.hint ?? 'Enter answer',
                              maxLines: 2,
                            ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  color: const Color(0xFF5B8CFF),
                  borderRadius: BorderRadius.circular(16),
                  onPressed: _submit,
                  child: const Text(
                    'Apply Answers',
                    style: TextStyle(fontWeight: FontWeight.w700),
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

class _PremiumTextField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String label;
  final String hintText;
  final int maxLines;

  const _PremiumTextField({
    required this.controller,
    this.focusNode,
    required this.label,
    required this.hintText,
    this.maxLines = 1,
  });

  @override
  State<_PremiumTextField> createState() => _PremiumTextFieldState();
}

class _PremiumTextFieldState extends State<_PremiumTextField> {
  late final FocusNode _internalFocusNode;

  FocusNode get _focusNode => widget.focusNode ?? _internalFocusNode;

  bool get _showClearButton =>
      _focusNode.hasFocus && widget.controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _internalFocusNode = FocusNode();
    _focusNode.addListener(_refresh);
    widget.controller.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant _PremiumTextField oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_refresh);
      widget.controller.addListener(_refresh);
    }

    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_refresh);
      widget.focusNode?.addListener(_refresh);
    }
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  void _clearText() {
    widget.controller.clear();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    widget.focusNode?.removeListener(_refresh);
    _internalFocusNode.removeListener(_refresh);
    _internalFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSingleLine = widget.maxLines == 1;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF23252E)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          crossAxisAlignment:
          isSingleLine ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.label,
                    style: const TextStyle(
                      color: Color(0xFF8E93A6),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: widget.controller,
                    focusNode: _focusNode,
                    maxLines: widget.maxLines,
                    minLines: isSingleLine ? 1 : widget.maxLines,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                    cursorColor: const Color(0xFF5B8CFF),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: widget.hintText,
                      hintStyle: const TextStyle(
                        color: Color(0xFF697086),
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_showClearButton) ...[
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _clearText,
                child: const Icon(
                  CupertinoIcons.xmark_circle_fill,
                  color: Color(0xFF8E93A6),
                  size: 18,
                ),
              ),
            ],
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
              child: items.isEmpty
                  ? const Center(
                child: Text(
                  'Empty',
                  style: TextStyle(
                    color: Color(0xFF8E93A6),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              )
                  : ListView.separated(
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

class _QuickPromptChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickPromptChip({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF101117),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF23252E)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFFB6BCD0),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _AiEmptyState extends StatelessWidget {
  const _AiEmptyState();

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
            CupertinoIcons.sparkles,
            color: Color(0xFF8E93A6),
            size: 20,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Describe the work and the system will build a draft estimate.',
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
            overflow: multiline ? null : TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.4,
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
            item.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
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

class _HistorySection extends StatelessWidget {
  final String title;
  final List<EstimateModel> estimates;
  final ValueChanged<String> onOpen;
  final ValueChanged<EstimateModel> onUse;

  const _HistorySection({
    required this.title,
    required this.estimates,
    required this.onOpen,
    required this.onUse,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFFB6BCD0),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        if (estimates.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF101117),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF23252E)),
            ),
            child: const Text(
              'No previous estimates',
              style: TextStyle(
                color: Color(0xFF8E93A6),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          )
        else
          Column(
            children: List.generate(estimates.length, (index) {
              final estimate = estimates[index];

              return Padding(
                padding: EdgeInsets.only(
                  bottom: index == estimates.length - 1 ? 0 : 10,
                ),
                child: _HistoryEstimateTile(
                  estimate: estimate,
                  onTap: () => onOpen(estimate.id),
                  onUse: () => onUse(estimate),
                ),
              );
            }),
          ),
      ],
    );
  }
}

class _HistoryEstimateTile extends StatelessWidget {
  final EstimateModel estimate;
  final VoidCallback onTap;
  final VoidCallback onUse;

  const _HistoryEstimateTile({
    required this.estimate,
    required this.onTap,
    required this.onUse,
  });

  Color _statusColor(String status) {
    switch (status) {
      case 'draft':
        return const Color(0xFF8F96AB);
      case 'sent':
        return const Color(0xFF4A90E2);
      case 'approved':
        return const Color(0xFF33C27F);
      case 'rejected':
        return const Color(0xFFE05A5A);
      case 'archived':
        return const Color(0xFF6C7283);
      default:
        return const Color(0xFF8F96AB);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(estimate.status);

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
                  EstimateFormatters.safeText(
                    estimate.title,
                    fallback: 'Untitled Estimate',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: statusColor.withOpacity(0.35),
                  ),
                ),
                child: Text(
                  EstimateFormatters.formatStatus(estimate.status),
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            EstimateFormatters.estimateSubtitle(
              estimateNumber: estimate.estimateNumber,
              createdAt: estimate.createdAt,
            ),
            style: const TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text(
                'Total',
                style: TextStyle(
                  color: Color(0xFF8E93A6),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                EstimateFormatters.formatCurrency(estimate.total),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _HistoryActionButton(
                  icon: CupertinoIcons.doc_text,
                  label: 'Open',
                  onTap: onTap,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HistoryActionButton(
                  icon: CupertinoIcons.arrow_turn_down_right,
                  label: 'Use',
                  onTap: onUse,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HistoryActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _HistoryActionButton({
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

class _PromptSuggestion {
  final EstimatePriceRuleModel rule;
  final String label;
  final String matchText;
  final double score;

  const _PromptSuggestion({
    required this.rule,
    required this.label,
    required this.matchText,
    required this.score,
  });
}