# TESTING GUIDE — Offline AI Flutter Demo
**Version:** 2.0 | **Stack:** Flutter 3.x · GetX · ObjectBox · Hive · llama_cpp_dart · crypto

---

## CATEGORY 1: First Launch Scenarios

| # | Scenario | Steps | Expected Result | Pass Verification | Common Failure & Fix |
|---|---|---|---|---|---|
| 1 | Fresh install, new device | Install APK/run on simulator with no prior data | App opens, chat screen shown, PDF Library empty, drawer accessible | Open drawer → PDF Library shows "No PDFs found" empty state | Hive box open fail → check main.dart openBox calls in try/catch |
| 2 | First launch with 4 bundled PDFs | Place 4 PDFs in assets/pdfs/, run script, `flutter run` | BundledPdfService detects all 4, copies to pdf_library/, starts indexing | Drawer → PDF Library shows 4 cards with "Processing" then "Indexed" | Asset not registered in pubspec.yaml → re-run generate_pdfs.dart |
| 3 | First launch with empty assets/pdfs/ | Remove all PDFs, `flutter run` | App launches without crash, PDF Library shows empty state | No crash in console, empty state UI shown | bundled_pdf_service crashes if no assets → confirmed safe via AssetManifest fallback |
| 4 | Corrupted PDF in assets/pdfs/ | Place a 0-byte or text file renamed to .pdf | App catches exception per file, marks that file "Failed", continues with others | That card shows red "Failed" badge, others index normally | Silent failure → ensure try/catch in `_syncBundledPdfs` per-file loop |
| 5 | Very large PDF (50+ pages) | Place a 50-page PDF in assets/pdfs/ | Indexing runs on background isolate, UI stays responsive | No ANR, card eventually shows "Indexed" with correct page count | OOM on low-RAM → reduce chunk size in DocumentIngestionService |
| 6 | App killed during first-launch indexing | Kill app mid-index, relaunch | Hash not stored (indexing never finished), so re-indexing starts fresh | Second launch re-indexes without duplicate entries in ObjectBox | Duplicate chunks → ensure deleteFromObjectBox called before re-ingest |
| 7 | No LLM model downloaded | Fresh install, ask a question without downloading model | App shows a model-not-found error message, no crash | Chat shows "No model installed" message | Unhandled ModelNotDownloadedException → confirmed handled in respond() |

---

## CATEGORY 2: PDF Library UI Scenarios

| # | Scenario | Steps | Expected Result | Pass Verification | Common Failure & Fix |
|---|---|---|---|---|---|
| 8 | Library shows 4 bundled PDFs | Open drawer → PDF Library | 4 cards shown, each with "Bundled" orange badge and "Indexed" green badge | Count cards = 4, all green | Re-run generate_pdfs.dart + flutter pub get if missing |
| 9 | Badge type display | Upload a PDF manually via FAB, then view library | User PDF shows "Uploaded" badge; bundled PDFs show "Bundled" badge | Source badge text differs per card | source field in PdfDocumentMeta must be set correctly in ingestion |
| 10 | Status badge transitions | Watch a card while indexing | Badge shows "Processing" (yellow) then transitions to "Indexed" (green) or "Failed" (red) | Observe badge change without manual refresh | Missing Obx() rebuild → ensure controller.documents is RxList |
| 11 | Empty state UI | Delete all PDFs from library | Empty state icon + message "No PDFs found in your library" centered on screen | Empty state widget visible, no overflow | mainAxisAlignment fix already applied (MainAxisAlignment.center) |
| 12 | Pull-to-refresh | Pull down on PDF Library list | List reloads from Hive, updated documents shown | Loading indicator appears briefly, list redraws | RefreshIndicator missing onRefresh → ensure controller.loadDocuments called |
| 13 | Delete bundled PDF | Long-press or menu on a bundled PDF card → Delete | PDF removed from library UI, Hive entry deleted, ObjectBox chunks removed | Card disappears, re-ask question → "No answer available" | ObjectBox chunks not deleted → verify deleteFromObjectBox(fileName) |
| 14 | Delete user-uploaded PDF | Upload a PDF, then delete it | Physical file deleted from pdf_library/, Hive entry deleted, ObjectBox cleared | File no longer exists at internalPath | File delete fails → check file permissions on Android |
| 15 | Re-index button | Tap "Re-index" on a Failed card | Old ObjectBox entries deleted, ingestion restarts, status → Processing → Indexed | Card badge changes to green | Controller not finding internalPath → verify meta.internalPath is non-null |
| 16 | Page count and embed date | View any indexed PDF card | Shows "X pages · Indexed on DD/MM/YYYY" | Numbers match the actual PDF | pageCount=0 → ingestDocument result not applied to copyWith |
| 17 | Shimmer/loading state | Open PDF Library before indexing completes | Loading shimmer shown while documents list is being built | Shimmer visible for 1–2 seconds on first load | Missing isLoading state in controller → add RxBool isLoading |

