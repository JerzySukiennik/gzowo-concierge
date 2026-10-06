// Gzowo Concierge - thin Gemini REST client (no SDK).
import { config } from './config.mjs';

const BASE = 'https://generativelanguage.googleapis.com/v1beta/models';

export async function generate({ model = config.chatModel, system, contents, tools, thinking = 'low', temperature, signal }) {
  const body = { contents };
  if (system) body.systemInstruction = { parts: [{ text: system }] };
  if (tools?.length) body.tools = tools;
  body.generationConfig = {};
  if (thinking) body.generationConfig.thinkingConfig = { thinkingLevel: thinking };
  if (temperature !== undefined) body.generationConfig.temperature = temperature;

  let lastErr;
  for (let attempt = 0; attempt < 3; attempt++) {
    const res = await fetch(`${BASE}/${model}:generateContent`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-goog-api-key': config.apiKey },
      body: JSON.stringify(body),
      signal,
    });
    if (res.ok) return res.json();
    const text = await res.text();
    lastErr = new Error(`Gemini ${res.status}: ${text.slice(0, 400)}`);
    lastErr.status = res.status;
    if (![429, 500, 503].includes(res.status)) break;
    await new Promise(r => setTimeout(r, 800 * (attempt + 1) ** 2));
  }
  throw lastErr;
}

export const textOf = parts => (parts || []).filter(p => p.text && !p.thought).map(p => p.text).join('');
