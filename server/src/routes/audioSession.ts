import { Router, Request, Response } from "express";
import { v4 as uuidv4 } from "uuid";
import { supabase } from "../services/supabase";

const router = Router();

// Supabase storage bucket name
const AUDIO_BUCKET = "audio-chunks";

/**
 * POST /v1/upload-session
 * Start a new recording session
 */
router.post("/v1/upload-session", async (req: Request, res: Response) => {
  console.log("\n📥 [POST /v1/upload-session] Received request");
  console.log("Request body:", JSON.stringify(req.body, null, 2));

  try {
    const { patientId, userId } = req.body;

    if (!patientId || !userId) {
      console.error("❌ Missing required fields:", { patientId, userId });
      return res.status(400).json({
        error: "Missing required fields",
        message: "patientId and userId are required",
      });
    }

    const sessionId = uuidv4();

    // Insert session into database
    const { error: dbError } = await supabase.client.from("sessions").insert({
      session_id: sessionId,
      patient_id: patientId,
      user_id: userId,
      start_time: new Date().toISOString(),
      status: "active",
      total_chunks: 0,
      uploaded_chunks: 0,
    });

    if (dbError) {
      console.error("Database error:", dbError);
      return res.status(500).json({
        error: "Failed to create session",
        message: dbError.message,
      });
    }

    console.log(`📝 Created session: ${sessionId} for patient: ${patientId}`);

    res.status(201).json({
      sessionId,
      uploadUrl: `${
        process.env.BASE_URL || "http://localhost:3000"
      }/api/v1/get-presigned-url`,
    });
  } catch (error: any) {
    console.error("Error creating session:", error);
    res.status(500).json({
      error: "Failed to create session",
      message: error.message,
    });
  }
});

/**
 * POST /v1/get-presigned-url
 * Get a presigned URL for uploading an audio chunk
 */
router.post("/v1/get-presigned-url", async (req: Request, res: Response) => {
  console.log("\n📥 [POST /v1/get-presigned-url] Received request");
  console.log("Request body:", JSON.stringify(req.body, null, 2));

  try {
    const { sessionId, chunkId, sequenceNumber } = req.body;

    if (!sessionId || !chunkId || sequenceNumber === undefined) {
      console.error("❌ Missing required fields:", {
        sessionId,
        chunkId,
        sequenceNumber,
      });
      return res.status(400).json({
        error: "Missing required fields",
        message: "sessionId, chunkId, and sequenceNumber are required",
      });
    }

    // Check if session exists
    const { data: session, error: sessionError } = await supabase.client
      .from("sessions")
      .select("*")
      .eq("session_id", sessionId)
      .single();

    if (sessionError || !session) {
      console.error("❌ Session not found:", sessionId, sessionError);
      return res.status(404).json({
        error: "Session not found",
        message: `Session ${sessionId} does not exist`,
      });
    }

    console.log("✅ Session found:", sessionId);

    // Insert chunk metadata
    const { error: chunkError } = await supabase.client.from("chunks").insert({
      chunk_id: chunkId,
      session_id: sessionId,
      sequence_number: sequenceNumber,
      status: "pending",
    });

    if (chunkError) {
      console.error("❌ Error creating chunk:", chunkError);
      return res.status(500).json({
        error: "Failed to create chunk",
        message: chunkError.message,
      });
    }

    console.log("✅ Chunk metadata created:", { chunkId, sequenceNumber });

    // Generate Supabase Storage signed URL for upload
    const filePath = `${sessionId}/chunk_${String(sequenceNumber).padStart(
      4,
      "0"
    )}_${chunkId}.wav`;

    const { data: uploadData, error: uploadError } =
      await supabase.client.storage
        .from(AUDIO_BUCKET)
        .createSignedUploadUrl(filePath);

    if (uploadError || !uploadData) {
      console.error("Error generating signed URL:", uploadError);
      return res.status(500).json({
        error: "Failed to generate upload URL",
        message: uploadError?.message || "Unknown error",
      });
    }

    // Update total chunks count
    await supabase.client
      .from("sessions")
      .update({ total_chunks: session.total_chunks + 1 })
      .eq("session_id", sessionId);

    console.log(
      `🔗 Generated upload URL for chunk ${sequenceNumber} of session ${sessionId}`
    );
    console.log("📦 File path:", filePath);
    console.log("✅ Total chunks updated:", session.total_chunks + 1);

    res.json({
      presignedUrl: uploadData.signedUrl,
      token: uploadData.token,
      path: uploadData.path,
      chunkId,
      sequenceNumber,
    });
  } catch (error: any) {
    console.error("Error generating presigned URL:", error);
    res.status(500).json({
      error: "Failed to generate presigned URL",
      message: error.message,
    });
  }
});

/**
 * POST /v1/notify-chunk-uploaded
 * Notify server that a chunk has been successfully uploaded
 */
