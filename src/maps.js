// The previous battlefield catalog and its authored geometry were discarded
// at the user's request. Register newly designed maps only after verification.
export const TIER_INFO = {
  basic: { name: 'Basic · 기초', difficulty: 1, words: 15, waves: 10 },
  beginner: { name: '초급', difficulty: 1.2, words: 20, waves: 10 },
  intermediate: { name: '중급', difficulty: 1.45, words: 25, waves: 11 },
  advanced: { name: '고급', difficulty: 1.7, words: 30, waves: 12 },
};
export const MAP_THEMES = [];
export const MAPS = [];
export function getMap() { return null; }
