import 'package:flutter/material.dart';
import '../ledger/ledger_common.dart' show toast;
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/expense_company_service.dart';
import '../ledger/ledger_home_screen.dart';

class CreateCompanyScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const CreateCompanyScreen({
    Key? key,
    required this.userId,
    required this.userName,
  }) : super(key: key);

  @override
  State<CreateCompanyScreen> createState() => _CreateCompanyScreenState();
}

class _CreateCompanyScreenState extends State<CreateCompanyScreen> {
  static const Color creamSheet = Color(0xFF195754);
  static const Color darkSurface = Color(0xFF113F3D);
  static const Color mintAccent = Color(0xFF10B981);
  static const Color darkText = Color(0xFF1E293B);

  final _formKey = GlobalKey<FormState>();
  late TextEditingController _userNameController;
  final _nameController = TextEditingController();
  final _detailsController = TextEditingController();

  bool _isCreating = false;

  // "Add staff from existing companies" (same as the web): people from my other companies
  List<Map<String, dynamic>> _candidates = [];
  bool _loadingCandidates = true;
  final Map<String, String> _picked = {}; // userId → role ("member" | "admin")
  String _search = "";

  @override
  void initState() {
    super.initState();
    _userNameController = TextEditingController(text: widget.userName);
    ExpenseCompanyService.memberCandidates(widget.userId).then((res) {
      if (!mounted) return;
      setState(() {
        _loadingCandidates = false;
        if (res["success"] == true) _candidates = List<Map<String, dynamic>>.from(res["candidates"] ?? const []);
      });
    });
  }

  List<Map<String, dynamic>> get _filteredCandidates {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return _candidates;
    return _candidates.where((c) {
      final companies = List<String>.from((c["companies"] as List? ?? const []).map((x) => x.toString()));
      return (c["name"]?.toString() ?? "").toLowerCase().contains(q) ||
          (c["email"]?.toString() ?? "").toLowerCase().contains(q) ||
          companies.any((x) => x.toLowerCase().contains(q));
    }).toList();
  }

