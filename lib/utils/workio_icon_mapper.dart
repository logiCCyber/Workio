import 'package:flutter/material.dart';

class WorkioIconMapper {
  WorkioIconMapper._();

  static final _map = <String, IconData>{
    'electrical_services': Icons.electrical_services,
    'outlet': Icons.outlet,
    'power': Icons.power,
    'lightbulb': Icons.lightbulb_outline,
    'light': Icons.light,
    'light_fixture': Icons.light_outlined,
    'fixture': Icons.light_outlined,
    'chandelier': Icons.light_outlined,
    'lamp': Icons.lightbulb_outline,
    'lighting': Icons.lightbulb_outline,
    'cable': Icons.cable,
    'ev_station': Icons.ev_station,
    'electric_bolt': Icons.electric_bolt,
    'smoke_detector': Icons.warning_amber_rounded,
    'sensor_door': Icons.sensor_door_outlined,
    'plumbing': Icons.plumbing,
    'sink': Icons.plumbing,
    'faucet': Icons.plumbing,
    'drain': Icons.plumbing,
    'water_drop': Icons.water_drop_outlined,
    'bathtub': Icons.bathtub_outlined,
    'shower': Icons.shower_outlined,
    'kitchen': Icons.kitchen,
    'hot_tub': Icons.hot_tub_outlined,
    'local_laundry_service': Icons.local_laundry_service,
    'dry_cleaning': Icons.local_laundry_service,
    'dishwasher': Icons.countertops_outlined,
    'water_heater': Icons.hot_tub,
    'water_damage': Icons.water_damage_outlined,
    'ac_unit': Icons.ac_unit,
    'heat_pump': Icons.heat_pump_outlined,
    'thermostat': Icons.thermostat,
    'air_purifier': Icons.air_outlined,
    'wind_power': Icons.wind_power,
    'kitchen_appliance': Icons.microwave_outlined,
    'microwave': Icons.microwave_outlined,
    'refrigerator': Icons.kitchen,
    'blender': Icons.blender_outlined,
    'construction': Icons.construction,
    'build': Icons.build_outlined,
    'hardware': Icons.hardware_outlined,
    'home_repair_service': Icons.home_repair_service_outlined,
    'handyman': Icons.handyman_outlined,
    'door_front': Icons.door_front_door_outlined,
    'window': Icons.window_outlined,
    'garage': Icons.garage_outlined,
    'fence': Icons.fence_outlined,
    'deck': Icons.deck_outlined,
    'roofing': Icons.roofing,
    'foundation': Icons.foundation,
    'stairs': Icons.stairs,
    'flooring': Icons.square_foot_outlined,
    'paint': Icons.format_paint_outlined,
    'wallpaper': Icons.wallpaper,
    'ceiling': Icons.vertical_align_top,
    'insulation': Icons.layers_outlined,
    'concrete': Icons.view_in_ar_outlined,
    'cleaning_services': Icons.cleaning_services_outlined,
    'vacuum': Icons.cleaning_services,
    'mop': Icons.cleaning_services_sharp,
    'sanitizer': Icons.sanitizer_outlined,
    'yard': Icons.yard_outlined,
    'grass': Icons.grass,
    'tree': Icons.park_outlined,
    'garden': Icons.local_florist_outlined,
    'sprinkler': Icons.water_outlined,
    'outdoor_grill': Icons.outdoor_grill_outlined,
    'pool': Icons.pool,
    'driveway': Icons.local_parking_outlined,
    'sidewalk': Icons.straighten_outlined,
    'local_shipping': Icons.local_shipping_outlined,
    'luggage': Icons.luggage_outlined,
    'delete_sweep': Icons.delete_sweep_outlined,
    'security': Icons.security_outlined,
    'lock': Icons.lock_outlined,
    'camera_indoor': Icons.camera_indoor_outlined,
    'alarm': Icons.alarm_outlined,
    'fire_extinguisher': Icons.fire_extinguisher_outlined,
    'home': Icons.home_outlined,
    'apartment': Icons.apartment_outlined,
    'business': Icons.business_outlined,
    'engineering': Icons.engineering_outlined,
    'settings': Icons.settings_outlined,
    'miscellaneous_services': Icons.miscellaneous_services_outlined,
    'welding': Icons.whatshot_outlined,
    'cutting': Icons.content_cut,
    'metal': Icons.hardware_outlined,
    'tile': Icons.grid_on,
    'ceramic': Icons.grid_on,
    'mosaic': Icons.grid_view_outlined,
    'drywall': Icons.vertical_shades_outlined,
    'plastering': Icons.format_paint,
    'caulking': Icons.edit_outlined,
    'glass': Icons.rectangle_outlined,
    'mirror': Icons.crop_portrait_outlined,
    'asphalt': Icons.add_road,
    'paving': Icons.add_road,
    'road': Icons.add_road,
    'sheet_metal': Icons.hardware,
    'stretch_ceiling': Icons.crop_landscape_outlined,
    'framing': Icons.grid_4x4,
    'rebar': Icons.grid_4x4,
    'excavation': Icons.terrain_outlined,
    'digging': Icons.terrain_outlined,
    'grading': Icons.terrain_outlined,
    'demolition': Icons.delete_forever_outlined,
    'crane': Icons.rv_hookup_outlined,
    'rigging': Icons.rv_hookup_outlined,
    'ventilation': Icons.air,
    'ductwork': Icons.device_hub_outlined,
    'gas': Icons.local_fire_department_outlined,
    'gas_pipe': Icons.local_fire_department_outlined,
    'general_labor': Icons.person_outlined,
    'labor': Icons.person_outlined,
  };

