# Implementation Plan - Instaminion Scheduling & Publishing Integration

This document outlines the detailed layout and integration plan to create the automated scheduling and publishing layers for the "Instaminion" social automation engine.

## User Review Required

> [!IMPORTANT]
> 1. **Meta Graph API Public URL Constraint:** The Meta Graph API requires media files (`image_url`, `video_url`) to be publicly accessible over the internet to download them. For local assets scanned in the directory watcher, in production you must either copy the asset to a public cloud storage bucket (e.g., AWS S3) or serve them over a public tunnel (e.g., ngrok). In our scaffolding, we will pass the local path or a simulated public URL, and log the execution flow transparently.
> 2. **Token Security:** The `InstagramClient` will expect an encrypted access token and include a decryption hook (`decryptToken`) which base64-decodes it for baseline runtime security, matching the specification.

## Proposed Changes

---

### [Component Name] Ingest and State Tracking

#### [NEW] [ingest.go](file:///home/nondeus/Projects/lcpool/core/ingest.go)
Defines:
- `Asset` struct tracking Filename, Absolute Path, Type (image/video), Status (pending/deployed), and timestamps.
- `TrackerData` struct holding the list of assets and the last execution time.
- `StateTracker` struct providing atomic operations to read/write `state.json` tracker file.
- `ScanDirectory(dirPath)`: Scans the target folder for media files (`.jpg`, `.jpeg`, `.png`, `.mp4`). Adds new files as `pending` while leaving existing files untouched.

---

### [Component Name] Meta Graph API Integration

#### [NEW] [instagram.go](file:///home/nondeus/Projects/lcpool/integrations/instagram.go)
Defines:
- `InstagramClient` struct housing the access token, Business ID, and an optimized HTTP client.
- The 3-step Meta Graph API v22.0 Content Publishing Dance:
  - **Step 1 (Container Creation)**: POST to `https://graph.facebook.com/v22.0/{ig-user-id}/media` to register the asset (caption + URL) and retrieve a `container_id`.
  - **Step 2 (Status Polling)**: Uses a `time.Ticker` calling `GET https://graph.facebook.com/v22.0/{container_id}?fields=status_code` every 5 seconds until the status is returned as `"FINISHED"`.
  - **Step 3 (Final Publish)**: POST to `https://graph.facebook.com/v22.0/{ig-user-id}/media_publish` passing the `creation_id` to make the post live.
- Implements robust error handling and structured JSON logging logging Meta API failures (like invalid tokens).

---

### [Component Name] Background Scheduling Engine

#### [NEW] [scheduler.go](file:///home/nondeus/Projects/lcpool/core/scheduler.go)
Defines:
- `Scheduler` loop executing at custom intervals using a `time.Ticker`.
- On execution trigger:
  - Scans the content directory using `StateTracker`.
  - Extracts the first `pending` media asset.
  - Generates an optimal caption/hashtags using the `instagram_creator` bot profile through the `BotPool` (querying our local Gemma-3 Ollama engine).
  - Routes the generated caption along with the asset path directly to the `InstagramClient.Publish` integration pipeline.
  - Updates the asset status to `deployed` in `state.json` and updates the last execution timestamp.

---

## Verification Plan

### Automated Tests
- Create `core/ingest_test.go` verifying state JSON load/save and directory scanning.
- Create `integrations/instagram_test.go` utilizing `httptest.Server` to mock the 3-step Meta Graph API dance, confirming parameters, polling timeouts, and error handling.
- Create `core/scheduler_test.go` to test the integrated scheduling trigger loop.

### Manual Verification
- Register a mock `instagram_creator` bot profile in `cmd/news_bot/main.go`, populate a local `content/` folder with dummy files, and verify the console shows successful scanning, caption generation, and publishing logs.
