const Company = require("../models/company");
const CompanyMember = require("../models/companyMember");
const Expense = require("../models/expense");
const Settlement = require("../models/settlement");
const User = require("../models/user");

// Helper to generate a unique 6-digit numeric join code
const generateJoinCode = async () => {
  let code;
  let exists = true;
  while (exists) {
    code = Math.floor(100000 + Math.random() * 900000).toString();
    const found = await Company.findOne({ joinCode: code });
    if (!found) exists = false;
  }
  return code;
};

// 1. Create Company
exports.createCompany = async (req, res) => {
  try {
    const { name, details, userId } = req.body;
    if (!name || !userId) {
      return res.status(400).json({ success: false, message: "Company Name and User ID are required" });
    }

    const joinCode = await generateJoinCode();
    const company = new Company({
      name,
      details: details || "",
      joinCode,
      joinCodeCreatedAt: new Date(),
      createdBy: userId,
    });
    await company.save();

    const member = new CompanyMember({
      companyId: company._id,
      userId,
      role: "admin",
    });
    await member.save();

    res.status(201).json({
      success: true,
      message: "Company created successfully",
      company,
      joinCode,
    });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// 2. Join Company via 6-digit Code
exports.joinCompany = async (req, res) => {
  try {
    const { joinCode, userId } = req.body;
    if (!joinCode || !userId) {
      return res.status(400).json({ success: false, message: "Join Code and User ID are required" });
    }

    const company = await Company.findOne({ joinCode: joinCode.trim() });
    if (!company) {
      return res.status(404).json({ success: false, message: "Invalid 6-digit Company Code" });
    }

    const existingMember = await CompanyMember.findOne({ companyId: company._id, userId });
    if (existingMember) {
      return res.status(200).json({
        success: true,
        message: "You are already a member of this company",
        company,
      });
    }

    // Check code expiration (valid for 5 minutes only)
    const codeCreatedAt = company.joinCodeCreatedAt || company.createdAt;
    const ageInMs = Date.now() - new Date(codeCreatedAt).getTime();
    if (ageInMs > 5 * 60 * 1000) {
      return res.status(400).json({
        success: false,
        message: "This join code has expired (valid for 5 minutes only). Please ask an Admin to regenerate a code.",
      });
    }

    const newMember = new CompanyMember({
      companyId: company._id,
      userId,
      role: "member",
    });
    await newMember.save();

    res.status(200).json({
      success: true,
      message: "Joined company successfully",
      company,
    });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// 3. Get User Companies
exports.getUserCompanies = async (req, res) => {
  try {
    const { userId } = req.params;
    const memberships = await CompanyMember.find({ userId }).populate("companyId");
    
    const companies = memberships
      .filter((m) => m.companyId != null)
      .map((m) => ({
        ...m.companyId._doc,
        userRole: m.role,
        joinedAt: m.joinedAt,
      }));

    res.status(200).json({ success: true, companies });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// 4. Get Company Details & Members
exports.getCompanyDetails = async (req, res) => {
  try {
    const { companyId } = req.params;
    const { userId } = req.query;

    const company = await Company.findById(companyId);
    if (!company) {
      return res.status(404).json({ success: false, message: "Company not found" });
    }

    if (!company.joinCodeCreatedAt) {
      company.joinCodeCreatedAt = company.createdAt || new Date();
      await company.save();
    }

    const members = await CompanyMember.find({ companyId }).populate("userId", "name email");
    const currentMember = members.find((m) => m.userId && m.userId._id.toString() === userId);

    res.status(200).json({
      success: true,
      company,
      members: members.map((m) => ({
        _id: m._id,
        userId: m.userId ? m.userId._id : null,
        name: m.userId ? m.userId.name : "Unknown",
        email: m.userId ? m.userId.email : "",
        role: m.role,
        joinedAt: m.joinedAt,
      })),
      currentUserRole: currentMember ? currentMember.role : "member",
    });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// 5. Admin Regenerate Join Code
exports.regenerateJoinCode = async (req, res) => {
  try {
    const { companyId } = req.params;
    const { userId } = req.body;

    const adminUserIds = await getCompanyAdminUserIds(companyId);
    const isAdmin = adminUserIds.includes(userId ? userId.toString() : "");

    if (!isAdmin) {
      return res.status(403).json({ success: false, message: "Only Admin can regenerate join code" });
    }

    const newCode = await generateJoinCode();
    const company = await Company.findByIdAndUpdate(
      companyId,
      { joinCode: newCode, joinCodeCreatedAt: new Date() },
      { new: true }
    );

    res.status(200).json({
      success: true,
      message: "Join code regenerated successfully",
      joinCode: company.joinCode,
      joinCodeCreatedAt: company.joinCodeCreatedAt,
    });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// 5b. Start/Touch Join Code Timer (when Admin copies or triggers timer)
exports.touchJoinCodeTimer = async (req, res) => {
  try {
    const { companyId } = req.params;
    const { userId } = req.body;

    const member = await CompanyMember.findOne({ companyId, userId });
    if (!member || member.role !== "admin") {
      return res.status(403).json({ success: false, message: "Only Admin can start code timer" });
    }

    const company = await Company.findByIdAndUpdate(
      companyId,
      { joinCodeCreatedAt: new Date() },
      { new: true }
    );

    res.status(200).json({
      success: true,
      message: "Join code timer started for 5 minutes",
      joinCodeCreatedAt: company.joinCodeCreatedAt,
    });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// 6. Admin Remove Member
exports.removeMember = async (req, res) => {
  try {
    const { companyId, memberUserId } = req.params;
    const { userId } = req.body; // Caller ID

    const caller = await CompanyMember.findOne({ companyId, userId });
    if (!caller || caller.role !== "admin") {
      return res.status(403).json({ success: false, message: "Only Admin can remove members" });
    }

    if (memberUserId === userId) {
      return res.status(400).json({ success: false, message: "Admin cannot remove themselves" });
    }

    await CompanyMember.findOneAndDelete({ companyId, userId: memberUserId });

    res.status(200).json({ success: true, message: "Member removed successfully" });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// Helper to get all Admin user IDs for a company
const getCompanyAdminUserIds = async (companyId) => {
  const company = await Company.findById(companyId);
  const adminMembers = await CompanyMember.find({ companyId, role: "admin" });
  const adminUserIds = adminMembers.map((m) => m.userId.toString());
  if (company && company.createdBy) {
    const creatorIdStr = company.createdBy.toString();
    if (!adminUserIds.includes(creatorIdStr)) {
      adminUserIds.push(creatorIdStr);
    }
  }
  return adminUserIds;
};

// 7. Create Expense
exports.createExpense = async (req, res) => {
  try {
    const { companyId, userId, amount, description, category, date, attachment } = req.body;
    if (!companyId || !userId || !amount || !description) {
      return res.status(400).json({ success: false, message: "Company ID, User ID, Amount and Description are required" });
    }

    // Check caller's role in the company: if Admin, expense is not outstanding (marked as paid)
    const adminUserIds = await getCompanyAdminUserIds(companyId);
    const isAdmin = adminUserIds.includes(userId.toString());
    const initialStatus = isAdmin ? "paid" : "outstanding";

    const expense = new Expense({
      companyId,
      createdBy: userId,
      amount: parseFloat(amount),
      description,
      category: category || "General",
      date: date ? new Date(date) : new Date(),
      attachment: attachment || "",
      status: initialStatus,
    });
    await expense.save();

    res.status(201).json({
      success: true,
      message: isAdmin ? "Expense logged and settled (Admin)" : "Expense created successfully",
      expense,
    });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// 8. Get Company Expenses (Feed)
exports.getCompanyExpenses = async (req, res) => {
  try {
    const { companyId } = req.params;

    const adminUserIds = await getCompanyAdminUserIds(companyId);

    // Auto-fix: Admin-created expenses are automatically paid
    await Expense.updateMany(
      { companyId, createdBy: { $in: adminUserIds }, status: "outstanding" },
      { status: "paid" }
    );

    // Fetch all settlements for company in chronological order
    const settlements = await Settlement.find({ companyId })
      .populate("paidBy", "name email")
      .populate("paidTo", "name email")
      .sort({ createdAt: 1 });

    const settlementsMap = {};
    settlements.forEach((s) => {
      const key = s.expenseId.toString();
      if (!settlementsMap[key]) {
        settlementsMap[key] = [];
      }
      settlementsMap[key].push(s);
    });

    const expenses = await Expense.find({ companyId, parentExpenseId: null })
      .populate("createdBy", "name email")
      .sort({ createdAt: -1 });

    const enrichedExpenses = expenses.map((exp) => {
      const expSettlements = settlementsMap[exp._id.toString()] || [];
      const latestSettlement = expSettlements.length > 0 ? expSettlements[expSettlements.length - 1] : null;
      let currentCreditor = exp.createdBy;
      if (latestSettlement && latestSettlement.paidBy) {
        currentCreditor = latestSettlement.paidBy;
      }
      return {
        ...exp._doc,
        settlements: expSettlements,
        settlement: latestSettlement,
        currentCreditor,
      };
    });

    res.status(200).json({ success: true, expenses: enrichedExpenses });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// 9. Pay Flow (§7.1)
exports.payExpense = async (req, res) => {
  try {
    const { expenseId } = req.params;
    const { userId, paymentMode, paymentProof } = req.body;

    if (!userId || !paymentMode || !paymentProof) {
      return res.status(400).json({ success: false, message: "Payment mode and proof of payment image are required" });
    }

    const originalExpense = await Expense.findById(expenseId);
    if (!originalExpense) {
      return res.status(404).json({ success: false, message: "Expense not found" });
    }

    if (originalExpense.status === "paid") {
      return res.status(400).json({ success: false, message: "This expense is already settled by Admin" });
    }

    const existingSettlements = await Settlement.find({ expenseId: originalExpense._id }).sort({ createdAt: -1 });
    const latestSettlement = existingSettlements.length > 0 ? existingSettlements[0] : null;
    const currentCreditorId = latestSettlement
      ? latestSettlement.paidBy.toString()
      : originalExpense.createdBy.toString();

    if (currentCreditorId === userId.toString()) {
      return res.status(400).json({ success: false, message: "You are currently owed this payment and cannot pay yourself" });
    }

    const adminUserIds = await getCompanyAdminUserIds(originalExpense.companyId);
    const isPayerAdmin = adminUserIds.includes(userId.toString());

    // Create NEW Settlement history record (preserves full history)
    const settlement = new Settlement({
      companyId: originalExpense.companyId,
      expenseId: originalExpense._id,
      paidBy: userId,
      paidTo: currentCreditorId,
      amount: originalExpense.amount,
      paymentMode,
      paymentProof,
      initiatedBy: "payer",
    });
    await settlement.save();

    // Mark original expense as paid ONLY if payer is Admin
    if (isPayerAdmin) {
      originalExpense.status = "paid";
      await originalExpense.save();
    }

    res.status(200).json({
      success: true,
      message: isPayerAdmin
        ? "Payment completed. Expense settled by Admin."
        : "Payment recorded. Claim transferred to you until Admin settles it.",
      settlement,
      expense: originalExpense,
    });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// 10. Received Flow (§7.2)
exports.receiveExpense = async (req, res) => {
  try {
    const { expenseId } = req.params;
    const { userId, payerUserId, paymentMode } = req.body;

    if (!userId || !payerUserId || !paymentMode) {
      return res.status(400).json({ success: false, message: "Payer and Payment mode are required" });
    }

    const originalExpense = await Expense.findById(expenseId);
    if (!originalExpense) {
      return res.status(404).json({ success: false, message: "Expense not found" });
    }

    if (originalExpense.status === "paid") {
      return res.status(400).json({ success: false, message: "This expense is already settled by Admin" });
    }

    const existingSettlements = await Settlement.find({ expenseId: originalExpense._id }).sort({ createdAt: -1 });
    const latestSettlement = existingSettlements.length > 0 ? existingSettlements[0] : null;
    const currentCreditorId = latestSettlement
      ? latestSettlement.paidBy.toString()
      : originalExpense.createdBy.toString();

    if (currentCreditorId !== userId.toString()) {
      return res.status(403).json({ success: false, message: "Only the current creditor can confirm payment received" });
    }

    const adminUserIds = await getCompanyAdminUserIds(originalExpense.companyId);
    const isPayerAdmin = adminUserIds.includes(payerUserId.toString());

    // Create NEW Settlement history record (preserves full history)
    const settlement = new Settlement({
      companyId: originalExpense.companyId,
      expenseId: originalExpense._id,
      paidBy: payerUserId,
      paidTo: userId,
      amount: originalExpense.amount,
      paymentMode,
      paymentProof: "",
      initiatedBy: "receiver",
    });
    await settlement.save();

    // Mark original expense as paid ONLY if payer is Admin
    if (isPayerAdmin) {
      originalExpense.status = "paid";
      await originalExpense.save();
    }

    res.status(200).json({
      success: true,
      message: isPayerAdmin
        ? "Expense marked as received from Admin and settled."
        : "Payment recorded. Claim transferred to payer until Admin settles it.",
      settlement,
    });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// 11. Company User Balance Summary
exports.getCompanyBalanceSummary = async (req, res) => {
  try {
    const { companyId, userId } = req.params;

    const adminUserIds = await getCompanyAdminUserIds(companyId);
    await Expense.updateMany(
      { companyId, createdBy: { $in: adminUserIds }, status: "outstanding" },
      { status: "paid" }
    );

    const outstandingExpenses = await Expense.find({
      companyId,
      parentExpenseId: null,
      status: "outstanding",
    });

    const settlements = await Settlement.find({ companyId }).sort({ createdAt: 1 });
    const settlementsMap = {};
    settlements.forEach((s) => {
      const key = s.expenseId.toString();
      if (!settlementsMap[key]) {
        settlementsMap[key] = [];
      }
      settlementsMap[key].push(s);
    });

    let totalReceivable = 0;
    let totalPayable = 0;

    for (const exp of outstandingExpenses) {
      const expSettlements = settlementsMap[exp._id.toString()] || [];
      const latestSettlement = expSettlements.length > 0 ? expSettlements[expSettlements.length - 1] : null;
      const creditorIdStr = latestSettlement && latestSettlement.paidBy
        ? latestSettlement.paidBy.toString()
        : exp.createdBy.toString();
      if (creditorIdStr === userId.toString()) {
        totalReceivable += exp.amount;
      } else {
        totalPayable += exp.amount;
      }
    }

    // Total company spent (all settled/paid expenses)
    const paidExpenses = await Expense.find({ companyId, status: "paid" });
    const totalCompanySpent = paidExpenses.reduce((sum, e) => sum + e.amount, 0);

    res.status(200).json({
      success: true,
      totalReceivable,
      totalPayable,
      totalCompanySpent,
      netBalance: totalReceivable - totalPayable,
    });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};