  // Keyword → icon mapping for auto-detection from title
  static final _keywords = <String, IconData>{
    // Electrical
    'outlet': Icons.outlet,
    'socket': Icons.outlet,
    'switch': Icons.electrical_services,
    'breaker': Icons.electrical_services,
    'panel': Icons.electrical_services,
    'wiring': Icons.electrical_services,
    'wire': Icons.cable,
    'electrical': Icons.electrical_services,
    'electric': Icons.electrical_services,
    'circuit': Icons.electrical_services,
    'fuse': Icons.electrical_services,
    'voltage': Icons.electric_bolt,
    'charger': Icons.ev_station,
    'ev': Icons.ev_station,

    // Lighting
    'light': Icons.light_outlined,
    'fixture': Icons.light_outlined,
    'chandelier': Icons.light_outlined,
    'lamp': Icons.lightbulb_outline,
    'bulb': Icons.lightbulb_outline,
    'led': Icons.lightbulb_outline,
    'dimmer': Icons.light_outlined,
    'fan': Icons.air_outlined,

    // Plumbing
    'faucet': Icons.plumbing,
    'tap': Icons.plumbing,
    'sink': Icons.plumbing,
    'drain': Icons.plumbing,
    'pipe': Icons.plumbing,
    'plumb': Icons.plumbing,
    'toilet': Icons.plumbing,
    'shower': Icons.shower_outlined,
    'bathtub': Icons.bathtub_outlined,
    'tub': Icons.bathtub_outlined,
    'valve': Icons.plumbing,
    'leak': Icons.water_damage_outlined,
    'water': Icons.water_drop_outlined,
    'sewer': Icons.plumbing,

    // Appliances
    'fridge': Icons.kitchen,
    'refrigerator': Icons.kitchen,
    'freezer': Icons.kitchen,
    'dishwasher': Icons.countertops_outlined,
    'washer': Icons.local_laundry_service,
    'dryer': Icons.local_laundry_service,
    'laundry': Icons.local_laundry_service,
    'microwave': Icons.microwave_outlined,
    'oven': Icons.microwave_outlined,
    'stove': Icons.microwave_outlined,
    'range': Icons.microwave_outlined,
    'blender': Icons.blender_outlined,
    'appliance': Icons.kitchen,

    // HVAC
    'ac': Icons.ac_unit,
    'air': Icons.ac_unit,
    'hvac': Icons.ac_unit,
    'heat': Icons.heat_pump_outlined,
    'furnace': Icons.heat_pump_outlined,
    'boiler': Icons.heat_pump_outlined,
    'thermostat': Icons.thermostat,
    'duct': Icons.device_hub_outlined,
    'vent': Icons.air,
    'heater': Icons.heat_pump_outlined,

    // Construction / Renovation
    'door': Icons.door_front_door_outlined,
    'window': Icons.window_outlined,
    'floor': Icons.square_foot_outlined,
    'tile': Icons.grid_on,
    'wall': Icons.vertical_shades_outlined,
    'ceiling': Icons.vertical_align_top,
    'paint': Icons.format_paint_outlined,
    'drywall': Icons.vertical_shades_outlined,
    'roof': Icons.roofing,
    'deck': Icons.deck_outlined,
    'fence': Icons.fence_outlined,
    'garage': Icons.garage_outlined,
    'stair': Icons.stairs,
    'cabinet': Icons.countertops_outlined,
    'countertop': Icons.countertops_outlined,
    'insulation': Icons.layers_outlined,
    'concrete': Icons.view_in_ar_outlined,
    'foundation': Icons.foundation,
    'framing': Icons.grid_4x4,
    'demo': Icons.delete_forever_outlined,

    // Exterior / Landscaping
    'yard': Icons.yard_outlined,
    'lawn': Icons.grass,
    'grass': Icons.grass,
    'tree': Icons.park_outlined,
    'garden': Icons.local_florist_outlined,
    'driveway': Icons.local_parking_outlined,
    'paving': Icons.add_road,
    'asphalt': Icons.add_road,
    'pool': Icons.pool,
    'grill': Icons.outdoor_grill_outlined,
    'sprinkler': Icons.water_outlined,

    // Cleaning
    'clean': Icons.cleaning_services_outlined,
    'pressure': Icons.cleaning_services_outlined,
    'mold': Icons.cleaning_services_outlined,

    // Security
    'lock': Icons.lock_outlined,
    'camera': Icons.camera_indoor_outlined,
    'alarm': Icons.alarm_outlined,
    'security': Icons.security_outlined,
    'smoke': Icons.warning_amber_rounded,
    'detector': Icons.warning_amber_rounded,

    // Moving / Junk
    'moving': Icons.local_shipping_outlined,
    'junk': Icons.delete_sweep_outlined,
    'haul': Icons.local_shipping_outlined,
    'removal': Icons.delete_sweep_outlined,
    'debris': Icons.delete_sweep_outlined,

    // Gas
    'gas': Icons.local_fire_department_outlined,
    'fireplace': Icons.local_fire_department_outlined,

    // General
    'inspection': Icons.search,
    'inspect': Icons.search,
    'diagnos': Icons.search,
    'repair': Icons.home_repair_service_outlined,
    'install': Icons.handyman_outlined,
    'replace': Icons.home_repair_service_outlined,
    'service': Icons.home_repair_service_outlined,
    'visit': Icons.electric_bolt,
    'rush': Icons.electric_bolt,
  };

