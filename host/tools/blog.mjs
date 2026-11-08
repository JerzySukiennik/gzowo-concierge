// Gzowo Concierge - Gzowo Times tools: write drafts of Jurek's blog on gzowo.fun with pictures and a project card, publish them only after he approves.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { config } from '../config.mjs';

const run = promisify(execFile);
const MAX = 1400000;
let projects = null;

async function api(p, body) {
  if (!config.blog.key) throw new Error('Gzowo Times is not set up on this Mac: GZOWO_BLOG_KEY is missing in .env.');
  const r = await fetch(config.blog.api + p, {
    method: body ? 'POST' : 'GET',
    headers: { 'content-type': 'application/json', 'x-blog': config.blog.key },
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(60000),
  });
  const j = await r.json().catch(() => ({}));
  if (!r.ok || j.error) throw new Error(j.error || `Gzowo Times answered ${r.status}`);
  return j;
}

const MIME = { jpg: 'jpeg', jpeg: 'jpeg', png: 'png', webp: 'webp' };
function sniff(buf) {
  if (buf[0] === 0xff && buf[1] === 0xd8) return 'jpeg';
  if (buf[0] === 0x89 && buf[1] === 0x50) return 'png';
  if (buf.slice(0, 4).toString() === 'RIFF' && buf.slice(8, 12).toString() === 'WEBP') return 'webp';
  return null;
}

async function picture(src) {
  let buf;
  if (/^https?:\/\//i.test(src)) {
    const r = await fetch(src, { signal: AbortSignal.timeout(30000) });
    if (!r.ok) throw new Error(`Could not download ${src} (${r.status})`);
    buf = Buffer.from(await r.arrayBuffer());
    if (buf.length > 25e6) throw new Error(`${src} is over 25 MB`);
  } else {
    const file = path.resolve(src.replace(/^~(?=\/)/, os.homedir()));
    if (!file.startsWith(os.homedir() + path.sep)) throw new Error('Pictures must come from his home folder or a web address.');
    try { buf = fs.readFileSync(file); } catch (e) { throw new Error(`Could not read ${file}: ${e.code || e.message}`); }
  }
  let type = sniff(buf);
  if (type && buf.length <= MAX && type !== 'png') return `data:image/${type};base64,${buf.toString('base64')}`;
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'gt-')), a = path.join(tmp, 'in'), b = path.join(tmp, 'out.jpg');
  try {
    fs.writeFileSync(a, buf);
    for (const [side, q] of [[1600, 82], [1400, 72], [1100, 64]]) {
      await run('/usr/bin/sips', ['-Z', String(side), '-s', 'format', 'jpeg', '-s', 'formatOptions', String(q), a, '--out', b]);
      const out = fs.readFileSync(b);
      if (out.length <= MAX) return `data:image/jpeg;base64,${out.toString('base64')}`;
    }
    throw new Error('That picture is too big even after shrinking.');
  } catch (e) {
    if (/sips/.test(String(e.message))) throw new Error('That file is not a picture macOS can open.');
    throw e;
  } finally { fs.rmSync(tmp, { recursive: true, force: true }); }
}

const slim = (p) => ({ id: p.id, title: p.title, status: p.status === 'live' ? 'published' : 'draft', by: p.by, pictures: (p.imgs || []).length, project: p.project, updated: new Date(p.up || p.t).toISOString().slice(0, 16), text: String(p.body || '').slice(0, 400) });

