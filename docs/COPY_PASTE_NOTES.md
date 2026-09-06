# Copy and paste findings

Checked 2026-09-04. The plan prompt was shortened from 4,399 to 3,510 characters (kg, rest 90) at the owner's request. The example JSON retains exactly the same data; the rules retain the schedule, cycle, rest, progression, timed-set, bodyweight, drop, group, naming, notes, ordering and complete-output requirements. The 4,000-character regression test now matches the prompt.

ChatGPT currently converts pastes over 10,000 characters into attachments. This is a composer behavior, not evidence that the text was truncated. The release notes describe an option to move the attachment back into the text field. The prompt itself is below that threshold, although the user's appended workout description could cross it. [OpenAI release notes, August 4 and June 22, 2026](https://help.openai.com/en/articles/6825453-chatgpt-release-notes).

The app's import limit is 1,048,576 UTF-8 bytes, not characters. Oversized input is rejected before parsing with `E_TOO_LARGE`; the import pipeline never silently clips the original paste. Multibyte text is counted by bytes. Fenced replies, surrounding prose, BOM/zero-width characters and curly quotes are covered by the fixture tests. The plan stores the original source text for copying back out.

A reply cut off mid-object reports `E_NOT_JSON` with an end-of-file/position message. The fix-it prompt retains that message and requests the entire corrected JSON. A syntactically complete plan that a chatbot silently omitted exercises from cannot be detected automatically: the user must compare the preview to the requested workout. The prompt explicitly forbids abbreviated output and exercise removal.

The regression tests include a large valid 31-day, 50-exercise-per-day plan, preservation of its complete source text, a truncated copy of that plan, exactly-at-limit and over-limit inputs, and multibyte input over the byte limit. These test Core string handling, not the system clipboard.

Actual iPhone copying/pasting, paste permissions, rich-text conversion, and the Import editor are pending M4/device validation. The original prompt-pasted and prompt-example fixtures remain unchanged; a separate test covers the new rendered prompt. There is no claim that every chatbot or clipboard implementation accepts the same maximum length.