---

## CATEGORY 3: User PDF Upload Scenarios

| # | Scenario | Steps | Expected Result | Pass Verification | Common Failure & Fix |
|---|---|---|---|---|---|
| 18 | Upload valid PDF | Tap "Add PDF" FAB → pick PDF | File copied to pdf_library/, indexed, card appears with green badge | Card shows correct filename, page count | file_picker returns null on Android 13+ → ensure READ_MEDIA_IMAGES permission |
| 19 | Duplicate filename | Upload same-named PDF twice | Second upload either overwrites or is rejected with user feedback | No duplicate cards in library | Check filename uniqueness before copyFileToLibrary |
| 20 | Non-PDF file | Try picking a .docx or .jpg file | File picker filters to PDF only, non-PDF cannot be selected | File picker only shows .pdf files in filter | file_picker allowedExtensions: ['pdf'] must be set |
| 21 | Password-protected PDF | Upload an encrypted PDF | Ingestion fails gracefully, card shows "Failed" badge | Failed badge shown, no app crash | syncfusion_flutter_pdf throws exception → caught in try/catch |
| 22 | Image-only (scanned) PDF | Upload a scanned PDF with no text layer | Indexing completes but 0 chunks extracted, card shows "Indexed" with 0 chunks | Card indexed with chunkCount=0, chat returns "No answer available" | Misleading "Indexed" state → consider showing warning for 0-chunk PDFs |
| 23 | Very large PDF (100+ pages) | Upload a 100-page PDF | Indexing runs in isolate, progress shown, eventually indexed | No ANR, card indexed within reasonable time | Timeout → increase isolate timeout or chunk in batches |
| 24 | Cancel file picker | Tap "Add PDF" then press Back | No crash, no empty card added to library | Library unchanged after cancel | filePicker returns null → ensure null check before processing |
| 25 | Rapid back-to-back uploads | Upload 3 PDFs quickly | All 3 indexed correctly without race conditions | 3 cards visible, all indexed | Race condition in Hive writes → use sequential async processing |
| 26 | Original file deleted | Upload PDF from Downloads, then delete source file | KB still answers questions from internal copy | Question answered correctly, source file gone | Only possible if physical copy was made → verify copyFileToLibrary runs |
| 27 | Storage full during copy | Fill device storage, then upload PDF | Graceful error shown, no corrupted partial file | Error snackbar shown, no broken card in library | IOException → wrap File.copy in try/catch, clean up partial file |

---

## CATEGORY 4: Hash Detection & Re-indexing Scenarios

