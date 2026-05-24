import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:intl_phone_number_input/intl_phone_number_input.dart';

import '../models/company_settings_model.dart';

import '../services/company_settings_service.dart';

import '../utils/estimate_calculator.dart';
import '../utils/company_logo_helper.dart';

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
  PhoneNumber _initialPhoneNumber = PhoneNumber(isoCode: 'CA');
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
      _companyPhoneController.text = settings?.companyPhone ?? '';
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

      final savedPhone = settings?.companyPhone?.trim() ?? '';
      _normalizedPhoneNumber = savedPhone.isEmpty ? null : savedPhone;

      if (savedPhone.isNotEmpty) {
        try {
          _initialPhoneNumber =
          await PhoneNumber.getRegionInfoFromPhoneNumber(savedPhone, 'CA');
        } catch (_) {
          _initialPhoneNumber = PhoneNumber(
            phoneNumber: savedPhone,
            isoCode: 'CA',
          );
        }
      } else {
        _initialPhoneNumber = PhoneNumber(isoCode: 'CA');
      }

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
      backgroundColor: const Color(0xFF15161C),
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
      backgroundColor: const Color(0xFF15161C),
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
      appBar: AppBar(
        backgroundColor: background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 20,
        title: const Text(
          'Company Settings',
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
              onPressed: _isSaving ? null : _saveSettings,
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
                  const Divider(color: Color(0xFF23252E), height: 1),
                  _PremiumTextField(
                    controller: _companyEmailController,
                    label: 'Email',
                    hintText: 'info@company.com',
                    keyboardType: TextInputType.emailAddress,
                    leadingIcon: CupertinoIcons.mail,
                  ),
                  const Divider(color: Color(0xFF23252E), height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    CupertinoIcons.phone,
                                    color: Color(0xFF8E93A6),
                                    size: 16,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Phone',
                                    style: TextStyle(
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
                            child: InternationalPhoneNumberInput(
                                initialValue: _initialPhoneNumber,
                                textFieldController: _companyPhoneController,
                              selectorConfig: const SelectorConfig(
                                selectorType: PhoneInputSelectorType.BOTTOM_SHEET,
                                showFlags: false,
                                useEmoji: false,
                                setSelectorButtonAsPrefixIcon: true,
                              ),
                                onInputChanged: (PhoneNumber number) {
                                  if (!mounted) return;
                                  setState(() {
                                    _initialPhoneNumber = number;
                                    _normalizedPhoneNumber = number.phoneNumber;
                                  });
                                },
                                onInputValidated: (bool value) {
                                  if (!mounted) return;
                                  setState(() {
                                    _isPhoneValid = value;
                                  });
                                },
                                ignoreBlank: true,
                                autoValidateMode: AutovalidateMode.disabled,
                                formatInput: true,
                                keyboardType: const TextInputType.numberWithOptions(
                                  signed: true,
                                  decimal: false,
                                ),
                                cursorColor: const Color(0xFF5B8CFF),
                                selectorTextStyle: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                                textStyle: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  height: 1.35,
                                ),
                                inputBorder: InputBorder.none,
                                inputDecoration: InputDecoration(
                                  isDense: true,
                                  hintText: 'Phone number',
                                  hintStyle: const TextStyle(
                                    color: Color(0xFF697086),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w400,
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                  suffixIcon: _companyPhoneController.text.trim().isNotEmpty
                                      ? GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _companyPhoneController.clear();
                                        _normalizedPhoneNumber = null;
                                        _isPhoneValid = true;
                                        _initialPhoneNumber = PhoneNumber(isoCode: 'CA');
                                      });
                                    },
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
                             ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Color(0xFF23252E), height: 1),
                  _PremiumTextField(
                    controller: _companyWebsiteController,
                    label: 'Website',
                    hintText: 'www.company.com',
                    keyboardType: TextInputType.url,
                    leadingIcon: CupertinoIcons.globe,
                  ),
                  const Divider(color: Color(0xFF23252E), height: 1),
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
                      color: const Color(0xFF101117),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF23252E)),
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
                          color: const Color(0xFF5B8CFF),
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
                  const Divider(color: Color(0xFF23252E), height: 1),
                  _PremiumTextField(
                    controller: _defaultTaxRateController,
                    label: 'Default Tax Rate %',
                    hintText: '13',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    leadingIcon: CupertinoIcons.percent,
                  ),
                  const Divider(color: Color(0xFF23252E), height: 1),
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
                  const Divider(color: Color(0xFF23252E), height: 1),
                  _BusinessPickerRow(
                    icon: CupertinoIcons.location_solid,
                    label: 'Region',
                    value: _regionText(),
                    code: _regionCode,
                    onTap: _pickRegionCode,
                  ),
                  const Divider(color: Color(0xFF23252E), height: 1),
                  _BusinessPickerRow(
                    icon: CupertinoIcons.time,
                    label: 'Timezone',
                    value: _timezoneText(),
                    code: _timezone,
                    onTap: _pickTimezone,
                  ),
                  const Divider(color: Color(0xFF23252E), height: 1),
                  _BusinessSwitchRow(
                    icon: CupertinoIcons.calendar,
                    label: 'System Holidays',
                    subtitle: 'Show official holidays in calendar',
                    value: _enableSystemHolidays,
                    onChanged: (v) {
                      setState(() => _enableSystemHolidays = v);
                    },
                  ),
                  const Divider(color: Color(0xFF23252E), height: 1),
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
                  const Divider(color: Color(0xFF23252E), height: 1),
                  _PreviewRow(
                    icon: CupertinoIcons.mail,
                    label: 'Email',
                    value: _companyEmailController.text.trim().isEmpty
                        ? '—'
                        : _companyEmailController.text.trim(),
                  ),
                  const Divider(color: Color(0xFF23252E), height: 1),
                  _PreviewRow(
                    icon: CupertinoIcons.phone,
                    label: 'Phone',
                    value: _companyPhoneController.text.trim().isEmpty
                        ? '—'
                        : _companyPhoneController.text.trim(),
                  ),
                  const Divider(color: Color(0xFF23252E), height: 1),
                  _PreviewRow(
                    icon: CupertinoIcons.tag,
                    label: 'Tax',
                    value: _taxLabelController.text.trim().isEmpty
                        ? 'Tax'
                        : _taxLabelController.text.trim(),
                  ),
                  const Divider(color: Color(0xFF23252E), height: 1),
                  _PreviewRow(
                    icon: CupertinoIcons.percent,
                    label: 'Default Rate',
                    value:
                    '${EstimateCalculator.parseNumber(_defaultTaxRateController.text).toStringAsFixed(2)}%',
                  ),
                  const Divider(color: Color(0xFF23252E), height: 1),
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
              color: const Color(0xFF5B8CFF),
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
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF23252E)),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildSectionCard({
    required String title,
    String? subtitle,
    required Widget child,
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            children: [
              Icon(
                icon,
                color: const Color(0xFF8E93A6),
                size: 17,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF8E93A6),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      code,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF697086),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                CupertinoIcons.chevron_down,
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            Icon(
              icon,
              color: const Color(0xFF8E93A6),
              size: 17,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    enabled ? subtitle : 'Available only for Quebec, Canada',
                    style: const TextStyle(
                      color: Color(0xFF8E93A6),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: enabled && value,
              activeColor: const Color(0xFF5B8CFF),
              onChanged: enabled ? onChanged : null,
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
    _focusNode.removeListener(_refresh);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSingleLine = widget.maxLines == 1;

    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.leadingIcon != null) ...[
                        Icon(
                          widget.leadingIcon,
                          color: const Color(0xFF8E93A6),
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                      ],
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
                    padding: EdgeInsets.only(
                      left: widget.leadingIcon != null ? 24 : 0,
                    ),
                    child: TextField(
                      controller: widget.controller,
                      focusNode: _focusNode,
                      keyboardType: widget.keyboardType,
                      maxLines: widget.maxLines,
                      minLines: isSingleLine ? 1 : widget.maxLines,
                      textCapitalization: widget.textCapitalization,
                      inputFormatters: widget.inputFormatters,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                      ),
                      cursorColor: const Color(0xFF5B8CFF),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: widget.hintText,
                        hintStyle: const TextStyle(
                          color: Color(0xFF697086),
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CupertinoIcons.money_dollar_circle,
                          color: Color(0xFF8E93A6),
                          size: 16,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Currency Code',
                          style: TextStyle(
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Icon(
            icon,
            color: const Color(0xFF8E93A6),
            size: 18,
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
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