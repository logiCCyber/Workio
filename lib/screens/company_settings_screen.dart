import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import '../models/company_settings_model.dart';

import '../services/company_settings_service.dart';

import '../utils/estimate_calculator.dart';
import '../utils/company_logo_helper.dart';

const _kCompanyAccent = Color(0xFF38BDF8);
const _kCompanyCard = Color(0xFF1F232C);
const _kCompanyPanel = Color(0xFF202530);
const _kCompanyPanelSoft = Color(0xFF1B2028);
const _kCompanyBorder = Color(0xFF3A4050);
const _kCompanyTextSoft = Color(0xFFA0A7B8);

class CompanySettingsScreen extends StatefulWidget {
  const CompanySettingsScreen({super.key});

  @override
  State<CompanySettingsScreen> createState() => _CompanySettingsScreenState();
}

class _CompanySettingsScreenState extends State<CompanySettingsScreen> {
  final TextEditingController _companyNameController = TextEditingController();
  final TextEditingController _companyEmailController = TextEditingController();
  final TextEditingController _companyPhoneController = TextEditingController();
  final TextEditingController _companyWebsiteController = TextEditingController();
  final TextEditingController _companyAddressController = TextEditingController();
  final TextEditingController _taxLabelController = TextEditingController();
  final TextEditingController _defaultTaxRateController = TextEditingController();
  final TextEditingController _currencyCodeController = TextEditingController();

  String _countryCode = 'CA';
  String _regionCode = 'QC';
  String _timezone = 'America/Toronto';
  bool _enableSystemHolidays = true;
  bool _enableConstructionHoliday = true;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploadingLogo = false;
  Uint8List? _logoPreviewBytes;

  CompanySettingsModel? _settings;
  bool _isPhoneValid = true;
  String? _normalizedPhoneNumber;

  @override
  void initState() {
    super.initState();

    _companyNameController.addListener(_handlePreviewChanged);
    _companyEmailController.addListener(_handlePreviewChanged);
    _companyPhoneController.addListener(_handlePreviewChanged);
    _companyWebsiteController.addListener(_handlePreviewChanged);
    _companyAddressController.addListener(_handlePreviewChanged);
    _taxLabelController.addListener(_handlePreviewChanged);
    _defaultTaxRateController.addListener(_handlePreviewChanged);
    _currencyCodeController.addListener(_handlePreviewChanged);

    _loadSettings();
  }

  @override
  void dispose() {
    _companyNameController.removeListener(_handlePreviewChanged);
    _companyEmailController.removeListener(_handlePreviewChanged);
    _companyPhoneController.removeListener(_handlePreviewChanged);
    _companyWebsiteController.removeListener(_handlePreviewChanged);
    _companyAddressController.removeListener(_handlePreviewChanged);
    _taxLabelController.removeListener(_handlePreviewChanged);
    _defaultTaxRateController.removeListener(_handlePreviewChanged);
    _currencyCodeController.removeListener(_handlePreviewChanged);

    _companyNameController.dispose();
    _companyEmailController.dispose();
    _companyPhoneController.dispose();
    _companyWebsiteController.dispose();
    _companyAddressController.dispose();
    _taxLabelController.dispose();
    _defaultTaxRateController.dispose();
    _currencyCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final settings = await CompanySettingsService.getSettings();

      if (!mounted) return;

      _settings = settings;

      _companyNameController.text = settings?.companyName ?? '';
      _companyEmailController.text = settings?.companyEmail ?? '';
      final savedPhone = settings?.companyPhone?.trim() ?? '';
      _companyPhoneController.text = _formatPhoneDisplay(savedPhone);
      _normalizedPhoneNumber =
      savedPhone.isEmpty ? null : _normalizePhoneForSave(savedPhone);
      _companyWebsiteController.text = settings?.companyWebsite ?? '';
      _companyAddressController.text = settings?.companyAddress ?? '';
      _taxLabelController.text = settings?.taxLabel ?? 'Tax';
      _defaultTaxRateController.text =
          ((settings?.defaultTaxRate ?? 0.13) * 100).toStringAsFixed(2);
      _currencyCodeController.text = settings?.currencyCode ?? 'CAD';
      _countryCode = settings?.countryCode ?? 'CA';
      _regionCode = settings?.regionCode ?? (_countryCode == 'US' ? 'PA' : 'QC');
      _timezone = settings?.timezone ?? (_countryCode == 'US' ? 'America/New_York' : 'America/Toronto');
      _enableSystemHolidays = settings?.enableSystemHolidays ?? true;
      _enableConstructionHoliday = settings?.enableConstructionHoliday ?? true;

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showSnack('Failed to load company settings');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _handlePreviewChanged() {
    if (!mounted) return;
    setState(() {});
  }

  String _normalizePhoneForSave(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.isEmpty) return '';

    if (digits.length == 10) {
      return '+1$digits';
    }

    if (digits.length == 11 && digits.startsWith('1')) {
      return '+$digits';
    }

    if (raw.trim().startsWith('+')) {
      return '+$digits';
    }

    return '+1$digits';
  }

