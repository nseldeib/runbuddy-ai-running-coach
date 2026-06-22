#!/usr/bin/env node
// Extracts a compressed, readable summary from a Claude Code OR Gemini CLI session .jsonl file.
//
// The two formats differ on disk but produce the same internal message shape, so all
// sections (full / user-only / decisions / errors) work identically across sources.
//
// Format detection: prefers the file path (`.gemini/` or `/chats/session-`), then falls
// back to the first parseable line (Claude has `obj.message`, Gemini has `obj.kind: "main"`
// or top-level `obj.type` of "user"/"gemini"/"info").
//
// Usage: node extract-session.mjs <path-to-session.jsonl> [--section=<section>]
//
// Sections:
//   full        - Full conversation flow (default)
//   user-only   - Only user messages (prompts/instructions)
//   decisions   - Tool calls + user messages (shows what was done)
//   errors      - Only error results and corrections

import { createReadStream } from 'node:fs';
import { createInterface } from 'node:readline';
import { stat } from 'node:fs/promises';
import { basename } from 'node:path';

const inputFile = process.argv[2];
if (!inputFile) {
  process.stderr.write('Usage: node extract-session.mjs <session.jsonl> [--section=full|user-only|decisions|errors]\n');
  process.exit(1);
}

let section = 'full';
for (const arg of process.argv.slice(3)) {
  if (arg.startsWith('--section=')) section = arg.slice('--section='.length);
}

try {
  const st = await stat(inputFile);
  process.stderr.write(`Reading ${basename(inputFile)} (${Math.round(st.size / 1024)}KB)...\n`);
} catch {
  process.stderr.write(`File not found: ${inputFile}\n`);
  process.exit(1);
}

// ── Format detection from path (overridden by first-line if path is unclear) ──
let detectedFormat = null;
if (inputFile.includes('/.gemini/') || /\/chats\/session-/.test(inputFile)) detectedFormat = 'gemini';
else if (inputFile.includes('/.claude/')) detectedFormat = 'claude';

const messages = [];
let lineCount = 0;

// Gemini streams the same event multiple times as it updates (e.g. an initial response
// then a second emission with toolCalls populated). We dedupe by event id and keep the
// last-seen version, then convert to messages in insertion order.
const geminiEvents = new Map();

const rl = createInterface({ input: createReadStream(inputFile) });
for await (const line of rl) {
  lineCount++;
  let obj;
  try { obj = JSON.parse(line); } catch { continue; }

  if (detectedFormat === null) {
    if (obj.type === 'user' && obj.message) detectedFormat = 'claude';
    else if (obj.type === 'assistant' && obj.message) detectedFormat = 'claude';
    else if (obj.type === 'summary' && 'summary' in obj) detectedFormat = 'claude';
    else if (obj.kind === 'main' || obj.sessionId) detectedFormat = 'gemini';
    else if (obj.message) detectedFormat = 'claude';
    else detectedFormat = 'gemini';
  }

  if (detectedFormat === 'claude') {
    appendClaudeMessage(obj);
  } else {
    if (obj.kind || obj.$set) continue; // session metadata / metadata-update lines
    if (!obj.type) continue;
    if (obj.id) {
      geminiEvents.set(obj.id, obj);
    } else {
      appendGeminiMessage(obj);
    }
  }
}

if (detectedFormat === 'gemini') {
  for (const obj of geminiEvents.values()) appendGeminiMessage(obj);
}

process.stderr.write(`Format: ${detectedFormat}. Parsed ${messages.length} messages from ${lineCount} lines.\n`);

// ── Format-specific parsers ──────────────────────────────────────────────

/**
 * Truncate `s` to `max` characters, appending a `...[truncated]`
 * marker when the value was cut.
 */
function truncate(s, max) {
  return s.length > max ? s.slice(0, max) + '...[truncated]' : s;
}

