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
    const { name, details, userId, userName } = req.body;
    if (!name || !userId) {
      return res.status(400).json({ success: false, message: "Company Name and User ID are required" });
    }

    if (userName && userName.trim().length > 0) {
      await User.findByIdAndUpdate(userId, { name: userName.trim() });
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
    const { joinCode, userId, userName } = req.body;
    if (!joinCode || !userId) {
      return res.status(400).json({ success: false, message: "Join Code and User ID are required" });
    }

    if (userName && userName.trim().length > 0) {
      await User.findByIdAndUpdate(userId, { name: userName.trim() });
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
      .map((m) => {
        const compDoc = m.companyId._doc || m.companyId;
        const isCreator = compDoc.createdBy && compDoc.createdBy.toString() === userId.toString();
        const canSeeBank = isCreator || m.role === "admin";
        return {
          ...compDoc,
          bankAccounts: canSeeBank ? (compDoc.bankAccounts || []) : [],
          userRole: isCreator ? "admin" : (m.role || "member"),
          joinedAt: m.joinedAt,
        };
      });

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

    const rawMembers = await CompanyMember.find({ companyId }).lean();
    
    // Extract all member user IDs
    const memberUserIds = rawMembers
      .map((m) => m.userId)
      .filter((id) => id != null);

    // Query User collection directly to prevent 'Unknown' names
    const users = await User.find({ _id: { $in: memberUserIds } }).select("name email").lean();
    const usersMap = {};
    users.forEach((u) => {
      usersMap[u._id.toString()] = u;
    });

    const membersList = rawMembers.map((m) => {
      const uIdStr = m.userId ? m.userId.toString() : "";
      const userObj = usersMap[uIdStr] || {};
      const isCreator = company.createdBy && company.createdBy.toString() === uIdStr;
      return {
        _id: m._id,
        userId: m.userId,
        name: userObj.name || "Member",
        email: userObj.email || "",
        role: isCreator ? "admin" : (m.role || "member"),
        joinedAt: m.joinedAt,
      };
    });

    // Sort: Admins always at the top, then alphabetically by name
    membersList.sort((a, b) => {
      if (a.role === "admin" && b.role !== "admin") return -1;
      if (a.role !== "admin" && b.role === "admin") return 1;
      return a.name.localeCompare(b.name, undefined, { sensitivity: "base" });
    });

    // Determine current requesting user's role
    let currentUserRole = "member";
    if (userId) {
      const creatorIdStr = company.createdBy ? company.createdBy.toString() : "";
      if (creatorIdStr && creatorIdStr === userId.toString()) {
        currentUserRole = "admin";
      } else {
        const foundMember = membersList.find((m) => m.userId && m.userId.toString() === userId.toString());
        if (foundMember) {
          currentUserRole = foundMember.role;
        }
      }
    }

    const companyOut = company.toObject();
    if (currentUserRole !== "admin") companyOut.bankAccounts = [];

    res.status(200).json({
      success: true,
      company: companyOut,
      members: membersList,
      currentUserRole,
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
    const { companyId, userId, amount, description, category, date, attachment, logAs, visibleTo } = req.body;
    if (!companyId || !userId || !amount || !description) {
      return res.status(400).json({ success: false, message: "Company ID, User ID, Amount and Description are required" });
    }

    const adminUserIds = await getCompanyAdminUserIds(companyId);
    const isAdmin = adminUserIds.includes(userId.toString());

    // If logAs is 'company' (and creator is Admin), marked as 'paid' (Company expense).
    // If logAs is 'self', marked as 'outstanding' (User/Self expense).
    const isCompanyExpense = logAs ? (logAs === "company") : false;
    const initialStatus = (isAdmin && isCompanyExpense) ? "paid" : "outstanding";

    // Format visibleTo array (defaults to empty array if all members are selected/not restricted)
    let visibleToUsers = [];
    if (Array.isArray(visibleTo)) {
      visibleToUsers = visibleTo.map((id) => id.toString());
    }

    const expense = new Expense({
      companyId,
      createdBy: userId,
      amount: parseFloat(amount),
      description,
      category: category || "General",
      date: date ? new Date(date) : new Date(),
      attachment: attachment || "",
      status: initialStatus,
      logAs: isCompanyExpense ? "company" : "self",
      visibleTo: visibleToUsers,
    });
    await expense.save();
    await rememberCategory(companyId, expense.category);

    res.status(201).json({
      success: true,
      message: (isAdmin && isCompanyExpense) ? "Expense logged and settled (Company)" : "Expense created successfully",
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
    const { userId } = req.query;

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

    const adminUserIds = await getCompanyAdminUserIds(companyId);
    const requestingUserIdStr = userId ? userId.toString() : "";
    const isRequestingAdmin = adminUserIds.includes(requestingUserIdStr);

    const expenseQuery = { companyId, parentExpenseId: null };
    if (!isRequestingAdmin) {
      expenseQuery.$or = [
        { logAs: "self" },
        { logAs: { $ne: "company" }, createdBy: { $nin: adminUserIds } }
      ];
    }

    const expenses = await Expense.find(expenseQuery)
      .populate("createdBy", "name email")
      .sort({ createdAt: -1 });

    const enrichedExpenses = [];

    for (const exp of expenses) {
      const expSettlements = settlementsMap[exp._id.toString()] || [];
      const latestSettlement = expSettlements.length > 0 ? expSettlements[expSettlements.length - 1] : null;
      let currentCreditor = exp.createdBy;
      if (latestSettlement && latestSettlement.paidBy) {
        currentCreditor = latestSettlement.paidBy;
      }

      const isPaidOrSettled = exp.status === "paid" || expSettlements.length > 0;
      const creatorIdStr = exp.createdBy ? exp.createdBy._id.toString() : "";

      // Visibility Rule:
      // 1. Admin can see ALL expenses without restrictions.
      // 2. Creator can see their own expense.
      // 3. Once ANY settlement / payment happens (isPaidOrSettled), restriction lock is disabled & everyone can see it.
      // 4. If visibleTo is empty/not specified, everyone can see it.
      // 5. Otherwise, only users explicitly listed in visibleTo can see it.
      let isVisibleToUser = false;

      if (isRequestingAdmin || !requestingUserIdStr) {
        isVisibleToUser = true;
      } else if (creatorIdStr === requestingUserIdStr) {
        isVisibleToUser = true;
      } else if (isPaidOrSettled) {
        isVisibleToUser = true;
      } else if (!exp.visibleTo || exp.visibleTo.length === 0) {
        isVisibleToUser = true;
      } else {
        const visibleToStrs = exp.visibleTo.map((id) => id.toString());
        if (visibleToStrs.includes(requestingUserIdStr)) {
          isVisibleToUser = true;
        }
      }

      if (isVisibleToUser) {
        enrichedExpenses.push({
          ...exp._doc,
          settlements: expSettlements,
          settlement: latestSettlement,
          currentCreditor,
        });
      }
    }

    res.status(200).json({ success: true, expenses: enrichedExpenses });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// 9. Pay Flow (§7.1)
exports.payExpense = async (req, res) => {
  try {
    const { expenseId } = req.params;
    const { userId, paymentMode, paymentProof, payAs, bankAccountId } = req.body;

    if (!userId || !paymentMode || !paymentProof) {
      return res.status(400).json({ success: false, message: "Payment mode and proof of payment image are required" });
    }
    if (!["cash", "card", "upi"].includes(paymentMode)) {
      return res.status(400).json({ success: false, message: "Payment mode must be Cash, Card or UPI" });
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

    const adminUserIds = await getCompanyAdminUserIds(originalExpense.companyId);
    const isPayerAdmin = adminUserIds.includes(userId.toString());
    const isCompanyPayment = payAs ? (payAs === "company") : isPayerAdmin;

    if (currentCreditorId === userId.toString() && !(isPayerAdmin && isCompanyPayment)) {
      return res.status(400).json({ success: false, message: "You are currently owed this payment and cannot pay yourself" });
    }

    let bankName = "";
    let bankAccountRef = null;
    if (isPayerAdmin && isCompanyPayment) {
      const company = await Company.findById(originalExpense.companyId);
      const account = company && company.bankAccounts.id(bankAccountId);
      if (!account) {
        return res.status(400).json({ success: false, message: "Select the company bank account used for this payment" });
      }
      bankName = account.bankName;
      bankAccountRef = account._id;
    }

    // Create NEW Settlement history record (preserves full history)
    const settlement = new Settlement({
      bankAccountId: bankAccountRef,
      bankName,
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

    // Mark original expense as paid ONLY if payer is Admin and pays as Company
    if (isPayerAdmin && isCompanyPayment) {
      originalExpense.status = "paid";
      await originalExpense.save();
    } else {
      originalExpense.status = "outstanding";
      await originalExpense.save();
    }

    res.status(200).json({
      success: true,
      message: (isPayerAdmin && isCompanyPayment)
        ? "Payment completed. Expense settled by Company."
        : "Payment recorded. Claim transferred to you until settled by Company.",
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

// 12. Change Expense Status (To Paid or Unpaid)
exports.resetExpenseToUnpaid = async (req, res) => {
  try {
    const { expenseId } = req.params;
    const { userId, status } = req.body;

    if (!userId) {
      return res.status(400).json({ success: false, message: "User ID is required" });
    }

    const expense = await Expense.findById(expenseId);
    if (!expense) {
      return res.status(404).json({ success: false, message: "Expense not found" });
    }

    const adminUserIds = await getCompanyAdminUserIds(expense.companyId);
    const isAdmin = adminUserIds.includes(userId.toString());
    const isCreator = expense.createdBy.toString() === userId.toString();

    const settlement = await Settlement.findOne({ expenseId: expense._id }).sort({ createdAt: -1 });
    const isPayer = settlement && settlement.paidBy && settlement.paidBy.toString() === userId.toString();
    const isReceiver = settlement && settlement.paidTo && settlement.paidTo.toString() === userId.toString();

    if (!isAdmin && !isCreator && !isPayer && !isReceiver) {
      return res.status(403).json({ success: false, message: "Only an Admin, Expense Creator, or Payment Settler can change expense status" });
    }

    const targetStatus = status === "paid" ? "paid" : "outstanding";

    if (targetStatus === "paid") {
      expense.status = "paid";
      expense.manuallyReopened = true;
      await expense.save();

      if (!settlement) {
        const newSettlement = new Settlement({
          companyId: expense.companyId,
          expenseId: expense._id,
          paidBy: userId,
          paidTo: expense.createdBy,
          amount: expense.amount,
          paymentMode: "cash",
          paymentProof: "",
          initiatedBy: "payer",
        });
        await newSettlement.save();
      }

      return res.status(200).json({
        success: true,
        message: "Expense status changed to Paid / Settled",
        expense,
      });
    } else {
      expense.status = "outstanding";
      expense.manuallyReopened = true;
      await expense.save();

      // Delete ALL settlement records for this expense to completely reset payment history
      await Settlement.deleteMany({ expenseId: expense._id });

      return res.status(200).json({
        success: true,
        message: "Expense status changed to Unpaid (Outstanding)",
        expense,
      });
    }
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// 13. Edit Payment Details (Mode / Proof)
exports.editExpenseSettlement = async (req, res) => {
  try {
    const { expenseId } = req.params;
    const { userId, paymentMode, paymentProof } = req.body;

    if (!userId) {
      return res.status(400).json({ success: false, message: "User ID is required" });
    }

    const expense = await Expense.findById(expenseId);
    if (!expense) {
      return res.status(404).json({ success: false, message: "Expense not found" });
    }

    const adminUserIds = await getCompanyAdminUserIds(expense.companyId);
    const isAdmin = adminUserIds.includes(userId.toString());
    const isCreator = expense.createdBy.toString() === userId.toString();

    let settlement = await Settlement.findOne({ expenseId: expense._id }).sort({ createdAt: -1 });
    const isPayer = settlement && settlement.paidBy && settlement.paidBy.toString() === userId.toString();
    const isReceiver = settlement && settlement.paidTo && settlement.paidTo.toString() === userId.toString();

    if (!isAdmin && !isCreator && !isPayer && !isReceiver) {
      return res.status(403).json({ success: false, message: "Only an Admin, Expense Creator, or Payment Settler can edit payment details" });
    }

    if (settlement) {
      if (paymentMode) settlement.paymentMode = paymentMode;
      if (paymentProof !== undefined) settlement.paymentProof = paymentProof;
      await settlement.save();
    } else {
      settlement = new Settlement({
        companyId: expense.companyId,
        expenseId: expense._id,
        paidBy: userId,
        paidTo: expense.createdBy,
        amount: expense.amount,
        paymentMode: paymentMode || "cash",
        paymentProof: paymentProof || "",
        initiatedBy: "payer",
      });
      await settlement.save();
    }

    res.status(200).json({
      success: true,
      message: "Payment details updated successfully",
      settlement,
    });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// 14. Delete Company (Admin Only)
exports.deleteCompany = async (req, res) => {
  try {
    const { companyId } = req.params;
    const userId = req.body.userId || req.query.userId;

    if (!userId) {
      return res.status(400).json({ success: false, message: "User ID is required" });
    }

    const adminUserIds = await getCompanyAdminUserIds(companyId);
    const isAdmin = adminUserIds.includes(userId.toString());

    if (!isAdmin) {
      return res.status(403).json({ success: false, message: "Only an Admin can delete the company ledger" });
    }

    await Company.findByIdAndDelete(companyId);
    await CompanyMember.deleteMany({ companyId });
    await Expense.deleteMany({ companyId });
    await Settlement.deleteMany({ companyId });

    res.status(200).json({ success: true, message: "Company ledger deleted successfully" });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// 15. Delete Expense (Admin or Expense Creator before status/settlement change)
exports.deleteExpense = async (req, res) => {
  try {
    const { expenseId } = req.params;
    const userId = req.body.userId || req.query.userId;

    if (!userId) {
      return res.status(400).json({ success: false, message: "User ID is required" });
    }

    const expense = await Expense.findById(expenseId);
    if (!expense) {
      return res.status(404).json({ success: false, message: "Expense not found" });
    }

    const adminUserIds = await getCompanyAdminUserIds(expense.companyId);
    const isAdmin = adminUserIds.includes(userId.toString());
    const isCreator = expense.createdBy.toString() === userId.toString();

    const settlements = await Settlement.find({ expenseId: expense._id });
    const hasSettlement = settlements.length > 0;
    const isPaid = expense.status === "paid";

    const canDelete = isAdmin || (isCreator && !isPaid && !hasSettlement);

    if (!canDelete) {
      return res.status(403).json({
        success: false,
        message: "You do not have permission to delete this expense once status is changed or settled.",
      });
    }

    await Expense.findByIdAndDelete(expenseId);
    await Settlement.deleteMany({ expenseId });

    res.status(200).json({ success: true, message: "Expense deleted successfully" });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// 14. Edit Expense (creator only, and only until any payment/settlement happens)
exports.updateExpense = async (req, res) => {
  try {
    const { expenseId } = req.params;
    const { userId, amount, description, category, date } = req.body;

    if (!userId) {
      return res.status(400).json({ success: false, message: "User ID is required" });
    }

    const expense = await Expense.findById(expenseId);
    if (!expense) {
      return res.status(404).json({ success: false, message: "Expense not found" });
    }

    if (expense.createdBy.toString() !== userId.toString()) {
      return res.status(403).json({ success: false, message: "Only the expense creator can edit this expense" });
    }

    const settlementCount = await Settlement.countDocuments({ expenseId: expense._id });
    if (expense.status === "paid" || settlementCount > 0) {
      return res.status(400).json({ success: false, message: "This expense can no longer be edited because a payment has been made" });
    }

    if (amount !== undefined) {
      const parsed = parseFloat(amount);
      if (!(parsed > 0)) {
        return res.status(400).json({ success: false, message: "Amount must be greater than zero" });
      }
      expense.amount = parsed;
    }
    if (description !== undefined) {
      if (!String(description).trim()) {
        return res.status(400).json({ success: false, message: "Description is required" });
      }
      expense.description = String(description).trim();
    }
    if (category !== undefined && String(category).trim()) expense.category = String(category).trim();
    if (date) expense.date = new Date(date);

    await expense.save();
    await rememberCategory(expense.companyId, expense.category);
    res.status(200).json({ success: true, message: "Expense updated successfully", expense });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// Custom categories are stored on the company and are never removed.
const BASE_CATEGORIES = ["General", "Food & Dining", "Travel & Transport", "Office Supplies", "Utilities", "Software & Tech", "Other"];
const rememberCategory = async (companyId, category) => {
  const name = category ? String(category).trim() : "";
  if (!name || BASE_CATEGORIES.includes(name)) return;
  await Company.updateOne({ _id: companyId }, { $addToSet: { customCategories: name } });
};

// 15. Add Custom Category
exports.addCustomCategory = async (req, res) => {
  try {
    const { companyId } = req.params;
    const { userId, name } = req.body;
    const member = await CompanyMember.findOne({ companyId, userId });
    if (!member) {
      return res.status(403).json({ success: false, message: "Only company members can add categories" });
    }
    if (!name || !String(name).trim()) {
      return res.status(400).json({ success: false, message: "Category name is required" });
    }
    await rememberCategory(companyId, name);
    const company = await Company.findById(companyId);
    res.status(200).json({ success: true, customCategories: company ? company.customCategories : [] });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// 16. Company bank accounts (admin only)
exports.addBankAccount = async (req, res) => {
  try {
    const { companyId } = req.params;
    const { userId, bankName, accountHolder, accountNumber, ifsc } = req.body;
    const adminUserIds = await getCompanyAdminUserIds(companyId);
    if (!userId || !adminUserIds.includes(userId.toString())) {
      return res.status(403).json({ success: false, message: "Only Admin can manage bank accounts" });
    }
    if (!bankName || !String(bankName).trim() || !accountNumber || !String(accountNumber).trim()) {
      return res.status(400).json({ success: false, message: "Bank name and account number are required" });
    }
    const company = await Company.findById(companyId);
    if (!company) {
      return res.status(404).json({ success: false, message: "Company not found" });
    }
    company.bankAccounts.push({
      bankName: String(bankName).trim(),
      accountHolder: accountHolder ? String(accountHolder).trim() : "",
      accountNumber: String(accountNumber).trim(),
      ifsc: ifsc ? String(ifsc).trim().toUpperCase() : "",
    });
    await company.save();
    res.status(200).json({ success: true, bankAccounts: company.bankAccounts });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

exports.deleteBankAccount = async (req, res) => {
  try {
    const { companyId, accountId } = req.params;
    const { userId } = req.body;
    const adminUserIds = await getCompanyAdminUserIds(companyId);
    if (!userId || !adminUserIds.includes(userId.toString())) {
      return res.status(403).json({ success: false, message: "Only Admin can manage bank accounts" });
    }
    await Company.updateOne({ _id: companyId }, { $pull: { bankAccounts: { _id: accountId } } });
    const company = await Company.findById(companyId);
    res.status(200).json({ success: true, bankAccounts: company ? company.bankAccounts : [] });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};
