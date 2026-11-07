/**
 * Pure planning logic for the one-off 2026-10 production reset + teacher import.
 *
 * Kept free of Convex imports so it can be unit-tested with node --test.
 * The Convex wrapper lives in oneoffTeacherImport.ts.
 */

/** Dummy/test business tables that are wiped entirely (rows created before the dry-run snapshot). */
export const ONEOFF_WIPE_TABLES = [
  "duties",
  "dutyAttendances",
  "dutyMessages",
  "dutyImportUploads",
  "officeDocuments",
  "workItems",
  "workMessages",
  "personalTasks",
  "personalReminders",
  "approvalLogs",
  "chatThreads",
  "chatInbox",
  "chatCounters",
  "chatHubSync",
  "chatNotificationEvents",
  "chatGroups",
  "chatGroupMembers",
  "groupMessages",
  "notificationReads",
  "notificationDismissals",
  "personnelFaults",
  "personnelEvaluationFiles",
  "personnelEvaluationTexts",
  "peopleReviewSaveRequests",
  "driveUploadStages",
  "boardingPeriods",
] as const;

export type OneoffWipeTable = (typeof ONEOFF_WIPE_TABLES)[number];

export function isOneoffWipeTable(value: string): value is OneoffWipeTable {
  return (ONEOFF_WIPE_TABLES as readonly string[]).includes(value);
}

/** Department labels used in the teacher sheet → department codes in the CRM catalog. */
export const TEACHER_DEPARTMENT_LABEL_TO_CODE: Record<string, string> = {
  "ngữ văn": "VAN",
  "tiếng anh": "ANH",
  khtn: "KHTN",
  gdcd: "GDCD-GDTC-NT",
  "toán": "TOAN",
  "lịch sử và địa lí": "SU-DIA",
  "công nghệ": "TIN-CN",
  "tin học": "TIN-CN",
};

export const ONEOFF_CONFIRM_PHRASE = "XOA-DU-LIEU-MAU-VA-NHAP-GIAO-VIEN";

export type TeacherInput = {
  name: string;
  email: string;
  department: string;
  /** Homeroom class as written in the sheet, e.g. "8/6". */
  homeroom: string;
};

export type LegacyAccountInput = { newEmail: string; oldEmail: string };

export type PlanUser = {
  _id: string;
  email?: string;
  name?: string;
  role: string;
  status: string;
  departmentId?: string;
  permissionGroupId?: string;
  positionId?: string;
  mustChangePassword?: boolean;
};

export type PlanCatalogRow = { _id: string; code?: string; active?: boolean };
export type PlanClass = { _id: string; code: string; schoolYearId: string; status?: string };
export type PlanAssignment = {
  _id: string;
  classId: string;
  userId: string;
  assignmentType: string;
  active: boolean;
  effectiveTo?: string;
};

export type PlannedTeacher = {
  rowNumber: number;
  name: string;
  email: string;
  role: string;
  departmentId?: string;
  departmentCode?: string;
  permissionGroupId?: string;
  permissionGroupCode?: string;
  positionId?: string;
  positionCode?: string;
  classId: string;
  classCode: string;
  source: "default" | "legacy";
  legacyEmail?: string;
  /** create = new account; exists = account already present (idempotent re-run). */
  action: "create" | "exists";
  existingUserId?: string;
};

export type PlannedAssignment = {
  classId: string;
  classCode: string;
  email: string;
  userId?: string;
  action: "create" | "exists";
};

export type PlannedUserDelete = { userId: string; email: string; role: string; name?: string };

export type TeacherImportPlan = {
  schoolYearId?: string;
  classCodePrefix?: string;
  teachers: PlannedTeacher[];
  assignments: PlannedAssignment[];
  deleteUsers: PlannedUserDelete[];
  missingDeleteEmails: string[];
  errors: string[];
  warnings: string[];
};

export function normalizeTeacherEmail(value: unknown): string {
  return String(value ?? "").trim().toLowerCase();
}

export function normalizeTeacherName(value: unknown): string {
  return String(value ?? "").replace(/\s+/g, " ").trim();
}

/** "2026-2027" → "2627". */
export function classCodePrefixForYear(yearName: string): string | null {
  const match = /^(\d{4})\s*-\s*(\d{4})$/.exec(String(yearName || "").trim());
  if (!match) return null;
  return `${match[1].slice(2)}${match[2].slice(2)}`;
}

/** "8/6" (or "8-6", "Lớp 8/6") → "2627-8-6". */
export function classCodeFromHomeroom(homeroom: string, prefix: string): string | null {
  const match = /(\d{1,2})\s*[/\-.]\s*(\d{1,2})\s*$/.exec(String(homeroom || "").trim());
  if (!match) return null;
  return `${prefix}-${Number(match[1])}-${Number(match[2])}`;
}

