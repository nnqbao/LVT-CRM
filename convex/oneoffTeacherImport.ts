/**
 * ONE-OFF (2026-10): wipe dummy/test data on the school deployment, delete test accounts,
 * import the teacher list and assign each teacher as homeroom teacher (GVCN) of a class.
 *
 * Internal-only: runnable solely with a deploy key via `convex run`. Remove after use.
 *
 *   convex run oneoffTeacherImport:run '{"dryRun":true, ...}'
 *   convex run oneoffTeacherImport:run '{"dryRun":false,"createdBefore":<snapshotAt>,"confirm":"...", ...}'
 *
 * Order in a real run (each step idempotent, safe to re-run after a partial failure):
 *   1. create teacher accounts (mustChangePassword=true; legacy pairs copy the old account's access)
 *   2. insert homeroom assignments (with audit)
 *   3. hard-delete listed test/legacy users + their auth/session/device/push rows (with audit)
 *   4. wipe dummy business tables, rows created before the dry-run snapshot only
 */
import { createAccount } from "@convex-dev/auth/server";
import { v } from "convex/values";
import { internal } from "./_generated/api";
import type { Id } from "./_generated/dataModel";
import { internalAction, internalMutation, internalQuery } from "./_generated/server";
import {
  buildTeacherImportPlan,
  isOneoffWipeTable,
  ONEOFF_CONFIRM_PHRASE,
  ONEOFF_WIPE_TABLES,
  type TeacherImportPlan,
} from "./oneoffTeacherImportPlan";

const teacherArg = v.object({
  name: v.string(),
  email: v.string(),
  department: v.string(),
  homeroom: v.string(),
});
const legacyArg = v.object({ newEmail: v.string(), oldEmail: v.string() });

const planArgs = {
  teachers: v.array(teacherArg),
  legacyAccounts: v.array(legacyArg),
  deleteEmails: v.array(v.string()),
  actorEmail: v.string(),
  effectiveFrom: v.string(),
};

const SOURCE = "oneoff.teacherImport.202610";
const BATCH = 200;

type Snapshot = {
  snapshotAt: number;
  actorUserId: string | null;
  plan: TeacherImportPlan;
  wipeCounts: Record<string, number>;
  wipeTotal: number;
  driveFileIds: string[];
  authCounts: Record<string, Record<string, number>>;
};

export const snapshot = internalQuery({
  args: planArgs,
  handler: async (ctx, args): Promise<Snapshot> => {
    const snapshotAt = Date.now();
    const users = await ctx.db.query("users").collect();
    const schoolYear =
      (await ctx.db.query("schoolYears").withIndex("by_active", (q) => q.eq("active", true)).first()) ?? null;
    const classes = schoolYear
      ? await ctx.db.query("homeroomClasses").withIndex("by_year", (q) => q.eq("schoolYearId", String(schoolYear._id))).collect()
      : [];
    const plan = buildTeacherImportPlan({
      teachers: args.teachers,
      legacyAccounts: args.legacyAccounts,
      deleteEmails: args.deleteEmails,
      actorEmail: args.actorEmail,
      users: users.map((u) => ({ ...u, _id: String(u._id) })),
      departments: (await ctx.db.query("departments").collect()).map((r) => ({ ...r, _id: String(r._id) })),
      positions: (await ctx.db.query("positions").collect()).map((r) => ({ ...r, _id: String(r._id) })),
      permissionGroups: (await ctx.db.query("permissionGroups").collect()).map((r) => ({ ...r, _id: String(r._id) })),
      schoolYear: schoolYear ? { _id: String(schoolYear._id), name: schoolYear.name } : null,
      classes: classes.map((r) => ({ _id: String(r._id), code: r.code, schoolYearId: r.schoolYearId, status: r.status })),
      assignments: (await ctx.db.query("homeroomAssignments").collect()).map((r) => ({ ...r, _id: String(r._id) })),
    });
    if (!/^\d{4}-\d{2}-\d{2}$/.test(args.effectiveFrom)) plan.errors.push(`INVALID_EFFECTIVE_FROM:${args.effectiveFrom}`);

    const wipeCounts: Record<string, number> = {};
    const driveFileIds: string[] = [];
    for (const table of ONEOFF_WIPE_TABLES) {
      const rows = await ctx.db.query(table as any).collect();
      wipeCounts[table] = rows.length;
      if (table === "officeDocuments" || table === "personnelFaults" || table === "personnelEvaluationFiles") {
        for (const row of rows as any[]) if (row.driveFileId) driveFileIds.push(String(row.driveFileId));
      }
    }
    const wipeTotal = Object.values(wipeCounts).reduce((a, b) => a + b, 0);

    const authCounts: Record<string, Record<string, number>> = {};
    for (const target of plan.deleteUsers) {
      const userId = target.userId as Id<"users">;
      const sessions = await ctx.db.query("authSessions").withIndex("userId", (q) => q.eq("userId", userId)).collect();
      let refreshTokens = 0;
      for (const session of sessions) {
        refreshTokens += (
          await ctx.db.query("authRefreshTokens").withIndex("sessionId", (q) => q.eq("sessionId", session._id)).collect()
        ).length;
      }
      const accounts = await ctx.db.query("authAccounts").withIndex("userIdAndProvider", (q) => q.eq("userId", userId)).collect();
      authCounts[target.email] = {
        authAccounts: accounts.length,
        authSessions: sessions.length,
        authRefreshTokens: refreshTokens,
        deviceSessions: (await ctx.db.query("deviceSessions").withIndex("by_user", (q) => q.eq("userId", userId)).collect()).length,
        pushTokens: (await ctx.db.query("pushTokens").withIndex("by_user", (q) => q.eq("userId", String(userId))).collect()).length,
      };
    }
    const actor = users.find((u) => (u.email ?? "").toLowerCase() === args.actorEmail.trim().toLowerCase());
    return {
      snapshotAt,
      actorUserId: actor ? String(actor._id) : null,
      plan,
      wipeCounts,
      wipeTotal,
      driveFileIds,
      authCounts,
    };
  },
});