export const blogTools = [
  {
    name: 'blog_draft',
    action: 'blog.draft',
    policy: 'auto',
    description: "Write or update a DRAFT post on Gzowo Times, Jurek's blog on gzowo.fun (visitors read it in the news ticker above the taskbar). Use it when he says \"dodaj na bloga\", \"wrzuć na Gzowo Times\", \"napisz post o...\". Write in Polish, in his voice: short, concrete, no hype, no emoji. Separate paragraphs with an empty line; links can be pasted as addresses or written as [tekst](https://...); **bold** works. Pictures: web addresses (https://...) or file paths in his home folder, up to 12. Optional project: the slug of a Gzowo Labs project from blog_projects, it shows as a card under the post. To change an existing draft pass its draft_id, and only the fields that change. A draft is invisible on the site; tell him it is ready and offer to publish it with blog_publish.",
    parameters: { type: 'object', properties: {
      draft_id: { type: 'string', description: 'Id of an existing draft to change, empty for a new post' },
      title: { type: 'string', description: 'Title in Polish, up to about 80 characters' },
      text: { type: 'string', description: 'Post text in Polish, paragraphs separated by an empty line' },
      pictures: { type: 'array', items: { type: 'string' }, description: 'New pictures to add: https addresses or file paths' },
      project: { type: 'string', description: 'Gzowo Labs project slug from blog_projects, or empty' },
    } },
    summarize: a => (a.draft_id ? 'Poprawiam szkic na Gzowo Times' : 'Piszę szkic na Gzowo Times'),
    run: async ({ draft_id, title, text, pictures, project }) => {
      const add = [];
      for (const p of (pictures || []).slice(0, 12)) add.push(await picture(String(p)));
      const body = { status: 'draft', add };
      if (draft_id) body.id = draft_id; else body.by = 'concierge';
      if (title !== undefined) body.title = title;
      if (text !== undefined) body.body = text;
      if (project !== undefined) body.project = project || null;
      const { post } = await api('/blog/save', body);
      return { draft: slim(post), note: 'Draft saved, not visible on the site yet. Publish only after he says so, with blog_publish.' };
    },
  },
  {
    name: 'blog_list',
    action: 'blog.read',
    policy: 'auto',
    description: 'List the Gzowo Times posts and drafts, newest first, with their ids and status. Use it before changing, publishing or deleting a post he names by title.',
    parameters: { type: 'object', properties: {} },
    summarize: () => 'Sprawdzam wpisy na Gzowo Times',
    run: async () => ({ posts: (await api('/blog/admin')).posts.slice(0, 30).map(slim) }),
  },
  {
    name: 'blog_projects',
    action: 'blog.read',
    policy: 'auto',
    description: 'List Gzowo Labs projects (slug and name) that a Gzowo Times post can link to as a card.',
    parameters: { type: 'object', properties: {} },
    summarize: () => 'Sprawdzam projekty Gzowo Labs',
    run: async () => {
      if (!projects) {
        const r = await fetch('https://gzowo.fun/assets/data.json', { signal: AbortSignal.timeout(20000) });
        projects = ((await r.json()).projects || []).map(p => ({ slug: p.slug, name: p.name, section: p.section }));
      }
      return { projects };
    },
  },
  {
    name: 'blog_publish',
    action: 'blog.publish',
    policy: 'ask',
    description: 'Publish a Gzowo Times draft so everyone on gzowo.fun sees it in the news ticker. Only after he asked to publish or approved the draft. Pass the draft id and its title.',
    parameters: { type: 'object', properties: {
      draft_id: { type: 'string', description: 'Id of the draft' },
      title: { type: 'string', description: 'Title of the draft, shown on the approval card' },
    }, required: ['draft_id'] },
    askText: a => `Opublikować na Gzowo Times: „${a.title || a.draft_id}”?`,
    summarize: () => 'Publikuję na Gzowo Times',
    run: async ({ draft_id }) => ({ post: slim((await api('/blog/save', { id: draft_id, status: 'live' })).post), url: 'https://gzowo.fun/' }),
  },
  {
    name: 'blog_unpublish',
    action: 'blog.publish',
    policy: 'ask',
    description: 'Take a published Gzowo Times post off the site and turn it back into a draft.',
    parameters: { type: 'object', properties: {
      post_id: { type: 'string', description: 'Id of the post' },
      title: { type: 'string', description: 'Title of the post, shown on the approval card' },
    }, required: ['post_id'] },
    askText: a => `Zdjąć z Gzowo Times: „${a.title || a.post_id}”? Wróci do szkiców.`,
    summarize: () => 'Zdejmuję wpis z Gzowo Times',
    run: async ({ post_id }) => ({ post: slim((await api('/blog/save', { id: post_id, status: 'draft' })).post) }),
  },
  {
    name: 'blog_delete',
    action: 'blog.delete',
    policy: 'ask',
    description: 'Delete a Gzowo Times post or draft for good, pictures and reactions too. Cannot be undone.',
    parameters: { type: 'object', properties: {
      post_id: { type: 'string', description: 'Id of the post or draft' },
      title: { type: 'string', description: 'Title, shown on the approval card' },
    }, required: ['post_id'] },
    askText: a => `Usunąć na zawsze z Gzowo Times: „${a.title || a.post_id}”? Tego nie da się cofnąć.`,
    summarize: () => 'Usuwam wpis z Gzowo Times',
    run: async ({ post_id }) => api('/blog/delete', { id: post_id }),
  },
  {
    name: 'blog_editor_link',
    action: 'blog.read',
    policy: 'auto',
    hidden: true,
    description: 'Give him the private link that opens the Gzowo Times editor on gzowo.fun in his own browser (it signs that browser in for editing). Only when he asks for the editor.',
    parameters: { type: 'object', properties: {} },
    summarize: () => 'Przygotowuję link do edytora',
    run: async () => {
      if (!config.blog.key) throw new Error('GZOWO_BLOG_KEY is missing in .env.');
      return { link: `https://gzowo.fun/#blog=${config.blog.key}`, note: 'Private: whoever has this link can edit the blog. Show it only to him.' };
    },
  },
];