  Widget _buildMemberPicker() {
    final filtered = _filteredCandidates;
    final allPicked = filtered.isNotEmpty && filtered.every((c) => _picked.containsKey(c["userId"].toString()));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Text(
            "Add staff from existing companies${_candidates.isNotEmpty ? " (${_picked.length}/${_candidates.length} selected)" : ""}",
            style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
        if (filtered.isNotEmpty)
          TextButton(
            onPressed: () => setState(() {
              if (allPicked) {
                for (final c in filtered) {
                  _picked.remove(c["userId"].toString());
                }
              } else {
                for (final c in filtered) {
                  _picked.putIfAbsent(c["userId"].toString(), () => "member");
                }
              }
            }),
            child: Text(allPicked ? "Deselect all" : "Select all", style: GoogleFonts.inter(color: darkSurface, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
      ]),
      const SizedBox(height: 6),
      if (_loadingCandidates)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(children: [
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: darkSurface)),
            const SizedBox(width: 10),
            Text("Loading staff from your companies…", style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.6), fontSize: 13)),
          ]),
        )
      else if (_candidates.isEmpty)
        Text(
          "No staff found in other companies yet. You will be the admin and can invite staff with the 6-digit join code after creation.",
          style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.6), fontSize: 13),
        )
      else ...[
        if (_candidates.length > 3)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              style: GoogleFonts.inter(color: darkText, fontSize: 14),
              decoration: InputDecoration(
                hintText: "Search staff name, email or company…",
                hintStyle: GoogleFonts.inter(color: darkText.withValues(alpha: 0.4), fontSize: 13),
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                prefixIcon: const Icon(Icons.search_rounded, color: darkSurface, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08))),
              ),
            ),
          ),
        if (filtered.isEmpty)
          Text("No staff matching “$_search”", style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.6), fontSize: 13))
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final c in filtered) _candidateTile(c),
              ],
            ),
          ),
      ],
    ]);
  }

  Widget _candidateTile(Map<String, dynamic> c) {
    final id = c["userId"].toString();
    final picked = _picked.containsKey(id);
    final companies = List<String>.from((c["companies"] as List? ?? const []).map((x) => x.toString()));
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: picked ? const Color(0xFFF0FDF4) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: picked ? darkSurface : Colors.black.withValues(alpha: 0.08), width: picked ? 1.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => picked ? _picked.remove(id) : _picked[id] = "member"),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(children: [
            Checkbox(
              value: picked,
              activeColor: darkSurface,
              onChanged: (v) => setState(() => v == true ? _picked[id] = "member" : _picked.remove(id)),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c["name"]?.toString() ?? "Member", style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold, fontSize: 14)),
                if (companies.isNotEmpty)
                  Text(companies.join(", "), maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(color: const Color(0xFF334155), fontSize: 11, fontWeight: FontWeight.w600)),
                if ((c["email"]?.toString() ?? "").isNotEmpty)
                  Text(c["email"].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.55), fontSize: 12)),
              ]),
            ),
            if (picked)
              DropdownButton<String>(
                value: _picked[id],
                underline: const SizedBox.shrink(),
                style: GoogleFonts.inter(color: darkText, fontSize: 12, fontWeight: FontWeight.w600),
                dropdownColor: Colors.white,
                items: const [
                  DropdownMenuItem(value: "member", child: Text("Staff")),
                  DropdownMenuItem(value: "admin", child: Text("Admin")),
                ],
                onChanged: (v) => setState(() => _picked[id] = v ?? "member"),
              ),
          ]),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _userNameController.dispose();
    _nameController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _submitCreateCompany() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isCreating = true);

    final res = await ExpenseCompanyService.createCompany(
      userId: widget.userId,
      userName: _userNameController.text.trim(),
      name: _nameController.text.trim(),
      details: _detailsController.text.trim(),
      memberUserIds: _picked.entries.map((e) => {"userId": e.key, "role": e.value}).toList(),
    );

    if (!mounted) return;
    setState(() => _isCreating = false);

    if (res["success"] == true) {
      final company = res["company"];
      final joinCode = res["joinCode"] ?? company["joinCode"];

      _showCodeSuccessModal(company, joinCode.toString());
    } else {
      toast(context, res["message"] ?? "Failed to create company", error: true);
    }
  }

  void _showCodeSuccessModal(Map<String, dynamic> company, String joinCode) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: creamSheet,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: darkSurface,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded, color: mintAccent, size: 36),
              ),
              const SizedBox(height: 16),
              Text(
                "Company Created!",
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Your 6-digit join code is ready. Share it with staff so they can join. It is valid for 5 minutes; you can generate a new one any time in Settings.",
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 20),

              // Code Display Card
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      joinCode,
                      style: GoogleFonts.ibmPlexMono(
                        color: darkText,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: joinCode));
                        toast(ctx, "Join code copied to clipboard!");
                      },
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text("Copy"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: darkSurface,
                        foregroundColor: mintAccent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx); // Close modal
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LedgerHomeScreen(
                          userId: widget.userId,
                          userName: _userNameController.text.trim().isNotEmpty ? _userNameController.text.trim() : widget.userName,
                          companies: [company],
                          initialCompanyId: company["_id"].toString(),
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: darkSurface,
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    "Go to Company Dashboard",
                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: creamSheet,
      appBar: AppBar(
        backgroundColor: creamSheet,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: darkSurface,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Create Company",
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Set Up Organization",
                    style: GoogleFonts.inter(
                      color: darkText,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Create a company ledger to track reimbursements and settlements with team members.",
                    style: GoogleFonts.inter(
                      color: darkText.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // User Name Field
                  Text(
                    "Your Name *",
                    style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _userNameController,
                    validator: (val) => val == null || val.trim().isEmpty ? "Your name is required" : null,
                    style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: "Enter your full name",
                      hintStyle: GoogleFonts.inter(color: darkText.withValues(alpha: 0.4), fontSize: 14),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      prefixIcon: const Icon(Icons.person_rounded, color: darkSurface, size: 20),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: darkSurface, width: 1.6)),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Company Name Field
                  Text(
                    "Company Name *",
                    style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _nameController,
                    validator: (val) => val == null || val.trim().isEmpty ? "Company name is required" : null,
                    style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: "e.g. Acme Corporation, Yencode Tech",
                      hintStyle: GoogleFonts.inter(color: darkText.withValues(alpha: 0.4), fontSize: 14),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      prefixIcon: const Icon(Icons.business_rounded, color: darkSurface, size: 20),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: darkSurface, width: 1.6)),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Description Field
                  Text(
                    "Company Details / Description (Optional)",
                    style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _detailsController,
                    maxLines: 3,
                    style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: "e.g. Engineering Team Reimbursement Ledger",
                      hintStyle: GoogleFonts.inter(color: darkText.withValues(alpha: 0.4), fontSize: 14),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: darkSurface, width: 1.6)),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _buildMemberPicker(),
                  const SizedBox(height: 24),

                  // Submit Button
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton.icon(
                      onPressed: _isCreating ? null : _submitCreateCompany,
                      icon: _isCreating
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: mintAccent, strokeWidth: 2))
                          : const Icon(Icons.add_business_rounded, color: Colors.white, size: 18),
                      label: Text(
                        _isCreating ? "Creating Company..." : "Create & Generate Code",
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: darkSurface,
                        elevation: 0,
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