export const wipeTableBatch = internalMutation({
  args: { table: v.string(), createdBefore: v.number(), limit: v.optional(v.number()) },
  handler: async (ctx, args) => {
    if (!isOneoffWipeTable(args.table)) throw new Error(`TABLE_NOT_ALLOWED:${args.table}`);
    const rows = await ctx.db
      .query(args.table as any)
      .withIndex("by_creation_time", (q: any) => q.lt("_creationTime", args.createdBefore))
      .take(Math.min(args.limit ?? BATCH, 500));
    for (const row of rows) await ctx.db.delete(row._id);
    return { deleted: rows.length, more: rows.length === Math.min(args.limit ?? BATCH, 500) };
  },
});

/** Deletes one user's auth/device rows in bounded batches; deletes the user row last. */
export const deleteUserBatch = internalMutation({
  args: { userId: v.id("users"), email: v.string(), actorUserId: v.string(), limit: v.optional(v.number()) },
  handler: async (ctx, args) => {
    const budget = Math.min(args.limit ?? 400, 1000);
    let deleted = 0;
    const counts: Record<string, number> = {};
    const del = async (table: string, id: any) => {
      await ctx.db.delete(id);
      deleted += 1;
      counts[table] = (counts[table] ?? 0) + 1;
    };
    const user = await ctx.db.get(args.userId);
    if (user && String(user.email ?? "").toLowerCase() !== args.email.trim().toLowerCase()) {
      throw new Error("USER_EMAIL_MISMATCH");
    }

    const sessions = await ctx.db.query("authSessions").withIndex("userId", (q) => q.eq("userId", args.userId)).collect();
    for (const session of sessions) {
      const tokens = await ctx.db
        .query("authRefreshTokens")
        .withIndex("sessionId", (q) => q.eq("sessionId", session._id))
        .take(budget - deleted);
      for (const token of tokens) await del("authRefreshTokens", token._id);
      if (deleted >= budget) return { done: false, deleted, counts };
      for (const device of await ctx.db.query("deviceSessions").withIndex("by_session", (q) => q.eq("sessionId", session._id)).collect()) {
        await del("deviceSessions", device._id);
      }
      for (const verifier of await ctx.db.query("authVerifiers").collect()) {
        if (verifier.sessionId === session._id) await del("authVerifiers", verifier._id);
      }
      await del("authSessions", session._id);
      if (deleted >= budget) return { done: false, deleted, counts };
    }
    for (const device of await ctx.db.query("deviceSessions").withIndex("by_user", (q) => q.eq("userId", args.userId)).collect()) {
      await del("deviceSessions", device._id);
    }
    for (const token of await ctx.db.query("pushTokens").withIndex("by_user", (q) => q.eq("userId", String(args.userId))).collect()) {
      await del("pushTokens", token._id);
    }
    const accounts = await ctx.db
      .query("authAccounts")
      .withIndex("userIdAndProvider", (q) => q.eq("userId", args.userId))
      .collect();
    const rateLimitKeys = new Set<string>([args.email.trim().toLowerCase()]);
    for (const account of accounts) {
      rateLimitKeys.add(String(account._id));
      for (const code of await ctx.db.query("authVerificationCodes").withIndex("accountId", (q) => q.eq("accountId", account._id)).collect()) {
        await del("authVerificationCodes", code._id);
      }
      await del("authAccounts", account._id);
    }
    for (const key of rateLimitKeys) {
      for (const limit of await ctx.db.query("authRateLimits").withIndex("identifier", (q) => q.eq("identifier", key)).collect()) {
        await del("authRateLimits", limit._id);
      }
    }
    if (user) {
      await ctx.db.delete(user._id);
      counts.users = 1;
      await ctx.db.insert("auditLogs", {
        actorUserId: args.actorUserId,
        action: "user.hard_delete",
        targetUserId: String(args.userId),
        targetEmail: args.email,
        details: JSON.stringify({ source: SOURCE, role: user.role, name: user.name }),
        at: Date.now(),
      });
    }
    return { done: true, deleted, counts };
  },
});