router.post(
  "/v1/notify-chunk-uploaded",
  async (req: Request, res: Response) => {
    console.log("\n📥 [POST /v1/notify-chunk-uploaded] Received request");
    console.log("Request body:", JSON.stringify(req.body, null, 2));

    try {
      const { sessionId, chunkId, sequenceNumber, checksum, fileSize } =
        req.body;

      if (!sessionId || !chunkId || sequenceNumber === undefined) {
        console.error("❌ Missing required fields:", {
          sessionId,
          chunkId,
          sequenceNumber,
        });
        return res.status(400).json({
          error: "Missing required fields",
          message: "sessionId, chunkId, and sequenceNumber are required",
        });
      }

      // Log checksum if provided
      if (checksum) {
        console.log(`📝 Received checksum for chunk ${chunkId}: ${checksum}`);
      }

      // Construct storage path
      const storagePath = `${sessionId}/chunk_${String(sequenceNumber).padStart(
        4,
        "0"
      )}_${chunkId}.wav`;

      // Update chunk status with storage_path, file_size, and checksum (if provided)
      const updateData: any = {
        status: "uploaded",
        upload_time: new Date().toISOString(),
        storage_path: storagePath,
      };

      if (fileSize) {
        updateData.file_size = fileSize;
      }

      if (checksum) {
        // Note: Add checksum column to chunks table if you want to store it
        // For now, we'll just log it
        console.log(`✅ Checksum verification: ${checksum}`);
      }

      const { error: chunkError } = await supabase.client
        .from("chunks")
        .update(updateData)
        .eq("chunk_id", chunkId)
        .eq("session_id", sessionId);

      if (chunkError) {
        console.error("Error updating chunk:", chunkError);
        return res.status(500).json({
          error: "Failed to update chunk",
          message: chunkError.message,
        });
      }

      // Get session and update uploaded chunks count
      const { data: session, error: sessionError } = await supabase.client
        .from("sessions")
        .select("*")
        .eq("session_id", sessionId)
        .single();

      if (!sessionError && session) {
        await supabase.client
          .from("sessions")
          .update({ uploaded_chunks: session.uploaded_chunks + 1 })
          .eq("session_id", sessionId);
      }

      // Get total chunks count
      const { count } = await supabase.client
        .from("chunks")
        .select("*", { count: "exact", head: true })
        .eq("session_id", sessionId);

      const { count: uploadedCount } = await supabase.client
        .from("chunks")
        .select("*", { count: "exact", head: true })
        .eq("session_id", sessionId)
        .eq("status", "uploaded");

      console.log(
        `✅ Chunk ${sequenceNumber} uploaded for session ${sessionId} (${uploadedCount}/${count})`
      );
      console.log(`📁 Storage path: ${storagePath}`);
      if (fileSize) {
        console.log(`📦 File size: ${fileSize} bytes`);
      }

      res.json({
        success: true,
        message: "Chunk upload confirmed",
        sessionId,
        chunkId,
        sequenceNumber,
        totalChunks: count || 0,
        uploadedChunks: uploadedCount || 0,
      });
    } catch (error: any) {
      console.error("Error confirming chunk upload:", error);
      res.status(500).json({
        error: "Failed to confirm chunk upload",
        message: error.message,
      });
    }
  }
);

/**
 * POST /v1/complete-session
 * Mark session as completed
 */
router.post("/v1/complete-session", async (req: Request, res: Response) => {
  console.log("\n📥 [POST /v1/complete-session] Received request");
  console.log("Request body:", JSON.stringify(req.body, null, 2));

  try {
    const { sessionId } = req.body;

    if (!sessionId) {
      console.error("❌ Missing sessionId");
      return res.status(400).json({
        error: "Missing required field",
        message: "sessionId is required",
      });
    }

    // Update session status
    const { error } = await supabase.client
      .from("sessions")
      .update({
        status: "completed",
        end_time: new Date().toISOString(),
      })
      .eq("session_id", sessionId);

    if (error) {
      return res.status(500).json({
        error: "Failed to complete session",
        message: error.message,
      });
    }

    // Get final counts
    const { data: session } = await supabase.client
      .from("sessions")
      .select("*")
      .eq("session_id", sessionId)
      .single();

    const { count: failedCount } = await supabase.client
      .from("chunks")
      .select("*", { count: "exact", head: true })
      .eq("session_id", sessionId)
      .eq("status", "failed");

    console.log(
      `🎉 Session ${sessionId} completed with ${
        session?.uploaded_chunks || 0
      }/${session?.total_chunks || 0} chunks uploaded`
    );

    res.json({
      success: true,
      message: "Session completed",
      sessionId,
      totalChunks: session?.total_chunks || 0,
      uploadedChunks: session?.uploaded_chunks || 0,
      failedChunks: failedCount || 0,
    });
  } catch (error: any) {
    console.error("Error completing session:", error);
    res.status(500).json({
      error: "Failed to complete session",
      message: error.message,
    });
  }
});

/**
 * GET /v1/session/:sessionId
 * Get session details and status
 */
