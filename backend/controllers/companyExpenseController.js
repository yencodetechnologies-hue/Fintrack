const mongoose = require("mongoose");
const Company = require("../models/company");
const CompanyMember = require("../models/companyMember");
const Expense = require("../models/expense");
const CompanyIncome = require("../models/companyIncome");
const Settlement = require("../models/settlement");
const User = require("../models/user");
const { ExpenseGroup } = require("../models/expenseGroup");

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

exports.createExpenseGroup = async (req, res) => {
  try {
    const { companyId, userId, name, memberIds = [] } = req.body;
    if (!companyId || !userId || !name || !name.trim()) {
      return res.status(400).json({ success: false, message: "Company, group name, and creator are required" });
    }

    const company = await Company.findById(companyId).select("_id");
    if (!company) return res.status(404).json({ success: false, message: "Company not found" });

    const creatorMembership = await CompanyMember.findOne({ companyId, userId });
    if (!creatorMembership) return res.status(403).json({ success: false, message: "Only company members can create a group" });

    const selectedIds = [...new Set([userId.toString(), ...(Array.isArray(memberIds) ? memberIds.map(String) : [])])];
    const validMembers = await CompanyMember.find({ companyId, userId: { $in: selectedIds } }).select("userId").lean();
    if (validMembers.length !== selectedIds.length) {
      return res.status(400).json({ success: false, message: "Every group member must belong to the selected company" });
    }

    const group = await ExpenseGroup.create({
      companyId,
      name: name.trim(),
      createdBy: userId,
      members: selectedIds,
    });
    const created = await ExpenseGroup.findById(group._id)
      .populate("companyId", "name")
      .populate("createdBy", "name email")
      .populate("members", "name email");
    return res.status(201).json({ success: true, group: created, message: "Group created" });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};

exports.getUserExpenseGroups = async (req, res) => {
  try {
    const { userId } = req.query;
    if (!userId || !(await User.exists({ _id: userId }))) {
      return res.status(401).json({ success: false, message: "A valid signed-in user is required" });
    }

    const memberships = await CompanyMember.find({ userId }).select("companyId").lean();
    const companyIds = memberships.map((membership) => membership.companyId);
    const groups = await ExpenseGroup.find({
      $or: [
        { createdBy: userId },
        ...(companyIds.length ? [{ companyId: { $in: companyIds }, members: userId }] : []),
      ],
    })
      .populate("companyId", "name")
      .populate("createdBy", "name")
      .sort({ createdAt: -1 })
      .lean();

    return res.status(200).json({ success: true, groups });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};

async function getGroupForMember(groupId, userId) {
  const group = await ExpenseGroup.findById(groupId).lean();
  if (!group) return { error: { status: 404, message: "Group not found" } };
  const isMember = String(group.createdBy) === String(userId) || (group.members || []).some((id) => String(id) === String(userId));
  if (!isMember) return { error: { status: 403, message: "You are not a member of this group" } };
  return { group };
}

exports.getGroupExpenses = async (req, res) => {
  try {
    const { userId } = req.query;
    if (!userId) return res.status(400).json({ success: false, message: "User ID is required" });
    const result = await getGroupForMember(req.params.groupId, userId);
    if (result.error) return res.status(result.error.status).json({ success: false, message: result.error.message });
    const [group, expenses] = await Promise.all([
      ExpenseGroup.findById(req.params.groupId)
        .populate("companyId", "name")
        .populate("createdBy", "name")
        .populate("members", "name email")
        .populate("settlementCompanyId", "name")
        .populate("settledBy", "name")
        .lean(),
      Expense.find({ groupId: req.params.groupId })
        .select("-attachment -paymentReceipt")
        .populate("createdBy", "name")
        .sort({ createdAt: -1 })
        .lean(),
    ]);
    return res.json({
      success: true,
      group,
      expenses: expenses.map((expense) => ({ ...expense, hasAttachment: Boolean(expense.hasAttachment) })),
    });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};

exports.getGroupMembers = async (req, res) => {
  try {
    const { userId } = req.query;
    if (!userId) return res.status(400).json({ success: false, message: "User ID is required" });
    const { group, error } = await getGroupForMember(req.params.groupId, userId);
    if (error) return res.status(error.status).json({ success: false, message: error.message });
    const currentIds = (group.members || []).map(String);
    const isGroupAdmin = String(group.createdBy) === String(userId);
    const [members, admin] = await Promise.all([
      User.find({ _id: { $in: currentIds } }).select("name email").lean(),
      User.findById(group.createdBy).select("name email").lean(),
    ]);
    let candidates = [];
    if (isGroupAdmin) {
      const memberships = await CompanyMember.find({
        companyId: group.companyId,
        userId: { $nin: currentIds },
      }).select("userId role").lean();
      const candidateUsers = await User.find({ _id: { $in: memberships.map((member) => member.userId) } })
        .select("name email")
        .lean();
      const roleById = new Map(memberships.map((member) => [String(member.userId), member.role]));
      candidates = candidateUsers.map((candidate) => ({ ...candidate, companyRole: roleById.get(String(candidate._id)) || "member" }));
    }
    return res.json({
      success: true,
      members,
      candidates,
      admin,
      group: { _id: group._id, name: group.name, createdBy: group.createdBy, settlementStatus: group.settlementStatus },
    });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};

exports.addGroupMember = async (req, res) => {
  try {
    const { userId, memberId } = req.body;
    if (!userId || !memberId) return res.status(400).json({ success: false, message: "User and member IDs are required" });
    const { group, error } = await getGroupForMember(req.params.groupId, userId);
    if (error) return res.status(error.status).json({ success: false, message: error.message });
    if (String(group.createdBy) !== String(userId)) return res.status(403).json({ success: false, message: "Only the group admin can manage members" });
    if (group.settlementStatus === "settled") return res.status(409).json({ success: false, message: "Members cannot be changed after the group is settled" });
    if (!(await CompanyMember.exists({ companyId: group.companyId, userId: memberId }))) {
      return res.status(400).json({ success: false, message: "The person must be a member of the group's company" });
    }
    const updated = await ExpenseGroup.findByIdAndUpdate(
      req.params.groupId,
      { $addToSet: { members: memberId } },
      { returnDocument: "after" }
    ).populate("members", "name email");
    return res.json({ success: true, group: updated, message: "Member added to group" });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};

exports.removeGroupMember = async (req, res) => {
  try {
    const { userId } = req.body;
    const { memberId } = req.params;
    if (!userId) return res.status(400).json({ success: false, message: "User ID is required" });
    const { group, error } = await getGroupForMember(req.params.groupId, userId);
    if (error) return res.status(error.status).json({ success: false, message: error.message });
    if (String(group.createdBy) !== String(userId)) return res.status(403).json({ success: false, message: "Only the group admin can manage members" });
    if (group.settlementStatus === "settled") return res.status(409).json({ success: false, message: "Members cannot be changed after the group is settled" });
    if (String(group.createdBy) === String(memberId)) return res.status(400).json({ success: false, message: "The group admin must remain a member" });
    if (!(group.members || []).some((id) => String(id) === String(memberId))) {
      return res.status(404).json({ success: false, message: "Group member not found" });
    }
    const updated = await ExpenseGroup.findByIdAndUpdate(
      req.params.groupId,
      { $pull: { members: memberId } },
      { returnDocument: "after" }
    ).populate("members", "name email");
    return res.json({ success: true, group: updated, message: "Member removed from group" });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};

exports.createGroupExpense = async (req, res) => {
  try {
    const { userId, amount, description, category, date, attachment } = req.body;
    const value = Number(amount);
    if (!userId || !(value > 0) || !String(description || "").trim()) {
      return res.status(400).json({ success: false, message: "User, a positive amount, and description are required" });
    }
    const result = await getGroupForMember(req.params.groupId, userId);
    if (result.error) return res.status(result.error.status).json({ success: false, message: result.error.message });
    const { group } = result;
    if (group.settlementStatus === "settled") {
      return res.status(409).json({ success: false, message: "This group is already settled" });
    }

    const expense = await Expense.create({
      companyId: group.companyId,
      groupId: group._id,
      createdBy: userId,
      isAdminCreated: false,
      amount: value,
      description: String(description).trim(),
      category: category || "General",
      date: date ? new Date(date) : new Date(),
      attachment: attachment || "",
      visibleTo: group.members,
      lifecycle: null,
      status: "outstanding",
      logAs: "self",
      payerType: "unpaid",
    });
    return res.status(201).json({
      success: true,
      expense: { ...expense.toObject(), attachment: undefined, hasAttachment: Boolean(expense.hasAttachment) },
    });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};

exports.getGroupExpenseReceipt = async (req, res) => {
  try {
    const { userId } = req.query;
    const result = await getGroupForMember(req.params.groupId, userId);
    if (result.error) return res.status(result.error.status).json({ success: false, message: result.error.message });
    const expense = await Expense.findOne({ _id: req.params.expenseId, groupId: req.params.groupId }).select("attachment");
    if (!expense) return res.status(404).json({ success: false, message: "Group expense not found" });
    return res.json({ success: true, attachment: expense.attachment || "" });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};
// 1. Create Company
exports.createCompany = async (req, res) => {
  try {
    const { name, details, userId, userName, memberUserIds = [] } = req.body;
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

    // Add selected members if provided
    if (Array.isArray(memberUserIds) && memberUserIds.length > 0) {
      for (const item of memberUserIds) {
        const mUserId = typeof item === "object" && item !== null ? (item.userId || item._id || item.id) : item;
        const role = typeof item === "object" && item?.role === "admin" ? "admin" : "member";
        if (!mUserId || String(mUserId) === String(userId)) continue;

        try {
          const exists = await CompanyMember.findOne({ companyId: company._id, userId: mUserId });
          if (!exists) {
            await CompanyMember.create({
              companyId: company._id,
              userId: mUserId,
              role,
            });
          }
        } catch (mErr) {
          console.error(`Failed to add member ${mUserId} to company:`, mErr);
        }
      }
    }

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

// Candidate members from any company
exports.getAllCompanyMemberCandidates = async (req, res) => {
  try {
    const { userId } = req.query;

    const rawMembers = await CompanyMember.find({})
      .populate("companyId", "name")
      .populate("userId", "name email")
      .lean();

    const userMap = new Map();

    for (const m of rawMembers) {
      if (!m.userId || !m.userId._id) continue;
      const uId = m.userId._id.toString();
      if (userId && uId === String(userId)) continue;

      if (!userMap.has(uId)) {
        userMap.set(uId, {
          userId: uId,
          name: m.userId.name || "Staff",
          email: m.userId.email || "",
          companies: [],
        });
      }

      if (m.companyId && m.companyId.name) {
        const item = userMap.get(uId);
        if (!item.companies.includes(m.companyId.name)) {
          item.companies.push(m.companyId.name);
        }
      }
    }

    const allUsers = await User.find(userId ? { _id: { $ne: userId } } : {}).select("name email").lean();
    for (const u of allUsers) {
      const uId = u._id.toString();
      if (!userMap.has(uId)) {
        userMap.set(uId, {
          userId: uId,
          name: u.name || "User",
          email: u.email || "",
          companies: [],
        });
      }
    }

    const candidates = Array.from(userMap.values()).sort((a, b) => a.name.localeCompare(b.name));

    return res.status(200).json({ success: true, candidates });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
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

exports.getAllAvailableCompanies = async (req, res) => {
  try {
    const { userId } = req.query;
    if (!userId || !(await User.exists({ _id: userId }))) {
      return res.status(401).json({ success: false, message: "A valid signed-in user is required" });
    }
    const companies = await Company.find({})
      .select("name external gstin")
      .sort({ name: 1 })
      .lean();
    return res.status(200).json({ success: true, companies });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
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
          cashBalance: canSeeBank ? (compDoc.cashBalance || 0) : 0,
          cashAccountName: compDoc.cashAccountName || "InCash",
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
        name: userObj.name || "Staff",
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
    if (currentUserRole !== "admin") {
      companyOut.bankAccounts = [];
      companyOut.cashBalance = 0;
    }

    const ownMembership = userId
      ? rawMembers.find((m) => m.userId && m.userId.toString() === userId.toString())
      : null;

    res.status(200).json({
      success: true,
      company: companyOut,
      members: membersList,
      currentUserRole,
      hiddenStaffIds: (ownMembership?.hiddenStaffIds || []).map(String),
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
      { returnDocument: "after" }
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
      { returnDocument: "after" }
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
  const [company, adminMembers] = await Promise.all([
    Company.findById(companyId).select("createdBy").lean(),
    CompanyMember.find({ companyId, role: "admin" }).select("userId").lean(),
  ]);
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
    const { companyId, userId, amount, description, category, date, attachment, logAs, visibleTo, fundId } = req.body;
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

    let fund = null;
    if (isAdmin && isCompanyExpense) {
      try {
        fund = await resolveFund(companyId, fundId, parseFloat(amount));
      } catch (e) {
        return res.status(e.status || 400).json({ success: false, message: e.message });
      }
    }

    const expense = new Expense({
      fundType: fund ? fund.type : "",
      fundBankAccountId: fund ? fund.bankAccountId : null,
      fundName: fund ? fund.name : "",
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
    if (fund) await applyFund(companyId, fund, -expense.amount);
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
    const { userId, summary, ledgerOnly } = req.query;

    const isLedgerOnly = ledgerOnly === "1";
    const expenseQuery = { companyId, parentExpenseId: null, groupId: null };
    if (ledgerOnly === "1") expenseQuery.lifecycle = { $ne: null };
    const compObjectId = new mongoose.Types.ObjectId(companyId);

    // Parallelize all lookups simultaneously across MongoDB Atlas
    const [settlements, adminUserIds, requestingUser, expenses] = await Promise.all([
      isLedgerOnly
        ? []
        : Settlement.find({ companyId })
            .populate("paidBy", "name email")
            .populate("paidTo", "name email")
            .sort({ createdAt: 1 })
            .lean(),
      getCompanyAdminUserIds(companyId),
      userId ? User.findById(userId).select("platformRole").lean() : null,
      Expense.find(expenseQuery)
        .select("-attachment -paymentReceipt")
        .populate("createdBy", "name email")
        .populate("approvedBy", "name email")
        .populate("paidByAdminId", "name email")
        .populate("paidByUserId", "name email")
        .sort({ createdAt: -1 })
        .lean(),
    ]);

    const settlementsMap = {};
    if (!isLedgerOnly) {
      settlements.forEach((s) => {
        const key = s.expenseId.toString();
        if (!settlementsMap[key]) {
          settlementsMap[key] = [];
        }
        settlementsMap[key].push(s);
      });
    }

    const requestingUserIdStr = userId ? userId.toString() : "";
    const isRequestingAdmin = adminUserIds.includes(requestingUserIdStr) || requestingUser?.platformRole === "super_admin";

    const enrichedExpenses = [];

    for (const exp of expenses) {
      const expIdStr = exp._id.toString();
      const expSettlements = isLedgerOnly ? [] : (settlementsMap[expIdStr] || []);
      const latestSettlement = expSettlements.length > 0 ? expSettlements[expSettlements.length - 1] : null;
      let currentCreditor = exp.createdBy;
      if (latestSettlement && latestSettlement.paidBy) {
        currentCreditor = latestSettlement.paidBy;
      }

      const creatorIdStr = exp.createdBy ? (exp.createdBy._id ? exp.createdBy._id.toString() : exp.createdBy.toString()) : "";
      const adminCreated = exp.isAdminCreated === true ||
        (exp.isAdminCreated !== false && adminUserIds.includes(creatorIdStr));
      const isVisibleToUser = isRequestingAdmin || !adminCreated ||
        (exp.visibleTo || []).some((id) => id.toString() === requestingUserIdStr);

      if (isVisibleToUser) {
        enrichedExpenses.push({
          ...exp,
          hasAttachment: Boolean(exp.hasAttachment),
          hasPaymentReceipt: Boolean(exp.hasPaymentReceipt),
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

exports.getExpenseReceipts = async (req, res) => {
  try {
    const { userId } = req.query;
    if (!userId) return res.status(400).json({ success: false, message: "User ID is required" });
    const expense = await Expense.findById(req.params.expenseId)
      .select("companyId createdBy isAdminCreated visibleTo attachment paymentReceipt");
    if (!expense) return res.status(404).json({ success: false, message: "Expense not found" });

    const company = await Company.findById(expense.companyId).select("createdBy");
    if (!company) return res.status(404).json({ success: false, message: "Company not found" });
    const user = await User.findById(userId).select("platformRole");
    if (!user) return res.status(403).json({ success: false, message: "Not authorized" });
    const admins = await getCompanyAdminUserIds(expense.companyId);
    const isAdmin = user.platformRole === "super_admin" || admins.includes(String(userId));
    const isMember = isAdmin || String(company.createdBy || "") === String(userId) ||
      !!(await CompanyMember.exists({ companyId: expense.companyId, userId }));
    if (!isMember) return res.status(403).json({ success: false, message: "Not authorized" });

    const creatorId = String(expense.createdBy);
    const adminCreated = expense.isAdminCreated === true ||
      (expense.isAdminCreated !== false && admins.includes(creatorId));
    if (!isAdmin && adminCreated && !(expense.visibleTo || []).some((id) => id.toString() === String(userId))) {
      return res.status(404).json({ success: false, message: "Expense not found" });
    }
    res.json({ success: true, attachment: expense.attachment, paymentReceipt: expense.paymentReceipt });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// 9. Pay Flow (§7.1)
exports.payExpense = async (req, res) => {
  try {
    const { expenseId } = req.params;
    const { userId, paymentMode, paymentProof, payAs, fundId } = req.body;

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
    if (originalExpense.groupId) {
      return res.status(403).json({ success: false, message: "Group expenses are settled only when the group is closed" });
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

    let fund = null;
    if (isPayerAdmin && isCompanyPayment) {
      try {
        fund = await resolveFund(originalExpense.companyId, fundId, originalExpense.amount);
      } catch (e) {
        return res.status(e.status || 400).json({ success: false, message: e.message });
      }
    }

    // Create NEW Settlement history record (preserves full history)
    const settlement = new Settlement({
      fundType: fund ? fund.type : "",
      bankAccountId: fund ? fund.bankAccountId : null,
      bankName: fund ? fund.name : "",
      paidAs: (isPayerAdmin && isCompanyPayment) ? "company" : "self",
      companyId: originalExpense.companyId,
      expenseId: originalExpense._id,
      paidBy: userId,
      paidTo: currentCreditorId,
      amount: originalExpense.amount,
      paymentMode,
      paymentProof,
      initiatedBy: "payer",
    });
    if (fund) await applyFund(originalExpense.companyId, fund, -originalExpense.amount);
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
      const oldSettlements = await Settlement.find({ expenseId: expense._id });
      await refundExpenseFunds(expense, oldSettlements);
      expense.fundType = "";
      expense.fundBankAccountId = null;
      expense.fundName = "";
      await expense.save();
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

    const expense = await Expense.findById(expenseId).select("-attachment -paymentReceipt");
    if (!expense) {
      return res.status(404).json({ success: false, message: "Expense not found" });
    }

    const adminUserIds = await getCompanyAdminUserIds(expense.companyId);
    const isAdmin = adminUserIds.includes(userId.toString());
    const isCreator = expense.createdBy.toString() === userId.toString();

    const settlements = await Settlement.find({ expenseId: expense._id });
    const hasSettlement = settlements.length > 0;
    const isPaid = expense.status === "paid" || Boolean(expense.lifecycle && expense.lifecycle.startsWith("paid"));
    const isApproved = expense.lifecycle === "approved";
    const canDelete = isAdmin || (isCreator && !isPaid && !hasSettlement && !isApproved);

    if (!canDelete) {
      return res.status(403).json({
        success: false,
        message: "You do not have permission to delete this expense once approved, paid, or settled.",
      });
    }

    await refundExpenseFunds(expense, settlements);
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

    const adminUserIds = await getCompanyAdminUserIds(expense.companyId);
    const isAdmin = adminUserIds.includes(userId.toString());
    const isCreator = expense.createdBy && expense.createdBy.toString() === userId.toString();

    if (!isAdmin && !isCreator) {
      return res.status(403).json({ success: false, message: "You can only edit your own expenses" });
    }

    // Staff can only edit before approval
    if (!isAdmin && expense.lifecycle && expense.lifecycle !== "submitted") {
      return res.status(400).json({ success: false, message: "Staff can only edit expenses before approval" });
    }

    // Manager can edit before paid by company (or any paid status / settlement)
    const settlementCount = await Settlement.countDocuments({ expenseId: expense._id });
    const isPaid =
      expense.status === "paid" ||
      (expense.lifecycle && expense.lifecycle.startsWith("paid")) ||
      settlementCount > 0;
    if (isPaid) {
      return res.status(400).json({ success: false, message: "This expense can no longer be edited because a payment has already been made" });
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

// 15b. Update Cash Account Name (admin only)
exports.updateCashAccountName = async (req, res) => {
  try {
    const { companyId } = req.params;
    const { userId, cashAccountName } = req.body;
    const adminUserIds = await getCompanyAdminUserIds(companyId);
    if (!userId || !adminUserIds.includes(userId.toString())) {
      return res.status(403).json({ success: false, message: "Only Admin can edit cash account name" });
    }
    const name = String(cashAccountName || "").trim();
    if (!name) {
      return res.status(400).json({ success: false, message: "Cash account name cannot be empty" });
    }
    const company = await Company.findByIdAndUpdate(
      companyId,
      { cashAccountName: name },
      { returnDocument: "after" }
    );
    if (!company) {
      return res.status(404).json({ success: false, message: "Company not found" });
    }
    res.status(200).json({
      success: true,
      message: "Cash account name updated successfully",
      cashAccountName: company.cashAccountName,
    });
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
    const existing = await Company.findById(companyId);
    const acct = existing && existing.bankAccounts.id(accountId);
    if (acct && acct.balance !== 0) {
      return res.status(400).json({ success: false, message: "Move or spend the remaining balance before removing this bank account" });
    }
    await Company.updateOne({ _id: companyId }, { $pull: { bankAccounts: { _id: accountId } } });
    const company = await Company.findById(companyId);
    res.status(200).json({ success: true, bankAccounts: company ? company.bankAccounts : [] });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// ---------- Company funds (bank accounts + InCash) ----------
// fundId is either "cash" (InCash) or a bank account _id.
async function resolveFund(companyId, fundId, amount) {
  const fail = (msg) => { const e = new Error(msg); e.status = 400; return e; };
  if (!fundId) throw fail("Select the bank account or InCash used for this payment");
  const company = await Company.findById(companyId);
  if (!company) throw fail("Company not found");
  if (fundId === "cash") {
    const cashName = company.cashAccountName || "InCash";
    if ((company.cashBalance || 0) < amount) throw fail("Insufficient " + cashName + " balance (₹" + (company.cashBalance || 0) + ")");
    return { type: "cash", bankAccountId: null, name: cashName };
  }
  const account = company.bankAccounts.id(fundId);
  if (!account) throw fail("Selected bank account was not found");
  if ((account.balance || 0) < amount) throw fail("Insufficient balance in " + account.bankName + " (₹" + (account.balance || 0) + ")");
  return { type: "bank", bankAccountId: account._id, name: account.bankName };
}

async function applyFund(companyId, fund, delta) {
  if (fund.type === "cash") {
    await Company.updateOne({ _id: companyId }, { $inc: { cashBalance: delta } });
  } else if (fund.bankAccountId) {
    await Company.updateOne(
      { _id: companyId, "bankAccounts._id": fund.bankAccountId },
      { $inc: { "bankAccounts.$.balance": delta } }
    );
  }
}

async function refundExpenseFunds(expense, settlements) {
  if (expense.fundType) {
    await applyFund(expense.companyId, { type: expense.fundType, bankAccountId: expense.fundBankAccountId }, expense.amount);
  }
  for (const s of settlements) {
    if (s.fundType) {
      await applyFund(s.companyId, { type: s.fundType, bankAccountId: s.bankAccountId }, s.amount);
    }
  }
}

// 17. Add Income (admin only)
// destination "cash": money moves from an existing bank account into InCash.
// destination <bankId>: money is added to that bank account.
exports.addIncome = async (req, res) => {
  try {
    const { companyId } = req.params;
    const { userId, amount, destination, sourceBankAccountId, description } = req.body;
    const adminUserIds = await getCompanyAdminUserIds(companyId);
    if (!userId || !adminUserIds.includes(userId.toString())) {
      return res.status(403).json({ success: false, message: "Only Admin can add income" });
    }
    const value = parseFloat(amount);
    if (!(value > 0)) {
      return res.status(400).json({ success: false, message: "Enter a valid amount" });
    }
    const company = await Company.findById(companyId);
    if (!company) {
      return res.status(404).json({ success: false, message: "Company not found" });
    }

    const cashName = company.cashAccountName || "InCash";
    const record = {
      companyId,
      createdBy: userId,
      amount: value,
      description: typeof description === "string" ? description.trim() : "",
    };
    if (destination === "cash") {
      const source = company.bankAccounts.id(sourceBankAccountId);
      if (!source) {
        return res.status(400).json({ success: false, message: "Select the bank account the cash is coming from" });
      }
      if ((source.balance || 0) < value) {
        return res.status(400).json({ success: false, message: "Insufficient balance in " + source.bankName + " (₹" + (source.balance || 0) + ")" });
      }
      await applyFund(companyId, { type: "bank", bankAccountId: source._id }, -value);
      await applyFund(companyId, { type: "cash" }, value);
      Object.assign(record, {
        destinationType: "cash",
        destinationName: cashName,
        sourceBankAccountId: source._id,
        sourceName: source.bankName,
      });
    } else {
      const target = company.bankAccounts.id(destination);
      if (!target) {
        return res.status(400).json({ success: false, message: "Select a bank account or InCash" });
      }
      await applyFund(companyId, { type: "bank", bankAccountId: target._id }, value);
      Object.assign(record, {
        destinationType: "bank",
        destinationBankAccountId: target._id,
        destinationName: target.bankName,
      });
    }
    await new CompanyIncome(record).save();

    const updated = await Company.findById(companyId);
    res.status(200).json({ success: true, bankAccounts: updated.bankAccounts, cashBalance: updated.cashBalance });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// 18. Income history (admin only)
exports.getIncomeHistory = async (req, res) => {
  try {
    const { companyId } = req.params;
    const { userId } = req.query;
    const adminUserIds = await getCompanyAdminUserIds(companyId);
    if (!userId || !adminUserIds.includes(userId.toString())) {
      return res.status(403).json({ success: false, message: "Only Admin can view income" });
    }
    const income = await CompanyIncome.find({ companyId }).sort({ createdAt: -1 }).limit(30);
    res.status(200).json({ success: true, income });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};


