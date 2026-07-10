-- Migration 001 DOWN
-- Reverts 001 UP: drops the video_path column (and its COMMENT automatically).
-- Only safe while no application code depends on video_path (verified: none).
ALTER TABLE lessons DROP COLUMN video_path;