router.get("/v1/session/:sessionId", async (req: Request, res: Response) => {
  console.log("\n📥 [GET /v1/session/:sessionId] Received request");

  try {
    const { sessionId } = req.params;
    console.log("Session ID:", sessionId);

    // Get session data
    const { data: session, error: sessionError } = await supabase.client
      .from("sessions")
      .select("*")
      .eq("session_id", sessionId)
      .single();

    if (sessionError || !session) {
      console.error("❌ Session not found:", sessionId);
      return res.status(404).json({
        error: "Session not found",
        message: `Session ${sessionId} does not exist`,
      });
    }

    console.log("✅ Session retrieved:", session.session_id);

    // Get chunks
    const { data: chunks } = await supabase.client
      .from("chunks")
      .select("*")
      .eq("session_id", sessionId)
      .order("sequence_number");

    const { count: pendingCount } = await supabase.client
      .from("chunks")
      .select("*", { count: "exact", head: true })
      .eq("session_id", sessionId)
      .eq("status", "pending");

    const { count: failedCount } = await supabase.client
      .from("chunks")
      .select("*", { count: "exact", head: true })
      .eq("session_id", sessionId)
      .eq("status", "failed");

    res.json({
      sessionId: session.session_id,
      patientId: session.patient_id,
      userId: session.user_id,
      startTime: session.start_time,
      endTime: session.end_time,
      status: session.status,
      totalChunks: session.total_chunks,
      uploadedChunks: session.uploaded_chunks,
      pendingChunks: pendingCount || 0,
      failedChunks: failedCount || 0,
      chunks: chunks || [],
    });
  } catch (error: any) {
    console.error("Error fetching session:", error);
    res.status(500).json({
      error: "Failed to fetch session",
      message: error.message,
    });
  }
});

/**
 * GET /v1/fetch-session-by-patient/:patientId
 * Get all sessions for a specific patient
 */
router.get(
  "/v1/fetch-session-by-patient/:patientId",
  async (req: Request, res: Response) => {
    console.log(
      "\n📥 [GET /v1/fetch-session-by-patient/:patientId] Received request"
    );

    try {
      const { patientId } = req.params;
      console.log("Patient ID:", patientId);

      // Get all sessions for this patient
      const { data: sessions, error: sessionsError } = await supabase.client
        .from("sessions")
        .select("*")
        .eq("patient_id", patientId)
        .order("start_time", { ascending: false });

      if (sessionsError) {
        console.error("❌ Error fetching sessions:", sessionsError);
        return res.status(500).json({
          error: "Failed to fetch sessions",
          message: sessionsError.message,
        });
      }

      console.log(
        `✅ Retrieved ${
          sessions?.length || 0
        } sessions for patient ${patientId}`
      );

      // Transform to match Flutter model format
      const formattedSessions = (sessions || []).map((session) => ({
        sessionId: session.session_id,
        patientId: session.patient_id,
        userId: session.user_id,
        startTime: session.start_time,
        endTime: session.end_time,
        status: session.status,
        totalChunks: session.total_chunks,
        uploadedChunks: session.uploaded_chunks,
      }));

      res.json({
        sessions: formattedSessions,
      });
    } catch (error: any) {
      console.error("Error fetching patient sessions:", error);
      res.status(500).json({
        error: "Failed to fetch patient sessions",
        message: error.message,
      });
    }
  }
);

/**
 * GET /v1/session/:sessionId/uploaded-chunks
 * Get all uploaded chunks for a session with signed URLs
 */
router.get(
  "/v1/session/:sessionId/uploaded-chunks",
  async (req: Request, res: Response) => {
    console.log(
      "\n📥 [GET /v1/session/:sessionId/uploaded-chunks] Received request"
    );

    try {
      const { sessionId } = req.params;
      console.log("Session ID:", sessionId);

      // Get uploaded chunks
      const { data: chunks, error: chunksError } = await supabase.client
        .from("chunks")
        .select("*")
        .eq("session_id", sessionId)
        .eq("status", "uploaded")
        .order("sequence_number");

      if (chunksError) {
        console.error("❌ Error fetching chunks:", chunksError);
        return res.status(500).json({
          error: "Failed to fetch chunks",
          message: chunksError.message,
        });
      }

      // Generate signed URLs for each chunk
      const chunksWithUrls = await Promise.all(
        (chunks || []).map(async (chunk) => {
          if (!chunk.storage_path) {
            return { ...chunk, signedUrl: null };
          }

          const { data, error } = await supabase.client.storage
            .from(AUDIO_BUCKET)
            .createSignedUrl(chunk.storage_path, 3600); // 1 hour expiry

          if (error) {
            console.error(
              `❌ Error generating signed URL for chunk ${chunk.chunk_id}:`,
              error
            );
            return { ...chunk, signedUrl: null };
          }

          return {
            chunkId: chunk.chunk_id,
            sequenceNumber: chunk.sequence_number,
            uploadTime: chunk.upload_time,
            fileSize: chunk.file_size,
            signedUrl: data.signedUrl,
          };
        })
      );

      console.log(`✅ Retrieved ${chunksWithUrls.length} uploaded chunks`);

      res.json({
        sessionId,
        chunks: chunksWithUrls,
      });
    } catch (error: any) {
      console.error("Error fetching uploaded chunks:", error);
      res.status(500).json({
        error: "Failed to fetch uploaded chunks",
        message: error.message,
      });
    }
  }
);

export default router;