| # | Scenario | Steps | Expected Result | Pass Verification | Common Failure & Fix |
|---|---|---|---|---|---|
| 28 | Content updated, script rerun | Edit text in generate_pdfs.dart, run script, relaunch app | App computes new hash, detects mismatch, deletes old embeddings, re-indexes | Old answers gone, new answers reflect updated content | Hash stored before indexing completes → hash only written after successful ingest |
| 29 | Content updated, script NOT rerun | Edit config but skip script | PDF bytes unchanged, hash matches, no re-indexing | Same answers as before, no re-index in logs | Correct behavior — no action needed |
| 30 | Two PDFs updated simultaneously | Edit 2 PDFs in config, rerun script | Both PDFs re-indexed, other 2 skipped | Log shows 2 re-indexes, 2 skips | Loop processes each independently — should work by design |
| 31 | Hash box corrupted | Manually delete bundled_pdf_hashes Hive box file | On launch, hash not found → treated as new → re-indexed | All bundled PDFs re-indexed once | Hive.deleteBoxFromDisk only if corruption detected — add to recovery catch |
| 32 | Re-indexing fails halfway | Force an error mid-ingest (e.g. OOM) | Status shows "Failed", hash NOT stored, next launch retries | Next launch re-attempts indexing for that file | Hash written before ingest → bug. Hash must only be written on success |
| 33 | PDF removed from config | Delete a _Pdf entry, rerun script, relaunch app | PDF deleted from assets/, pubspec updated, library entry deleted, ObjectBox chunks removed | Card gone from library, questions about it return "No answer available" | Stale PDF detection in _syncBundledPdfs uses configFileNames set |

---

## CATEGORY 5: RAG & Chat Scenarios

| # | Scenario | Steps | Expected Result | Pass Verification | Common Failure & Fix |
|---|---|---|---|---|---|
| 34 | Question in bundled PDF | Ask "What is an EMI?" | Concise answer from Home Loan FAQ, no repetition, correct sources shown | Answer matches FAQ content, source badge shown | Repetition loop → penalty=1.2 fix applied, deduplication active |
| 35 | Question not in KB | Ask "What is Bitcoin?" | Returns "No answer available." | Exact fallback string shown | LLM hallucinating → topic guard (_isOnTopic) blocks off-topic queries |
| 36 | Multi-PDF question | Ask "What documents do I need for any loan?" | Aggregated answer from multiple loan FAQs | Sources show multiple files | Context deduplication may exclude 2nd chunk → allow same-file chunks with different content |
| 37 | Query during indexing | Upload PDF and immediately ask a question about it | Question returns "No answer available" (not indexed yet) | Correct fallback — not an error | Expected behavior; user should wait for "Indexed" badge |
| 38 | Chat after re-indexing | Re-index a PDF, then ask a related question | Updated answer reflected | New content in answer | Old ObjectBox chunks must be deleted before re-ingest |
| 39 | Chat after deletion | Delete a PDF, ask about its content | Returns "No answer available." | Fallback confirmed | deleteFromObjectBox must remove all chunks with matching source/fileName |
| 40 | Emergency query | Ask about chest pain or seizure | Emergency alert message shown immediately | Hardcoded safety message returned | isEmergency check must precede all RAG lookups |
| 41 | Empty KB query | Ask question with zero indexed PDFs | Returns "No answer available." | Fallback confirmed | Should reach noAnswer() branch in retrieval |
| 42 | Long streaming response | Ask a complex question | Response streams token-by-token without UI freeze | Text appears progressively, no ANR | Stream not yielding → verify yield in respond() |

---

## CATEGORY 6: Model Management Scenarios