  String _formatPhoneDisplay(String raw) {
    final trimmed = raw.trim();
    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.isEmpty) return '';

    final local = digits.length == 11 && digits.startsWith('1')
        ? digits.substring(1)
        : digits;

    if (local.length <= 3) {
      return '+1 $local';
    }

    if (local.length <= 6) {
      return '+1 ${local.substring(0, 3)}-${local.substring(3)}';
    }

    if (local.length <= 10) {
      return '+1 ${local.substring(0, 3)}-${local.substring(3, 6)}-${local.substring(6)}';
    }

    if (trimmed.startsWith('+')) {
      return '+$digits';
    }

    return '+$digits';
  }

  void _handleCompanyPhoneChanged(String rawValue) {
    final formatted = _formatPhoneDisplay(rawValue);

    if (_companyPhoneController.text != formatted) {
      _companyPhoneController.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }

    final normalized = _normalizePhoneForSave(formatted);
    final digits = normalized.replaceAll(RegExp(r'[^0-9]'), '');

    setState(() {
      _normalizedPhoneNumber = normalized.isEmpty ? null : normalized;
      _isPhoneValid = digits.isEmpty || digits.length >= 10;
    });
  }

  Future<void> _saveSettings() async {
    final companyName = _companyNameController.text.trim();
    final taxLabel = _taxLabelController.text.trim();
    final currencyCode = _currencyCodeController.text.trim().toUpperCase();
    final taxPercent =
    EstimateCalculator.parseNumber(_defaultTaxRateController.text);

    if ((_normalizedPhoneNumber ?? '').trim().isNotEmpty && !_isPhoneValid) {
      _showSnack('Enter valid phone number');
      return;
    }

    if (companyName.isEmpty) {
      _showSnack('Enter Company Name');
      return;
    }

    if (taxLabel.isEmpty) {
      _showSnack('Enter Tax Label');
      return;
    }

    if (currencyCode.isEmpty) {
      _showSnack('Enter Currency Code');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final payload = CompanySettingsModel(
        id: _settings?.id ?? '',
        adminAuthId: _settings?.adminAuthId ?? '',
        companyName: companyName,
        companyEmail: _emptyToNull(_companyEmailController.text),
        companyPhone: _emptyToNull(_normalizedPhoneNumber ?? _companyPhoneController.text),
        companyWebsite: _emptyToNull(_companyWebsiteController.text),
        companyAddress: _emptyToNull(_companyAddressController.text),
        taxLabel: taxLabel,
        defaultTaxRate: taxPercent / 100,
        currencyCode: currencyCode,
        countryCode: _countryCode,
        regionCode: _regionCode,
        timezone: _timezone,
        enableSystemHolidays: _enableSystemHolidays,
        enableConstructionHoliday: _enableConstructionHoliday,
        logoPath: _settings?.logoPath,
        logoUrl: _settings?.logoUrl,
        createdAt: _settings?.createdAt,
        updatedAt: _settings?.updatedAt,
      );

      final saved = await CompanySettingsService.upsertSettings(payload);

      if (!mounted) return;

      setState(() {
        _settings = saved;
      });

      _showSnack('Company settings saved');
    } catch (e) {
      if (!mounted) return;

      _showSnack('Failed to save settings');
    } finally {
      if (!mounted) return;

      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<void> _pickAndUploadLogo() async {
    if (_isUploadingLogo) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final bytes = file.bytes;

      if (bytes == null || bytes.isEmpty) {
        _showSnack('Failed to read PNG');
        return;
      }

      final fileName = file.name.toLowerCase();
      if (!fileName.endsWith('.png')) {
        _showSnack('PNG files only');
        return;
      }

      if (bytes.length > 2 * 1024 * 1024) {
        _showSnack('PNG must be 2 MB or smaller');
        return;
      }

      setState(() {
        _isUploadingLogo = true;
        _logoPreviewBytes = bytes;
      });

      final current = _settings;
      if (current == null) {
        _showSnack('Save company settings first');
        return;
      }

      final uploaded = await CompanySettingsService.uploadLogoPng(
        bytes: bytes,
        fileName: 'logo.png',
      );

      final payload = CompanySettingsModel(
        id: current.id,
        adminAuthId: current.adminAuthId,
        companyName: _companyNameController.text.trim(),
        companyEmail: _emptyToNull(_companyEmailController.text),
        companyPhone: _emptyToNull(_normalizedPhoneNumber ?? _companyPhoneController.text),
        companyWebsite: _emptyToNull(_companyWebsiteController.text),
        companyAddress: _emptyToNull(_companyAddressController.text),
        taxLabel: _taxLabelController.text.trim().isEmpty
            ? 'Tax'
            : _taxLabelController.text.trim(),
        defaultTaxRate:
        EstimateCalculator.parseNumber(_defaultTaxRateController.text) / 100,
        currencyCode: _currencyCodeController.text.trim().isEmpty
            ? 'CAD'
            : _currencyCodeController.text.trim().toUpperCase(),
        countryCode: _countryCode,
        regionCode: _regionCode,
        timezone: _timezone,
        enableSystemHolidays: _enableSystemHolidays,
        enableConstructionHoliday: _enableConstructionHoliday,
        logoPath: uploaded['path']?.toString(),
        logoUrl: uploaded['url']?.toString(),
        createdAt: current.createdAt,
        updatedAt: current.updatedAt,
      );

      final saved = await CompanySettingsService.upsertSettings(payload);

      if (!mounted) return;

      setState(() {
        _settings = saved;
      });

      _showSnack('Logo uploaded');
    } catch (e) {
      debugPrint('PNG upload failed: $e');
      _showSnack('PNG upload failed: $e');
    } finally {
      if (!mounted) return;
      setState(() {
        _isUploadingLogo = false;
      });
    }
  }

  Future<void> _removeLogo() async {
    if (_isUploadingLogo) return;

    final current = _settings;
    if (current == null) return;

    try {
      setState(() {
        _isUploadingLogo = true;
        _logoPreviewBytes = null;
      });

      final existingPath = current.logoPath?.trim() ?? '';
      if (existingPath.isNotEmpty) {
        await CompanySettingsService.deleteLogo(existingPath);
      }

      final payload = CompanySettingsModel(
        id: current.id,
        adminAuthId: current.adminAuthId,
        companyName: _companyNameController.text.trim(),
        companyEmail: _emptyToNull(_companyEmailController.text),
        companyPhone: _emptyToNull(_normalizedPhoneNumber ?? _companyPhoneController.text),
        companyWebsite: _emptyToNull(_companyWebsiteController.text),
        companyAddress: _emptyToNull(_companyAddressController.text),
        taxLabel: _taxLabelController.text.trim().isEmpty
            ? 'Tax'
            : _taxLabelController.text.trim(),
        defaultTaxRate:
        EstimateCalculator.parseNumber(_defaultTaxRateController.text) / 100,
        currencyCode: _currencyCodeController.text.trim().isEmpty
            ? 'CAD'
            : _currencyCodeController.text.trim().toUpperCase(),
        countryCode: _countryCode,
        regionCode: _regionCode,
        timezone: _timezone,
        enableSystemHolidays: _enableSystemHolidays,
        enableConstructionHoliday: _enableConstructionHoliday,
        logoPath: null,
        logoUrl: null,
        createdAt: current.createdAt,
        updatedAt: current.updatedAt,
      );

      final saved = await CompanySettingsService.upsertSettings(payload);

      if (!mounted) return;

      setState(() {
        _settings = saved;
      });

      _showSnack('Logo removed');
    } catch (e) {
      _showSnack('Failed to remove logo');
    } finally {
      if (!mounted) return;
      setState(() {
        _isUploadingLogo = false;
      });
    }
  }

  final Map<String, String> _countryOptions = const {
    'CA': 'Canada',
    'US': 'United States',
  };

  final Map<String, Map<String, String>> _regionOptions = const {
    'CA': {
      'AB': 'Alberta',
      'BC': 'British Columbia',
      'MB': 'Manitoba',
      'NB': 'New Brunswick',
      'NL': 'Newfoundland and Labrador',
      'NS': 'Nova Scotia',
      'NT': 'Northwest Territories',
      'NU': 'Nunavut',
      'ON': 'Ontario',
      'PE': 'Prince Edward Island',
      'QC': 'Quebec',
      'SK': 'Saskatchewan',
      'YT': 'Yukon',
    },
    'US': {
      'AL': 'Alabama',
      'AK': 'Alaska',
      'AZ': 'Arizona',
      'AR': 'Arkansas',
      'CA': 'California',
      'CO': 'Colorado',
      'CT': 'Connecticut',
      'FL': 'Florida',
      'GA': 'Georgia',
      'IL': 'Illinois',
      'MA': 'Massachusetts',
      'MI': 'Michigan',
      'NJ': 'New Jersey',
      'NY': 'New York',
      'OH': 'Ohio',
      'PA': 'Pennsylvania',
      'TX': 'Texas',
      'WA': 'Washington',
    },
  };

  final Map<String, String> _timezoneOptions = const {
    'America/Toronto': 'Eastern Time',
    'America/Montreal': 'Montreal / Quebec',
    'America/New_York': 'New York / Pennsylvania',
    'America/Chicago': 'Central Time',
    'America/Denver': 'Mountain Time',
    'America/Los_Angeles': 'Pacific Time',
    'America/Vancouver': 'Vancouver',
  };

  String _countryText() => _countryOptions[_countryCode] ?? _countryCode;

  String _regionText() {
    final regions = _regionOptions[_countryCode] ?? const <String, String>{};
    return regions[_regionCode] ?? _regionCode;
  }

  String _timezoneText() => _timezoneOptions[_timezone] ?? _timezone;

  String _defaultRegionForCountry(String country) {
    if (country == 'US') return 'PA';
    return 'QC';
  }

  String _defaultTimezoneForCountry(String country) {
    if (country == 'US') return 'America/New_York';
    return 'America/Toronto';
  }

  Future<String?> _pickSimpleOption({
    required String title,
    required Map<String, String> options,
    required String selectedCode,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _kCompanyCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        final entries = options.entries.toList();

        return SafeArea(
          top: false,
          child: FractionallySizedBox(
            heightFactor: 0.62,
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
                        CupertinoIcons.location_solid,
                        color: Color(0xFFB8C1D9),
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
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.separated(
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = entries[index];
                        final selectedNow = item.key == selectedCode;

                        return Material(
                          color: selectedNow
                              ? const Color(0xFF16233F)
                              : const Color(0xFF101117),
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => Navigator.pop(sheetContext, item.key),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: selectedNow
                                      ? const Color(0xFF5B8CFF)
                                      : const Color(0xFF23252E),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    selectedNow
                                        ? CupertinoIcons.checkmark_circle_fill
                                        : CupertinoIcons.circle,
                                    color: selectedNow
                                        ? const Color(0xFF5B8CFF)
                                        : const Color(0xFF8E93A6),
                                    size: 19,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      item.value,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    item.key,
                                    style: const TextStyle(
                                      color: Color(0xFF8E93A6),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
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

  Future<void> _pickCountryCode() async {
    final selected = await _pickSimpleOption(
      title: 'Choose Country',
      options: _countryOptions,
      selectedCode: _countryCode,
    );

    if (selected == null) return;

    setState(() {
      _countryCode = selected;
      _regionCode = _defaultRegionForCountry(selected);
      _timezone = _defaultTimezoneForCountry(selected);

      if (_countryCode != 'CA') {
        _enableConstructionHoliday = false;
      }
    });
  }

  Future<void> _pickRegionCode() async {
    final options = _regionOptions[_countryCode] ?? const <String, String>{};

    final selected = await _pickSimpleOption(
      title: 'Choose Region',
      options: options,
      selectedCode: _regionCode,
    );

    if (selected == null) return;

    setState(() {
      _regionCode = selected;
    });
  }

  Future<void> _pickTimezone() async {
    final selected = await _pickSimpleOption(
      title: 'Choose Timezone',
      options: _timezoneOptions,
      selectedCode: _timezone,
    );

    if (selected == null) return;

    setState(() {
      _timezone = selected;
    });
  }

  final List<String> _currencyOptions = const [
    'CAD',
    'USD',
    'EUR',
    'GBP',
    'AUD',
    'NZD',
    'CHF',
    'JPY',
    'CNY',
    'INR',
    'AED',
    'TRY',
  ];

  Future<void> _pickCurrencyCode() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _kCompanyCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: FractionallySizedBox(
            heightFactor: 0.62,
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
                        CupertinoIcons.money_dollar_circle,
                        color: Color(0xFFB8C1D9),
                        size: 22,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Choose Currency',
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
                      itemCount: _currencyOptions.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final code = _currencyOptions[index];
                        final selectedNow =
                            code == _currencyCodeController.text.trim().toUpperCase();

                        return Material(
                          color: selectedNow
                              ? const Color(0xFF16233F)
                              : const Color(0xFF101117),
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => Navigator.pop(sheetContext, code),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: selectedNow
                                      ? const Color(0xFF5B8CFF)
                                      : const Color(0xFF23252E),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    CupertinoIcons.money_dollar_circle,
                                    color: selectedNow
                                        ? const Color(0xFF8FB0FF)
                                        : const Color(0xFF8E93A6),
                                    size: 19,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      code,
                                      style: const TextStyle(
                                        color: Colors.white,
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
                                        ? const Color(0xFF5B8CFF)
                                        : const Color(0xFF8E93A6),
                                    size: selectedNow ? 20 : 16,
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
      _currencyCodeController.text = selected;
    });
  }

  String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF0B0B0F);

    return Scaffold(
      backgroundColor: background,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(104),
        child: _CompanySettingsTopBar(
          onBack: () => Navigator.of(context).maybePop(),
          onSave: _isSaving ? null : _saveSettings,
          isSaving: _isSaving,
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
            _buildSectionCard(
              title: 'Company Info',
              subtitle: 'Main company information',
              child: _formPanel(
                children: [
                  _PremiumTextField(
                    controller: _companyNameController,
                    label: 'Company Name',
                    hintText: 'Sharof Renovation',
                    leadingIcon: CupertinoIcons.building_2_fill,
                  ),
                  const SizedBox(height: 10),
                  _PremiumTextField(
                    controller: _companyEmailController,
                    label: 'Email',
                    hintText: 'info@company.com',
                    keyboardType: TextInputType.emailAddress,
                    leadingIcon: CupertinoIcons.mail,
                  ),
                  const SizedBox(height: 10),
                  _CompanyPhoneField(
                    controller: _companyPhoneController,
                    isValid: _isPhoneValid,
                    onChanged: _handleCompanyPhoneChanged,
                    onClear: () {
                      setState(() {
                        _companyPhoneController.clear();
                        _normalizedPhoneNumber = null;
                        _isPhoneValid = true;
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  _PremiumTextField(
                    controller: _companyWebsiteController,
                    label: 'Website',
                    hintText: 'www.company.com',
                    keyboardType: TextInputType.url,
                    leadingIcon: CupertinoIcons.globe,
                  ),
                  const SizedBox(height: 10),
                  _PremiumTextField(
                    controller: _companyAddressController,
                    label: 'Address',
                    hintText: 'Montreal, QC, Canada',
                    maxLines: 3,
                    leadingIcon: CupertinoIcons.location,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'Company Logo',
              subtitle: 'PNG only • Preview 100 x 75',
              child: Column(
                children: [
                  Container(
                    width: 100,
                    height: 75,
                    decoration: BoxDecoration(
                      color: _kCompanyPanelSoft,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: _kCompanyBorder),
                    ),
                    alignment: Alignment.center,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _logoPreviewBytes != null
                          ? Image.memory(
                        _logoPreviewBytes!,
                        width: 100,
                        height: 75,
                        fit: BoxFit.contain,
                      )
                          : Image.network(
                        CompanyLogoHelper.resolvedLogoUrl(_settings),
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
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: CupertinoButton(
                          color: const Color(0xFF3B82F6),
                          borderRadius: BorderRadius.circular(16),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          onPressed: _isUploadingLogo ? null : _pickAndUploadLogo,
                          child: _isUploadingLogo
                              ? const CupertinoActivityIndicator(color: Colors.white)
                              : const Text(
                            'Upload PNG',
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
                          color: const Color(0xFF2A2D36),
                          borderRadius: BorderRadius.circular(16),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          onPressed: _isUploadingLogo ? null : _removeLogo,
                          child: const Text(
                            'Remove',
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
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'Estimate Defaults',
              subtitle: 'Default values for estimates and PDFs',
              child: _formPanel(
                children: [
                  _PremiumTextField(
                    controller: _taxLabelController,
                    label: 'Tax Label',
                    hintText: 'Tax',
                    leadingIcon: CupertinoIcons.tag,
                  ),
                  const SizedBox(height: 10),
                  _PremiumTextField(
                    controller: _defaultTaxRateController,
                    label: 'Default Tax Rate %',
                    hintText: '13',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    leadingIcon: CupertinoIcons.percent,
                  ),
                  const SizedBox(height: 10),
                  _CurrencyPickerRow(
                    label: 'Currency Code',
                    value: _currencyCodeController.text.trim().isEmpty
                        ? 'CAD'
                        : _currencyCodeController.text.trim().toUpperCase(),
                    onTap: _pickCurrencyCode,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'Business Calendar',
              subtitle: 'Country, region, holidays and schedule rules',
              child: _formPanel(
                children: [
                  _BusinessPickerRow(
                    icon: CupertinoIcons.globe,
                    label: 'Country',
                    value: _countryText(),
                    code: _countryCode,
                    onTap: _pickCountryCode,
                  ),
                  const SizedBox(height: 10),
                  _BusinessPickerRow(
                    icon: CupertinoIcons.location_solid,
                    label: 'Region',
                    value: _regionText(),
                    code: _regionCode,
                    onTap: _pickRegionCode,
                  ),
                  const SizedBox(height: 10),
                  _BusinessPickerRow(
                    icon: CupertinoIcons.time,
                    label: 'Timezone',
                    value: _timezoneText(),
                    code: _timezone,
                    onTap: _pickTimezone,
                  ),
                  const SizedBox(height: 10),
                  _BusinessSwitchRow(
                    icon: CupertinoIcons.calendar,
                    label: 'System Holidays',
                    subtitle: 'Show official holidays in calendar',
                    value: _enableSystemHolidays,
                    onChanged: (v) {
                      setState(() => _enableSystemHolidays = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  _BusinessSwitchRow(
                    icon: CupertinoIcons.hammer,
                    label: 'Construction Holiday',
                    subtitle: 'Quebec construction vacation logic',
                    value: _enableConstructionHoliday,
                    enabled: _countryCode == 'CA' && _regionCode == 'QC',
                    onChanged: (v) {
                      setState(() => _enableConstructionHoliday = v);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'Preview',
              subtitle: 'How this will appear in the estimate',
              child: _formPanel(
                children: [
                  _PreviewRow(
                    icon: CupertinoIcons.building_2_fill,
                    label: 'Company',
                    value: _companyNameController.text.trim().isEmpty
                        ? '—'
                        : _companyNameController.text.trim(),
                  ),
                  const SizedBox(height: 10),
                  _PreviewRow(
                    icon: CupertinoIcons.mail,
                    label: 'Email',
                    value: _companyEmailController.text.trim().isEmpty
                        ? '—'
                        : _companyEmailController.text.trim(),
                  ),
                  const SizedBox(height: 10),
                  _PreviewRow(
                    icon: CupertinoIcons.phone,
                    label: 'Phone',
                    value: _companyPhoneController.text.trim().isEmpty
                        ? '—'
                        : _companyPhoneController.text.trim(),
                  ),
                  const SizedBox(height: 10),
                  _PreviewRow(
                    icon: CupertinoIcons.tag,
                    label: 'Tax',
                    value: _taxLabelController.text.trim().isEmpty
                        ? 'Tax'
                        : _taxLabelController.text.trim(),
                  ),
                  const SizedBox(height: 10),
                  _PreviewRow(
                    icon: CupertinoIcons.percent,
                    label: 'Default Rate',
                    value:
                    '${EstimateCalculator.parseNumber(_defaultTaxRateController.text).toStringAsFixed(2)}%',
                  ),
                  const SizedBox(height: 10),
                  _PreviewRow(
                    icon: CupertinoIcons.money_dollar_circle,
                    label: 'Currency',
                    value: _currencyCodeController.text.trim().isEmpty
                        ? 'CAD'
                        : _currencyCodeController.text.trim().toUpperCase(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            CupertinoButton(
              color: const Color(0xFF3B82F6),
              borderRadius: BorderRadius.circular(18),
              padding: const EdgeInsets.symmetric(vertical: 16),
              onPressed: _isSaving ? null : _saveSettings,
              child: _isSaving
                  ? const CupertinoActivityIndicator(color: Colors.white)
                  : const Text(
                'Save',
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

  Widget _formPanel({
    required List<Widget> children,
  }) {
    return Column(
      children: children,
    );
  }

  Widget _buildSectionCard({
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    final cleanSubtitle = (subtitle ?? '').trim();

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        color: _kCompanyCard,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: _kCompanyBorder,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.34),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.025),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFF4F6FA),
              fontSize: 21,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.25,
              height: 1.0,
            ),
          ),
          if (cleanSubtitle.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              cleanSubtitle,
              style: const TextStyle(
                color: _kCompanyTextSoft,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
            ),
          ],
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _CompanySettingsTopBar extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback? onSave;
  final bool isSaving;

  const _CompanySettingsTopBar({
    required this.onBack,
    required this.onSave,
    required this.isSaving,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Container(
          height: 82,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            color: _kCompanyCard,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: _kCompanyBorder,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.42),
                blurRadius: 30,
                offset: const Offset(0, 16),
              ),
              BoxShadow(
                color: Colors.white.withOpacity(0.035),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              CupertinoButton(
                padding: EdgeInsets.zero,
                minSize: 0,
                onPressed: onBack,
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: _kCompanyPanel,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _kCompanyBorder),
                  ),
                  child: const Icon(
                    CupertinoIcons.chevron_left,
                    color: Color(0xFFF3F6FC),
                    size: 25,
                  ),
                ),
              ),

              const SizedBox(width: 14),

              const Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Company Settings',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Color(0xFFF4F6FA),
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.25,
                        height: 1.0,
                      ),
                    ),
                    SizedBox(height: 7),
                    Text(
                      'Business profile, logo, tax and defaults',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _kCompanyTextSoft,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              CupertinoButton(
                padding: EdgeInsets.zero,
                minSize: 0,
                onPressed: onSave,
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFF202530),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _kCompanyBorder),
                  ),
                  child: isSaving
                      ? const CupertinoActivityIndicator(
                    color: Color(0xFFF3F6FC),
                  )
                      : const Icon(
                    CupertinoIcons.checkmark,
                    color: _kCompanyAccent,
                    size: 23,
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

class _BusinessPickerRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String code;
  final VoidCallback onTap;

  const _BusinessPickerRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.code,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minSize: 0,
      onPressed: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 70),
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
        decoration: BoxDecoration(
          color: _kCompanyPanelSoft,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _kCompanyBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 12,
              offset: const Offset(0, 7),
            ),
            BoxShadow(
              color: Colors.white.withOpacity(0.02),
              blurRadius: 6,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: const Color(0xFF9AA3B7),
              size: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: _kCompanyTextSoft,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFF3F6FC),
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(
                color: _kCompanyPanel,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _kCompanyBorder),
              ),
              child: Center(
                child: Text(
                  code,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFD6DCE8),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              CupertinoIcons.chevron_down,
              color: Color(0xFF8E93A6),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

class _BusinessSwitchRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _BusinessSwitchRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final opacity = enabled ? 1.0 : 0.42;

    return Opacity(
      opacity: opacity,
      child: Container(
        constraints: const BoxConstraints(minHeight: 74),
        padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
        decoration: BoxDecoration(
          color: _kCompanyPanelSoft,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _kCompanyBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 12,
              offset: const Offset(0, 7),
            ),
            BoxShadow(
              color: Colors.white.withOpacity(0.02),
              blurRadius: 6,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: const Color(0xFF9AA3B7),
              size: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFFF3F6FC),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    enabled ? subtitle : 'Available only for Quebec, Canada',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF8E93A6),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            Transform.scale(
              scale: 0.86,
              child: Switch.adaptive(
                value: enabled && value,
                activeColor: _kCompanyAccent,
                onChanged: enabled ? onChanged : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hintText;
  final int maxLines;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final IconData? leadingIcon;

  const _PremiumTextField({
    required this.controller,
    required this.label,
    required this.hintText,
    this.maxLines = 1,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.leadingIcon,
  });

  @override
  State<_PremiumTextField> createState() => _PremiumTextFieldState();
}

class _PremiumTextFieldState extends State<_PremiumTextField> {
  late final FocusNode _focusNode;

  bool get _showClearButton =>
      widget.maxLines == 1 &&
          _focusNode.hasFocus &&
          widget.controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
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
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _clearText() {
    widget.controller.clear();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    _focusNode.removeListener(_refresh);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSingleLine = widget.maxLines == 1;

    return Container(
      constraints: BoxConstraints(
        minHeight: isSingleLine ? 70 : 112,
      ),
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      decoration: BoxDecoration(
        color: _kCompanyPanelSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _kCompanyBorder,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 12,
            offset: const Offset(0, 7),
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment:
        isSingleLine ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          if (widget.leadingIcon != null) ...[
            Padding(
              padding: EdgeInsets.only(top: isSingleLine ? 0 : 5),
              child: Icon(
                widget.leadingIcon,
                color: const Color(0xFF9AA3B7),
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment:
              isSingleLine ? MainAxisAlignment.center : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.label,
                  style: const TextStyle(
                    color: _kCompanyTextSoft,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 7),
                TextField(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  keyboardType: widget.keyboardType,
                  maxLines: widget.maxLines,
                  minLines: isSingleLine ? 1 : widget.maxLines,
                  textCapitalization: widget.textCapitalization,
                  inputFormatters: widget.inputFormatters,
                  cursorColor: _kCompanyAccent,
                  style: const TextStyle(
                    color: Color(0xFFF3F6FC),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: widget.hintText,
                    hintStyle: const TextStyle(
                      color: Color(0xFF697086),
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
          if (_showClearButton) ...[
            const SizedBox(width: 8),
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
    );
  }
}

class _CompanyPhoneField extends StatelessWidget {
  final TextEditingController controller;
  final bool isValid;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _CompanyPhoneField({
    required this.controller,
    required this.isValid,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 70),
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      decoration: BoxDecoration(
        color: _kCompanyPanelSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isValid ? _kCompanyBorder : const Color(0xFFFF6B6B),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 12,
            offset: const Offset(0, 7),
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.phone,
            color: Color(0xFF9AA3B7),
            size: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Phone',
                  style: TextStyle(
                    color: _kCompanyTextSoft,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 7),
                TextField(
                  controller: controller,
                  onChanged: onChanged,
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                    decimal: false,
                  ),
                  cursorColor: _kCompanyAccent,
                  style: const TextStyle(
                    color: Color(0xFFF3F6FC),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '+1 514-777-2486',
                    hintStyle: const TextStyle(
                      color: Color(0xFF697086),
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    suffixIcon: controller.text.trim().isNotEmpty
                        ? GestureDetector(
                      onTap: onClear,
                      child: const Icon(
                        CupertinoIcons.xmark_circle_fill,
                        color: Color(0xFF8E93A6),
                        size: 18,
                      ),
                    )
                        : null,
                    suffixIconConstraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
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

class _CurrencyPickerRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _CurrencyPickerRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minSize: 0,
      onPressed: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 70),
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
        decoration: BoxDecoration(
          color: _kCompanyPanelSoft,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _kCompanyBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 12,
              offset: const Offset(0, 7),
            ),
            BoxShadow(
              color: Colors.white.withOpacity(0.02),
              blurRadius: 6,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(
              CupertinoIcons.money_dollar_circle,
              color: Color(0xFF9AA3B7),
              size: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: _kCompanyTextSoft,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Color(0xFFF3F6FC),
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
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
    );
  }
}

class _PreviewRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _PreviewRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final isEmpty = value.trim() == '—';

    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: _kCompanyPanelSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kCompanyBorder),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Icon(
              icon,
              color: const Color(0xFF9AA3B7),
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _kCompanyTextSoft,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isEmpty
                        ? const Color(0xFF697086)
                        : const Color(0xFFF3F6FC),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
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
