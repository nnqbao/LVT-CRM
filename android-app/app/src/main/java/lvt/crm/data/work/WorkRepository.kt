package lvt.crm.data.work

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import lvt.crm.data.convex.ConvexConfig
import lvt.crm.data.convex.ConvexException
import lvt.crm.data.convex.ConvexHttpClient
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.File
import java.net.URLEncoder
import java.util.concurrent.TimeUnit

data class WorkUploadedEvidence(
    val driveFileId: String,
    val driveChecksum: String,
    val cleanupToken: String,
    val fileName: String,
    val fileType: String,
    val fileSize: Long,
)

data class WorkTaskItem(
    val id: String,
    val kind: Kind,
    val title: String,
    val deadline: String,
    val status: String,
    val documentContent: String,
    val departmentName: String,
    val qualityPercent: Int?,
    val rejectionReason: String,
    val isAdmin: Boolean,
    val documentTitle: String = "",
    val fileName: String = "",
    val documentId: String = "",
    val fileUrl: String = "",
    val privateFile: Boolean = false,
    val memberNames: List<String> = emptyList(),
    val note: String = "",
) {
    enum class Kind { WorkItem, PersonalTask }
}

data class WorkMemberItem(
    val id: String,
    val name: String,
    val status: String,
)

data class WorkDocumentAssignment(
    val id: String,
    val departmentName: String,
    val content: String,
    val deadline: String,
    val status: String,
    val members: List<WorkMemberItem>,
    val type: String = "",
    val departmentId: String = "",
    val userIds: List<String> = emptyList(),
    val taskCount: Int? = null,
)

data class WorkCompletionReviewItem(
    val workItemId: String,
    val userId: String,
    val userName: String,
    val content: String,
    val deadline: String,
    val departmentName: String,
    val note: String = "",
)

/** One designated Ban giám hiệu approver and their decision on the current submission. */
data class WorkApproverView(
    val id: String,
    val name: String,
    val level: Int = 0,
    val approved: Boolean = false,
    val rejected: Boolean = false,
    val decidedAt: Long? = null,
    val reason: String = "",
)

data class WorkApprovalItem(
    val id: String,
    val fileName: String,
    val content: String,
    val deadline: String,
    /** Document approval status: `pending` | `approved` | `rejected`. */
    val status: String,
    val approvalCount: Int,
    val approvalTotal: Int,
    val myDecision: String,
    val assignments: List<WorkDocumentAssignment> = emptyList(),
    val fileUrl: String = "",
    val privateFile: Boolean = false,
    val title: String = "",
    val canEdit: Boolean = false,
    val canDelete: Boolean = false,
    val documentTypeId: String = "",
    /** List status from the server (`awaiting_approval`, `approval_returned`, `in_progress`, …). */
    val workStatus: String = "",
    /** Created by admin/mod: Ban giám hiệu must approve before release. */
    val requiresApproval: Boolean = false,
    /** First approval locks edit/delete for everyone. */
    val approvalLocked: Boolean = false,
    val submittedAt: Long = 0L,
    val decidedAt: Long? = null,
    val returnReason: String = "",
    val creatorName: String = "",
    /** `admin` | `moderator` | `user` (role kind only). */
    val creatorRole: String = "",
    val approvers: List<WorkApproverView> = emptyList(),
    /** Approval queue only: the current user still has to approve or return it. */
    val awaitingMyDecision: Boolean = false,
    /** Approval queue only: returning is still allowed (nobody approved yet). */
    val canReject: Boolean = false,
)

/** Prefill the create form. Individual assignees are one row each, matching web. */
fun WorkApprovalItem.editAssignments(): List<WorkCreateAssignment> = assignments.flatMap { row ->
    val individual = row.type == "individual" ||
        (row.type.isBlank() && row.departmentId.isBlank() &&
            (row.userIds.isNotEmpty() || row.departmentName == "Cá nhân"))
    if (!individual) {
        return@flatMap listOf(
            WorkCreateAssignment(
                type = "department",
                departmentId = row.departmentId,
                content = row.content,
                deadline = row.deadline,
            ),
        )
    }
    val ids = row.userIds.filter { it.isNotBlank() }.ifEmpty {
        row.members.map { it.id }.filter { it.isNotBlank() }
    }
    val people = ids.ifEmpty { listOf("") }
    people.map { id ->
        WorkCreateAssignment(
            type = "individual",
            userIds = if (id.isBlank()) emptyList() else listOf(id),
            content = row.content,
            deadline = row.deadline,
        )
    }
}