export const insertAssignment = internalMutation({
  args: {
    classId: v.string(),
    userId: v.string(),
    effectiveFrom: v.string(),
    actorUserId: v.string(),
  },
  handler: async (ctx, args) => {
    const classId = ctx.db.normalizeId("homeroomClasses", args.classId);
    const klass = classId ? await ctx.db.get(classId) : null;
    if (!klass || klass.status === "archived") throw new Error(`CLASS_NOT_FOUND:${args.classId}`);
    const userId = ctx.db.normalizeId("users", args.userId);
    const user = userId ? await ctx.db.get(userId) : null;
    if (!user || user.status !== "active") throw new Error(`USER_NOT_FOUND:${args.userId}`);
    const current = (
      await ctx.db
        .query("homeroomAssignments")
        .withIndex("by_class_type", (q) => q.eq("classId", args.classId).eq("assignmentType", "homeroom_teacher"))
        .collect()
    ).filter((row) => row.active && !row.effectiveTo);
    if (current.some((row) => row.userId === args.userId)) return { created: false };
    if (current.length) throw new Error(`CLASS_HAS_OTHER_HOMEROOM_TEACHER:${klass.code}`);
    const now = Date.now();
    const id = await ctx.db.insert("homeroomAssignments", {
      classId: args.classId,
      schoolYearId: klass.schoolYearId,
      userId: args.userId,
      assignmentType: "homeroom_teacher",
      scopeKind: "class",
      effectiveFrom: args.effectiveFrom,
      active: true,
      createdBy: args.actorUserId,
      createdAt: now,
      updatedAt: now,
    });
    await ctx.db.insert("auditLogs", {
      actorUserId: args.actorUserId,
      action: "homeroomAssignment.create",
      targetUserId: args.userId,
      details: JSON.stringify({
        id,
        classId: args.classId,
        classCode: klass.code,
        assignmentType: "homeroom_teacher",
        scopeKind: "class",
        effectiveFrom: args.effectiveFrom,
        source: SOURCE,
      }),
      at: now,
    });
    return { created: true };
  },
});

