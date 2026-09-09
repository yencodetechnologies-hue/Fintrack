import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/brand_model_service.dart';
import '../../services/vehicle_service.dart';

// Color palette — matches QFin cream + deep forest green look
const kBackground = Color(0xFFFBF9F1);
const kCard = Colors.white;
const kGreen = Color(0xFF0F261C);
const kMutedText = Color(0xFF6B7280);
const kBodyText = Color(0xFF1E293B);
const kBorder = Color(0xFFE2DDD0);
const kGold = Color(0xFFD4AF37);


enum VehicleType { car, bike }
enum FuelType { petrol, diesel, cng, electric, hybrid }

class FuelOption {
  final FuelType type;
  final String label;
  final IconData icon;
  final String keyString;
  const FuelOption(this.type, this.label, this.icon, this.keyString);
}

const List<FuelOption> kFuelOptions = [
  FuelOption(FuelType.petrol, 'Petrol', Icons.local_gas_station_outlined, 'petrol'),
  FuelOption(FuelType.diesel, 'Diesel', Icons.local_gas_station_rounded, 'diesel'),
  FuelOption(FuelType.cng, 'CNG', Icons.propane_tank_outlined, 'cng'),
  FuelOption(FuelType.electric, 'Electric', Icons.bolt_outlined, 'electric'),
  FuelOption(FuelType.hybrid, 'Hybrid', Icons.eco_outlined, 'hybrid'),
];

class AddVehicleScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const AddVehicleScreen({
    Key? key,
    required this.userId,
    required this.userName,
  }) : super(key: key);

  @override
  State<AddVehicleScreen> createState() => _AddVehicleScreenState();
}

class _AddVehicleScreenState extends State<AddVehicleScreen> {
  final _formKey = GlobalKey<FormState>();

  VehicleType _vehicleType = VehicleType.bike;
  FuelType _fuelType = FuelType.petrol;
  List<String> _allowedFuelTypes = ['petrol', 'cng', 'electric', 'hybrid'];

  bool _addManually = false;
  final _manualBrandController = TextEditingController();
  final _manualModelController = TextEditingController();

  List<String> _brandsList = [];
  List<String> _modelsList = [];

  String? _selectedBrand;
  String? _selectedModel;

  final _nicknameController = TextEditingController();
  final _mileageController = TextEditingController();
  final _capacityController = TextEditingController(text: '10');
  final _currentFuelController = TextEditingController(text: '7.5');
  final _safeAlertController = TextEditingController(text: '25');