function departmentCodeForLabel(label: string): string | null {
  const key = normalizeTeacherName(label).toLowerCase();
  return TEACHER_DEPARTMENT_LABEL_TO_CODE[key] ?? null;
}

export function buildTeacherImportPlan(input: {
  teachers: TeacherInput[];
  legacyAccounts: LegacyAccountInput[];
  deleteEmails: string[];
  actorEmail: string;
  users: PlanUser[];
  departments: PlanCatalogRow[];
  positions: PlanCatalogRow[];
  permissionGroups: PlanCatalogRow[];
  schoolYear: { _id: string; name: string } | null;
  classes: PlanClass[];
  assignments: PlanAssignment[];
  defaults?: { role?: string; permissionGroupCode?: string; positionCode?: string };
}): TeacherImportPlan {
  const errors: string[] = [];
  const warnings: string[] = [];
  const defaults = {
    role: input.defaults?.role ?? "user",
    permissionGroupCode: input.defaults?.permissionGroupCode ?? "TTNV",
    positionCode: input.defaults?.positionCode ?? "GV",
  };

  const usersByEmail = new Map<string, PlanUser>();
  for (const user of input.users) {
    const email = normalizeTeacherEmail(user.email);
    if (email) usersByEmail.set(email, user);
  }
  const byCode = (rows: PlanCatalogRow[]) => {
    const map = new Map<string, PlanCatalogRow>();
    for (const row of rows) if (row.active !== false && row.code) map.set(String(row.code).toUpperCase(), row);
    return map;
  };
  const departments = byCode(input.departments);
  const positions = byCode(input.positions);
  const groups = byCode(input.permissionGroups);
  const defaultGroup = groups.get(defaults.permissionGroupCode);
  const defaultPosition = positions.get(defaults.positionCode);
  if (!defaultGroup) errors.push(`PERMISSION_GROUP_NOT_FOUND:${defaults.permissionGroupCode}`);
  if (!defaultPosition) errors.push(`POSITION_NOT_FOUND:${defaults.positionCode}`);
  const codeById = (rows: PlanCatalogRow[], id?: string) =>
    id ? rows.find((row) => row._id === id)?.code : undefined;

  const actorEmail = normalizeTeacherEmail(input.actorEmail);
  const deleteEmails = [...new Set(input.deleteEmails.map(normalizeTeacherEmail).filter(Boolean))];
  if (deleteEmails.includes(actorEmail)) errors.push(`ACTOR_IN_DELETE_LIST:${actorEmail}`);
  if (!usersByEmail.has(actorEmail)) errors.push(`ACTOR_NOT_FOUND:${actorEmail}`);

  const legacyByNewEmail = new Map<string, string>();
  for (const legacy of input.legacyAccounts) {
    const newEmail = normalizeTeacherEmail(legacy.newEmail);
    const oldEmail = normalizeTeacherEmail(legacy.oldEmail);
    legacyByNewEmail.set(newEmail, oldEmail);
    if (!deleteEmails.includes(oldEmail)) errors.push(`LEGACY_OLD_ACCOUNT_NOT_IN_DELETE_LIST:${oldEmail}`);
  }

  const schoolYear = input.schoolYear;
  const prefix = schoolYear ? classCodePrefixForYear(schoolYear.name) : null;
  if (!schoolYear) errors.push("ACTIVE_SCHOOL_YEAR_NOT_FOUND");
  else if (!prefix) errors.push(`SCHOOL_YEAR_NAME_UNPARSEABLE:${schoolYear.name}`);
  const classesByCode = new Map<string, PlanClass>();
  for (const klass of input.classes) {
    if (schoolYear && klass.schoolYearId === schoolYear._id && klass.status !== "archived") {
      classesByCode.set(klass.code, klass);
    }
  }

  const teachers: PlannedTeacher[] = [];
  const assignments: PlannedAssignment[] = [];
  const seenEmails = new Set<string>();
  const seenClasses = new Set<string>();

  input.teachers.forEach((raw, index) => {
    const rowNumber = index + 2;
    const name = normalizeTeacherName(raw.name);
    const email = normalizeTeacherEmail(raw.email);
    if (!name || name.length > 120) errors.push(`ROW_${rowNumber}:INVALID_NAME`);
    if (!email || !/^\S+@\S+\.\S+$/.test(email) || email.length > 254) {
      errors.push(`ROW_${rowNumber}:INVALID_EMAIL:${email}`);
      return;
    }
    if (seenEmails.has(email)) errors.push(`ROW_${rowNumber}:DUPLICATE_EMAIL:${email}`);
    seenEmails.add(email);
    if (deleteEmails.includes(email)) errors.push(`ROW_${rowNumber}:EMAIL_IN_DELETE_LIST:${email}`);

    const classCode = prefix ? classCodeFromHomeroom(raw.homeroom, prefix) : null;
    const klass = classCode ? classesByCode.get(classCode) : undefined;
    if (!classCode || !klass) {
      errors.push(`ROW_${rowNumber}:CLASS_NOT_FOUND:${raw.homeroom}`);
      return;
    }
    if (seenClasses.has(klass._id)) errors.push(`ROW_${rowNumber}:DUPLICATE_CLASS:${classCode}`);
    seenClasses.add(klass._id);

    const existing = usersByEmail.get(email);
    const legacyEmail = legacyByNewEmail.get(email);
    let planned: PlannedTeacher;
    if (legacyEmail) {
      const old = usersByEmail.get(legacyEmail);
      if (!old && !existing) {
        errors.push(`ROW_${rowNumber}:LEGACY_ACCOUNT_NOT_FOUND:${legacyEmail}`);
        return;
      }
      const template = old ?? existing!;
      planned = {
        rowNumber,
        name,
        email,
        role: template.role,
        departmentId: template.departmentId,
        departmentCode: codeById(input.departments, template.departmentId),
        permissionGroupId: template.role === "user" ? template.permissionGroupId : undefined,
        permissionGroupCode:
          template.role === "user" ? codeById(input.permissionGroups, template.permissionGroupId) : undefined,
        positionId: template.positionId,
        positionCode: codeById(input.positions, template.positionId),
        classId: klass._id,
        classCode,
        source: "legacy",
        legacyEmail,
        action: existing ? "exists" : "create",
        existingUserId: existing?._id,
      };
    } else {
      const departmentCode = departmentCodeForLabel(raw.department);
      const department = departmentCode ? departments.get(departmentCode) : undefined;
      if (!department) errors.push(`ROW_${rowNumber}:DEPARTMENT_NOT_FOUND:${raw.department}`);
      planned = {
        rowNumber,
        name,
        email,
        role: defaults.role,
        departmentId: department?._id,
        departmentCode: departmentCode ?? undefined,
        permissionGroupId: defaultGroup?._id,
        permissionGroupCode: defaultGroup?.code,
        positionId: defaultPosition?._id,
        positionCode: defaultPosition?.code,
        classId: klass._id,
        classCode,
        source: "default",
        action: existing ? "exists" : "create",
        existingUserId: existing?._id,
      };
    }
    if (existing) {
      if (existing.status !== "active") errors.push(`ROW_${rowNumber}:EXISTING_USER_NOT_ACTIVE:${email}`);
      if (existing.role !== planned.role) warnings.push(`ROW_${rowNumber}:EXISTING_USER_ROLE_DIFFERS:${email}`);
    }
    teachers.push(planned);

    const classAssignments = input.assignments.filter(
      (row) => row.classId === klass._id && row.assignmentType === "homeroom_teacher" && row.active && !row.effectiveTo,
    );
    const mine = existing ? classAssignments.find((row) => row.userId === existing._id) : undefined;
    const others = classAssignments.filter((row) => !existing || row.userId !== existing._id);
    if (others.length) errors.push(`ROW_${rowNumber}:CLASS_HAS_OTHER_HOMEROOM_TEACHER:${classCode}`);
    assignments.push({
      classId: klass._id,
      classCode,
      email,
      userId: existing?._id,
      action: mine ? "exists" : "create",
    });
  });

  const deleteUsers: PlannedUserDelete[] = [];
  const missingDeleteEmails: string[] = [];
  for (const email of deleteEmails) {
    const user = usersByEmail.get(email);
    if (!user) {
      missingDeleteEmails.push(email);
      continue;
    }
    deleteUsers.push({ userId: user._id, email, role: user.role, name: user.name });
  }
  const deleteIds = new Set(deleteUsers.map((row) => row.userId));
  const remainingAdmins = input.users.filter(
    (user) => user.role === "admin" && user.status === "active" && !deleteIds.has(user._id),
  );
  const newAdmins = teachers.filter((row) => row.role === "admin" && row.action === "create").length;
  if (remainingAdmins.length + newAdmins === 0) errors.push("NO_ACTIVE_ADMIN_WOULD_REMAIN");
  const stuckAssignments = input.assignments.filter((row) => row.active && deleteIds.has(row.userId));
  for (const row of stuckAssignments) errors.push(`DELETED_USER_HAS_ACTIVE_ASSIGNMENT:${row.userId}:${row.classId}`);

  return {
    schoolYearId: schoolYear?._id,
    classCodePrefix: prefix ?? undefined,
    teachers,
    assignments,
    deleteUsers,
    missingDeleteEmails,
    errors,
    warnings,
  };
}