data class WorkSnapshot(
    val assignerMode: String,
    val isAdmin: Boolean,
    val accessLevel: Int,
    val tasks: List<WorkTaskItem>,
    /** Documents the user manages ("Việc tôi tạo", from `work:listAdmin`). */
    val approvals: List<WorkApprovalItem>,
    val completionReviews: List<WorkCompletionReviewItem> = emptyList(),
    val canCreate: Boolean = false,
    val isOps: Boolean = false,
    val documentTypes: List<WorkDocumentType> = emptyList(),
    /** Ban giám hiệu "Chờ tôi duyệt" queue (from `work:listMine.approvals`, 30-day history included). */
    val approvalQueue: List<WorkApprovalItem> = emptyList(),
    val currentUserId: String = "",
)

internal data class ApprovalDecision(
    val userId: String,
    val approved: Boolean,
    val rejected: Boolean,
)

internal fun decisionForUser(currentUserId: String, approvers: List<ApprovalDecision>): String {
    val approver = approvers.firstOrNull { it.userId == currentUserId } ?: return ""
    return when {
        approver.approved -> "approved"
        approver.rejected -> "rejected"
        else -> ""
    }
}

internal fun publicFileUrl(raw: String?): String {
    val value = raw?.trim().orEmpty()
    if (value.isEmpty() || value.equals("null", ignoreCase = true) || value.equals("undefined", ignoreCase = true)) {
        return ""
    }
    if (!value.startsWith("https://") && !value.startsWith("http://")) return ""
    return value
}

private fun JSONObject.optPublicFileUrl(key: String): String {
    if (!has(key) || isNull(key)) return ""
    return publicFileUrl(optString(key, ""))
}

interface WorkOperations {
    suspend fun listMine(): WorkSnapshot
    suspend fun complete(
        item: WorkTaskItem,
        qualityPercent: Int? = null,
        evidence: WorkUploadedEvidence? = null,
        note: String? = null,
        documentTypeId: String? = null,
    )
    suspend fun uploadEvidence(fileBytes: ByteArray, fileName: String, mimeType: String): WorkUploadedEvidence =
        throw UnsupportedOperationException()
    /** Approve, or return with a required [reason] (`work:approveDocument` / `work:rejectDocument`). */
    suspend fun decideApproval(documentId: String, approve: Boolean, reason: String? = null)
    suspend fun reviewCompletion(
        review: WorkCompletionReviewItem,
        approve: Boolean,
        qualityPercent: Int? = null,
        rejectionReason: String? = null,
    )
    suspend fun formOptions(): WorkFormOptions = throw UnsupportedOperationException()
    suspend fun createDocument(
        title: String,
        assignments: List<WorkCreateAssignment>,
        evidence: WorkUploadedEvidence? = null,
        documentTypeId: String? = null,
        approverUserIds: List<String>? = null,
    ): String = throw UnsupportedOperationException()

    suspend fun updateDocument(
        documentId: String,
        title: String,
        assignments: List<WorkCreateAssignment>,
        evidence: WorkUploadedEvidence? = null,
        documentTypeId: String? = null,
        approverUserIds: List<String>? = null,
    ): Unit = throw UnsupportedOperationException()

    suspend fun deleteDocument(documentId: String): Unit = throw UnsupportedOperationException()
}

