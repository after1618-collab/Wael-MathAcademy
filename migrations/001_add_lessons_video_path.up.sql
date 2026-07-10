-- Migration 001 UP
--
-- Reason for adding `video_path`:
--   `lessons.video_url` currently mixes TWO different concepts in one column:
--     1) External video URLs (YouTube, Vimeo, Drive, ...)
--     2) Provider-generated URLs for directly uploaded files
--   `video_path` separates storage metadata (the R2 object key / path) from
--   external URLs. This keeps the storage layer provider-independent and
--   matches the image-storage philosophy: store the path, generate the URL
--   at read time via storage.get_url(bucket=..., remote_path=video_path).
--
-- Safe: nullable, does NOT remove `video_url` (backward compatible).
ALTER TABLE lessons ADD COLUMN video_path TEXT NULL;

COMMENT ON COLUMN lessons.video_path IS
  'Storage key (object path) for directly uploaded videos inside Cloudflare R2. '
  'Separates storage metadata from external video URLs (YouTube/Vimeo/Drive) '
  'so the architecture stays provider-independent.';
