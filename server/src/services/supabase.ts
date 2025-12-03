import { createClient, SupabaseClient } from "@supabase/supabase-js";

let supabaseInstance: SupabaseClient | null = null;

const getSupabaseClient = () => {
  if (!supabaseInstance) {
    const supabaseUrl = process.env.SUPABASE_URL;
    const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

    if (!supabaseUrl || !supabaseKey) {
      throw new Error(
        "Missing environment variables: SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY"
      );
    }

    supabaseInstance = createClient(supabaseUrl, supabaseKey, {
      auth: { persistSession: false },
    });
  }
  return supabaseInstance;
};

export const supabase = {
  get client() {
    return getSupabaseClient();
  },
};

// Database Types
export interface Session {
  session_id: string;
  patient_id: string;
  user_id: string;
  start_time: string;
  total_chunks: number;
  uploaded_chunks: number;
  created_at: string;
  updated_at: string;
}

export interface Chunk {
  chunk_id: string;
  session_id: string;
  sequence_number: number;
  upload_time?: string;
  storage_path?: string;
  status: "pending" | "uploaded" | "failed";
  file_size?: number;
  created_at: string;
  updated_at: string;
}

export interface Patient {
  id: string;
  user_id: string;
  name: string;
  phone_number?: string;
  email?: string;
  age?: number;
  gender?: string;
  created_at: string;
  updated_at: string;
}