class WorkRepository(
    private val convex: ConvexHttpClient,
    private val tokenProvider: () -> String? = { null },
    cacheDir: File? = null,
    private val webUrl: String = ConvexConfig.webUrl,
) : WorkOperations {
    private val documentCache = cacheDir?.let { WorkDocumentCache(File(it, "work-documents")) }
    private val downloadHttp = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(180, TimeUnit.SECONDS)
        .writeTimeout(45, TimeUnit.SECONDS)
        .followRedirects(true)
        .build()
    override suspend fun listMine(): WorkSnapshot {
        var result = convex.query("work:listMine")
        if (parseDocumentTypes(result).isEmpty()) {
            runCatching { convex.mutation("documentTypes:ensureDefaults") }
            result = convex.query("work:listMine")
        }
        val isAdmin = result.optBoolean("isAdmin", false)
        val canCreate = result.optBoolean("canCreate", false)
        val accessLevel = result.optInt("level", 0)
        val assignerMode = result.optString("assignerMode", "")
        val currentUserId = result.optString("userId")
        val tasks = mutableListOf<WorkTaskItem>()
        val approvals = mutableListOf<WorkApprovalItem>()
        var isOps = isAdmin

        // Ban giám hiệu approval queue: listMine.approvals (admin/mod never get one).
        val approvalQueue = parseApprovalQueue(result.optJSONArray("approvals"), currentUserId)

        var completionReviews = emptyList<WorkCompletionReviewItem>()
        if (isAdmin || canCreate) {
            val adminResult = convex.query("work:listAdmin")
            isOps = adminResult.optBoolean("isOps", isAdmin)
            val documents = adminResult.optJSONArray("documents") ?: org.json.JSONArray()
            for (i in 0 until documents.length()) {
                val document = documents.getJSONObject(i)
                approvals += parseApproval(document, "")
            }
            completionReviews = parseCompletionReviews(adminResult.optJSONArray("pendingCompletionReviews"))
        } else {
            completionReviews = parseCompletionReviews(result.optJSONArray("pendingCompletionReviews"))
        }

        val myTasks = result.optJSONArray("myTasks")
        if (myTasks != null) {
            for (i in 0 until myTasks.length()) {
                val t = myTasks.getJSONObject(i)
                tasks += WorkTaskItem(
                    id = t.optString("_id"),
                    kind = WorkTaskItem.Kind.WorkItem,
                    title = t.optString("content"),
                    deadline = t.optString("deadline"),
                    status = t.optString("status"),
                    documentContent = t.optString("documentContent"),
                    departmentName = t.optString("departmentName"),
                    qualityPercent = t.optIntOrNull("qualityPercent"),
                    rejectionReason = t.optString("rejectionReason"),
                    isAdmin = isAdmin,
                    documentTitle = t.optString("documentTitle"),
                    fileName = t.optString("fileName"),
                    documentId = t.optString("documentId"),
                    fileUrl = t.optPublicFileUrl("fileUrl"),
                    privateFile = t.optBoolean("privateFile", false),
                    memberNames = t.optJSONArray("members").toMemberNames(),
                    note = t.optWorkNote(),
                )
            }
        }

        val personal = result.optJSONArray("personalTasks")
        if (personal != null) {
            for (i in 0 until personal.length()) {
                val t = personal.getJSONObject(i)
                tasks += WorkTaskItem(
                    id = t.optString("_id"),
                    kind = WorkTaskItem.Kind.PersonalTask,
                    title = t.optString("title").ifBlank { t.optString("documentContent") },
                    deadline = t.optString("deadline"),
                    status = t.optString("status"),
                    documentContent = t.optString("documentContent"),
                    departmentName = t.optString("departmentName"),
                    qualityPercent = t.optIntOrNull("qualityPercent"),
                    rejectionReason = t.optString("rejectionReason"),
                    isAdmin = isAdmin,
                    documentTitle = t.optString("documentTitle"),
                    fileName = t.optString("fileName"),
                    documentId = t.optString("documentId"),
                    fileUrl = t.optPublicFileUrl("fileUrl"),
                    privateFile = t.optBoolean("privateFile", false),
                    memberNames = t.optJSONArray("assignees").toMemberNames(),
                    note = t.optWorkNote(),
                )
            }
        }

        return WorkSnapshot(
            assignerMode = assignerMode,
            isAdmin = isAdmin,
            accessLevel = accessLevel,
            tasks = orderedWorkTasks(tasks),
            approvals = approvals.sortedWith(compareBy<WorkApprovalItem>({ it.status != "pending" }, { it.deadline })),
            completionReviews = completionReviews,
            canCreate = canCreate,
            isOps = isOps,
            documentTypes = parseDocumentTypes(result),
            approvalQueue = approvalQueue,
            currentUserId = currentUserId,
        )
    }

    override suspend fun formOptions(): WorkFormOptions {
        var result = convex.query("work:formOptions")
        var documentTypes = parseDocumentTypes(result)
        if (documentTypes.isEmpty()) {
            convex.mutation("documentTypes:ensureDefaults")
            result = convex.query("work:formOptions")
            documentTypes = parseDocumentTypes(result)
        }
        return parseWorkFormOptions(result, documentTypes)
    }

    override suspend fun createDocument(
        title: String,
        assignments: List<WorkCreateAssignment>,
        evidence: WorkUploadedEvidence?,
        documentTypeId: String?,
        approverUserIds: List<String>?,
    ): String {
        val args = documentMutationArgs(title, assignments, evidence, documentTypeId, approverUserIds)
        return try {
            val result = convex.mutation("work:createDocument", args)
            if (evidence != null && evidence.cleanupToken.isNotBlank()) {
                settleUploadedFile(evidence.cleanupToken, finalize = true)
            }
            result.optString("value").ifBlank { result.optString("_id") }
        } catch (error: Exception) {
            if (evidence != null && evidence.cleanupToken.isNotBlank()) {
                settleUploadedFile(evidence.cleanupToken, finalize = false)
            }
            throw error
        }
    }

    override suspend fun updateDocument(
        documentId: String,
        title: String,
        assignments: List<WorkCreateAssignment>,
        evidence: WorkUploadedEvidence?,
        documentTypeId: String?,
        approverUserIds: List<String>?,
    ) {
        val args = documentMutationArgs(title, assignments, evidence, documentTypeId, approverUserIds)
            .put("documentId", documentId)
        try {
            val result = convex.mutation("work:updateDocument", args)
            if (evidence != null && evidence.cleanupToken.isNotBlank()) {
                settleUploadedFile(evidence.cleanupToken, finalize = true)
            }
            settleCleanupJob(result.optString("cleanupJobId"))
        } catch (error: Exception) {
            if (evidence != null && evidence.cleanupToken.isNotBlank()) {
                settleUploadedFile(evidence.cleanupToken, finalize = false)
            }
            throw error
        }
    }

    override suspend fun deleteDocument(documentId: String) {
        val result = convex.mutation(
            "work:deleteDocument",
            JSONObject().put("documentId", documentId),
        )
        settleCleanupJob(result.optString("cleanupJobId"))
    }

    private fun documentMutationArgs(
        title: String,
        assignments: List<WorkCreateAssignment>,
        evidence: WorkUploadedEvidence?,
        documentTypeId: String?,
        approverUserIds: List<String>?,
    ): JSONObject {
        val args = JSONObject()
            .put("title", title.trim())
            .put("assignments", assignmentPayload(assignments))
        if (!documentTypeId.isNullOrBlank()) {
            args.put("documentTypeId", documentTypeId.trim())
        }
        // Only sent when the form collected approvers; the server decides whether they are needed.
        val approvers = approverUserIds.orEmpty().map { it.trim() }.filter { it.isNotEmpty() }.distinct()
        if (approvers.isNotEmpty()) {
            args.put("approverUserIds", org.json.JSONArray(approvers))
        }
        if (evidence != null) {
            args.put("driveFileId", evidence.driveFileId)
            args.put("driveChecksum", evidence.driveChecksum)
            args.put("cleanupToken", evidence.cleanupToken)
            args.put("fileName", evidence.fileName)
            args.put("fileType", evidence.fileType)
            args.put("fileSize", evidence.fileSize)
        }
        return args
    }

    private fun assignmentPayload(assignments: List<WorkCreateAssignment>) = org.json.JSONArray().apply {
        assignments.forEach { row ->
            put(
                JSONObject().apply {
                    put("type", row.type)
                    put("content", row.content.trim())
                    put("deadline", row.deadline.trim())
                    if (row.isIndividual) {
                        put("userIds", org.json.JSONArray(row.userIds.filter { it.isNotBlank() }))
                    } else {
                        put("departmentId", row.departmentId)
                    }
                },
            )
        }
    }

    override suspend fun complete(
        item: WorkTaskItem,
        qualityPercent: Int?,
        evidence: WorkUploadedEvidence?,
        note: String?,
        documentTypeId: String?,
    ) {
        val args = JSONObject()
        if (qualityPercent != null) {
            args.put("qualityPercent", qualityPercent)
        }
        if (evidence != null) {
            args.put("driveFileId", evidence.driveFileId)
            args.put("driveChecksum", evidence.driveChecksum)
            args.put("cleanupToken", evidence.cleanupToken)
            args.put("fileName", evidence.fileName)
            args.put("fileType", evidence.fileType)
            args.put("fileSize", evidence.fileSize)
        }
        if (!documentTypeId.isNullOrBlank()) {
            args.put("documentTypeId", documentTypeId.trim())
        }
        val trimmedNote = note?.trim().orEmpty()
        if (trimmedNote.isNotEmpty()) {
            args.put("note", trimmedNote.take(500))
        }
        when (item.kind) {
            WorkTaskItem.Kind.WorkItem -> {
                args.put("workItemId", item.id)
                convex.mutation("work:completeWorkItem", args)
            }
            WorkTaskItem.Kind.PersonalTask -> {
                args.put("taskId", item.id)
                convex.mutation("work:completePersonalTask", args)
            }
        }
        if (evidence != null && evidence.cleanupToken.isNotBlank()) {
            settleUploadedFile(evidence.cleanupToken, finalize = true)
        }
    }

    override suspend fun uploadEvidence(fileBytes: ByteArray, fileName: String, mimeType: String): WorkUploadedEvidence = withContext(Dispatchers.IO) {
        if (fileBytes.isEmpty()) {
            throw ConvexException("INVALID_FILE", "Tệp đính kèm không có nội dung.")
        }
        if (fileBytes.size > 20 * 1024 * 1024) {
            throw ConvexException("FILE_TOO_LARGE", "Dung lượng tệp vượt quá giới hạn 20MB.")
        }
        val token = tokenProvider()?.takeIf { it.isNotBlank() }
            ?: throw ConvexException("AUTH_REQUIRED", "Vui lòng đăng nhập lại.")
        val base = webUrl.trimEnd('/')
        val encodedName = URLEncoder.encode(fileName, Charsets.UTF_8.name()).replace("+", "%20")
        val mediaType = mimeType.toMediaTypeOrNull() ?: "application/octet-stream".toMediaType()
        val request = Request.Builder()
            .url("$base/api/files/upload")
            .header("Authorization", "Bearer $token")
            .header("Content-Type", mimeType)
            .header("X-File-Name", encodedName)
            .header("X-LVT-Upload-Purpose", "work")
            .post(fileBytes.toRequestBody(mediaType))
            .build()

        downloadHttp.newCall(request).execute().use { response ->
            val body = response.body?.string().orEmpty()
            if (!response.isSuccessful) {
                val errorJson = runCatching { JSONObject(body) }.getOrNull()
                val code = errorJson?.optString("error")?.takeIf { it.isNotBlank() } ?: "WORK_UPLOAD_FAILED:${response.code}"
                throw ConvexException(code, "Không thể tải bằng chứng lên. Vui lòng thử lại.")
            }
            val json = runCatching { JSONObject(body) }.getOrElse {
                throw ConvexException("WORK_UPLOAD_INVALID_RESPONSE", "Phản hồi tải tệp không hợp lệ.")
            }
            val driveFileId = json.optString("driveFileId")
            val cleanupToken = json.optString("cleanupToken")
            if (driveFileId.isBlank() || cleanupToken.isBlank()) {
                throw ConvexException("WORK_UPLOAD_INVALID_RESPONSE", "Phản hồi tải tệp không hợp lệ.")
            }
            val driveChecksum = json.optString("driveChecksum")
            WorkUploadedEvidence(
                driveFileId = driveFileId,
                driveChecksum = driveChecksum,
                cleanupToken = cleanupToken,
                fileName = fileName,
                fileType = mimeType,
                fileSize = fileBytes.size.toLong(),
            )
        }
    }

    private suspend fun settleCleanupJob(cleanupJobId: String) = withContext(Dispatchers.IO) {
        val jobId = cleanupJobId.trim()
        if (jobId.isEmpty() || jobId == "null") return@withContext
        val token = tokenProvider()?.takeIf { it.isNotBlank() } ?: return@withContext
        val encoded = URLEncoder.encode(jobId, Charsets.UTF_8.name()).replace("+", "%20")
        val request = Request.Builder()
            .url("${webUrl.trimEnd('/')}/api/files/cleanup-jobs/work/$encoded")
            .header("Authorization", "Bearer $token")
            .delete("".toRequestBody("text/plain".toMediaType()))
            .build()
        runCatching { downloadHttp.newCall(request).execute().close() }
    }

    private suspend fun settleUploadedFile(cleanupToken: String, finalize: Boolean) = withContext(Dispatchers.IO) {
        val token = tokenProvider()?.takeIf { it.isNotBlank() } ?: return@withContext
        val encodedToken = URLEncoder.encode(cleanupToken, Charsets.UTF_8.name()).replace("+", "%20")
        val base = webUrl.trimEnd('/')
        val request = Request.Builder()
            .url("$base/api/files/uploads/$encodedToken")
            .header("Authorization", "Bearer $token")
            .method(if (finalize) "POST" else "DELETE", "".toRequestBody("text/plain".toMediaType()))
            .build()
        runCatching { downloadHttp.newCall(request).execute().close() }
    }

    override suspend fun decideApproval(documentId: String, approve: Boolean, reason: String?) {
        if (approve) {
            convex.mutation("work:approveDocument", JSONObject().put("documentId", documentId))
        } else {
            convex.mutation(
                "work:rejectDocument",
                JSONObject().put("documentId", documentId).put("reason", reason?.trim().orEmpty()),
            )
        }
    }

    override suspend fun reviewCompletion(
        review: WorkCompletionReviewItem,
        approve: Boolean,
        qualityPercent: Int?,
        rejectionReason: String?,
    ) {
        val args = JSONObject()
            .put("workItemId", review.workItemId)
            .put("userId", review.userId)
            .put("decision", if (approve) "approve" else "reject")
        if (qualityPercent != null) args.put("qualityPercent", qualityPercent)
        if (!rejectionReason.isNullOrBlank()) args.put("rejectionReason", rejectionReason)
        convex.mutation("work:reviewWorkCompletion", args)
    }

    suspend fun downloadDocument(document: WorkApprovalItem): File = withContext(Dispatchers.IO) {
        val cache = documentCache
            ?: throw ConvexException("WORK_FILE_UNAVAILABLE", "Tệp công văn chưa sẵn sàng để mở.")
        val request: Request
        val sourceIdentity: String
        val publicUrl = publicFileUrl(document.fileUrl)
        if (document.privateFile) {
            val token = tokenProvider()?.takeIf { it.isNotBlank() }
                ?: throw ConvexException("WORK_FILE_FORBIDDEN", "Bạn không còn quyền mở tệp công văn này.")
            val encodedId = URLEncoder.encode(document.id, Charsets.UTF_8.name()).replace("+", "%20")
            val base = webUrl.trimEnd('/')
            val metadataRequest = Request.Builder()
                .url("$base/api/files/$encodedId/metadata")
                .header("Authorization", "Bearer $token")
                .get()
                .build()
            val metadata = downloadHttp.newCall(metadataRequest).execute().use { response ->
                val body = response.body?.string().orEmpty()
                if (!response.isSuccessful) {
                    throw ConvexException("WORK_FILE_FORBIDDEN", "Bạn không còn quyền mở tệp công văn này.")
                }
                runCatching { JSONObject(body) }.getOrElse {
                    throw ConvexException("WORK_FILE_FORBIDDEN", "Bạn không còn quyền mở tệp công văn này.")
                }
            }
            val fileVersion = metadata.optString("fileVersion")
            if (fileVersion.isBlank()) {
                throw ConvexException("WORK_FILE_FORBIDDEN", "Bạn không còn quyền mở tệp công văn này.")
            }
            request = Request.Builder()
                .url("$base/api/files/$encodedId")
                .header("Authorization", "Bearer $token")
                .get()
                .build()
            sourceIdentity = "private:${document.id}:$fileVersion"
        } else if (publicUrl.isNotEmpty()) {
            request = Request.Builder().url(publicUrl).get().build()
            sourceIdentity = "public:${document.id}:$publicUrl"
        } else {
            throw ConvexException("WORK_FILE_UNAVAILABLE", "Tệp công văn chưa sẵn sàng để mở.")
        }
        cache.cachedFile(sourceIdentity)?.let { cached ->
            return@withContext cached
        }
        val tempDir = cacheDirFallback().apply { mkdirs() }
        val downloaded = File.createTempFile("lvt-work-", ".part", tempDir)
        try {
            downloadHttp.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    throw ConvexException("WORK_FILE_DOWNLOAD_FAILED", "Không thể tải tệp công văn. Hãy thử lại.")
                }
                val body = response.body
                    ?: throw ConvexException("WORK_FILE_DOWNLOAD_FAILED", "Không thể tải tệp công văn. Hãy thử lại.")
                body.byteStream().use { input ->
                    downloaded.outputStream().use { output -> input.copyTo(output) }
                }
            }
            if (downloaded.length() <= 0L) {
                throw ConvexException("WORK_FILE_DOWNLOAD_FAILED", "Không thể tải tệp công văn. Hãy thử lại.")
            }
            return@withContext cache.store(
                downloaded,
                sourceIdentity,
                document.fileName.ifBlank { "cong-van" },
            )
        } catch (error: ConvexException) {
            downloaded.delete()
            throw error
        } catch (_: Exception) {
            downloaded.delete()
            throw ConvexException("WORK_FILE_DOWNLOAD_FAILED", "Không thể tải tệp công văn. Hãy thử lại.")
        }
    }

    private fun cacheDirFallback(): File = File(System.getProperty("java.io.tmpdir") ?: ".", "lvt-work-temp")
}

