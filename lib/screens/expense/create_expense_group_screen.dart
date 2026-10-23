import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/expense_company_service.dart';

class CreateExpenseGroupScreen extends StatefulWidget {
  final String userId;

  const CreateExpenseGroupScreen({
    super.key,
    required this.userId,
  });

  @override
  State<CreateExpenseGroupScreen> createState() => _CreateExpenseGroupScreenState();
}

class _CreateExpenseGroupScreenState extends State<CreateExpenseGroupScreen> {
  // Brand color palette
  static const Color primaryGreen = Color(0xFF195754);
  static const Color darkGreen = Color(0xFF063323);
  static const Color mintAccent = Color(0xFF10B981);
  static const Color mintLight = Color(0xFF34D399);

  final _nameController = TextEditingController();
  final Set<String> _selectedMemberIds = {};
  String? _companyId;
  List<Map<String, dynamic>> _availableCompanies = [];
  bool _loadingCompanies = true;
  String? _companyError;
  List<Map<String, dynamic>> _members = [];
  bool _loadingMembers = false;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAvailableCompanies();
  }

  Future<void> _loadAvailableCompanies() async {
    setState(() {
      _loadingCompanies = true;
      _companyError = null;
    });
    final companies = (await ExpenseCompanyService.getUserCompanies(widget.userId)).where((c) => c["external"] != true).toList();
    if (!mounted) return;
    setState(() {
      _loadingCompanies = false;
      _availableCompanies = companies;
      _companyError = companies.isEmpty ? "Join or create a company first. Tap to retry." : null;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String _id(dynamic value) {
    if (value is Map) return (value["_id"] ?? value["id"] ?? "").toString();
    return value?.toString() ?? "";
  }

  String _initials(dynamic name) {
    if (name == null) return "?";
    final parts = name.toString().trim().split(RegExp(r"\s+"));
    if (parts.isEmpty || parts[0].isEmpty) return "?";
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  Future<void> _selectCompany(String? companyId) async {
    if (companyId == null) return;
    setState(() {
      _companyId = companyId;
      _members = [];
      _selectedMemberIds.clear();
      _loadingMembers = true;
      _error = null;
    });
    final response = await ExpenseCompanyService.getCompanyDetails(companyId, widget.userId);
    if (!mounted) return;
    final rawMembers = response["members"];
    setState(() {
      _loadingMembers = false;
      if (response["success"] == true && rawMembers is List) {
        _members = rawMembers
            .whereType<Map>()
            .map((member) => Map<String, dynamic>.from(member))
            .where((member) => _id(member["userId"]).isNotEmpty)
            .toList();
      } else {
        _error = (response["message"] ?? "Could not load company members").toString();
      }
    });
  }

  void _toggleSelectAll() {
    if (_members.isEmpty) return;
    setState(() {
      if (_selectedMemberIds.length == _members.length) {
        _selectedMemberIds.clear();
      } else {
        _selectedMemberIds.clear();
        for (final m in _members) {
          final id = _id(m["userId"]);
          if (id.isNotEmpty) _selectedMemberIds.add(id);
        }
      }
    });
  }

  void _toggleMember(String memberId) {
    if (_submitting) return;
    setState(() {
      if (_selectedMemberIds.contains(memberId)) {
        _selectedMemberIds.remove(memberId);
      } else {
        _selectedMemberIds.add(memberId);
      }
    });
  }

  Future<void> _createGroup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = "Please enter a group name.");
      return;
    }
    if (_companyId == null) {
      setState(() => _error = "Please choose a company to link with this group.");
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final response = await ExpenseCompanyService.createExpenseGroup(
      companyId: _companyId!,
      userId: widget.userId,
      name: name,
      memberIds: _selectedMemberIds.toList(),
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (response["success"] == true) {
      Navigator.pop(context, response["group"]);
    } else {
      setState(() => _error = (response["message"] ?? "Could not create group").toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [darkGreen, primaryGreen],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  children: [
                    _buildHeroHeader(),
                    const SizedBox(height: 24),
                    _buildSectionLabel("GROUP NAME"),
                    const SizedBox(height: 8),
                    _buildNameField(),
                    const SizedBox(height: 18),
                    _buildSectionLabel("ASSOCIATED COMPANY"),
                    const SizedBox(height: 8),
                    _buildCompanyDropdown(),
                    if (_companyError != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _loadAvailableCompanies,
                          style: TextButton.styleFrom(
                            foregroundColor: mintLight,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          ),
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: Text(_companyError!, style: GoogleFonts.inter(fontSize: 12.5)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    _buildMembersHeader(),
                    const SizedBox(height: 10),
                    _buildMembersList(),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      _buildErrorBanner(_error!),
                    ],
                    const SizedBox(height: 24),
                    _buildSubmitButton(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          const SizedBox(width: 14),
          Text(
            "Create Group",
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: mintAccent.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: mintAccent.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.hub_rounded, size: 13, color: mintLight),
              const SizedBox(width: 6),
              Text(
                "SHARED LEDGER",
                style: GoogleFonts.inter(
                  color: mintLight,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.9,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          "Set up a group",
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          "Create a collaborative space to track and split expenses with team members.",
          style: GoogleFonts.inter(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 13.5,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        color: const Color(0xFF6EE7B7),
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
      ),
    );
  }

  Widget _buildNameField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: _nameController,
        textCapitalization: TextCapitalization.words,
        style: GoogleFonts.inter(
          color: const Color(0xFF0F172A),
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          hintText: "e.g. Sales Team, Marketing, Project",
          hintStyle: GoogleFonts.inter(
            color: const Color(0xFF94A3B8),
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
          prefixIcon: Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primaryGreen.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.group_rounded, color: primaryGreen, size: 20),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        ),
      ),
    );
  }

  Widget _buildCompanyDropdown() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: DropdownButtonHideUnderline(
        child: DropdownButtonFormField<String>(
          initialValue: _companyId,
          isExpanded: true,
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(14),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: primaryGreen, size: 24),
          style: GoogleFonts.inter(
            color: const Color(0xFF0F172A),
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            border: InputBorder.none,
            prefixIcon: Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: primaryGreen.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.business_rounded, color: primaryGreen, size: 20),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
          ),
          hint: Text(
            _loadingCompanies ? "Loading companies…" : "Select a company",
            style: GoogleFonts.inter(
              color: const Color(0xFF94A3B8),
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
          items: _availableCompanies.map((company) {
            final id = _id(company["_id"]);
            final name = (company["name"] ?? "Company").toString();
            return DropdownMenuItem<String>(
              value: id,
              child: Text(
                name,
                style: GoogleFonts.inter(
                  color: const Color(0xFF0F172A),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }).toList(),
          onChanged: _submitting || _loadingCompanies || _availableCompanies.isEmpty ? null : _selectCompany,
        ),
      ),
    );
  }

  Widget _buildMembersHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          children: [
            _buildSectionLabel("ADD MEMBERS"),
            if (_members.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: mintAccent.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: mintAccent.withValues(alpha: 0.45)),
                ),
                child: Text(
                  "${_selectedMemberIds.length}/${_members.length}",
                  style: GoogleFonts.inter(
                    color: const Color(0xFF34D399),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
        if (_members.isNotEmpty)
          TextButton(
            onPressed: _submitting ? null : _toggleSelectAll,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: const Color(0xFF6EE7B7),
            ),
            child: Text(
              _selectedMemberIds.length == _members.length ? "Deselect all" : "Select all",
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }

  Widget _buildMembersList() {
    if (_loadingMembers) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 36),
        alignment: Alignment.center,
        child: Column(
          children: [
            const CircularProgressIndicator(color: mintLight, strokeWidth: 2.5),
            const SizedBox(height: 12),
            Text(
              "Fetching team members…",
              style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (_companyId == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.apartment_rounded, color: mintLight, size: 26),
            ),
            const SizedBox(height: 12),
            Text(
              "No Company Selected",
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Select a company above to view and add its members.",
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    }

    if (_members.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Column(
          children: [
            const Icon(Icons.person_off_rounded, color: Colors.white60, size: 26),
            const SizedBox(height: 10),
            Text(
              "No other company members found",
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: _members.map((member) {
        final memberId = _id(member["userId"]);
        final selected = _selectedMemberIds.contains(memberId);
        final role = (member["role"] ?? "member").toString().toLowerCase();
        final name = (member["name"] ?? "Member").toString();
        final email = (member["email"] ?? "").toString();

        return Container(
          margin: const EdgeInsets.only(bottom: 9),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? mintAccent : Colors.transparent,
              width: 1.8,
            ),
            boxShadow: [
              BoxShadow(
                color: selected
                    ? mintAccent.withValues(alpha: 0.20)
                    : Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: _submitting ? null : () => _toggleMember(memberId),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: selected ? primaryGreen : const Color(0xFFE2E8F0),
                      child: Text(
                        _initials(name),
                        style: GoogleFonts.inter(
                          color: selected ? Colors.white : const Color(0xFF334155),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  name,
                                  style: GoogleFonts.inter(
                                    color: const Color(0xFF0F172A),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14.5,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (role == "admin") ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    "Admin",
                                    style: GoogleFonts.inter(
                                      color: const Color(0xFF92400E),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            role == "admin"
                                ? "Company admin · joined as group member"
                                : (email.isNotEmpty ? email : "Company member"),
                            style: GoogleFonts.inter(
                              color: const Color(0xFF64748B),
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: selected ? mintAccent : Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected ? mintAccent : const Color(0xFFCBD5E1),
                          width: 2,
                        ),
                      ),
                      child: selected
                          ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFFCA5A5), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF10B981), Color(0xFF059669)],
        ),
        boxShadow: [
          BoxShadow(
            color: mintAccent.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _submitting ? null : _createGroup,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          disabledBackgroundColor: Colors.white.withValues(alpha: 0.1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: _submitting
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  ),
                  SizedBox(width: 10),
                  Text(
                    "Setting up group…",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.group_add_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    "Create Group",
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15.5,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
