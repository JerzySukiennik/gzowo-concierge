// Gzowo Concierge - skills: markdown instruction packs (bundled in skills/, user-made in data/skills/).
import fs from 'node:fs';
import path from 'node:path';
import { ROOT, config } from './config.mjs';

const BUNDLED = path.join(ROOT, 'skills');
const USER = path.join(config.dataDir, 'skills');
const NAME = /^[a-z0-9][a-z0-9-]{1,39}$/;

function parse(file) {
  const raw = fs.readFileSync(file, 'utf8');
  const m = raw.match(/^---\n([\s\S]*?)\n---\n?([\s\S]*)$/);
  if (!m) return null;
  const meta = {};
  for (const line of m[1].split('\n')) { const kv = line.match(/^(\w+):\s*(.*)$/); if (kv) meta[kv[1]] = kv[2].trim(); }
  if (!meta.name || !meta.description) return null;
  return { name: meta.name, description: meta.description, body: m[2].trim() };
}

function scan(dir, source) {
  if (!fs.existsSync(dir)) return [];
  const out = [];
  for (const d of fs.readdirSync(dir, { withFileTypes: true })) {
    if (!d.isDirectory()) continue;
    const f = path.join(dir, d.name, 'SKILL.md');
    if (!fs.existsSync(f)) continue;
    try { const s = parse(f); if (s) out.push({ ...s, source }); } catch {}
  }
  return out;
}

export function listSkills() {
  const bundled = scan(BUNDLED, 'bundled');
  const taken = new Set(bundled.map(s => s.name));
  return [...bundled, ...scan(USER, 'user').filter(s => !taken.has(s.name))].sort((a, b) => a.name.localeCompare(b.name));
}

export const getSkill = name => listSkills().find(s => s.name === name) || null;

export function createSkill({ name, description, instructions }) {
  name = String(name || '').trim().toLowerCase();
  if (!NAME.test(name)) throw new Error('Skill name must be 2-40 chars: lowercase letters, digits, hyphens.');
  if (scan(BUNDLED, 'bundled').some(s => s.name === name)) throw new Error('A built-in skill with this name exists.');
  description = String(description || '').replace(/\s+/g, ' ').trim();
  instructions = String(instructions || '').trim();
  if (!description || description.length > 200) throw new Error('Description is required (max 200 chars).');
  if (instructions.length < 20 || instructions.length > 6000) throw new Error('Instructions must be 20-6000 chars.');
  const dir = path.join(USER, name);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'SKILL.md'), `---\nname: ${name}\ndescription: ${description}\n---\n${instructions}\n`);
  return { name, description };
}

export function deleteSkill(name) {
  const s = scan(USER, 'user').find(x => x.name === name);
  if (!s) throw new Error('No user skill with this name (built-in skills cannot be deleted).');
  fs.rmSync(path.join(USER, name), { recursive: true, force: true });
  return true;
}