private fun org.json.JSONArray?.toMemberNames(): List<String> {
    if (this == null) return emptyList()
    return List(length()) { index ->
        val member = optJSONObject(index) ?: return@List ""
        member.optString("name").ifBlank { member.optString("email") }
    }.filter { it.isNotBlank() }
}

internal fun parseApprovalQueue(items: org.json.JSONArray?, currentUserId: String): List<WorkApprovalItem> {
    if (items == null) return emptyList()
    return List(items.length()) { index ->
        val document = items.getJSONObject(index)
        val approvers = parseApprovers(document.optJSONArray("approvers"))
        val decision = decisionForUser(
            currentUserId,
            approvers.map { ApprovalDecision(it.id, it.approved, it.rejected) },
        )
        parseApproval(document, decision)
    }
}

internal fun parseApproval(document: JSONObject, myDecision: String) = WorkApprovalItem(
    id = document.optString("_id"),
    fileName = document.optString("fileName"),
    content = document.optString("content"),
    deadline = document.optString("deadline"),
    status = document.optString("status"),
    approvalCount = document.optInt("approvalCount"),
    approvalTotal = document.optInt("approvalTotal"),
    myDecision = myDecision,
    assignments = parseAssignments(document.optJSONArray("assignments")),
    fileUrl = document.optPublicFileUrl("fileUrl"),
    privateFile = document.optBoolean("privateFile", false),
    title = document.optString("title"),
    canEdit = document.optBoolean("canEdit", false),
    canDelete = document.optBoolean("canDelete", false),
    documentTypeId = document.optString("documentTypeId"),
    workStatus = document.optStringOrBlank("workStatus"),
    requiresApproval = document.optBoolean("requiresApproval", false),
    approvalLocked = document.optBoolean("approvalLocked", false),
    submittedAt = document.optLongOrNull("submittedAt") ?: document.optLongOrNull("createdAt") ?: 0L,
    decidedAt = document.optLongOrNull("decidedAt"),
    returnReason = document.optStringOrBlank("returnReason"),
    creatorName = document.optStringOrBlank("creatorName"),
    creatorRole = document.optStringOrBlank("creatorRole"),
    approvers = parseApprovers(document.optJSONArray("approvers")),
    awaitingMyDecision = document.optBoolean("awaitingMyDecision", false),
    canReject = document.optBoolean("canReject", false),
)

