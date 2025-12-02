# AI Scribe Server

Backend server for AI Scribe medical transcription app. Handles real-time audio chunk streaming, patient management, and session tracking.

## Features

- **Audio Session Management**: Create and manage recording sessions
- **Chunk Upload Handling**: Stream audio chunks during recording with presigned URLs
- **Patient Management**: CRUD operations for patient records
- **Cloudinary Integration**: Secure audio file storage in the cloud

## API Endpoints

### Audio Session Routes

#### POST /api/v1/upload-session

Start a new recording session.

**Request Body:**

```json
{
  "patientId": "string",
  "userId": "string"
}
```

**Response:**

```json
{
  "sessionId": "uuid",
  "uploadUrl": "string"
}
```

#### POST /api/v1/get-presigned-url

Get a presigned URL for uploading an audio chunk.

**Request Body:**

```json
{
  "sessionId": "string",
  "chunkId": "string",
  "sequenceNumber": number
}
```

**Response:**

```json
{
  "presignedUrl": "string",
  "uploadParams": {
    "timestamp": number,
    "signature": "string",
    "api_key": "string",
    "public_id": "string",
    "folder": "string",
    "resource_type": "string"
  },
  "chunkId": "string",
  "sequenceNumber": number
}
```

#### POST /api/v1/notify-chunk-uploaded

Confirm that a chunk has been uploaded successfully.

**Request Body:**

```json
{
  "sessionId": "string",
  "chunkId": "string",
  "sequenceNumber": number
}
```

**Response:**

```json
{
  "success": true,
  "message": "Chunk upload confirmed",
  "sessionId": "string",
  "chunkId": "string",
  "sequenceNumber": number,
  "totalChunks": number,
  "uploadedChunks": number
}
```

#### POST /api/v1/complete-session

Mark a recording session as completed.

**Request Body:**

```json
{
  "sessionId": "string"
}
```

#### GET /api/v1/session/:sessionId

Get session details and status.

### Patient Routes

#### GET /api/v1/patients?userId=string

Get all patients for a user.

#### POST /api/v1/add-patient-ext

Add a new patient.

**Request Body:**

```json
{
  "name": "string",
  "userId": "string",
  "phoneNumber": "string (optional)",
  "email": "string (optional)",
  "age": number (optional),
  "gender": "string (optional)"
}
```

#### GET /api/v1/patient/:patientId

Get patient details.

## Setup

### Prerequisites

- Node.js 18+ and npm
- Cloudinary account (for audio storage)

### Installation

1. Install dependencies:

```bash
npm install
```

2. Create `.env` file:

```bash
cp .env.example .env
```

3. Configure environment variables in `.env`:

```env
PORT=3000
NODE_ENV=development

# Cloudinary Configuration
CLOUDINARY_CLOUD_NAME=your_cloud_name
CLOUDINARY_API_KEY=your_api_key
CLOUDINARY_API_SECRET=your_api_secret

BASE_URL=http://localhost:3000
```

### Development

Run the development server with hot reload:

```bash
npm run dev
```

### Production

Build and run:

```bash
npm run build
npm start
```

## Architecture

- **Express.js**: Web framework
- **TypeScript**: Type-safe development
- **Cloudinary**: Cloud storage for audio files
- **In-memory storage**: Currently using Maps (replace with database in production)

## Next Steps

- [ ] Replace in-memory storage with database (PostgreSQL/MongoDB)
- [ ] Add authentication and authorization
- [ ] Implement AI transcription integration
- [ ] Add WebSocket support for real-time updates
- [ ] Implement rate limiting and security headers
- [ ] Add request validation middleware
- [ ] Set up logging and monitoring
