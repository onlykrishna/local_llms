# 🚀 Offline AI Flutter Demo: Local LLMs with Clean Architecture

A high-performance, premium Flutter application demonstrating how to build a **completely offline AI assistant**. This app leverages local Large Language Models (LLMs) via Ollama while implementing a multi-layered fallback system to ensure it *never* stops providing intelligent-like responses, even when disconnected from the server.

---

## ✨ Key Features

1.  **🚀 Hybrid Intelligence System**:
    *   **Primary Mode**: Connects to local Ollama server (Mistral, LLaMA 2, etc.) for real-time, high-quality reasoning.
    *   **Offline Mode**: Automatic, zero-latency fallback to a bundled JSON dataset with 60+ categorized responses (Flutter, Coding, Greetings, AI tips).
    *   **Streaming Logic**: Both Ollama and the fallback service simulate real-time token-by-token generation for a premium experience.
2.  **🛡️ Clean Architecture**:
    *   Strict separation of concerns (Core, Domain, Data, Presentation).
    *   Dependency Injection (DI) using GetX for a decoupled and testable codebase.
3.  **📦 Local Data Persistence**:
    *   Uses **Hive** (NoSQL) for ultra-fast, encrypted chat history storage.
    *   Uses **GetStorage** for persistent user preferences (Theme, Selected Model).
4.  **💎 Premium Material 3 UI**:
    *   **Gradients & Glassmorphism**: Interactive chat bubbles with user-specific gradients.
    *   **Auto-Scroll & Typing**: Intelligent scrolling and animated typing indicators.
    *   **Real-time Binary Status**: A dynamic top banner alerts users if the Ollama server is offline.
5.  **⚙️ Multi-Model Support**: Dropdown to switch between various local models (`mistral`, `llama2`, `codellama`, `phi`).

---

## 🛠️ Tech Stack & Packages

| Package | Purpose |
| :--- | :--- |
| **`get`** | State Management, Routing, and Dependency Injection. |
| **`get_storage`** | Fast persistence for user settings (Theme, Model). |
| **`hive`** | Lightweight & fast NoSQL database for chat history. |
| **`http`** | Handling streaming REST API calls to the Ollama server. |
| **`flutter_markdown`** | Rendering AI responses with full code highlighting and bold text. |
| **`flutter_spinkit`** | Beautiful, animated typing indicators. |
| **`intl`** | Date/Time formatting for message timestamps. |
| **`uuid`** | Generating unique IDs for each message and chat session. |
| **`google_fonts`** | Implementing the "Inter" typography for a modern aesthetic. |

---

## 🏗️ Architecture Overview

The project follows a strict **Clean Architecture** pattern to ensure the codebase remains scalable:

*   **`core/`**: Shared services (Settings, Fallback Dataset), constants, and the app's design system/theme.
*   **`domain/`**: Pure Dart logic. Contains Entities (`ChatMessage`) and Repository interfaces. No framework dependencies!
*   **`data/`**: Implementation of repositories. Handles the bridge between network (Ollama), local DB (Hive), and the fallback service.
*   **`presentation/`**: GetX controllers, sleek UI pages, and reusable premium widgets.

---

## 🧪 Setup & Run

1.  **Ollama Setup**: Ensure [Ollama](https://ollama.ai) is installed and running. Pull models: `ollama pull mistral`.
2.  **Clone & Run**:
    ```bash
    flutter pub get
    flutter run
    ```
3.  **Android Emulator**: The app is pre-configured to use `10.0.2.2:11434` for default connectivity.

---

*Developed by Antigravity—Expertly Crafted for High-Performance Flutter Development.*