function appendClaudeMessage(obj) {
  if (!obj.type) return;

  if (obj.type === 'user') {
    const content = obj.message?.content;
    if (!content) return;
    if (typeof content === 'string') {
      messages.push({ role: 'user', text: content, ts: obj.timestamp });
    } else if (Array.isArray(content)) {
      const parts = [];
      let hasError = false;
      for (const item of content) {
        if (item.type === 'tool_result') {
          const t = typeof item.content === 'string' ? item.content : JSON.stringify(item.content);
          if (item.is_error) hasError = true;
          parts.push({ kind: 'tool_result', error: !!item.is_error, text: truncate(t, 800) });
        } else if (typeof item === 'string') {
          parts.push({ kind: 'text', text: item });
        } else if (item.type === 'text') {
          parts.push({ kind: 'text', text: item.text });
        }
      }
      messages.push({ role: 'user_complex', parts, hasError, ts: obj.timestamp });
    }
    return;
  }

  if (obj.type === 'assistant') {
    const items = obj.message?.content;
    if (!Array.isArray(items)) return;
    const parts = [];
    for (const item of items) {
      if (item.type === 'text' && item.text) {
        parts.push({ kind: 'text', text: item.text });
      } else if (item.type === 'thinking') {
        const t = item.thinking || '';
        parts.push({ kind: 'thinking', text: truncate(t, 1500) });
      } else if (item.type === 'tool_use') {
        const inputStr = typeof item.input === 'string' ? item.input : JSON.stringify(item.input);
        parts.push({ kind: 'tool', name: item.name, input: truncate(inputStr, 500) });
      }
    }
    if (parts.length > 0) messages.push({ role: 'assistant', parts, ts: obj.timestamp });
  }
}

function extractGeminiToolResult(tc) {
  if (!Array.isArray(tc.result) || tc.result.length === 0) return null;
  const texts = [];
  let error = false;
  for (const r of tc.result) {
    const fr = r?.functionResponse?.response;
    if (!fr) continue;
    if (fr.error) {
      error = true;
      if (typeof fr.error === 'string') texts.push(fr.error);
      else texts.push(JSON.stringify(fr.error));
      continue;
    }
    if (typeof fr.output === 'string') texts.push(fr.output);
    else if (fr.output !== undefined) texts.push(JSON.stringify(fr.output));
    else texts.push(JSON.stringify(fr));
  }
  if (texts.length === 0) texts.push(JSON.stringify(tc.result));
  return { error, text: truncate(texts.join('\n'), 800) };
}

function appendGeminiMessage(obj) {
  if (obj.type === 'user') {
    let text;
    if (typeof obj.content === 'string') {
      text = obj.content;
    } else if (Array.isArray(obj.content)) {
      text = obj.content
        .map((p) => (typeof p === 'string' ? p : p?.text || ''))
        .filter(Boolean)
        .join('\n');
    } else {
      return;
    }
    if (text && text.trim()) messages.push({ role: 'user', text, ts: obj.timestamp });
    return;
  }

  if (obj.type === 'gemini') {
    const parts = [];
    if (Array.isArray(obj.thoughts)) {
      for (const t of obj.thoughts) {
        const txt = typeof t === 'string' ? t : t?.text || '';
        if (!txt) continue;
        parts.push({ kind: 'thinking', text: truncate(txt, 1500) });
      }
    }
    if (typeof obj.content === 'string' && obj.content.length > 0) {
      parts.push({ kind: 'text', text: obj.content });
    }
    const toolResults = [];
    if (Array.isArray(obj.toolCalls)) {
      for (const tc of obj.toolCalls) {
        const inputStr = JSON.stringify(tc.args ?? {});
        parts.push({ kind: 'tool', name: tc.name || '?', input: truncate(inputStr, 500) });
        const result = extractGeminiToolResult(tc);
        if (result) toolResults.push(result);
      }
    }
    if (parts.length > 0) {
      messages.push({ role: 'assistant', parts, ts: obj.timestamp });
    }
    if (toolResults.length > 0) {
      messages.push({
        role: 'user_complex',
        parts: toolResults.map((r) => ({ kind: 'tool_result', error: r.error, text: r.text })),
        hasError: toolResults.some((r) => r.error),
        ts: obj.timestamp,
      });
    }
    return;
  }

  if (obj.type === 'info') {
    if (typeof obj.content === 'string' && obj.content.trim()) {
      messages.push({ role: 'user', text: `[info] ${obj.content}`, ts: obj.timestamp });
    }
  }
}

