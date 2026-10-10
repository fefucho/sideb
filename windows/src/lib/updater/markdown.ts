export type Inline = { kind: 'text' | 'code' | 'strong' | 'emphasis' | 'link'; text: string; url?: string };
export type Block = { kind: 'heading' | 'paragraph' | 'quote' | 'code' | 'list'; text: string; level?: number; ordered?: boolean; items?: string[] };
function url(value: string): string | undefined { try { const parsed = new URL(value); return ['https:', 'http:'].includes(parsed.protocol) ? parsed.href : undefined; } catch { return undefined; } }
/** Release content stays text. Raw HTML, image execution and custom URL schemes are never interpreted. */
export function inlineMarkdown(value: string): Inline[] {
  const pattern = /(`[^`]+`|\*\*[^*]+\*\*|__[^_]+__|\*[^*\n]+\*|\[[^\]]+\]\([^\s)]+\))/g;
  const items: Inline[] = []; let end = 0;
  for (const match of value.matchAll(pattern)) {
    if (match.index > end) items.push({ kind: 'text', text: value.slice(end, match.index) });
    const token = match[0];
    if (token.startsWith('`')) items.push({ kind: 'code', text: token.slice(1, -1) });
    else if (token.startsWith('**') || token.startsWith('__')) items.push({ kind: 'strong', text: token.slice(2, -2) });
    else if (token.startsWith('*')) items.push({ kind: 'emphasis', text: token.slice(1, -1) });
    else { const link = /^\[([^\]]+)\]\(([^)]+)\)$/.exec(token)!; const safe = url(link[2]); items.push(safe ? { kind: 'link', text: link[1], url: safe } : { kind: 'text', text: token }); }
    end = match.index + token.length;
  }
  if (end < value.length) items.push({ kind: 'text', text: value.slice(end) });
  return items;
}
export function markdownBlocks(value: string): Block[] {
  const lines = value.replace(/\r\n?/g, '\n').split('\n'); const blocks: Block[] = [];
  for (let index = 0; index < lines.length;) {
    const line = lines[index];
    if (!line.trim()) { index++; continue; }
    if (/^\s*```/.test(line)) { const content = []; index++; while (index < lines.length && !/^\s*```/.test(lines[index])) content.push(lines[index++]); index++; blocks.push({ kind: 'code', text: content.join('\n') }); continue; }
    const heading = /^(#{1,6})\s+(.+)$/.exec(line); if (heading) { blocks.push({ kind: 'heading', level: heading[1].length, text: heading[2] }); index++; continue; }
    const list = /^\s*(?:([-*+])|(\d+)\.)\s+(.+)$/.exec(line);
    if (list) { const items = []; const ordered = !!list[2]; while (index < lines.length) { const item = /^\s*(?:([-*+])|(\d+)\.)\s+(.+)$/.exec(lines[index]); if (!item || !!item[2] !== ordered) break; items.push(item[3]); index++; } blocks.push({ kind: 'list', text: '', ordered, items }); continue; }
    if (line.startsWith('> ')) { blocks.push({ kind: 'quote', text: line.slice(2) }); index++; continue; }
    const text = [line]; index++;
    while (index < lines.length && lines[index].trim() && !/^(?:#{1,6}\s|\s*[-*+]\s|\s*\d+\.\s|>|\s*```)/.test(lines[index])) text.push(lines[index++]);
    blocks.push({ kind: 'paragraph', text: text.join('\n') });
  }
  return blocks;
}
