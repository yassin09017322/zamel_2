# Manual Testing Instructions

## PendingIndicator verification

1. Launch the app and sign in with a test account.
2. Open any existing chat room or create a new one.
3. Send a message from the signed-in account in a condition where the client has not received the Firestore status update yet.
4. Confirm the own sent message shows the rotating `PendingIndicator` rather than the normal checkmark icon.
5. Observe the indicator only on the local message bubble while the message is still in `MessageStatus.pending`.
6. After the Firestore status is updated, confirm the UI switches to the delivered/seen state icon logic used in the same bubble.

## Expected UI behavior

- In [lib/widgets/message_bubble.dart](lib/widgets/message_bubble.dart#L314-L334), messages with `message.status == MessageStatus.pending` should render the rotating clock icon from [lib/widgets/message_status_indicator.dart](lib/widgets/message_status_indicator.dart).
- The normal message-status icon path remains active for `failed`, `seen`, `read`, and `delivered`.

## Notes

- This is a UI-level manual verification step. A full runtime validation also requires a working Flutter terminal in the local environment.
- If the app is offline or the message write is queued, the pending state is the intended UI signal.
