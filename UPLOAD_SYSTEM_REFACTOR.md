# Chat System Upload Refactor - Complete Implementation Guide

## Overview
This document outlines all changes made to the chat/messaging system's upload functionality, ensuring reliable file uploads with progress tracking, error handling, and network resilience.

## Files Modified

### 1. lib/services/media_service.dart
**Status**: ✅ COMPLETE

#### New Classes & Structures
- **UploadProgress**: Real-time upload tracking with:
  - uploadedBytes: Current bytes uploaded
  - totalBytes: Total file size
  - percentComplete: Progress percentage (0.0-1.0)
  - elapsedTime: Duration since upload start
  - estimatedRemainingTime: ETA calculation

- **MediaUploadResult**: Enhanced with:
  - mimeType: Detected MIME type
  - detectedFileType: Classification (image|video|audio|file|document|archive)

#### New Methods
- **uploadFileWithProgress()**: Upload with progress callbacks
- **uploadFileWithResultAndProgress()**: Upload with detailed result
- **_detectFileType()**: Automatic file type detection from extension
- **_getMimeType()**: Comprehensive MIME type mapping (50+ types)
- **_isRetryableError()**: Error classification for smart retry logic
- **MediaUploadResultExt.copyWith()**: Result builder pattern

#### Enhancements
- File type detection: PDF, DOC, DOCX, PPT, XLS, ZIP, RAR, 7Z, TAR, GZ, etc.
- MIME type mapping: Complete coverage for all common formats
- File size validation: 500MB limit with pre-upload check
- Progress tracking: onSendProgress callback from Dio
- Improved retry: 3 attempts with exponential backoff (500ms, 1s, 2s)
- Error classification: Retryable (408, 429, 5xx) vs non-retryable (4xx except above)

### 2. lib/models/chat_message.dart
**Status**: ✅ COMPLETE

#### New Fields (Isar @Collection)
```dart
double uploadProgress = 0.0;              // 0.0 to 1.0
String uploadErrorReason = '';            // Error message if failed
int uploadedBytes = 0;                    // Bytes uploaded so far
DateTime uploadStartedAt = ...;           // Retry tracking
```

#### Updated Methods
- **fromFirestore()**: Initialize upload fields from cloud
- **fromJson()**: Deserialize upload tracking data
- **toJson()**: Serialize upload state (local only, not synced)

#### Key Notes
- Upload fields are LOCAL ONLY, not persisted to Firestore
- Automatically reset to defaults in fromFirestore()
- Preserve upload state during Isar sync

### 3. lib/services/chat_service.dart
**Status**: ✅ COMPLETE

#### Breaking Changes
- **REMOVED**: Dual writes to /chats collection
- **CONSOLIDATED**: All writes to /chatRooms only

#### Modified Methods
- sendMessage(): Single write to /chatRooms/{roomId}/messages
- updateMessage(): Single update to /chatRooms only
- updateDisappearingState(): Single update to /chatRooms only
- pinMessage(): Single update to /chatRooms only
- deleteMessage(): Single delete from /chatRooms only

#### Migration Path
- Existing /chats collection can be safely deleted
- No user-facing changes
- All queries updated to use /chatRooms

### 4. lib/screens/chat_room_screen.dart
**Status**: ✅ COMPLETE

#### New Methods
- **retryUpload()**: Retry failed uploads with:
  - State reset (progress = 0, status = pending)
  - Progress tracking during retry
  - Error reason updates
  - User feedback

- **_updateUploadProgress()**: Track upload progress
  - Stores percentage to Isar
  - Triggers UI rebuild
  - Handles null Isar gracefully

- **_updateLocalMessageError()**: Store error details
  - Captures error reason for display
  - Updates Isar
  - Triggers UI rebuild

#### Enhanced Methods
- **_uploadAndSendMedia()**: Comprehensive refactor
  - Initialize upload progress tracking
  - Call onProgress callback during upload
  - Detect file types automatically
  - Update error reason on failure
  - Support all file types: image, video, audio, file/document

- **_monitorMessageCommit()**: Updated to use /chatRooms

- **_markMessagesAsDelivered()**: Consolidated writes

#### Instance Variables
- No new required variables
- All tracking done via ChatMessage fields

### 5. lib/widgets/message_bubble.dart
**Status**: ✅ COMPLETE

#### New Parameter
- **onRetry**: Callback for retry button
  ```dart
  final void Function(ChatMessage)? onRetry;
  ```

#### New UI Elements

**Upload Progress Bar** (when status == pending && mediaType != text)
- Shows: "جاري الرفع... XX%"
- Visual progress bar
- Color-coded (blue/white based on message direction)

**Error Message** (when status == failed && uploadErrorReason != '')
- Red error box with details
- Retry button (if onRetry provided and isMine)
- User-friendly error display

#### Implementation
- No breaking changes to existing parameter
- Backward compatible (onRetry is optional)
- Graceful degradation if onRetry not provided

### 6. Other Services (NOT MODIFIED - Verified)
- **lib/services/audio_service.dart**: Uses standard upload methods ✓
- **lib/services/atyaaf_reel_upload_service.dart**: Uses standard upload methods ✓
- **lib/services/call_service.dart**: Uses updated ChatService correctly ✓

## Key Features

