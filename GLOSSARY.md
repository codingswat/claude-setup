# My coding glossary — plain English only

**What this is:** every technical term I've met, one line each, in language I actually use.
Started empty and grew one line at a time; it is my substitute for a CS degree.

**How to use it:** copy this file somewhere of your own and keep adding to it. The rule that
makes it work is in the rulebook: whenever a session explains a new term to you in chat, it
then appends that term here — one line, same plain style, alphabetical order. The chat is
where the explaining happens; this file is only the copy you can come back to.

This published version is a **snapshot** with the domain-specific entries removed, so it is
a starting set rather than a complete one.

---

- **AGPL** — an open-source license with a catch: build your service on AGPL code and you must open-source your whole service too (or buy a commercial license). Check every library's license before depending on it.
- **Allowlist vs denylist** — two ways to filter: an allowlist blocks everything except what you explicitly permit (the safe default); a denylist permits everything except what you explicitly block — one forgotten item and it slips through.
- **API** — a menu of requests one program can make to another ("give me the weather for my city").
- **API key** — a secret string proving it's MY account calling a service; usage bills to it, so it must never leak.
- **Backend** — the brain of an app; rules and logic running on a server ("is this password right?").
- **Branch (git)** — a parallel copy of the code for risky experiments; merge it into main only if it works.
- **Build output (dist)** — the ready-to-run copy of code that a build step produces from the source (our TypeScript must be converted to plain JavaScript before it can run); it goes stale the moment the source changes, until someone rebuilds — and anything pointed at a stale copy runs old code even while the source and its tests are fine.
- **Cache** — a kept copy of something already downloaded or computed, so the next time is faster (npm keeps every package it ever fetched); clearing a cache is safe and costs only a slower next run.
- **Commit (git)** — a save point, like a video-game checkpoint; you can always return to it.
- **Cross-platform** — one codebase for iPhone AND Android (Flutter, React Native); ~90% native feel is the price.
- **Database** — the app's memory; where data survives after the app closes. Rows = records, columns = properties.
- **Deploy** — publish the app to an always-on server so anyone can use it.
- **Domain** — a rented memorable address (myapp.com) that points at your server. ~$12/year.
- **Domain model** — a written map of the real-world things your app deals with (customer, order, invoice) and how they relate; agreed before coding so everyone uses the same words.
- **.env file** — where secrets live, next to the code but never uploaded (gitignored).
- **Error 401** — "who are you?" — missing or invalid key/login.
- **Error 404** — that thing doesn't exist.
- **Error 429** — too many requests; slow down (rate limit).
- **Error 500** — the server's own code crashed.
- **Error codes rule** — 2xx = success, 4xx = the request was wrong, 5xx = the server broke.
- **Fixture** — a saved sample input file that tests run against, so every test starts from the same known data instead of whatever happens to be lying around.
- **Foreign key** — a column pointing at a row in another table ("this order belongs to user 42").
- **Framework** — a prefab house kit built from a language's raw materials (React, Django, Flutter).
- **Frontend** — what you see and touch; buttons and screens, running on YOUR device.
- **Git** — the tool that tracks code history on my machine; my undo button and safety net.
- **GitHub** — the website that stores a cloud copy of git's history; backup and sharing.
- **Golden test** — a test that compares the program's output against a known-correct reference answer (e.g. a published textbook example); if they differ, the code is wrong.
- **Hook** — a script the app itself runs at a fixed moment; enforcement, not a suggestion a model can forget.
- **Hosting** — renting a computer that never sleeps to run your backend.
- **HTTPS** — the S means encrypted; without it, passwords cross the internet readable.
- **IndexedDB** — a real database inside the browser on the user's own device; holds gigabytes, survives page reloads, costs the server nothing.
- **JSON** — labeled data as text: {"city": "my city", "temp": 43}. How programs exchange information.
- **Language (programming)** — the raw building material (Python, JavaScript, Swift).
- **Local-first** — an app design where each user's data lives on their own device and the server only does what truly needs a server; scales cheaply, private by default, but the user's device becomes the only copy unless you add backup.
- **Localhost** — my own computer; an app there is invisible to everyone else.
- **Managed platform** — hosting where they run the machinery (Vercel, Railway); push code, it's live.
- **Merge conflict** — when two branches changed the same lines and git can't decide which version wins; a human (or careful AI) must pick line by line.
- **Migration** — changing a database's table shapes while carefully preserving live data. Back up first, always.
- **npm / pip** — app stores for code packages (JavaScript / Python).
- **OCR** — software that reads text out of a picture or scan; the only way to get numbers off a drawing that is just a photo.
- **Package** — ready-made code by other developers that my project pulls in instead of writing from scratch.
- **Plugin (Claude Code)** — a bundle of skills and settings you install into Claude Code once and it works in every project; can auto-update itself.
- **PostgreSQL / SQLite** — database brands; SQLite for small personal tools, PostgreSQL for real users.
- **PWA** — a website installed to the phone's home screen so it behaves like an app (icon, offline, more storage protection); no app store needed.
- **Rate limit** — a service's cap on how often you may call it; exceed it and you get 429.
- **Raw cloud** — AWS/Google Cloud/Azure; infinite power, you manage the machinery and the surprise bills.
- **Re-record (a golden file)** — when you change output ON PURPOSE, the saved reference answer is now "wrong" and the golden test goes red; re-recording replaces it with the new output. Always read the differences first — this is the one step where a genuine bug can be saved as the new "correct" answer.
- **Record / replay (AI fixtures)** — pay for the real AI answers ONCE and save them as files ("recording"); every test run after that reads the saved files back ("replay") — free, fast, and identical each time. Drift risk: if the questions the tests ask stop matching the recorded ones, the recordings silently go unused.
- **Server** — a computer somewhere else that's always on, running backends.
- **Session (Claude Code)** — one conversation, anchored to the folder path where it was started; its working directory, saved history and memory are keyed to that exact path. Moving the folder never harms the repo, but it strands any open session — pause or close sessions before moving folders (global rule 17).
- **Skill (Claude Code)** — a saved instruction sheet Claude follows for a specific kind of task (like "how to debug" or "how to plan a feature"); triggered by name (/something) or automatically.
- **Spec** — a written description of exactly what a feature should do, agreed before any code is written; the contract the code is checked against.
- **SQL** — the language for asking databases questions ("get all orders over $50"); not a brand.
- **Subagent** — a helper AI that a Claude chat hires for one task; it works in its own separate memory and reports back, keeping the main chat's memory free for judgement.
- **TDD (test-driven development)** — write the failing test first, then write just enough code to make it pass; guarantees every feature has a test that can fail.
- **Tunnel (cloudflared)** — a small program on your server that dials OUT to Cloudflare, so visitors reach the server through Cloudflare without any door (open port) into your home network; free, and the password gate stays on Cloudflare's side.
- **Ultracode** — a keyword you type anywhere in a Claude Code message to allow workflow mode for that one message (typing `/effort ultracode` switches it on for the whole session); more thorough, burns usage much faster.
- **Usage limit (session limit)** — the ceiling a Claude subscription puts on how much work fits in a time window; hit it and every request fails with "resets at <time>" until the window rolls over. Big multi-agent reviews eat it much faster than normal chat.
- **Workflow (Claude Code)** — Claude hiring a temporary team of helper AIs and coordinating them with a fixed script: parallel work, cross-checking, verifying each other's findings. For jobs too big or too important for one chat; you have to switch it on (see Ultracode).
- **Worktree (git)** — a second folder holding a different branch of the same repo, so two pieces of work can run side by side without touching each other.
