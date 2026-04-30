# RAG Pipeline Diagnostic Guide

If the system returns "No answer available," use these logs in the Flutter console to identify the break point.

## 1. Startup Diagnostics [DIAG]
These logs appear when the app first launches and initializes `BundledPdfService`.

- `[DIAG] Stored KB version`: Should match `Current KB version`. If not, a re-index is triggered.
- `[DIAG] ObjectBox chunks BEFORE indexing`: If this is `0` on first run, it's normal. If `0` after indexing, the pipeline failed.
- `[DIAG] Asset loaded OK`: Verifies that the PDF files in `assets/pdfs/` are being found and read.
- `[DIAG] ObjectBox chunks AFTER indexing`: Should be `> 0`. For 4 PDFs, you expect `100-200` chunks.

## 2. Ingestion Diagnostics [INGEST]
These logs appear during the re-indexing process.

- `[INGEST] Extracted X chunks from fileName.pdf`: If `X` is `0`, text extraction from the PDF failed.
- `[INGEST] Generated X embedded chunks`: If this is `0` but extraction was `> 0`, the Embedding Service (Isolate) is failing or crashing.

## 3. Retrieval Diagnostics [RAG-DIAG]
These logs appear every time you send a message.

- `[RAG-DIAG] Total chunks in ObjectBox`: If this is `0`, the database is empty. Check Step 1.
- `[RAG-DIAG] Resolved scope`: Shows if the query was mapped to a specific PDF (e.g. `home_loan_faqs`).
- `[RAG-DIAG] Raw results count`: How many chunks were found by vector search.
- `[RAG-DIAG] Top score`: The similarity score of the best match. 
    - **Scoped threshold**: 0.25 (Lower because we are already in the right document)
    - **Unscoped threshold**: 0.40
- `[RAG-DIAG] Match: true/false`: If `false`, the score was too low and "No answer available" is returned.

## 4. Emergency Recovery
If the Knowledge Base is stuck or corrupt:
1. Go to `BundledPdfService.dart`.
2. Locate the `nuclearReset()` method.
3. Call it from a button in the UI or temporarily call it in `init()`.
4. This will wipe everything and perform a fresh, safe re-index.
