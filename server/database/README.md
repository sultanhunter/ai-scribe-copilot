# Supabase Setup Guide

## Database Setup

1. **Create a new Supabase project** at https://supabase.com

2. **Run the schema.sql file**:
   - Go to SQL Editor in your Supabase dashboard
   - Copy and paste the contents of `database/schema.sql`
   - Click "Run" to create all tables and indexes

## Storage Setup

1. **Create a storage bucket**:

   - Go to Storage in your Supabase dashboard
   - Click "New bucket"
   - Name: `audio-chunks`
   - Public: `No` (keep it private)
   - File size limit: `50 MB` (or adjust based on your needs)

2. **Configure storage policies**:

   ```sql
   -- Allow authenticated users to upload
   CREATE POLICY "Allow authenticated uploads"
   ON storage.objects FOR INSERT
   TO authenticated
   WITH CHECK (bucket_id = 'audio-chunks');

   -- Allow authenticated users to read their own files
   CREATE POLICY "Allow authenticated reads"
   ON storage.objects FOR SELECT
   TO authenticated
   USING (bucket_id = 'audio-chunks');
   ```

## Environment Variables

Update your `.env` file with your Supabase credentials:

```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
```

You can find these values in:

- Supabase Dashboard → Settings → API

## Testing

1. Start the server:

   ```bash
   npm run dev
   ```

2. Test the health endpoint:

   ```bash
   curl http://localhost:3000/
   ```

3. Create a test session:
   ```bash
   curl -X POST http://localhost:3000/api/v1/upload-session \
     -H "Content-Type: application/json" \
     -d '{"patientId":"test-patient-id","userId":"test-user-id"}'
   ```

## Database Schema

### Tables

- **patients**: Store patient information
- **sessions**: Recording sessions metadata
- **chunks**: Individual audio chunk metadata

### Key Features

- Automatic timestamps (created_at, updated_at)
- Foreign key relationships
- Status tracking (pending, uploaded, failed)
- Row Level Security (RLS) enabled
- Optimized indexes for queries
