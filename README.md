# Salio

## Overview
Salio is a mobile-first, offline-first debt and credit tracking system designed for small retail businesses such as shops, agrovets, kiosks, and informal traders. 

## Problem Statement
Small retail businesses frequently sell goods on credit but struggle to track these transactions effectively. They often rely on paper-based debt books, which leads to challenges such as:
- Losing track of who owes them money.
- Not knowing exactly how much is owed.
- Difficulty in tracking partial payments.
- Forgetting about overdue debts.

## Solution Overview
Salio replaces paper-based debt books with a fast, simple digital system that works entirely offline. It provides an easy-to-use interface for businesses to record debts, manage customer balances, and track payments seamlessly, even without an internet connection.

## Tech Stack
- **Mobile App**: Flutter (Dart) with SQLite for local offline-first storage.
- **Backend API**: Go (Golang) for a high-performance RESTful API.
- **Database**: PostgreSQL for backend data persistence.
- **Architecture**: Monorepo structure containing both the mobile client and backend server.

## Monorepo Structure
The repository is organized as a monorepo to keep the frontend, backend, and documentation tightly coupled and easy to manage:

```text
salio/
├── mobile/       # Flutter application (Offline-first mobile client)
├── server/       # Go backend REST API
└── docs/         # Project documentation and architecture specs
```

### Directory Breakdown

#### `/mobile`
This directory contains the Flutter mobile application. Since Salio is offline-first, this app relies heavily on a local SQLite database as the source of truth.
- **Core Modules**: Customer management, debt tracking, payment recording, customer balance view, and debt history.
- **Architecture Focus**: Simple, scalable state management to handle local offline data updates and UI reactivity before any syncing occurs.

#### `/server`
This directory holds the Go backend API. 
- **Core Responsibilities**: Provides a REST API for customers, debts, and payments. It uses PostgreSQL for centralized data storage.
- **Initial Phase Strategy**: Focuses strictly on robust data persistence. Authentication, complex middleware, and advanced features are deferred to keep the foundational implementation clean.

#### `/docs`
Contains the source of truth for project planning and architecture.
- **Contents**: Architecture overview, API specifications, database schemas, offline sync conflict resolution strategies, and product requirements.

## Development Roadmap

1. **Phase 1: Mobile App (Core Features)**
   - Build the core offline-first mobile app using Flutter.
   - Implement customer management, debt tracking, and payment recording using local SQLite.
2. **Phase 2: Backend API (Go)**
   - Develop the Go REST API for managing customers, debts, and payments.
   - Set up the PostgreSQL database schema.
3. **Phase 3: Synchronization System**
   - Introduce robust offline sync capabilities.
   - Implement UUID-based records across both systems.
   - Build conflict handling strategies (e.g., last-write-wins or server-authoritative) and a background sync service.
4. **Phase 4: Advanced Features & Polish**
   - Multi-user support with Owner and Staff roles via secure Invite Codes.
   - Server-side Business Analytics with offline graceful degradation.
   - Deep UI/UX Polish with micro-animations and robust error silencing for disconnected environments.