| # | Scenario | Steps | Expected Result | Pass Verification | Common Failure & Fix |
|---|---|---|---|---|---|
| 43 | No model downloaded | Launch app without model, go to chat | "No model installed" message shown | ModelNotDownloadedException caught and surfaced | Unhandled exception → wrap inference call in try/catch |
| 44 | Backgrounded during download | Start download, switch to another app | Download continues or pauses cleanly, no crash on return | Resume shows correct progress | Background task cancellation → use foreground service for downloads |
| 45 | Download complete warm-start | Model downloads, immediate warmup | Warmup() auto-triggers after model path set | Model ready indicator updates | warmup() not called → ensure settings listener triggers warmup |
| 46 | Switch model mid-chat | Change model in settings during active conversation | Previous inference cancelled, new model loaded | New responses from new model | Model not reinitialised → call unloadModel() then warmup() on model change |
| 47 | Low RAM, large model | Load 3B model on 3GB RAM device | Graceful OOM handling, error message shown | App doesn't crash, shows error | Native crash → add memory check before model load |
| 48 | Corrupted model file | Replace model with 0-byte file | validateModelFile() catches it, error message shown | "File too small/corrupt" error | File size check in validateModelFile() handles this |
| 49 | Partial download | Interrupt download mid-way | Partial file marked as incomplete, resume supported | Next download attempt resumes or restarts | No resume logic currently → show retry button |

---

## CATEGORY 7: Data Persistence Scenarios

| # | Scenario | Steps | Expected Result | Pass Verification | Common Failure & Fix |
|---|---|---|---|---|---|
| 50 | Kill + relaunch → chat history | Kill app, relaunch | Previous chat messages still visible in history | Navigate to History page, messages present | Hive chatBox not opened → verify openBox<ChatMessage> in main.dart |
| 51 | Kill + relaunch → PDF Library | Kill app, relaunch | All PDF cards still shown with correct statuses | PDF Library shows same cards | PdfDocumentMeta not persisted → verify Hive box opened correctly |
| 52 | Kill + relaunch → model selection | Kill app, relaunch | Previously selected model still selected | Settings page shows same model | GetStorage persists modelPathKey → verified |
| 53 | Clear app data | Settings → Clear App Data | All Hive boxes reset, ObjectBox cleared, model selection gone | Fresh first-launch experience | Hive adapter not re-registered on clean open → adapters always registered |
| 54 | App version upgrade | Upgrade APK with new Hive fields | Existing data migrates, no crash | Old chat history preserved | Hive field index conflicts → always use explicit field IDs in adapters |
| 55 | Hive box open fails | Corrupt Hive file | App catches exception, deletes corrupt box, recreates | App launches with empty state instead of crashing | try/catch in main.dart already handles this |
| 56 | ObjectBox corrupted | Delete/corrupt objectbox DB files | App either recovers or resets gracefully | No crash, PDF re-indexing on next bundled PDF detection | ObjectBox has built-in recovery; worst case delete and rebuild |

---

## CATEGORY 8: Concurrent & Performance Scenarios

| # | Scenario | Steps | Expected Result | Pass Verification | Common Failure & Fix |
|---|---|---|---|---|---|
| 57 | Chat query during PDF indexing | Start indexing a large PDF, immediately send a chat message | Both operations complete without deadlock | Chat responds, PDF eventually indexed | Isolate contention → each uses separate isolate/async |
| 58 | Rapid consecutive queries | Send 2 chat messages before first completes | Second query queued or first cancelled cleanly | No duplicate responses, no crash | No queue implemented → second call creates race; add mutex or cancel first |
| 59 | Indexing in background | Upload PDF, immediately background the app | Indexing continues in isolate | Return to app → card shows Indexed | Dart isolate continues even when app backgrounded |
| 60 | 60 FPS during embedding | Generate embeddings for large PDF | UI stays smooth (no jank) | Use Flutter DevTools frame graph | Embedding on main thread → must run in isolate (already done) |
| 61 | Memory during large PDF | Ingest a 100-page PDF | RAM stays below 500MB on mid-range device | Android Memory Profiler | Large byte arrays → dispose after embedding, don't hold all pages in memory |
| 62 | ObjectBox with 1000+ chunks | Index 10+ large PDFs | Vector search still returns results in <500ms | Log timestamps in RagRetrievalService | Increase HNSW neighbors param if accuracy drops with large corpus |

---

## CATEGORY 9: Navigation & UI Scenarios