export const run = internalAction({
  args: {
    ...planArgs,
    dryRun: v.boolean(),
    createdBefore: v.optional(v.number()),
    confirm: v.optional(v.string()),
    temporaryPassword: v.optional(v.string()),
  },
  handler: async (ctx, args): Promise<any> => {
    const { dryRun, createdBefore, confirm, temporaryPassword, ...planInput } = args;
    const snap: Snapshot = await ctx.runQuery(internal.oneoffTeacherImport.snapshot, planInput);
    const { plan } = snap;
    const summary = {
      snapshotAt: snap.snapshotAt,
      errors: plan.errors,
      warnings: plan.warnings,
      missingDeleteEmails: plan.missingDeleteEmails,
      teachersToCreate: plan.teachers.filter((t) => t.action === "create").length,
      teachersExisting: plan.teachers.filter((t) => t.action === "exists").length,
      assignmentsToCreate: plan.assignments.filter((a) => a.action === "create").length,
      assignmentsExisting: plan.assignments.filter((a) => a.action === "exists").length,
      usersToDelete: plan.deleteUsers,
      authCounts: snap.authCounts,
      wipeCounts: snap.wipeCounts,
      wipeTotal: snap.wipeTotal,
      driveFileIds: snap.driveFileIds,
      teachers: plan.teachers.map((t) => ({
        email: t.email,
        name: t.name,
        role: t.role,
        group: t.permissionGroupCode ?? null,
        position: t.positionCode ?? null,
        department: t.departmentCode ?? null,
        class: t.classCode,
        source: t.source,
        action: t.action,
      })),
    };
    if (dryRun) return { dryRun: true, ...summary };

    if (confirm !== ONEOFF_CONFIRM_PHRASE) throw new Error("CONFIRM_PHRASE_REQUIRED");
    if (!createdBefore || createdBefore > snap.snapshotAt) throw new Error("CREATED_BEFORE_REQUIRED");
    if (!temporaryPassword || temporaryPassword.length < 8) throw new Error("TEMP_PASSWORD_TOO_SHORT");
    if (plan.errors.length) throw new Error(`PLAN_HAS_ERRORS:${plan.errors.join(",")}`);
    const actorUserId = snap.actorUserId!;

    // 1. Accounts
    const userIdByEmail = new Map<string, string>();
    let created = 0;
    for (const teacher of plan.teachers) {
      if (teacher.action === "exists") {
        userIdByEmail.set(teacher.email, teacher.existingUserId!);
        continue;
      }
      const now = Date.now();
      const result = await createAccount(ctx, {
        provider: "password",
        account: { id: teacher.email, secret: temporaryPassword },
        profile: {
          email: teacher.email,
          name: teacher.name,
          role: teacher.role,
          departmentId: teacher.departmentId,
          permissionGroupId: teacher.permissionGroupId,
          positionId: teacher.positionId,
          status: "active",
          mustChangePassword: true,
          createdBy: actorUserId,
          updatedBy: actorUserId,
          createdAt: now,
          updatedAt: now,
        } as any,
      });
      const userId = String(result.user._id);
      userIdByEmail.set(teacher.email, userId);
      created += 1;
      await ctx.runMutation(internal.users.audit, {
        actorUserId,
        action: "user.create",
        targetUserId: userId,
        targetEmail: teacher.email,
        details: JSON.stringify({
          source: SOURCE,
          role: teacher.role,
          departmentId: teacher.departmentId,
          permissionGroupId: teacher.permissionGroupId,
          positionId: teacher.positionId,
          legacyEmail: teacher.legacyEmail,
        }),
      });
    }

    // 2. Homeroom assignments
    let assigned = 0;
    for (const assignment of plan.assignments) {
      const userId = userIdByEmail.get(assignment.email);
      if (!userId) throw new Error(`USER_ID_MISSING:${assignment.email}`);
      const result = await ctx.runMutation(internal.oneoffTeacherImport.insertAssignment, {
        classId: assignment.classId,
        userId,
        effectiveFrom: args.effectiveFrom,
        actorUserId,
      });
      if (result.created) assigned += 1;
    }

    // 3. Test / legacy users
    const deletedUsers: Record<string, Record<string, number>> = {};
    for (const target of plan.deleteUsers) {
      const totals: Record<string, number> = {};
      for (let i = 0; i < 100; i += 1) {
        const result = await ctx.runMutation(internal.oneoffTeacherImport.deleteUserBatch, {
          userId: target.userId as Id<"users">,
          email: target.email,
          actorUserId,
        });
        for (const [k, n] of Object.entries(result.counts)) totals[k] = (totals[k] ?? 0) + (n as number);
        if (result.done) break;
      }
      deletedUsers[target.email] = totals;
    }

    // 4. Dummy business tables
    const wiped: Record<string, number> = {};
    for (const table of ONEOFF_WIPE_TABLES) {
      let total = 0;
      for (let i = 0; i < 1000; i += 1) {
        const result = await ctx.runMutation(internal.oneoffTeacherImport.wipeTableBatch, { table, createdBefore });
        total += result.deleted;
        if (!result.more) break;
      }
      wiped[table] = total;
    }

    await ctx.runMutation(internal.users.audit, {
      actorUserId,
      action: "oneoff.teacherImport.run",
      details: JSON.stringify({ source: SOURCE, created, assigned, deletedUsers: Object.keys(deletedUsers), wiped }),
    });
    const after: Snapshot = await ctx.runQuery(internal.oneoffTeacherImport.snapshot, planInput);
    return {
      dryRun: false,
      created,
      assigned,
      deletedUsers,
      wiped,
      after: {
        errors: after.plan.errors,
        teachersExisting: after.plan.teachers.filter((t) => t.action === "exists").length,
        assignmentsExisting: after.plan.assignments.filter((a) => a.action === "exists").length,
        usersStillPresent: after.plan.deleteUsers.map((u) => u.email),
        wipeRemaining: after.wipeCounts,
      },
    };
  },
});
