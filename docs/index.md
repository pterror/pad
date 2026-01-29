---
layout: home
hero:
  name: pad
  text: cognitive stdin sink
  tagline: Capture and structure text from pipes, commands, and clipboard
  actions:
    - theme: brand
      text: Get Started
      link: /cli
    - theme: alt
      text: HTTP API
      link: /api
features:
  - title: Pipe anything
    details: echo "hello" | pad — ingest from stdin, shell commands, clipboard, or file watches
  - title: Content-addressed
    details: Deduplication by hash, tiered storage (event/sketch/full), coldness-based aging
  - title: Local-first
    details: SQLite database, epoll daemon, no cloud, no accounts, no telemetry
---
