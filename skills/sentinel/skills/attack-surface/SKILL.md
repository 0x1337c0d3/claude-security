---
name: attack-surface
description: >
  Map the application attack surface. Use when the user asks to "map attack
  surface", "list entry points", "inventory API endpoints", "find all inputs",
  "enumerate routes", "discover exposed endpoints", or wants to understand
  where external data enters the system. Also useful as a pre-scan step before
  running /sentinel. Invoke with /sentinel:attack-surface.
---

# Attack Surface Mapping

Discover and inventory every entry point where external data enters the
application. Produces a ranked catalog of all routes, APIs, input handlers,
and external interfaces organized by exposure level and trust boundary.

Most useful as a **pre-scan step** before running `/sentinel` — identifies where
to focus scanning effort and surfaces unauthenticated endpoints that are high risk.

## Usage

```
/sentinel:attack-surface                  # Full surface map (default: full scope)
/sentinel:attack-surface --depth quick    # Route extraction only (fast)
/sentinel:attack-surface --depth deep     # Trace entry points to internal sinks
/sentinel:attack-surface --format json    # Machine-readable inventory
```

## Workflow

### Step 1 — Detect Framework and Language

Identify the application framework to determine route registration patterns:

| Framework | Route Pattern |
|-----------|--------------|
| Express/Koa/Fastify | `app.get()`, `router.post()`, `fastify.route()` |
| Django | `urlpatterns`, `path()`, `re_path()`, `@api_view` |
| Flask | `@app.route()`, `@blueprint.route()` |
| Spring | `@GetMapping`, `@PostMapping`, `@RequestMapping` |
| Rails | `routes.rb`, `resources :`, `get '/'` |
| Next.js/Nuxt | `pages/` and `app/` directory conventions, `route.ts` |
| ASP.NET | `[HttpGet]`, `[Route]`, `MapGet()`, `MapPost()` |
| Go net/http | `http.HandleFunc()`, `mux.Handle()`, gorilla/chi patterns |
| FastAPI | `@app.get()`, `@router.post()` |
| gRPC | `.proto` service definitions |
| GraphQL | Schema definitions, resolver registrations |

Use Grep to find these patterns directly in the source tree.

### Step 2 — Extract Entry Points

For each framework detected, systematically extract all entry points:

1. **HTTP Routes**: Method, path, handler function, middleware chain
2. **API Endpoints**: REST, GraphQL queries/mutations, gRPC services
3. **Form Handlers**: HTML form action targets, multipart upload handlers
4. **File Upload Endpoints**: Endpoints accepting file data, storage destinations
5. **WebSocket Handlers**: Connection endpoints, message handlers
6. **CLI Arguments**: Argument parsers (`argparse`, `commander`, `cobra`)
7. **Message Queue Consumers**: Kafka/RabbitMQ/SQS message handlers
8. **Webhook Receivers**: Endpoints accepting callbacks from external services
9. **Scheduled Tasks**: Cron jobs that process external data

### Step 3 — Classify Each Entry Point

For every discovered entry point, determine:

| Attribute | Values |
|-----------|--------|
| Authentication | None, API key, session, JWT, OAuth, mTLS, unknown |
| Authorization | None, role-based, attribute-based, unknown |
| Input types | Query params, path params, headers, body (JSON/XML/form), files, cookies |
| Validation | Present (with details) or absent |
| Rate Limiting | Present or absent |
| Network exposure | Internet-facing, internal network, localhost only |

### Step 4 — Rank by Exposure

| Level | Criteria |
|-------|----------|
| **CRITICAL** | Internet-facing, no authentication, accepts user input, interacts with sensitive data or system resources |
| **HIGH** | Internet-facing with authentication but handling sensitive data, or unauthenticated with limited input validation |
| **MEDIUM** | Authenticated endpoints with proper validation, or internal endpoints with no authentication |
| **LOW** | Internal endpoints with authentication, limited input surface, or read-only operations on non-sensitive data |

At `--depth deep`, trace each HIGH/CRITICAL entry point inward to identify
what sinks they reach (databases, file system, external services, system commands).

### Step 5 — Identify Shadow Endpoints

Look for:
- Debug/admin routes not behind auth middleware (`/debug`, `/admin`, `/metrics`, `/health` exposing internals)
- Deprecated API versions still routed (`/api/v1/` when `/api/v2/` is current)
- Swagger UI / OpenAPI browser exposed without authentication
- Endpoints in test configuration that may be active in production
- Routes registered dynamically that don't appear in static route lists

### Step 6 — Produce Inventory Report

```markdown
## Attack Surface Inventory

### Summary
- Total entry points: N
- Internet-facing: N (N unauthenticated)
- Internal: N
- Exposure: N CRITICAL, N HIGH, N MEDIUM, N LOW

### Entry Points by Exposure

| # | Method | Path | Auth | Input Types | Validation | Rate Limit | Exposure |
|---|--------|------|------|-------------|------------|------------|----------|
| 1 | POST | /api/v1/users | None | JSON body | None | No | CRITICAL |
| 2 | GET | /api/v1/users/:id | JWT | Path param | Partial | Yes | MEDIUM |

### Shadow Endpoints
[Undocumented or debug endpoints discovered]

### Trust Boundary Map (--depth deep)
[Entry points grouped by trust boundary — internet vs internal vs admin]

### Findings
[Missing security controls on HIGH/CRITICAL entry points]
```

### Step 7 — Produce Findings for Missing Controls

When entry points have clearly missing security controls, emit findings:

```
[SURF-XXX] Title
Severity: CRITICAL/HIGH/MEDIUM/LOW | CWE: CWE-306 (Missing Auth) or CWE-16 (Config)
Location: file:line (route definition)

Entry point: [METHOD] [path]
Issue: [Missing authentication / no rate limit / no input validation]

Risk: [Who can reach this and what they can do]

Fix: [Add auth middleware / rate limiter / input size limit]
```

Finding ID prefix: `SURF`

## Pragmatism Notes

- Health check endpoints (`/health`, `/ready`) without auth are normal in
  container orchestration. Only flag if they expose sensitive internal state.
- Internal APIs behind a service mesh or VPN still warrant inventory but at
  lower exposure level.
- CLI tools that only run locally have minimal attack surface unless they
  parse untrusted files.

## Sentinel Integration

Attack surface mapping is the ideal **pre-scan step** before `/sentinel`:
- Identifies unauthenticated endpoints to prioritize in SAST scan
- Gives Sentinel's `run-sast.sh` a focused target list
- Surfaces shadow/debug endpoints gitleaks won't find
- SURF findings map to OWASP A01 (Broken Access Control) and A05 (Misconfiguration)
- Combine with `/sentinel:api` for deep analysis of HIGH/CRITICAL endpoints


---

## Report Format

Format your final output following the standard Sentinel report structure defined in
`${CLAUDE_SKILL_DIR}/../../templates/report.md`. Use your skill's domain-specific
finding IDs (e.g. `STRIDE-SPOOF-001`, `RT-SK-001`, `API-001`) in the Finding ID column.
Include the Security Scorecard and Findings sections as a minimum. Omit the
Cross-Validation Summary section if you ran only AI analysis (no tool comparison).