internal fun parseApprovers(items: org.json.JSONArray?): List<WorkApproverView> {
    if (items == null) return emptyList()
    return List(items.length()) { index ->
        val item = items.optJSONObject(index) ?: return@List null
        WorkApproverView(
            id = item.optString("_id"),
            name = item.optString("name").ifBlank { item.optString("email") }.ifBlank { "Chưa đặt tên" },
            level = item.optInt("level", 0),
            approved = item.optBoolean("approved", false),
            rejected = item.optBoolean("rejected", false),
            decidedAt = item.optLongOrNull("decidedAt"),
            reason = item.optStringOrBlank("reason"),
        )
    }.filterNotNull().filter { it.id.isNotBlank() }
}

internal fun parseWorkFormOptions(result: JSONObject, documentTypes: List<WorkDocumentType>): WorkFormOptions {
    val departments = result.optJSONArray("departments") ?: org.json.JSONArray()
    val isOps = result.optBoolean("isOps", false)
    return WorkFormOptions(
        canCreate = result.optBoolean("canCreate", false),
        isOps = isOps,
        departments = List(departments.length()) { index ->
            val item = departments.getJSONObject(index)
            WorkFormDepartment(
                id = item.optString("_id"),
                name = item.optString("name"),
            )
        },
        users = parseFormUsers(result.optJSONArray("users")),
        documentTypes = documentTypes,
        requiresApproval = result.optBoolean("requiresApproval", false),
        // Older servers had no flag: only admin/mod assigned whole departments.
        canAssignDepartments = if (result.has("canAssignDepartments") && !result.isNull("canAssignDepartments")) {
            result.optBoolean("canAssignDepartments", isOps)
        } else {
            isOps
        },
        approvers = parseFormUsers(result.optJSONArray("approvers")),
    )
}

