// Pure helpers extracted from extract-session.mjs so they're importable
// in tests without auto-running the script's top-level CLI dispatch.

/**
 * Truncate `s` to `max` characters, appending a `...[truncated]`
 * marker when the value was cut.
 */
export function truncate(s, max) {
  return s.length > max ? s.slice(0, max) + '...[truncated]' : s;
}

/**
 * Format a timestamp as an `HH:MM:SS` string, returning `'?'` when
 * the value is falsy or unparseable.
 */
export function formatTs(ts) {
  if (!ts) return '?';
  try {
    return new Date(ts).toISOString().replace('T', ' ').slice(11, 19);
  } catch {
    return String(ts);
  }
}

/**
 * Push a Claude transcript record onto `messages`, normalizing
 * user / assistant / tool_use / tool_result shapes into the shared
 * review-session message format.
 */
export function appendClaudeMessage(obj, messages) {
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

/**
 * Pull the textual `output` / `error` payload out of a Gemini tool
 * call's `result[]` array, returning `{ error, text }` or `null` when
 * no functionResponse was attached.
 */
export function extractGeminiToolResult(tc) {
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

/**
 * Push a Gemini transcript record onto `messages`, normalizing
 * user / gemini / info shapes (including thoughts and tool calls)
 * into the shared review-session message format.
 */
export function appendGeminiMessage(obj, messages) {
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
