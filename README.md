# HiDocu

**A native macOS management suite for HiDock audio recording devices focused on transcription accuracy, data
sovereignty, and professional workflows.**

## Overview

HiDocu is a native macOS application designed to replace the proprietary HiNotes software for managing audio recordings
from HiDock hardware (H1, H1E, P1, and P1 Mini).

HiDocu's promises are simple:

- **No compromises on transcription quality**, no matter the language or technical jargon.
- **No paywalls or subscriptions**: all features are available for free.
- **Full privacy for sensitive recordings**: use only local models for maximum privacy, or connect to your own API keys
  for best-in-class transcription and analysis.
- **Full control over your data**: all audio files and metadata are stored locally. You decide if and when to sync or
  backup your recordings to the cloud of your choice.

## Motivation

This project addresses specific limitations found in the official HiNotes software:

* **Context-aware transcription:** Most transcription services treat audio as isolated segments, ignoring the broader
  context, specific terminology, or slang used in meetings. HiDocu is designed to leverage meeting metadata (e.g.,
  calendar events, participant lists) and company-specific glossaries to provide richer context, resulting in more
  accurate and relevant transcripts.
* **Mixed-language transcription:** HiDocu is optimized for meetings involving multiple languages or dialects, where
  speakers can jump between two, three, or more languages in the same sentence.
* **Focus on transcription accuracy over speed:** HiDocu prioritizes transcription accuracy. For complex scenarios, a
  user may choose to automatically create multiple variants of the same transcription (e.g., using different models or
  settings) and use an LLM-judge to select the most accurate one.
* **Proper and free speaker identification:** If the model provides speaker diarization, HiDocu captures and stores this
  information in the transcription metadata at no extra cost. It also makes an extra effort to map each phrase to the
  correct speaker based on the context of what is said and who was present in the meeting.
* **Focus on privacy and data control:** HiDocu treats sensitive audio recordings with the utmost care. The app is
  designed to operate primarily as a local application, ensuring that sensitive audio recordings remain only on the
  user's machine. The user chooses if they want to backup the data to a cloud service of their choice (e.g., iCloud,
  Dropbox) or if they want to use cloud or local-only transcription models. For cloud transcription, users bring their
  own API keys (BYOK), ensuring that no third-party service has access to their data without explicit permission.
* **Free automatic sync and transcription:** HiDocu does not hide critical features like automatic download and
  transcription behind paywalls.
* **Multi-project management:** Keep your professional and personal recordings separate. HiDocu allows users to organize
  recordings into multiple layers of folders or projects, each with its own transcription settings, glossaries, and
  cloud backup preferences. Multiple calendar accounts can be linked to different projects for automatic meeting
  association.
* **No subscriptions and cost transparency:** HiDocu is open-source and free to use without any subscriptions. Users can
  opt-out of cloud transcription and summarization entirely and use local models only. If cloud models are used, users
  bring their own API keys and are billed directly by the service provider (e.g., OpenAI, Google), ensuring full cost
  transparency.
* **Easy to use:** HiDocu features a modern, intuitive 3-column user interface, similar to native Apple apps like Mail,
  Contacts, or Notes, where all your folders and recordings are easily accessible and searchable without complex
  navigation.
* **Talk to your meetings:** Had a series of recurring meetings? Five rounds of interviews? Two years of team
  stand-ups? No problem. HiDocu allows you to query a group of meetings using your favorite LLM (local or cloud) to
  extract insights, ask questions, or find patterns across multiple transcripts or summaries.

## Hardware Support

* **HiDock H1** (Desktop Audio Dock)
* **HiDock H1E** (Essential Dock)
* **HiDock P1** (Portable AI Recorder)
* **HiDock P1 Mini** (Ultra-portable Recorder)

*Note: This project is not affiliated with, endorsed by, or sponsored by HiDock.*

---

## Project Structure

This monorepo is divided into three distinct components:

1. **`HiDocu`**: The main native macOS application.
2. **`hidock-cli`**: A command-line tool for power users and scripters to interact with HiDock devices without a GUI.
3. **`JensenUSB`**: A pure Swift library handling low-level IOKit communication, protocol encoding/decoding, and device
   state management. It serves as the driver layer.

## Installation & Building

### Prerequisites

* macOS 12.0 (Monterey) or later
* Xcode 15+ (Swift 5.9+)

### Build from Source

A `Makefile` is provided to orchestrate the build process for both the CLI and the GUI app.

```bash
# Clone the repository
git clone [https://github.com/vadimpronin/hidocu.git](https://github.com/vadimpronin/hidocu.git)
cd hidocu

# Build the GUI Application
make hidocu
# App will be located at: build/gui/Build/Products/Release/HiDocu.app

# Build the CLI tool
make build

# Run Unit Tests (Safe to run without device)
make test
```