  bool _isLoadingBrands = false;
  bool _isLoadingModels = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadBrands();
    _manualModelController.addListener(() {
      if (_addManually && _manualModelController.text.trim().isNotEmpty) {
        _applyModelSpecs(_manualModelController.text);
      }
    });
  }

  @override
  void dispose() {
    _manualBrandController.dispose();
    _manualModelController.dispose();
    _nicknameController.dispose();
    _mileageController.dispose();
    _capacityController.dispose();
    _currentFuelController.dispose();
    _safeAlertController.dispose();
    super.dispose();
  }

  Future<void> _loadBrands() async {
    setState(() {
      _isLoadingBrands = true;
      _selectedBrand = null;
      _selectedModel = null;
      _brandsList = [];
      _modelsList = [];
    });

    final typeStr = _vehicleType == VehicleType.bike ? 'bike' : 'car';
    final brands = await BrandModelService.fetchBrands(typeStr);

    if (mounted) {
      setState(() {
        _brandsList = brands;
        _isLoadingBrands = false;
      });
    }
  }

  Future<void> _loadModels(String brand) async {
    setState(() {
      _isLoadingModels = true;
      _selectedModel = null;
      _modelsList = [];
    });

    final typeStr = _vehicleType == VehicleType.bike ? 'bike' : 'car';
    final models = await BrandModelService.fetchModels(typeStr, brand);

    if (mounted) {
      setState(() {
        _modelsList = models;
        _isLoadingModels = false;
      });
    }
  }

  void _applyModelSpecs(String model) {
    if (model.trim().isEmpty) return;
    final typeStr = _vehicleType == VehicleType.bike ? 'bike' : 'car';
    final brand = _addManually ? _manualBrandController.text.trim() : (_selectedBrand ?? '');
    final spec = BrandModelService.getModelSpec(typeStr, brand, model);

    setState(() {
      _capacityController.text = spec.capacity.toStringAsFixed(spec.capacity.truncateToDouble() == spec.capacity ? 0 : 1);
      _currentFuelController.text = (spec.capacity * 0.75).toStringAsFixed(1);
      _mileageController.text = spec.defaultMileage.toStringAsFixed(1);
      _allowedFuelTypes = spec.availableFuelTypes;

      final currentKey = _fuelTypeKey(_fuelType);
      if (!_allowedFuelTypes.contains(currentKey)) {
        _fuelType = _parseFuelType(_allowedFuelTypes.first);
      }
    });
  }

  String _fuelTypeKey(FuelType type) {
    switch (type) {
      case FuelType.diesel:
        return 'diesel';
      case FuelType.cng:
        return 'cng';
      case FuelType.electric:
        return 'electric';
      case FuelType.hybrid:
        return 'hybrid';
      case FuelType.petrol:
        return 'petrol';
    }
  }


  FuelType _parseFuelType(String key) {
    switch (key) {
      case 'diesel':
        return FuelType.diesel;
      case 'cng':
        return FuelType.cng;
      case 'electric':
        return FuelType.electric;
      case 'hybrid':
        return FuelType.hybrid;
      case 'petrol':
      default:
        return FuelType.petrol;
    }
  }

  void _onVehicleTypeChanged(VehicleType type) {
    if (_vehicleType == type) return;
    setState(() {
      _vehicleType = type;
      _selectedBrand = null;
      _selectedModel = null;
      if (type == VehicleType.bike) {
        _capacityController.text = '10';
        _currentFuelController.text = '7.5';
        _allowedFuelTypes = ['petrol', 'cng', 'electric', 'hybrid'];
      } else {
        _capacityController.text = '45';
        _currentFuelController.text = '33.5';
        _allowedFuelTypes = ['petrol', 'diesel', 'cng', 'electric', 'hybrid'];
      }

      final currentKey = _fuelTypeKey(_fuelType);
      if (!_allowedFuelTypes.contains(currentKey)) {
        _fuelType = _parseFuelType(_allowedFuelTypes.first);
      }
    });
    _loadBrands();
  }

  Future<void> _saveVehicle() async {
    if (!_formKey.currentState!.validate()) return;

    final brandName = _addManually ? _manualBrandController.text.trim() : (_selectedBrand ?? '');
    final modelName = _addManually ? _manualModelController.text.trim() : (_selectedModel ?? '');

    if (brandName.isEmpty || modelName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select or enter Brand and Model')),
      );
      return;
    }

    setState(() => _isSaving = true);

    final name = _nicknameController.text.trim().isEmpty
        ? '$brandName $modelName'
        : _nicknameController.text.trim();

    final typeStr = _vehicleType == VehicleType.bike ? 'bike' : 'car';
    final fuelStr = _fuelTypeKey(_fuelType);

    final mileage = double.tryParse(_mileageController.text.trim()) ?? 15.0;
    final capacity = double.tryParse(_capacityController.text.trim()) ?? 40.0;
    final fuelLevel = double.tryParse(_currentFuelController.text.trim()) ?? (capacity * 0.75);
    final lowThreshold = double.tryParse(_safeAlertController.text.trim()) ?? 25.0;

    final res = await VehicleService.createVehicle(
      userId: widget.userId,
      name: name,
      vehicleType: typeStr,
      fuelType: fuelStr,
      brand: brandName,
      model: modelName,
      isManualModel: _addManually,
      averageMileage: mileage,
      tankCapacity: capacity,
      currentFuelLevel: fuelLevel,
      lowRangeThresholdKm: lowThreshold,
    );

    if (mounted) {
      setState(() => _isSaving = false);

      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vehicle added successfully!'), backgroundColor: kGreen),
        );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['message'] ?? 'Failed to add vehicle')),
        );
      }
    }
  }

  void _openSearchablePicker({
    required String title,
    required List<String> items,
    required String? selectedValue,
    required Function(String) onSelected,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: _SearchablePickerSheet(
            title: title,
            items: items,
            selectedValue: selectedValue,
            onSelected: onSelected,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isElectric = _fuelType == FuelType.electric;
    final capacityUnitLabel = isElectric ? 'Battery capacity (kWh)' : 'Tank capacity (L)';
    final currentFuelUnitLabel = isElectric ? 'Current charge (kWh)' : 'Current fuel (L)';
    final mileageHintLabel = isElectric ? 'km/kWh' : 'km/l';

    return Scaffold(
      backgroundColor: kBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Container(
            decoration: BoxDecoration(
              color: kCard,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: kBorder.withValues(alpha: 0.5)),
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 48),

              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 22),
                    _sectionLabel('Type'),
                    const SizedBox(height: 8),
                    _buildVehicleTypeRow(),
                    const SizedBox(height: 22),
                    _sectionLabel('Fuel or energy source — tap the gauge'),
                    const SizedBox(height: 10),
                    _buildFuelDials(),
                    const SizedBox(height: 14),
                    _buildManualCheckbox(),
                    const SizedBox(height: 22),
                    _sectionLabel('Brand and model'),
                    const SizedBox(height: 10),

                    if (_addManually) ...[
                      _buildTextField(
                        controller: _manualBrandController,
                        hint: 'Brand / manufacturer (e.g. Honda, Hyundai)',
                      ),
                      const SizedBox(height: 10),
                      _buildTextField(
                        controller: _manualModelController,
                        hint: 'Model name (e.g. Creta, Swift, Activa)',
                      ),
                    ] else ...[
                      // Brand Dropdown
                      _isLoadingBrands
                          ? const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(color: kGreen)))
                          : DropdownButtonFormField<String>(
                              value: _brandsList.contains(_selectedBrand) ? _selectedBrand : null,
                              isExpanded: true,
                              dropdownColor: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              elevation: 6,
                              menuMaxHeight: 340,
                              hint: Text(
                                'Select brand / manufacturer',
                                style: TextStyle(color: kBodyText.withValues(alpha: 0.6), fontSize: 13.5, fontWeight: FontWeight.w500),
                              ),
                              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: kGreen, size: 22),
                              decoration: _fieldDecoration('').copyWith(
                                prefixIcon: const Icon(Icons.business_rounded, color: kGreen, size: 20),
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.search_rounded, color: kGreen, size: 20),
                                  tooltip: 'Search Brand',
                                  onPressed: () {
                                    _openSearchablePicker(
                                      title: 'Select Brand / Manufacturer',
                                      items: _brandsList.toSet().toList(),
                                      selectedValue: _selectedBrand,
                                      onSelected: (val) {
                                        setState(() => _selectedBrand = val);
                                        _loadModels(val);
                                      },
                                    );
                                  },
                                ),
                              ),
                              items: _brandsList.toSet().map((brand) {
                                final isSelected = brand == _selectedBrand;
                                return DropdownMenuItem<String>(
                                  value: brand,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        brand,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          color: kBodyText,
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                        ),
                                      ),
                                      if (isSelected) const Icon(Icons.check_circle_rounded, size: 16, color: kGreen),
                                    ],
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _selectedBrand = val);
                                  _loadModels(val);
                                }
                              },
                            ),
                      const SizedBox(height: 10),

                      // Model Dropdown
                      _isLoadingModels
                          ? const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(color: kGreen)))
                          : DropdownButtonFormField<String>(
                              value: _modelsList.contains(_selectedModel) ? _selectedModel : null,
                              isExpanded: true,
                              dropdownColor: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              elevation: 6,
                              menuMaxHeight: 340,
                              hint: Text(
                                _selectedBrand == null ? 'Select brand first' : 'Select model name',
                                style: TextStyle(color: kBodyText.withValues(alpha: 0.6), fontSize: 13.5, fontWeight: FontWeight.w500),
                              ),
                              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: kGreen, size: 22),
                              decoration: _fieldDecoration('').copyWith(
                                prefixIcon: const Icon(Icons.directions_car_rounded, color: kGreen, size: 20),
                                suffixIcon: _modelsList.length > 5
                                    ? IconButton(
                                        icon: const Icon(Icons.search_rounded, color: kGreen, size: 20),
                                        tooltip: 'Search Model',
                                        onPressed: () {
                                          _openSearchablePicker(
                                            title: 'Select Model Name',
                                            items: _modelsList.toSet().toList(),
                                            selectedValue: _selectedModel,
                                            onSelected: (val) {
                                              setState(() => _selectedModel = val);
                                              _applyModelSpecs(val);
                                            },
                                          );
                                        },
                                      )
                                    : null,
                              ),
                              items: _modelsList.toSet().map((model) {
                                final isSelected = model == _selectedModel;
                                return DropdownMenuItem<String>(
                                  value: model,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        model,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          color: kBodyText,
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                        ),
                                      ),
                                      if (isSelected) const Icon(Icons.check_circle_rounded, size: 16, color: kGreen),
                                    ],
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _selectedModel = val);
                                  _applyModelSpecs(val);
                                }
                              },
                            ),
                    ],

                    const SizedBox(height: 22),
                    _sectionLabel('Specs and mileage'),
                    const SizedBox(height: 10),
                    _buildTextField(
                      controller: _nicknameController,
                      hint: 'Nickname (optional)',
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _buildLabeledField(
                            label: 'Avg mileage',
                            controller: _mileageController,
                            hint: mileageHintLabel,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildLabeledField(
                            label: capacityUnitLabel,
                            controller: _capacityController,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _buildLabeledField(
                            label: currentFuelUnitLabel,
                            controller: _currentFuelController,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildLabeledField(
                            label: 'Low fuel alert (km)',
                            controller: _safeAlertController,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    _buildSaveButton(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: kCard,
              shape: BoxShape.circle,
              border: Border.all(color: kGreen, width: 1.5),
            ),
            child: const Icon(Icons.arrow_back, size: 18, color: kGreen),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          'Add a vehicle',
          style: GoogleFonts.fraunces(
            fontStyle: FontStyle.italic,
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: kGreen,
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.bold,
        color: kGreen,
        letterSpacing: 0.2,
      ),
    );
  }


  Widget _buildVehicleTypeRow() {
    return Row(
      children: [
        Expanded(child: _vehicleTypeTile(VehicleType.car, Icons.directions_car_outlined, 'Car')),
        const SizedBox(width: 10),
        Expanded(child: _vehicleTypeTile(VehicleType.bike, Icons.two_wheeler_outlined, 'Bike')),
      ],
    );
  }

  Widget _vehicleTypeTile(VehicleType type, IconData icon, String label) {
    final selected = _vehicleType == type;
    return GestureDetector(
      onTap: () => _onVehicleTypeChanged(type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? kGreen : kCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kGreen, width: 1),
        ),
        child: Column(
          children: [
            Icon(icon, size: 22, color: selected ? kCard : kMutedText),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? kCard : kBodyText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFuelDials() {
    final activeOptions = kFuelOptions.where((opt) => _allowedFuelTypes.contains(opt.keyString)).toList();

    return SizedBox(
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.only(top: 6, right: 6, bottom: 2),
        itemCount: activeOptions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final option = activeOptions[index];
          final selected = _fuelType == option.type;
          return GestureDetector(
            onTap: () => setState(() => _fuelType = option.type),
            child: SizedBox(
              width: 78,
              child: Column(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected ? kGreen : kCard,
                          border: Border.all(
                            color: selected ? kGreen : kBorder,
                            width: 3,
                          ),
                        ),
                        child: Icon(
                          option.icon,
                          size: 24,
                          color: selected ? kCard : kMutedText,
                        ),
                      ),
                      if (selected)
                        Positioned(
                          top: -2,
                          right: -2,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: kGold,
                            ),
                            child: const Icon(Icons.check, size: 13, color: kGreen),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    option.label,
                    style: const TextStyle(fontSize: 12, color: kBodyText, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }


  Widget _buildManualCheckbox() {
    return Row(
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: Checkbox(
            value: _addManually,
            onChanged: (v) => setState(() => _addManually = v ?? false),
            activeColor: kGreen,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          "Can't find your model? Add it manually",
          style: TextStyle(fontSize: 12, color: kBodyText, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: kBodyText.withValues(alpha: 0.55), fontSize: 13.5, fontWeight: FontWeight.w500),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: kGreen.withValues(alpha: 0.3)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: kGreen.withValues(alpha: 0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kGreen, width: 1.8),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: _fieldDecoration(hint),
      style: const TextStyle(fontSize: 14, color: kBodyText, fontWeight: FontWeight.w600),
    );
  }

  Widget _buildLabeledField({
    required String label,
    required TextEditingController controller,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: kGreen, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 5),
        _buildTextField(
          controller: controller,
          hint: hint ?? '',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
      ],
    );
  }


  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isSaving ? null : _saveVehicle,
        icon: _isSaving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: kCard),
              )
            : const Icon(Icons.check, size: 16, color: kCard),
        label: Text(
          _isSaving ? 'Saving...' : 'Save vehicle',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: kCard),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: kGreen,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

class _SearchablePickerSheet extends StatefulWidget {
  final String title;
  final List<String> items;
  final String? selectedValue;
  final Function(String) onSelected;

  const _SearchablePickerSheet({
    Key? key,
    required this.title,
    required this.items,
    required this.selectedValue,
    required this.onSelected,
  }) : super(key: key);

  @override
  State<_SearchablePickerSheet> createState() => _SearchablePickerSheetState();
}

class _SearchablePickerSheetState extends State<_SearchablePickerSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<String> _filteredItems = [];

  @override
  void initState() {
    super.initState();
    _filteredItems = List.from(widget.items);
  }

  void _onSearchChanged(String query) {
    setState(() {
      if (query.trim().isEmpty) {
        _filteredItems = List.from(widget.items);
      } else {
        _filteredItems = widget.items
            .where((item) => item.toLowerCase().contains(query.trim().toLowerCase()))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: kBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),

      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 40,
              height: 4.5,
              decoration: BoxDecoration(
                color: kMutedText.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Title
          Text(
            widget.title,
            style: GoogleFonts.fraunces(
              color: kGreen,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),
          // Search Field
          TextField(
            controller: _searchCtrl,
            onChanged: _onSearchChanged,
            style: const TextStyle(fontSize: 13, color: kBodyText, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: 'Search brand or model...',
              hintStyle: const TextStyle(color: kMutedText, fontSize: 13),
              prefixIcon: const Icon(Icons.search_rounded, color: kGreen, size: 20),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, color: kBodyText, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        _onSearchChanged('');
                      },
                    )
                  : null,
              filled: true,
              fillColor: kBackground,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kBorder)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kBorder)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kGreen, width: 1.5)),
            ),
          ),
          const SizedBox(height: 14),
          // Items List
          Expanded(
            child: _filteredItems.isEmpty
                ? const Center(
                    child: Text(
                      'No matches found',
                      style: TextStyle(color: kMutedText, fontSize: 14),
                    ),
                  )
                : ListView.separated(
                    itemCount: _filteredItems.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: kBorder.withValues(alpha: 0.3)),
                    itemBuilder: (ctx, index) {
                      final item = _filteredItems[index];
                      final isSelected = item == widget.selectedValue;
                      return ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        tileColor: isSelected ? kGreen.withValues(alpha: 0.08) : Colors.transparent,
                        title: Text(
                          item,
                          style: TextStyle(
                            color: kBodyText,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                        trailing: isSelected ? const Icon(Icons.check, color: kGreen, size: 18) : null,
                        onTap: () {
                          widget.onSelected(item);
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
