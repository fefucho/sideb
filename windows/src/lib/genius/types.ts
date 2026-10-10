export interface GeniusTrack { videoId: string; title: string; artists: string; album: string | null; durationSeconds: number | null; isUpload: boolean }
export interface GeniusCandidate { id: number; title: string; artist: string; url: string | null; confidence: number }
export interface GeniusSong { id: number; title: string; artist: string; url: string | null; description: string | null; releaseDate: string | null; annotationCount: number; producers: string[]; writers: string[]; performances: { label: string; artists: string[] }[] }
export interface GeniusResolution { status: 'matched' | 'ambiguous' | 'notFound'; song: GeniusSong | null; candidates: GeniusCandidate[]; chosenByUser: boolean }
export interface GeniusAnnotation { id: number; referentId: number; fragment: string; body: string; author: string | null; verified: boolean; votes: number; shareUrl: string | null; bodySpans: { text: string; url: string | null }[]; imageUrls: string[] }
export interface GeniusAnnotations { items: GeniusAnnotation[]; nextPage: number | null }
export interface GeniusLyricSpan { text: string; referentId: number | null }
export interface GeniusLyricLine { text: string; referentId: number | null; isHeader: boolean; spans: GeniusLyricSpan[] }
export interface GeniusLyrics { lines: GeniusLyricLine[] }
export interface GeniusMetrics { requests: number; responseHeaderMs: number; cacheHits: number; http429: number; http403: number; http5xx: number; transportErrors: number; parseErrors: number }
export interface GeniusState {
  trackKey: string | null; phase: 'idle' | 'loading' | 'matched' | 'ambiguous' | 'notFound' | 'error';
  resolution: GeniusResolution | null; lyrics: GeniusLyricLine[]; annotations: GeniusAnnotation[]; nextPage: number | null;
  loadingLyrics: boolean; loadingAnnotations: boolean; searching: boolean; searchResults: GeniusCandidate[];
  error: { key: string; args: (string | number)[] } | null; reporting: boolean; reportSaved: boolean;
  automaticFetch: boolean; diagnostics: boolean;
}
export const emptyGeniusState = (): GeniusState => ({ trackKey: null, phase: 'idle', resolution: null, lyrics: [], annotations: [], nextPage: null, loadingLyrics: false, loadingAnnotations: false, searching: false, searchResults: [], error: null, reporting: false, reportSaved: false, automaticFetch: false, diagnostics: false });
/** Only ordinary external links leave the app; provider content is never rendered as HTML. */
export function externalUrl(value: string | null | undefined): string | null {
  try { const url = new URL(value ?? ''); return ['https:', 'http:'].includes(url.protocol) ? url.href : null; } catch { return null; }
}
export function lyricSpans(line: GeniusLyricLine): GeniusLyricSpan[] {
  return line.spans.length ? line.spans : [{ text: line.text, referentId: line.referentId }];
}