| # | Scenario | Steps | Expected Result | Pass Verification | Common Failure & Fix |
|---|---|---|---|---|---|
| 63 | Open PDF Library from drawer | Tap hamburger → PDF Library | Correct screen loads with correct title | "PDF Library" AppBar title visible | Wrong route → verify Get.to<PdfLibraryPage>() in AppDrawer |
| 64 | Navigate away mid-indexing | Start indexing, go back to chat | Indexing continues in background | Return to library → card shows updated status | GetX controller disposed on nav → use Get.put with permanent: true |
| 65 | Back button from PDF Library | Tap back/system back | Returns to Chat screen | Chat screen visible | Navigator stack correct |
| 66 | Keyboard dismissal | Tap outside chat input field | Keyboard dismisses | Keyboard hidden | GestureDetector with FocusScope.unfocus() needed |
| 67 | Dark mode glassmorphism | Enable dark mode in settings | Glassmorphism cards render correctly with blur | Cards visible, blur effect active | BackdropFilter needs opaque parent — check Stack/Material setup |
| 68 | Small screen (4-inch) | Run on low-res emulator | No RenderFlex overflow errors | Zero overflow errors in console | Use Flexible/Expanded instead of fixed widths |
| 69 | Landscape orientation | Rotate device to landscape | Layout adapts, no overflow | No overflow, content accessible | Use MediaQuery to adjust padding/columns |

---

## CATEGORY 10: Developer Workflow Scenarios

| # | Scenario | Steps | Expected Result | Pass Verification | Common Failure & Fix |
|---|---|---|---|---|---|
| 70 | Add new PDF via script | Add _Pdf entry, run script, flutter run | New PDF appears in library, indexed | New card visible in PDF Library | pubspec.yaml not updated → script auto-updates it |
| 71 | Update PDF content via script | Edit content, rerun script, relaunch app | Hash mismatch detected, re-indexing triggered | Updated answer in chat | Hash written before ingest → ensure hash only written after success |
| 72 | Remove PDF via script | Delete _Pdf entry, rerun script | PDF deleted from assets, pubspec, service, library, ObjectBox | No card in library, no answer from that content | Stale entry cleanup in _syncBundledPdfs |
| 73 | Run script twice, no changes | Run script twice without changing config | Same PDFs regenerated, same hashes, no re-indexing | No new cards, no re-index in logs | Script is idempotent — confirmed by file overwrite behavior |
| 74 | Malformed text content | Add empty or null-like content to _Pdf entry | Script generates a near-empty PDF, app indexes with 0 chunks | 0-chunk card, "No answer available" in chat | syncfusion handles empty content — add minimum content validation in script |
| 75 | pubspec.yaml auto-update | Run script | Auto-generated PDF block updated between BEGIN/END markers | Only PDF assets block changed, rest intact | Markers missing → script falls back to replacing `- assets/pdfs/` line |
| 76 | bundled_pdf_service.dart auto-update | Run script | _bundledPdfAssets list contains exactly the PDFs in config | Grep the list, verify file count matches | Markers not found → script adds list if class found |

---

## CATEGORY 11: Edge Cases & Stress Scenarios

