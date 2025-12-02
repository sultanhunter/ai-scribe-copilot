import { Router, Request, Response } from "express";
import { v4 as uuidv4 } from "uuid";
import { supabase } from "../services/supabase";

const router = Router();

/**
 * GET /v1/patients
 * Get all patients for a user
 */
router.get("/v1/patients", async (req: Request, res: Response) => {
  console.log("\n📥 [GET /v1/patients] Received request");
  console.log("Query params:", req.query);

  try {
    const { userId } = req.query;

    if (!userId) {
      console.error("❌ Missing userId parameter");
      return res.status(400).json({
        error: "Missing required parameter",
        message: "userId is required",
      });
    }

    const { data: patients, error } = await supabase.client
      .from("patients")
      .select("*")
      .eq("user_id", userId)
      .order("created_at", { ascending: false });

    if (error) {
      console.error("❌ Error fetching patients:", error);
      return res.status(500).json({
        error: "Failed to fetch patients",
        message: error.message,
      });
    }

    console.log(
      `✅ Retrieved ${patients?.length || 0} patients for user ${userId}`
    );

    res.json({
      patients: patients || [],
    });
  } catch (error: any) {
    console.error("Error fetching patients:", error);
    res.status(500).json({
      error: "Failed to fetch patients",
      message: error.message,
    });
  }
});

/**
 * POST /v1/add-patient-ext
 * Add a new patient
 */
router.post("/v1/add-patient-ext", async (req: Request, res: Response) => {
  console.log("\n📥 [POST /v1/add-patient-ext] Received request");
  console.log("Request body:", JSON.stringify(req.body, null, 2));

  try {
    const { name, phoneNumber, email, age, gender, userId } = req.body;

    if (!name || !userId) {
      console.error("❌ Missing required fields:", { name, userId });
      return res.status(400).json({
        error: "Missing required fields",
        message: "name and userId are required",
      });
    }

    const patientId = uuidv4();

    const { data: patient, error } = await supabase.client
      .from("patients")
      .insert({
        id: patientId,
        user_id: userId,
        name,
        phone_number: phoneNumber,
        email,
        age,
        gender,
      })
      .select()
      .single();

    if (error) {
      console.error("Error adding patient:", error);
      return res.status(500).json({
        error: "Failed to add patient",
        message: error.message,
      });
    }

    console.log(`👤 Added patient: ${name} (${patientId})`);

    res.status(201).json(patient);
  } catch (error: any) {
    console.error("Error adding patient:", error);
    res.status(500).json({
      error: "Failed to add patient",
      message: error.message,
    });
  }
});

/**
 * GET /v1/patient/:patientId
 * Get patient details
 */
router.get("/v1/patient/:patientId", async (req: Request, res: Response) => {
  console.log("\n📥 [GET /v1/patient/:patientId] Received request");

  try {
    const { patientId } = req.params;
    console.log("Patient ID:", patientId);

    const { data: patient, error } = await supabase.client
      .from("patients")
      .select("*")
      .eq("id", patientId)
      .single();

    if (error || !patient) {
      console.error("❌ Patient not found:", patientId);
      return res.status(404).json({
        error: "Patient not found",
        message: `Patient ${patientId} does not exist`,
      });
    }

    console.log("✅ Patient retrieved:", patient.name);

    res.json(patient);
  } catch (error: any) {
    console.error("Error fetching patient:", error);
    res.status(500).json({
      error: "Failed to fetch patient",
      message: error.message,
    });
  }
});

export default router;
