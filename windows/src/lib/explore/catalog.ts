export type ExploreTab = 'discover' | 'releases' | 'charts' | 'genres' | 'moods';
export type ExploreRoute = ExploreTab | `category:${string}` | `country:${string}`;
export interface ExploreCategory { id: string; hue: number; query: string }
export const tabs: ExploreTab[] = ['discover','releases','charts','genres','moods'];
export const moods: ExploreCategory[] = [{"id": "focus", "hue": 0.57, "query": "música para concentrarse"}, {"id": "relax", "hue": 0.47, "query": "música relajante"}, {"id": "workout", "hue": 0.03, "query": "música para entrenar"}, {"id": "party", "hue": 0.88, "query": "música fiesta"}, {"id": "sleep", "hue": 0.65, "query": "música para dormir"}, {"id": "road", "hue": 0.09, "query": "música para viajar"}, {"id": "good-mood", "hue": 0.13, "query": "música para sentirse bien"}, {"id": "romance", "hue": 0.96, "query": "canciones románticas"}];
export const genres: ExploreCategory[] = [{"id": "pop", "hue": 0.91, "query": "pop hits"}, {"id": "rock", "hue": 0.02, "query": "rock"}, {"id": "latin", "hue": 0.08, "query": "éxitos latinos"}, {"id": "hiphop", "hue": 0.12, "query": "hip hop"}, {"id": "electronic", "hue": 0.61, "query": "electrónica dance"}, {"id": "indie", "hue": 0.43, "query": "indie alternativa"}, {"id": "rnb", "hue": 0.76, "query": "R&B soul"}, {"id": "jazz", "hue": 0.55, "query": "jazz"}, {"id": "cumbia", "hue": 0.31, "query": "cumbia"}, {"id": "reggaeton", "hue": 0.04, "query": "reggaeton"}, {"id": "classical", "hue": 0.11, "query": "música clásica"}, {"id": "metal", "hue": 0.69, "query": "metal"}, {"id": "kpop", "hue": 0.83, "query": "k pop"}, {"id": "acoustic", "hue": 0.28, "query": "folk acústico"}, {"id": "reggae", "hue": 0.38, "query": "reggae"}, {"id": "soundtracks", "hue": 0.59, "query": "bandas sonoras"}];
export const category = (id: string) => [...genres, ...moods].find(item => item.id === id);
export function selectedTab(route: ExploreRoute): ExploreTab {
 if (route.startsWith('country:')) return 'charts';
 if (route.startsWith('category:')) return moods.some(item => item.id === route.slice(9)) ? 'moods' : 'genres';
 return route as ExploreTab;
}
export function countryName(code: string, language: string): string {
 if (code === 'ZZ') return language === 'en' ? 'Global' : 'Global';
 try { return new Intl.DisplayNames([language], {type:'region'}).of(code) ?? code; } catch { return code; }
}