| # | Scenario | Steps | Expected Result | Pass Verification | Common Failure & Fix |
|---|---|---|---|---|---|
| 77 | Upload 20 PDFs consecutively | Use FAB to add 20 PDFs one after another | All 20 indexed without crash or memory leak | 20 cards in library, all Indexed | Sequential processing prevents overload |
| 78 | Filename with special chars | Upload "my file (1) — résumé.pdf" | File saved internally with sanitized name, card shows original name | No crash, card visible | File path issues → sanitize filename before File creation |
| 79 | Extremely long paragraph PDF | PDF with one 10,000-word paragraph | Chunker splits it correctly | Multiple chunks stored, answer retrieved | Chunker must handle no-newline content |
| 80 | Internet lost mid-Ollama call | Use Ollama backend, cut WiFi during response | DioException caught, error message shown in chat | Error shown, no crash | DioExceptionType.connectionError caught in _streamOllama |
| 81 | Device storage at 0 bytes | Fill device storage completely before upload | IOException caught, user shown storage error | Error shown, no broken PDF card | wrap File.writeAsBytes in try/catch |
| 82 | Phone call during inference | Receive call while LLM is generating | Inference pauses or continues in isolate | App not crashed after call ends | Dart isolate unaffected by phone calls |
| 83 | Screen rotation during streaming | Rotate device while response is streaming | Streaming continues, UI re-renders correctly | Response still flowing, no duplicate text | GetX Obx() rebuilds correctly on rotation |
| 84 | Rapid "Add PDF" taps | Tap FAB 5 times quickly | File picker opens only once or requests debounced | Single file picker dialog | Add a bool guard or debounce on addNewPdf() |

---

## PRIORITY LIST — Top 10 to Test Before Release

| Priority | # | Scenario | Why Critical |
|---|---|---|---|
| 1 | 2 | First launch with bundled PDFs | Core feature — must work on all devices |
| 2 | 34 | Question answered by bundled PDF | Core RAG accuracy |
| 3 | 35 | Question NOT in KB → fallback | Prevents hallucination |
| 4 | 18 | User uploads valid PDF | Primary user action |
| 5 | 28 | Content updated, re-indexed | Developer workflow integrity |
| 6 | 50 | Chat history preserved after kill | Data safety |
| 7 | 13 | Delete PDF from library | Data management |
| 8 | 42 | Long streaming response | UX quality |
| 9 | 55 | Hive box open failure | Crash prevention |
| 10 | 57 | Chat query during PDF indexing | Concurrency safety |

---

## REGRESSION CHECKLIST — 15 Must-Pass After Any Code Change

```
[ ] 1.  App launches without crash on Android physical device
[ ] 2.  4 bundled PDFs appear in library on first launch
[ ] 3.  "What is an EMI?" returns correct answer from Home Loan FAQ
[ ] 4.  "What is Bitcoin?" returns "No answer available."
[ ] 5.  Uploading a new PDF creates a card with "Processing" then "Indexed"
[ ] 6.  Deleting a PDF removes its card and clears ObjectBox embeddings
[ ] 7.  Re-index button on Failed card retriggers ingestion
[ ] 8.  Chat history persists across app kill and relaunch
[ ] 9.  PDF Library state persists across app kill and relaunch
[ ] 10. Running generate_pdfs.dart twice produces identical results (idempotent)
[ ] 11. Editing a PDF in config + rerun script triggers re-index on next launch
[ ] 12. Removing a PDF from config + rerun script removes it from library
[ ] 13. pubspec.yaml BEGIN/END markers remain intact after script runs
[ ] 14. App does not crash when assets/pdfs/ is empty
[ ] 15. Emergency query (e.g. "chest pain") returns safety alert, not LLM answer
```

---

## DEVELOPER WORKFLOW TEST — Full End-to-End Validation