  /// Resolves icon from explicit iconName (from Price Rule).
  static IconData resolve(String? iconName) {
    if (iconName == null || iconName.trim().isEmpty) {
      return Icons.miscellaneous_services_outlined;
    }
    return _map[iconName.trim().toLowerCase()] ??
        Icons.miscellaneous_services_outlined;
  }

  /// Auto-detects icon from item title when no iconName is set.
  /// Falls back to [resolve] if iconName is provided.
  static IconData resolveFromTitle(String title, {String? iconName}) {
    final lower = title.toLowerCase();

    // Rush / Visit fee — always bolt
    if (lower.contains('rush') || lower.contains('visit fee')) {
      return Icons.electric_bolt;
    }

    // Materials — always box
    if (lower.contains('material') || lower.contains('parts')) {
      return Icons.inventory_2_outlined;
    }

    // Title keywords FIRST — more accurate than stored iconName
    for (final entry in _keywords.entries) {
      if (lower.contains(entry.key)) {
        return entry.value;
      }
    }

    // Fallback to stored iconName from Price Rule
    if (iconName != null && iconName.trim().isNotEmpty) {
      final mapped = _map[iconName.trim().toLowerCase()];
      if (mapped != null) return mapped;
    }

    return Icons.home_repair_service_outlined;
  }

  /// Returns the string key to save in DB based on service info.
  static String suggestIconName({
    required String serviceType,
    String? displayName,
    List<String> aliases = const [],
    List<String> aiKeywords = const [],
  }) {
    final candidates = [
      serviceType,
      displayName ?? '',
      ...aliases,
      ...aiKeywords,
    ].join(' ').toLowerCase();

    // Rush
    if (candidates.contains('rush') || candidates.contains('visit fee')) return 'electric_bolt';

    // Scan keywords map — return first matching key
    for (final key in _keywords.keys) {
      if (candidates.contains(key)) {
        // Find the string key in _map that gives same IconData
        final targetIcon = _keywords[key]!;
        final mapKey = _map.entries
            .firstWhere((e) => e.value == targetIcon,
            orElse: () => const MapEntry('home_repair_service', Icons.home_repair_service_outlined))
            .key;
        return mapKey;
      }
    }

    return 'home_repair_service';
  }
}