// ── Output formatter ─────────────────────────────────────────────────────
const output = [];

output.push(`# Session Transcript Review`);
output.push(`Source: ${basename(inputFile)} (${detectedFormat})`);
output.push(`Messages: ${messages.length}`);
output.push('');

if (section === 'user-only') {
  output.push('## User Messages Only\n');
  for (const msg of messages) {
    if (msg.role === 'user') {
      output.push(`### User [${formatTs(msg.ts)}]`);
      output.push(msg.text);
      output.push('');
    }
  }
} else if (section === 'errors') {
  output.push('## Errors and Corrections\n');
  for (const msg of messages) {
    if (msg.role === 'user_complex' && msg.hasError) {
      output.push(`### Error [${formatTs(msg.ts)}]`);
      for (const part of msg.parts) {
        if (part.kind === 'tool_result' && part.error) {
          output.push('```\n' + part.text + '\n```');
        }
      }
      output.push('');
    }
    // Capture user corrections (short messages) for either source
    if (msg.role === 'user' && msg.text.length < 500) {
      const lower = msg.text.toLowerCase();
      if (lower.includes('no') || lower.includes('wrong') || lower.includes('fix') ||
          lower.includes('actually') || lower.includes('instead') || lower.includes('not what') ||
          lower.includes('revert') || lower.includes('undo')) {
        output.push(`### Correction [${formatTs(msg.ts)}]`);
        output.push(msg.text);
        output.push('');
      }
    }
  }
} else if (section === 'decisions') {
  output.push('## Decisions and Actions\n');
  for (const msg of messages) {
    if (msg.role === 'user') {
      output.push(`### User [${formatTs(msg.ts)}]`);
      output.push(msg.text);
      output.push('');
    }
    if (msg.role === 'assistant') {
      for (const part of msg.parts) {
        if (part.kind === 'text') output.push(part.text);
        if (part.kind === 'tool') output.push(`  > ${part.name}: ${part.input}`);
      }
      output.push('');
    }
  }
} else {
  // full
  output.push('## Full Conversation Flow\n');
  for (const msg of messages) {
    if (msg.role === 'user') {
      output.push(`### USER [${formatTs(msg.ts)}]`);
      output.push(msg.text);
      output.push('');
    } else if (msg.role === 'user_complex') {
      output.push(`### USER (tool results) [${formatTs(msg.ts)}]`);
      for (const part of msg.parts) {
        if (part.kind === 'text') {
          output.push(part.text);
        } else if (part.kind === 'tool_result') {
          const prefix = part.error ? '[ERROR] ' : '';
          output.push(`  ${prefix}Result: ${part.text}`);
        }
      }
      output.push('');
    } else if (msg.role === 'assistant') {
      output.push(`### ASSISTANT [${formatTs(msg.ts)}]`);
      for (const part of msg.parts) {
        if (part.kind === 'thinking') {
          output.push(`<thinking>${part.text}</thinking>`);
        } else if (part.kind === 'text') {
          output.push(part.text);
        } else if (part.kind === 'tool') {
          output.push(`  > ${part.name}: ${part.input}`);
        }
      }
      output.push('');
    }
  }
}

process.stdout.write(output.join('\n'));

/**
 * Format a timestamp as an `HH:MM:SS` string, returning `'?'` when
 * the value is falsy or unparseable.
 */
function formatTs(ts) {
  if (!ts) return '?';
  try {
    return new Date(ts).toISOString().replace('T', ' ').slice(11, 19);
  } catch {
    return String(ts);
  }
}