```bash
# ─── STEP 1: Add a new PDF ───────────────────────────────────────────────────
# Open scripts/generate_pdfs.dart
# Add this entry to pdfContents list:
#   _Pdf(
#     fileName: 'test_doc.pdf',
#     title: 'Test Document',
#     content: 'TEST ANSWER: The capital of France is Paris.',
#   ),

cd scripts
dart run generate_pdfs.dart
# Expected output:
#   ✅ Generated: test_doc.pdf
#   📋 pubspec.yaml updated
#   🔧 bundled_pdf_service.dart updated

cd ..
flutter pub get
flutter run

# IN APP: Open drawer → PDF Library
# Expected: "test_doc.pdf" card appears with "Indexed" badge

# IN APP: Chat → "What is the capital of France?"
# Expected: "Paris" answer with source "test_doc.pdf"


# ─── STEP 2: Update PDF content ──────────────────────────────────────────────
# In generate_pdfs.dart, change content to:
#   'TEST ANSWER: The capital of Germany is Berlin.'

cd scripts && dart run generate_pdfs.dart && cd ..
flutter run

# Expected in logs: "[BundledPdfService] 🔄 Content changed: test_doc.pdf — re-indexing..."
# IN APP: Chat → "What is the capital of France?" → "No answer available."
# IN APP: Chat → "What is the capital of Germany?" → "Berlin"


# ─── STEP 3: Remove PDF ──────────────────────────────────────────────────────
# In generate_pdfs.dart, delete the test_doc _Pdf entry entirely

cd scripts && dart run generate_pdfs.dart && cd ..
# Expected: assets/pdfs/test_doc.pdf deleted

flutter run
# Expected in logs: "[BundledPdfService] Removing stale bundled PDF: test_doc.pdf"
# IN APP: PDF Library → "test_doc.pdf" card gone
# IN APP: Chat → "What is the capital of Germany?" → "No answer available."


# ─── STEP 4: Verify idempotency ──────────────────────────────────────────────
cd scripts && dart run generate_pdfs.dart && dart run generate_pdfs.dart
# Expected: Same files, no duplicates, pubspec unchanged
```

---

## KNOWN GOTCHAS — Flutter/ObjectBox/Hive on This Stack

| # | Gotcha | Description | How to Avoid |
|---|---|---|---|
| 1 | **Hive adapter type ID collision** | Two adapters with same typeId silently overwrite each other | Always use unique explicit `@HiveType(typeId: N)` across all models |
| 2 | **Hive box opened twice** | Opening the same box twice causes exception | Always check `Hive.isBoxOpen()` before `Hive.openBox()` |
| 3 | **ObjectBox on main thread** | Heavy ObjectBox queries on main thread cause jank | Run `store.box<>().query().build().find()` inside `compute()` or isolate |
| 4 | **GetX controller early disposal** | Controller disposed when navigating away, breaking background tasks | Register long-lived controllers with `Get.put(..., permanent: true)` |
| 5 | **file_picker Android 13+** | READ_EXTERNAL_STORAGE deprecated, need READ_MEDIA_DOCUMENTS | Add correct permissions to AndroidManifest.xml |
| 6 | **Dart isolate & GetX** | GetX services not accessible inside isolates | Pass only primitive data across isolate boundaries via SendPort |
| 7 | **Hive on background isolate** | Hive boxes not available in spawned isolates | Use regular file I/O or pass data via isolate message |
| 8 | **ObjectBox HNSW index rebuild** | Adding new entities doesn't update HNSW index if store not reopened | Close and reopen the store, or use `chunkBox.put()` properly |
| 9 | **sha256 on large files** | Computing hash of a 50MB PDF on main thread blocks UI | Run `sha256.convert(bytes)` inside a `compute()` call |
| 10 | **pdf package font encoding** | Default pdf package font doesn't support non-Latin characters | Import and register a Unicode font (e.g. NotoSans) in the pdf Document |
| 11 | **syncfusion_flutter_pdf trial watermark** | Community license adds watermark to generated PDFs | Register for a free community license at syncfusion.com |
| 12 | **path_provider on Android** | `getApplicationDocumentsDirectory()` returns different path pre/post Android 11 | Always use path_provider — never hardcode paths |
| 13 | **flutter_animate Curves.backOut** | `Curves.backOut` does not exist in Flutter — use `Curves.easeOutBack` | Already fixed in this codebase |
| 14 | **LLM repetition loop at temp=0.0** | Greedy decoding (temp=0) makes the model loop on ambiguous context | Keep temp >= 0.1 and penalty >= 1.2 (already applied) |
| 15 | **Silent Hive migration failure** | Adding a new field to a Hive model without a default causes NPE on old data | Always provide default values and use nullable types for new fields |
