// Gzowo Concierge - Claude Messages API over raw HTTP with streaming (no SDK, like the rest of the host): key fallback, retries, SSE assembled into one message.
import { config } from './config.mjs';
import { getSecret } from './secrets.mjs';

const API = 'https://api.anthropic.com/v1/messages';
const VERSION = '2026-10-21';
const RETRY = new Set([408, 429, 500, 502, 503, 504, 529]);

export function claudeKeys() {
  return [...new Set([getSecret('anthropic')?.apiKey, ...config.anthropicKeys].filter(Boolean))];
}

export const claudeReady = () => claudeKeys().length > 0;

const sleep = ms => new Promise(r => setTimeout(r, ms));

export async function streamMessage(body, { betas = [], signal } = {}) {
  const keys = claudeKeys();
  if (!keys.length) throw new Error('Brak klucza Anthropic.');
  let lastErr, k = 0;
  for (let attempt = 0; attempt < 6; attempt++) {
    const key = keys[k % keys.length];
    let res;
    try {
      res = await fetch(API, {
        method: 'POST',
        headers: {
          'content-type': 'application/json', 'x-api-key': key, 'anthropic-version': VERSION,
          ...(betas.length ? { 'anthropic-beta': betas.join(',') } : {}),
        },
        body: JSON.stringify({ ...body, stream: true }),
        signal: signal || AbortSignal.timeout(20 * 60e3),
      });
    } catch (err) {
      lastErr = err;
      await sleep(2000 * (attempt + 1));
      continue;
    }
    if (res.ok) {
      try { return await assemble(res); } catch (err) {
        if (!err.retryable) throw err;
        lastErr = err;
        await sleep(3000 * (attempt + 1));
        continue;
      }
    }
    const text = await res.text();
    let msg = text.slice(0, 300);
    try { msg = JSON.parse(text).error?.message || msg; } catch {}
    lastErr = Object.assign(new Error(`Claude ${res.status}: ${msg}`), { status: res.status });
    if ([401, 403].includes(res.status) && keys.length > 1) { k++; continue; }
    if (!RETRY.has(res.status)) throw lastErr;
    const wait = Number(res.headers.get('retry-after')) * 1000 || 2500 * (attempt + 1) ** 2;
    await sleep(Math.min(wait, 60e3));
  }
  throw lastErr;
}

async function assemble(res) {
  const decoder = new TextDecoder();
  let msg = null, buf = '';
  const handle = (event, data) => {
    if (event === 'message_start') msg = data.message;
    else if (event === 'content_block_start') {
      const block = { ...data.content_block };
      if (block.type === 'tool_use' || block.type === 'server_tool_use') block._json = '';
      msg.content[data.index] = block;
    } else if (event === 'content_block_delta') {
      const b = msg.content[data.index], d = data.delta;
      if (d.type === 'text_delta') b.text = (b.text || '') + d.text;
      else if (d.type === 'input_json_delta') b._json += d.partial_json;
      else if (d.type === 'thinking_delta') b.thinking = (b.thinking || '') + d.thinking;
      else if (d.type === 'signature_delta') b.signature = d.signature;
      else if (d.type === 'citations_delta') (b.citations ||= []).push(d.citation);
    } else if (event === 'content_block_stop') {
      const b = msg.content[data.index];
      if (b && '_json' in b) {
        const raw = b._json;
        delete b._json;
        if (raw.trim()) {
          try { b.input = JSON.parse(raw); } catch { b.input = {}; b._invalid = raw.slice(0, 2000); }
        }
      }
    } else if (event === 'message_delta') {
      Object.assign(msg, data.delta);
      if (data.usage) msg.usage = { ...msg.usage, ...data.usage };
    } else if (event === 'error') {
      const type = data.error?.type || '';
      throw Object.assign(new Error(`Claude stream: ${data.error?.message || type}`), { retryable: ['overloaded_error', 'api_error', 'rate_limit_error'].includes(type) });
    }
  };
  for await (const chunk of res.body) {
    buf += decoder.decode(chunk, { stream: true });
    let i;
    while ((i = buf.indexOf('\n\n')) >= 0) {
      const raw = buf.slice(0, i);
      buf = buf.slice(i + 2);
      let event = '', data = '';
      for (const line of raw.split('\n')) {
        if (line.startsWith('event:')) event = line.slice(6).trim();
        else if (line.startsWith('data:')) data += line.slice(5).trim();
      }
      if (data) handle(event, JSON.parse(data));
    }
  }
  if (!msg?.stop_reason) throw Object.assign(new Error('Claude stream ended early'), { retryable: true });
  msg.content = msg.content.filter(Boolean);
  return msg;
}

export const forHistory = content => content.map(({ _invalid, ...b }) => b);
