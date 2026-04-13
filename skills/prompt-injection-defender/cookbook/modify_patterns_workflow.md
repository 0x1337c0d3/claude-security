# Modify Patterns Workflow

## Triggers

- "add new pattern"
- "modify patterns"
- "update detection rules"
- "add custom detection"
- "change injection patterns"

## Workflow

### Step 1: Understand the Request

Use AskUserQuestion if needed:

1. **What type of pattern?**

   - Instruction Override
   - Role-Playing/DAN
   - Encoding/Obfuscation
   - Context Manipulation

2. **What should it detect?**

   - Get example text that should trigger
   - Get example text that should NOT trigger (avoid false positives)

3. **What severity?**
   - high: Definite attack
   - medium: Suspicious
   - low: Informational

### Step 2: Locate patterns.yaml

Check in order:

1. `.claude/hooks/prompt-injection-defender/patterns.yaml` (installed location)
2. Skill directory `patterns.yaml` (development)

### Step 3: Create the Pattern

Convert the user's requirement into a regex pattern:

```yaml
- pattern: '(?i)\buser_pattern_here\b'
  reason: "Description of what this catches"
  severity: high
```

**Pattern Tips:**

- Use `(?i)` for case-insensitive
- Use `\b` for word boundaries
- Escape special chars: `\.` `\(` `\[`
- Use `\s+` for whitespace
- Test with simple patterns first

### Step 4: Test the Pattern

Use the test-defender script:

```bash
# Interactive testing
uv run .claude/hooks/prompt-injection-defender/test-defender.py -i

# Or test directly
uv run .claude/hooks/prompt-injection-defender/test-defender.py --text "test string here"
```

Verify:

- Pattern catches the intended content
- Pattern does NOT catch legitimate content

### Step 5: Add to patterns.yaml

Read the current patterns.yaml and add the new pattern to the appropriate category:

```yaml
instructionOverridePatterns:
  # Existing patterns...

  # NEW: User's custom pattern
  - pattern: '(?i)\bnew_pattern_here\b'
    reason: "Detects XYZ attack technique"
    severity: high
```

### Step 6: Verify the Change

1. Re-run the test to confirm detection works
2. Show the user the updated pattern
3. Recommend testing with real-world content

## Common Pattern Examples

### Instruction Override

```yaml
- pattern: '(?i)\bignore\s+all\s+above\b'
  reason: "Attempts to ignore content above"
  severity: high
```

### Role-Playing

```yaml
- pattern: '(?i)\byou\s+are\s+now\s+evil\b'
  reason: "Evil persona activation"
  severity: high
```

### Encoding

```yaml
- pattern: '(?i)\bdecode\s+and\s+execute\b'
  reason: "Decode-execute instruction"
  severity: medium
```

### Context Manipulation

```yaml
- pattern: '(?i)\bsecurity\s+team\s+approved\b'
  reason: "Fake security approval claim"
  severity: high
```

## Removing Patterns

To remove a pattern:

1. Find it in patterns.yaml
2. Delete the entire block (pattern, reason, severity)
3. Test to confirm it no longer triggers