private fun parseFormUsers(items: org.json.JSONArray?): List<WorkFormUser> {
    if (items == null) return emptyList()
    return List(items.length()) { index ->
        val item = items.getJSONObject(index)
        WorkFormUser(
            id = item.optString("_id"),
            name = item.optString("name").ifBlank { item.optString("email") },
            departmentName = item.optString("departmentName"),
            level = item.optInt("level", 0),
            positionName = item.optStringOrBlank("positionName"),
        )
    }.filter { it.id.isNotBlank() }
}

private fun JSONObject.optStringOrBlank(key: String): String {
    if (!has(key) || isNull(key)) return ""
    return optString(key, "").trim()
}

private fun JSONObject.optLongOrNull(key: String): Long? {
    if (!has(key) || isNull(key)) return null
    val value = optDouble(key, Double.NaN)
    if (value.isNaN() || value <= 0.0) return null
    return value.toLong()
}

private fun parseAssignments(items: org.json.JSONArray?): List<WorkDocumentAssignment> {
    if (items == null) return emptyList()
    return List(items.length()) { index ->
        val item = items.getJSONObject(index)
        val members = item.optJSONArray("members") ?: org.json.JSONArray()
        val parsedMembers = List(members.length()) { memberIndex ->
            val member = members.getJSONObject(memberIndex)
            WorkMemberItem(
                id = member.optString("_id"),
                name = member.optString("name").ifBlank { member.optString("email") },
                status = member.optString("status"),
            )
        }
        val userIds = item.optJSONArray("userIds")?.let { ids ->
            List(ids.length()) { ids.optString(it) }.filter { it.isNotBlank() }
        }.orEmpty()
        WorkDocumentAssignment(
            id = item.optString("_id"),
            departmentName = item.optString("departmentName"),
            content = item.optString("content"),
            deadline = item.optString("deadline"),
            status = item.optString("status"),
            members = parsedMembers,
            type = item.optString("type"),
            departmentId = item.optString("departmentId"),
            userIds = userIds,
            taskCount = if (item.has("taskCount") && !item.isNull("taskCount")) item.optInt("taskCount") else null,
        )
    }
}

