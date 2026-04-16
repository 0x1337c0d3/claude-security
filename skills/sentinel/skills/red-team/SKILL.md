---
name: red-team
description: >
  Adversarial analysis from 6 attacker personas. Use when the user asks to
  "red team this", "think like an attacker", "simulate an attack", "threat
  model as an adversary", or wants to understand how their app would be attacked
  by a script kiddie, insider, organized crime, nation-state, hacktivist, or
  supply chain attacker. Invoke with /sentinel:red-team.
---

# Red Team — Adversarial Analysis

Simulate attacks against the codebase from 6 distinct attacker personas.
Each persona has different capabilities, motivations, and focus areas.
Together they cover opportunistic, financially motivated, politically motivated,
sophisticated persistent, and supply chain threats.

## Agents

| Agent | File | Threat Model | DREAD Emphasis |
|-------|------|-------------|----------------|
| Script Kiddie | `agents/script-kiddie.md` | Automated tools, known CVEs, low effort | Discoverability + Exploitability |
| Insider | `agents/insider.md` | Legitimate access abuse, exfiltration, audit gaps | Damage + Affected Users |
| Organized Crime | `agents/organized-crime.md` | Financial fraud, account takeover, ransomware | Damage + Reproducibility |
| Nation State / APT | `agents/nation-state.md` | Persistent access, intelligence gathering, stealth | Damage + low Discoverability |
| Hacktivist | `agents/hacktivist.md` | Data leaks, defacement, disruption, public impact | Damage + Affected Users |
| Supply Chain | `agents/supply-chain.md` | Dependency poisoning, CI/CD injection, build tampering | Reproducibility + Affected Users |

## Usage

```
/sentinel:red-team                        # Run all 6 personas against the codebase
/sentinel:red-team --persona insider      # Run a single persona
/sentinel:red-team --persona script-kiddie,supply-chain   # Run specific personas
/sentinel:red-team --depth expert         # Deep analysis with full attack chains
```

## Execution Protocol

### Step 1 — Context Gathering

Before dispatching agents, build context about the target codebase:

1. Detect languages, frameworks, and entry points by running:
   ```bash
   find . \( -name "package.json" -o -name "requirements.txt" -o -name "go.mod" \
             -o -name "pom.xml" -o -name "*.csproj" -o -name "Gemfile" \) \
     | grep -v node_modules | grep -v .git | head -20
   find . \( -name "main.*" -o -name "app.*" -o -name "server.*" -o -name "routes.*" \) \
     | grep -v node_modules | grep -v .git | head -20
   ```
2. If Sentinel has already run, load the most recent `reports/security-*.md` to give agents knowledge of known findings.
3. If `/sentinel:audit` output is available, use it as additional context.

### Step 2 — Dispatch Persona Agents

Load each requested agent definition from `agents/<persona>.md`.

For each persona, perform analysis by reading and following the agent definition:

1. **Read** the agent definition file to understand the persona's capabilities, focus areas, and attack approach.
2. **Apply** the persona's attack methodology to the codebase — examine the files, structure, dependencies, and configuration through their lens.
3. **Produce findings** in the format below.

When running all personas, work through each one sequentially or use parallel
subagents (Task tool calls in a single response) for efficiency.

### Step 3 — Findings Format

For each persona, produce:

```markdown
## [Persona Name] Analysis

**Threat model**: [1-sentence description of this attacker type]
**Primary motivation**: [What they want]

### Findings

#### [RT-SK-001 | RT-IN-001 | RT-OC-001 | RT-NS-001 | RT-HK-001 | RT-SC-001]-XXX
**Severity**: CRITICAL / HIGH / MEDIUM / LOW
**Finding**: [Title]

**What an attacker sees**: [How this persona would discover this]
**Attack scenario**:
1. [Step 1]
2. [Step 2]
3. [Impact]

**DREAD Score**: D[1-3] R[1-3] E[1-3] A[1-3] D[1-3] = [avg]/3 ([risk level])

**Remediation**: [Specific fix for this finding]
```

ID prefixes per persona:
- `RT-SK` — Script Kiddie
- `RT-IN` — Insider
- `RT-OC` — Organized Crime
- `RT-NS` — Nation State
- `RT-HK` — Hacktivist
- `RT-SC` — Supply Chain

### Step 4 — Cross-Persona Summary

After all personas complete, produce a consolidated summary:

```markdown
## Red Team Summary

| Finding | SK | IN | OC | NS | HK | SC | Max Severity |
|---------|----|----|----|----|----|----|-------------|
| [title] | ✓  |    | ✓  |    |    |    | HIGH        |

### Most Dangerous Findings
[Top 3-5 findings that multiple personas would exploit]

### Blind Spots
[Things the attacker personas could NOT exploit — what's well-defended]

### Priority Remediation
1. [Fix this first because multiple threat actors would exploit it]
2. [Next priority]
```

### Step 5 — Sentinel Integration

If Sentinel scan results are available, cross-reference:
- Map Sentinel findings (SENTINEL-XXX) to which personas would exploit them
- Identify findings Sentinel detected but no persona found (may be false positives)
- Identify findings personas found that Sentinel missed (logic flaws, misconfigurations)
- Produce adjusted risk score: Shell score ± red team delta

## DREAD Reference

Load `../../references/dread.md` for the DREAD scoring criteria when scoring findings.

## Scope Notes

Red team analysis is **read-only**. Personas analyze the codebase as a
black-box or grey-box attacker — they never modify files or run exploits.
All findings are theoretical: "an attacker could..." not "we confirmed...".

Flag findings that overlap with Sentinel's confirmed findings as **corroborated**
(higher confidence). Flag findings that require conditions Sentinel did not
confirm as **theoretical** (medium confidence).


---

## Report Format

Format your final output following the standard Sentinel report structure defined in
`${CLAUDE_SKILL_DIR}/../../templates/report.md`. Use your skill's domain-specific
finding IDs (e.g. `STRIDE-SPOOF-001`, `RT-SK-001`, `API-001`) in the Finding ID column.
Include the Security Scorecard and Findings sections as a minimum. Omit the
Cross-Validation Summary section if you ran only AI analysis (no tool comparison).