### 1. Automatic File Type Detection
```
Image files: .jpg, .jpeg, .png, .gif, .webp, .svg, .bmp, .ico
Video files: .mp4, .mov, .m4v, .webm, .avi, .mkv, .flv, .wmv, .3gp
Audio files: .mp3, .wav, .m4a, .aac, .flac, .ogg, .wma, .aiff
Documents: .pdf, .doc, .docx, .txt, .xls, .xlsx, .ppt, .pptx, .csv, .json, .xml, .html
Archives: .zip, .rar, .7z, .tar, .gz
```

### 2. Comprehensive MIME Type Mapping
- 50+ file type mappings
- Fallback to application/octet-stream
- Automatic detection based on extension

### 3. Progress Tracking
- Granular byte-level tracking via Dio's onSendProgress
- Real-time UI updates
- ETA calculation capability
- Progress persistence in Isar

### 4. Error Handling
- Network error classification
- Retryable errors: timeout, server errors (5xx), rate limits (429)
- Non-retryable: invalid credentials (401), forbidden (403), not found (404)
- User-friendly error messages
- Error reason storage and display

### 5. Retry Mechanism
- 3 attempts with exponential backoff
- Manual retry via UI button
- Progress reset on retry
- Error reason updates
- Network awareness

### 6. Network Resilience
- Timeout handling: 5-minute limits
- Connection recovery: Automatic retry on network restoration
- Exponential backoff prevents hammering servers
- Graceful degradation on web platform

## Testing Scenarios

### ✅ Text Messages
- Status: Not modified
- Expected: No regression, works as before

### ✅ Image Uploads
- Direct image selection from camera/gallery
- Web: bytes-based upload
- Mobile: file-based upload
- Progress tracking: Real-time
- Error handling: Retry available

### ✅ Video Uploads
- Video file selection
- Dual platform support
- Progress tracking enabled
- Retry mechanism available
- File size validation (≤500MB)

### ✅ File/Document Uploads
- Any file type support
- Type detection: PDF, Word, Excel, PowerPoint, etc.
- File size validation
- Error display with retry
- Progress tracking

### ✅ Audio Uploads
- AudioCommentService integration
- Uses standard upload methods
- No changes required
- Works as before

### ✅ Stories/Reels
- AtyaafReelUploadService integration
- Uses standard upload methods
- No changes required
- Works as before

### ✅ Failed Upload Retry
- Click retry button
- Progress resets to 0%
- Reattempt upload
- Success: Status → sent, progress → 100%
- Failure: Status → failed, error reason updated

### ✅ Network Interruption
- Upload in progress → network cuts
- Timeout after 5 minutes
- Error stored with reason
- User can retry when online
- Progress recovers to current state

### ✅ Large Files
- 500MB+ files: Rejected pre-upload
- 100MB-500MB: Upload with progress
- Multiple retries on failure
- Exponential backoff prevents overload

## Database Changes

### Firestore Structure
**Before**:
```
/chatRooms/{roomId}/messages/{msgId}     (active)
/chats/{roomId}/messages/{msgId}         (redundant, REMOVED)
```

**After**:
```
/chatRooms/{roomId}/messages/{msgId}     (single source of truth)
```

### Isar Schema (ChatMessage)
**New Fields** (local tracking only):
- uploadProgress: double
- uploadErrorReason: string
- uploadedBytes: int
- uploadStartedAt: datetime

## API Compatibility

### ChatService.sendMessage()
- ✅ **No breaking changes**: Signature unchanged
- Internal: Removed /chats write, kept /chatRooms
- Backward compatible with existing callers

### MediaService Upload Methods
- ✅ **Backward compatible**: All existing methods work
- 📍 **New methods**: uploadFileWithProgress() as alternative
- Existing code using uploadFile() continues to work

### ChatMessage Model
- ✅ **New fields**: Optional, default values provided
- ✅ **Backward compatible**: fromFirestore/fromJson handle missing fields
- ✅ **Local only**: Upload fields not synced to Firestore

## Deployment Checklist

- [x] Media upload enhancements (MediaService)
- [x] Chat message model updates (ChatMessage)
- [x] Firestore consolidation (ChatService)
- [x] Upload UI improvements (ChatRoomScreen, MessageBubble)
- [x] Error handling & retry (all components)
- [x] Testing: No regressions in existing features
- [x] No breaking changes to APIs
- [x] All imports and dependencies verified
- [x] Code compiles without errors

## Rollback Plan

If issues occur:
1. Media uploads: Roll back MediaService only (backward compatible)
2. Firestore: /chats collection still exists, can dual-write again
3. Chat UI: Revert ChatRoomScreen & MessageBubble changes

## Performance Implications

- ✅ Upload progress tracking: Negligible (Dio callback)
- ✅ File type detection: Minimal (regex on filename only)
- ✅ MIME type mapping: O(1) lookup from map
- ✅ Error classification: O(1) status code check
- ✅ Firestore consolidation: Reduced write operations by 50%

## Security Considerations

- ✅ No secrets in Flutter code
- ✅ Cloudflare Worker handles all S3/B2 auth
- ✅ File size validation prevents abuse
- ✅ MIME type detection on client (hint only, server validates)
- ✅ Error messages don't leak system details

## Monitoring & Logging

Recommended additions (outside scope):
- Track upload success/failure rates
- Monitor retry frequency per file type
- Log error reasons for debugging
- Measure upload time vs file size
- Alert on high failure rates

## Support & Documentation

- Code comments in Arabic for team understanding
- Clear error messages in Arabic for users
- Inline documentation for new methods
- Structured code following existing patterns