private fun parseCompletionReviews(items: org.json.JSONArray?): List<WorkCompletionReviewItem> {
    if (items == null) return emptyList()
    return List(items.length()) { index ->
        val item = items.getJSONObject(index)
        WorkCompletionReviewItem(
            workItemId = item.optString("workItemId"),
            userId = item.optString("userId"),
            userName = item.optString("userName"),
            content = item.optString("content"),
            deadline = item.optString("deadline"),
            departmentName = item.optString("departmentName"),
            note = item.optString("note").trim(),
        )
    }
}

internal fun needsCompletion(status: String): Boolean = status in setOf(
    "pending_task",
    "pending",
    "overdue",
    "rejected",
    "rejected_completion",
)

internal fun orderedWorkTasks(tasks: List<WorkTaskItem>): List<WorkTaskItem> = tasks.sortedWith(
    compareBy<WorkTaskItem>(
        { !needsCompletion(it.status) },
        { it.deadline },
        { it.title },
    ),
)

private fun JSONObject.optWorkNote(): String {
    val nested = optJSONObject("completion")?.optString("note")?.trim().orEmpty()
    if (nested.isNotEmpty()) return nested
    return optString("note").trim()
}

private fun JSONObject.optIntOrNull(key: String): Int? {
    if (!has(key) || isNull(key)) return null
    return optInt(key)
}

private fun parseDocumentTypes(result: JSONObject): List<WorkDocumentType> {
    val array = result.optJSONArray("documentTypes") ?: return emptyList()
    return List(array.length()) { index ->
        val item = array.optJSONObject(index) ?: return@List WorkDocumentType("", "")
        WorkDocumentType(
            id = item.optString("_id"),
            name = item.optString("name"),
            code = item.optString("code"),
        )
    }.filter { it.id.isNotBlank() && it.name.isNotBlank() }
}
