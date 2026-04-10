# Offline AI Flutter Demo: Project Overview

## 1. High-Level Architecture
The application is built using **Clean Architecture** patterns combined with **GetX** for dependency injection, state management, and navigation. This enforces a strict separation of concerns, ensuring high maintainability and testability.

### The Stack:
- **Framework:** Flutter
- **State Management & DI:** GetX (`get`)
- **Local Storage:** Hive (`hive_flutter`), GetStorage
- **On-Device AI Engine:** `llamadart` (Llama.cpp wrapper for `.gguf` models)
- **Networking:** Dio (for model downloads and Ollama API), `http`

## 2. Core Application Flow

### Startup and Initialization
1. Initialization checks orientation requirements (locked to portrait).
2. Local databases (Hive) are opened for `ChatMessage` and `DownloadState`.
3. Dependency injection registers essential services in a required sequence: `SettingsService`, `ModelDownloadService`, `FallbackDatasetService`, `DomainService`, `FactualHardeningService`, `OnDeviceInferenceService`, `InferenceRouterService`, and `ModelManagerController`.
4. App launches with a highly aesthetic UI (using `BackdropFilter` and glassmorphism) on the `HomeScreen`.

### Inference Routing (3-Layer Router)
When a user asks a question, the `InferenceRouterService` intercepts it and determines the best backend to use:
1. **On-Device (llamadart):** The primary focus. It utilizes fully local `.gguf` neural models downloaded to the device's application folder.
2. **Local Network (Ollama):** If configured in settings, it checks connectivity to a local Ollama server running on the same network.
3. **Remote API (Gemini):** Served as a fallback if the device has an API key configured and internet access available.

### Domain-Aware Prompting & Factual Hardening
The application features a unique `FactualHardeningService` tailored to combat LLM hallucinations on lightweight on-device models (e.g., LLaMA 3.2 1B/3B).
- **Silent Profiling:** The query is classified into different protocols (`DIRECT`, `NEGATION_TRAP`, `SPLITTER`, `FACT_BLOCK`, `UNCERTAINTY_ANCHOR`).
- **Emergency Sentries:** Hardcoded regex rules intercept medical queries (e.g., "fever 103F", "chest pain", "can't breathe"). If triggered, a strict "MEDICAL ALERT" is yielded instantly, bypassing AI generation entirely to prioritize user safety.
- **RAG (Retrieval-Augmented Generation):** For domains like Bollywood, it injects "Verified Fact Blocks" (e.g., facts about Filmfare 1954 or highest-grossing movies) into the prompt, forcing the LLM to only respond using 100% verified data, drastically cutting down hallucinations.
- **Output Sanitization:** Post-processing prevents raw ChatML tokens from leaking to the UI, enforces a specific UI output format, fixes merged words, and parses numbers and dates (appending `[VERIFY: <value>]` flags).

## 3. Model Management Pipeline
The app completely untethers itself from the internet by managing large AI weights locally via the `ModelDownloadService`:
- Uses **Dio** to perform HTTP range requests downloading multi-gigabyte `.gguf` models.
- Download supports **pausing, resuming, and cancellation** utilizing `CancelToken` and partial file saving (`.part`).
- Hive tracks download progress so that tasks can survive app restarts.
- Upon download completion, a fast 4-byte header check confirms GGUF file integrity before renaming it to the final state.

## 4. UI Layer
The UI centers on:
1. **Chat Page:** A scrolling view with speech bubbles, powered by the local Hive chat box. Status flags show whether the message was auto-routed or generated offline.
2. **Model Manager:** Allows the user to select whether they want to download the 1B Model (~600MB) or 3B Model (~2GB). Memory footprint logic warns users attempting to run 3B maxed setups on lower-tier hardware (like older iPhones with rigid RAM constraints).

## 5. Security & Safety Measures
- Avoids cloud server costs entirely for the core "Powerhouse Mode".
- Ensures users receive zero factual hallucination on critical domains (Hardened RAG blocks & Rule-based Firewalls).
- Data does not leave the phone when offline.
